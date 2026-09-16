# Cooking App — Implementation Notes

MVP of a step-by-step recipe navigator for iOS, built with SwiftUI. The core idea: a recipe is
a sequence of discrete steps shown one at a time, full-screen, tap-to-advance — easy to follow
mid-cook with messy hands, instead of scanning a wall of text. Some recipes also support a
**two-person mode**, splitting into a Person A track and a Person B track, with two nearby
iPhones syncing progress live over `MultipeerConnectivity` (no internet, no accounts, no backend).

Repo: https://github.com/yahiaelsamman/cooking-app

See `/Users/yahiaelsaman/.claude/plans/tranquil-wishing-deer.md` for the original approved plan
(the initial MVP build) and `/Users/yahiaelsaman/.claude/plans/reactive-mixing-balloon.md` for pass
7's plan (the two-person session overhaul). This document covers seven build passes since; where
something from an earlier pass was later changed, only the current behavior is described below —
check git history for the specifics of what changed when.

## 1. What was built

### `CookingAppCore/` — a local Swift Package (all the testable logic)

- **`Recipe.swift`** — `Recipe`, `RecipeStep`, `StepAssignee`, `DietaryTag`
  (`vegetarian`/`vegan`/`glutenFree`/`lactoseFree`/`nutFree`), `Ingredient`. **`Recipe` is now a
  SwiftData `@Model` class** — a real on-device database record, not a hardcoded Swift value —
  added in pass 5 as the "memory" layer requested before adding more recipes. `RecipeStep`,
  `Ingredient`, and `DietaryTag` deliberately stayed plain `Codable` structs/enums embedded on the
  model as attributes rather than becoming their own `@Model` types with SwiftData relationships:
  they never need independent identity or querying outside their parent recipe, so giving them
  relationship machinery would only add SwiftData's relationship-modeling complexity (in
  particular, inverse-relationship ambiguity between `soloSteps` and `twoPersonSteps` — two
  separate to-many relationships targeting the same model type) for no real benefit. Since `@Model`
  classes don't get Swift's automatic `Equatable`/`Hashable` synthesis (only structs/enums get
  that), `Recipe` has a small hand-written `Hashable` conformance based on `id`.

  A `Recipe` carries **two independently-authored step lists**, not one list with a derived
  variant:
  - `soloSteps: [RecipeStep]` — always present, every step tagged `.solo`, written to read
    naturally for one person (no "Both:" phrasing).
  - `twoPersonSteps: [RecipeStep]?` — `nil` if this recipe has no sensible way to split labor
    between two people. When present, its steps are tagged `.personA`/`.personB`/`.shared`.

  `Recipe.supportsTwoPerson` is just `twoPersonSteps != nil` — there is **no generic fallback**
  for recipes without a split (an earlier "mirror mode" that mirrored the full list to both roles
  was tried and then deliberately removed — see the pitfalls below for why). `Recipe.track(for:)`
  returns `soloSteps` for `role: nil`, or `twoPersonSteps` filtered to that role + `.shared` for
  `role: .personA/.personB`.

  Cook time is mode-specific too: `soloCookTimeMinutes` (always present) and
  `twoPersonCookTimeMinutes` (present only alongside `twoPersonSteps`, and shorter — splitting
  labor should actually save time, which `RecipeModelTests` asserts as a regression guard).
  `Recipe.cookTimeMinutes(forTwoPerson:)` picks the right one. Each `Recipe` also carries
  `iconSystemName`, `difficulty` (1...3), `spiceLevel` (0...3), `dietaryTags`, `ingredients`; each
  `RecipeStep` carries `imageSystemName`.
- **`SampleRecipes.swift`** — **8 recipes**, fixed `UUID(uuidString:)` literals (not random
  `UUID()` — see pitfalls): 5 solo-only, 3 with both a solo version and a curated two-person
  split. For the latter 3, the solo version's steps are a genuinely separate, reworded pass over
  the same tasks (not the two-person steps with the labels stripped) — see git history for the
  exact wording per recipe if you want to compare.
- **`SyncMessage.swift`** — wire protocol, **7 message types** (pass 7 added `introduce` and
  `presenceUpdate`): `recipeSync`, `introduce`, `progressUpdate`, `timerStarted`,
  `timerCancelled`, `presenceUpdate`, `leaveSession`. Carries only indices/IDs/names, never step
  instruction text. `recipeSync` now also carries `hostRole: StepAssignee` (the cooking role the
  host picked for themselves — see the role-toggle note below) and `senderName: String` (the
  host's chosen name); `introduce` is the joiner's reply carrying its own `senderName` back, since
  `recipeSync` is the one message the host doesn't wait on and so is the only one that can't also
  double as the joiner announcing *its* name; `presenceUpdate` carries `isAway: Bool`.
- **`PeerSyncService.swift`** — wraps `MCSession`/`MCNearbyServiceAdvertiser`/
  `MCNearbyServiceBrowser`. Auto-reconnects on an unexpected drop (restarts advertising/browsing);
  `leaveSession()` is a **deliberate** end — sends a best-effort `leaveSession` message, then
  `stop()`s with no auto-reconnect. Every delegate callback (`didChange:`, `didReceive:`,
  `foundPeer:`, `lostPeer:`) is a thin `DispatchQueue.main.async` wrapper around an `internal`
  synchronous handler (`handleSessionStateChange`, `handleReceivedMessage`, `handleFoundPeer`,
  `handleLostPeer`) — this is what makes `PeerSyncServiceTests` possible without any real
  networking (see §3).

  **Pass 7 additions**: `startHosting(recipeID:hostRole:)` takes the role the host chose (via a
  toggle on the connect screen — see below) and stores it as `resolvedStepAssignee` immediately;
  the joiner resolves its own `resolvedStepAssignee` as the opposite once `recipeSync` arrives.
  `partnerName` is learned from `recipeSync`/`introduce`. `partnerIsAway` is learned from
  `presenceUpdate` and reset to `false` on every fresh `.connected` (a reconnect should assume
  presence until told otherwise). A new `onConnected` closure fires on **every** transition into
  `.connected` — first connect and every later reconnect alike — which is what
  `CookingSessionViewModel` uses to re-announce current progress/timers on reconnect (see below).
  `handleSessionStateChange`'s `.connected` case now also guards on `role != nil`: `role` is only
  non-nil between `startHosting`/`startBrowsing` and `stop()`, so a stray/late `.connected`
  callback arriving after a deliberate `stop()` is refused (`session.disconnect()`) instead of
  resurrecting connected state — this is the fix for a session staying joinable after supposedly
  ending. `PeerRole.stepAssignee` (the old hardcoded host→PersonA/joiner→PersonB mapping) was
  removed now that the cooking role comes from the toggle instead — `PeerRole` (host/joiner) is
  now purely a network-topology concept (who advertises vs. who browses).
- **`CookingSessionViewModel.swift`** — `advance()`/`goBack()`, `isComplete`, `isLastStep`,
  `progressText`/`progressFraction`, `partnerStep`, `partnerProgressFraction` (partner's progress
  through *their own* track as a 0...1 fraction — comparable to mine even when the two tracks have
  different lengths), `endSharedSession()`, `partnerDidLeave`, and a **stacking timer engine**:
  `activeTimers: [ActiveTimer]` (mine) and `partnerActiveTimers` (mirrored from the partner's
  `timerStarted`/`timerCancelled` messages, ticked locally by the same 1Hz `Timer` rather than
  needing a message every second). `ActiveTimer` carries the full `RecipeStep`, not just an id, so
  any timer — a partner's, or one on a step you've navigated away from — can always show what task
  it belongs to. `onTimerScheduled`/`onTimerUnscheduled`/`onTimerFinished` are hooks the app layer
  uses to drive local notifications (see below).

  **Pass 7 additions**: `partnerName`/`partnerIsAway` pass-throughs and
  `announcePresence(isAway:)` (sends a `presenceUpdate` — the app layer calls this on
  appear/disappear of the step screen, see below). A private `announceProgressAndTimers()`,
  wired to `peerSync.onConnected`, re-sends my current step and every running timer's *remaining*
  (not total) time whenever the connection (re)reaches `.connected` — without this, a rejoin looked
  like the partner had "just started," even mid-recipe, since only `advance()`/`goBack()`/
  `startTimer()` ever sent anything on their own and a reconnect triggers none of those by itself.
  `advance()` now also cancels every still-running timer (mine) the moment it crosses into
  `isComplete` — reusing `cancelTimer(for:)`'s existing teardown, so the pending local notification
  is unscheduled too — fixing a timer notification arriving after the recipe was already finished.
- **`ActiveSessionStore.swift`** — holds a reference to whatever `CookingSessionViewModel` is
  currently in progress, independent of navigation. Lets the recipe list show a "Resume Cooking"
  button that jumps back into the *same* session object — see the "resume" note below for why
  that's what makes Person A/B role preservation work.
- **`PeerConnectionViewModel.swift`** — host/join connection screen logic. `host()` is now
  `host(as role: StepAssignee)` (pass 7 — the role picked via the connect-screen toggle);
  `resolvedStepAssignee` and `partnerName` are exposed as pass-throughs from `PeerSyncService` for
  the view to use once the handshake completes.
- **`RecipeSeeder.swift`** *(new, pass 5)* — `seedIfNeeded(context:)` inserts the 8
  `SampleRecipes` into a `ModelContext` only if the store currently has zero `Recipe` records, so
  it's safe to call on every launch without ever overwriting recipes a future version lets the
  user add, edit, or delete. `SampleRecipes.swift` itself is unchanged — same hardcoded Swift
  recipes as before, just now used as seed data for a real store instead of being the store.

### `CookingApp/` — the iOS app target (thin SwiftUI views over Core)

- **`CookingAppApp.swift`** — creates a `ModelContainer` for `Recipe` in `init()`, calls
  `RecipeSeeder.seedIfNeeded` against its `mainContext`, and attaches it via `.modelContainer(_:)`
  — alongside the `ActiveSessionStore`/`UNUserNotificationCenter` setup from earlier passes.
- **`RecipeListView.swift`** — recipes now come from `@Query(sort: \Recipe.title) private var
  recipes: [Recipe]`, a live SwiftData query, not the static `SampleRecipes.all` array. Rows show
  a spice-level flame row (only when `spiceLevel > 0`) alongside difficulty stars, the solo cook
  time, and an "Also for two" badge only for `supportsTwoPerson` recipes. A bottom-right floating
  **"Resume Cooking"** button appears whenever `ActiveSessionStore.hasActiveSession`. Requests
  notification permission once, in `.onAppear` — i.e. at app start, not the first time you open a
  recipe or start a timer. **Pass 7**: also shows the one-time `WelcomeNameView` sheet
  (non-dismissable until a name is entered) whenever `@AppStorage("cookName")` is empty.
- **`WelcomeNameView.swift`** *(new, pass 7)* — "What should we call you?" — a name field +
  Continue (disabled while empty/whitespace-only), shown once via the sheet above. The name is
  reused as the `MCPeerID`/`PeerSyncService` display name for every future two-person session
  (falls back to `"Cook"` if somehow still empty when a connect screen is opened) and shown to your
  partner as `partnerName` instead of "Person A/B" once learned.
- **`RecipeDetailView.swift`** — a **Solo / Two-Person segmented picker** appears *only* when
  `recipe.supportsTwoPerson`; a recipe without a two-person version shows no toggle at all. The
  displayed cook time updates live with the picker (`recipe.cookTimeMinutes(forTwoPerson:)`), and
  the steps-overview section switches between the solo read-through and the Together/Person
  A/Person B grouping depending on the selection. `startCooking()` branches on the picker.
  Registers the new session with `ActiveSessionStore` before pushing (solo path). **Pass 7**: the
  header icon is now a `PlaceholderPhotoView` (see below) instead of a bare SF Symbol tile.
- **`PeerConnectionView.swift`** — on a successful handshake, also registers the new session with
  `ActiveSessionStore` (the two-person equivalent of the above). **Pass 7**: the idle state now
  shows an "I'll be: Person A / Person B" segmented toggle before the Host/Join buttons — only
  meaningful if you host (the joiner is assigned whichever role the host didn't pick, resolved from
  the incoming `recipeSync`); constructs its `PeerSyncService` with the persisted cook name as
  `displayName` (see `WelcomeNameView` above) rather than the device hostname. Also fixed the
  navigation-stack shape on handshake: it now does `path.removeLast(); path.append(Route.steps(session))`
  instead of only appending, so this connect screen is *replaced* rather than left underneath the
  step screen — otherwise the step screen's back button (see below) would land back on "Connecting…"
  instead of the recipe overview.
- **`StepView.swift`** —
  - **Back button**: no longer grayed out/disabled at the first step. Tapping it there now pops
    back to the recipe overview (`path.removeLast()`) instead of doing nothing; at any later step
    it still steps back one recipe-step as before. *(Pass 7 fix — previously there was no way at
    all to leave the step screen except finishing the recipe.)*
  - **Hold-to-finish**: the final step no longer completes on a plain tap/swipe. A dedicated
    `HoldToFinishButton` (currently a 1-second hold, animated ring) appears instead; the ordinary
    back button stays available alongside it, not replaced by it. The completion screen still has
    "Go Back" for a genuine accidental hold.
  - **`TimerStackView`**: every timer running somewhere other than the currently-viewed step —
    yours (accent-color chips) and your partner's (orange chips, matching their marker color in
    `DualProgressSliderView` — pass 7 fixed these two views disagreeing about "the partner's
    color," previously blue here vs. orange there) — each labeled with the task it's timing.
  - **Timer-finished feedback** *(pass 7 — was a blocking `.alert`)*: now a small non-blocking
    toast banner (top overlay, auto-dismisses after ~4s or on tap) — the rest of the screen (tap
    to advance, swipe, timer controls) stays fully interactive underneath it, which matters most
    when the finished timer belongs to a step you've since swiped away from. Haptic feedback and
    notification-cancellation on finish are unchanged.
  - **Presence hooks** *(new, pass 7)*: for a two-person session, `.onAppear`/`.onDisappear` call
    `session.announcePresence(isAway:)` — so a partner sees "stepped away" (not silence, and not a
    real "disconnected") when you back out to the recipe overview, and sees you return the same
    way. This does **not** end or disconnect the session — it stays resumable via "Resume Cooking,"
    same as before; it's purely an informational status update.
  - **Auto-ends when both people finish** *(new, pass 7)*: a `bothFinished` check
    (`session.isComplete && session.partnerProgressFraction == 1.0`) triggers
    `session.endSharedSession()` + `ActiveSessionStore.clear()` — previously reaching the
    completion screen didn't touch the peer connection or the session store at all, so a finished
    two-person session stayed (in principle) resumable/joinable indefinitely. The
    "Partner Ended the Session" alert's copy is softened to "You Both Finished!" when this is what
    triggered it, rather than implying an early/unexpected exit.
  - **"End Session"** toolbar button (two-person only, hidden once already ended), with a
    confirmation dialog; calls `session.endSharedSession()`.
  - An alert when `session.partnerDidLeave` flips true, clearing `ActiveSessionStore` and
    resetting the nav path back to the recipe list on acknowledgement.
  - Notification scheduling: wires `session.onTimerScheduled`/`onTimerUnscheduled` to
    `NotificationScheduler.schedule`/`cancel`; `onTimerFinished` also cancels the pending
    notification (the in-app banner already covers that case) alongside showing the banner/haptic.
- **`HoldToFinishButton.swift`**, **`DualProgressSliderView.swift`**, **`TimerStackView.swift`** —
  the controls described above.
- **`PlaceholderPhotoView.swift`** *(new, pass 7)* — a rounded-rect "photo card": a soft gradient
  (using a tint color) with the step/recipe's SF Symbol shown large and faint on top, plus a small
  corner "photo" badge — previews the sizing/corner-radius/shadow treatment real step photography
  would have, without needing actual images (still no image-generation tool available — see the
  Next Steps entry on real illustrations). Used for `StepView`'s step illustration and
  `RecipeDetailView`'s header; left `RecipeListView`'s small row thumbnails as plain SF Symbols
  (the card look doesn't read well that small).
- **`PartnerStatusView.swift`** — renders `DualProgressSliderView` beneath the partner-step
  readout whenever connected. **Pass 7**: shows `session.partnerName` once known (falls back to
  "Partner (Person A/B)" before the name exchange completes); the connection dot gains a distinct
  color for "connected but stepped away" (muted blue) vs. genuinely connected (green); and the
  status text now checks `partnerProgressFraction == 1.0` **before** falling back to
  "Getting started…" — previously a partner who had actually *finished* looked indistinguishable
  from one who hadn't started yet, since `partnerStep` is `nil` in both cases. Also now shows
  "Partner stepped away…" instead of either of those when `partnerIsAway` is true.
- **`StepTimerControl.swift`** — the per-step tappable timer icon, built on the stacking API
  (`activeTimer(for:)`/`cancelTimer(for:)`).
- **`Notifications/NotificationScheduler.swift`** — schedules/cancels a local notification per
  step timer, keyed by the step's own id (so stacked timers each get an independent notification).
- **`Notifications/NotificationDelegate.swift`** — a `UNUserNotificationCenterDelegate` that
  suppresses the system banner/sound while the app is foregrounded (`willPresent` →
  `completionHandler([])`), since that case already gets the in-app alert — stops you from seeing
  both for the same event.
- **`Resources/Assets.xcassets/AppIcon.appiconset/`** *(new, pass 7)* — a real app icon (was
  empty before). `icon-1024.png` is a single 1024×1024 image, generated by
  `Scripts/generate_app_icon.py` (repo root, outside any Xcode target so it doesn't get bundled as
  a resource) — no image-generation tool was available in this environment, so it's drawn by hand
  with Pillow: a warm orange→red gradient with a simple frying-pan-and-fried-egg glyph. Purely
  placeholder-quality art, not a designed brand mark — re-run the script after editing it to
  tweak the design, or just replace the PNG once you have real branding.

### On "resume" and role preservation

Leaving the step screen and coming back used to mean re-choosing Host or Join, which could flip
who's Person A vs. B if you picked differently than last time. `ActiveSessionStore` sidesteps that
by holding a reference to the *same* `CookingSessionViewModel` (and its already-connected
`PeerSyncService`, for two-person sessions) — "Resume Cooking" re-enters that exact object rather
than reconstructing one, so role, step index, and any running timers all come back exactly as they
were. This only survives within one app process's lifetime (backgrounding is fine, a force-quit is
not — there's still no disk persistence; see Next Steps).

## 2. How to run it

Full Xcode (26.6) is now installed in this environment as of pass 5 — it wasn't for passes 1-4 (see
§3's tooling note for what changed and what that means for verification level). Just open the
project normally:

1. Open `CookingApp/CookingApp.xcodeproj` in Xcode (generated by
   [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `CookingApp/project.yml`; depends on the
   local `CookingAppCore` package via a relative path — both folders must stay siblings).
2. Select the `CookingApp` target → **Signing & Capabilities** → set your personal Apple ID as
   the team.
3. **Solo recipes**: Simulator is fine, no networking involved.
4. **Two-person**: needs two physical iPhones — see §3's manual verification list.
5. If you add new source files under `CookingApp/CookingApp/` or change `project.yml`, re-run
   `xcodegen generate` from inside `CookingApp/`.

## 3. How the tests were run

**123/123 tests passed** when last run in this session (`swift test` from `CookingAppCore/`, run
repeatedly to confirm no flakiness under swift-testing's default parallel execution), across six
files:

- **`RecipeModelTests.swift`** — solo/two-person step-list integrity (contiguous ordering per
  list, solo steps never say "Both:"), track filtering (including `role: nil` and the
  personA/personB fallback-to-solo edge cases for a solo-only recipe), `supportsTwoPerson`,
  mode-specific cook time (including the "two-person is always faster than solo" regression guard
  and a check that `twoPersonCookTimeMinutes`/`twoPersonSteps` never disagree about nil-ness),
  timer stacking, recipe/step id uniqueness (guards the fixed-UUID-literal convention — see the
  pitfalls list), a single-step-recipe edge case for the `isLastStep`/`progressFraction` math,
  `RecipeStep`/`Ingredient` Codable round-trips, and recipe metadata range checks.
- **`SyncMessageCodingTests.swift`** — Codable round-trips for all 7 message types (pass 7 added
  `introduce`/`presenceUpdate`), plus malformed JSON and an unknown `type` value both failing to
  decode (rather than crashing or silently defaulting) — the property `PeerSyncService`'s
  `try?`-based message handling actually relies on.
- **`PeerSyncServiceTests.swift`** — connection state transitions, auto-reconnect triggering after
  a prior successful connection vs. *not* triggering on a first-ever drop or after a deliberate
  `leaveSession()` (covering both the joiner's re-browsing path and the host's re-advertising
  path), every inbound message type's handling, and peer discovery/loss bookkeeping — all via the
  `internal` synchronous handlers, no real MultipeerConnectivity session needed. (One real bug this
  caught while writing the tests: `MCPeerID` equality isn't just display-name comparison — two
  separately-constructed instances with the same name aren't `==`. Every test constructs its peer
  id exactly once and reuses that instance, never a fresh one.) **Pass 7 additions**: host-role →
  joiner-resolved-role derivation (both directions), name exchange via `recipeSync`/`introduce`,
  `presenceUpdate` updating/being reset on reconnect, `onConnected` firing on both the initial
  connect and every later reconnect, and the stray-`.connected`-after-`stop()` guard (both after a
  deliberate stop and for a service that was never started at all).
- **`CookingSessionViewModelTests.swift`** — partner-timer mirroring resolved against the
  partner's own track (not mine), `partnerStep`/`partnerProgressFraction`/`partnerConnectionState`
  all correctly nil/idle before a peer connects (solo and disconnected-two-person alike) and
  resolving correctly once one does, `partnerDidLeave` firing only from an *incoming* leave, local
  navigation continuing after ending a shared session, `ActiveSessionStore`, and the
  notification-scheduling hooks. **Pass 7 additions**: `partnerName`/`partnerIsAway` pass-throughs,
  that `onConnected` is actually wired up in `init` (see below for why only the wiring, not the
  resulting outgoing message, is checked), `announcePresence` being a safe no-op with no peer, and
  — the fix for a real reported bug — `advance()` cancelling every running timer (and firing
  `onTimerUnscheduled` for each) the moment it crosses into `isComplete`, whether there's one timer
  or several, but leaving them alone on any advance that doesn't reach the end.
- **`RecipeSeederTests.swift`** — the pass-5 persistence layer's actual contract, against
  a real in-memory `ModelContainer`/`ModelContext`: seeding an empty store inserts every sample
  recipe under its fixed id/title/step-list shape, re-running `seedIfNeeded` (as every app launch
  does) never duplicates anything, a `@Query`-style predicate fetch resolves correctly against the
  seeded data, and — critically — a store that already has *any* recipe in it (simulating a future
  user-added/edited recipe) is left completely alone rather than topped back up to the full sample
  set. See that file's header comment for a SwiftData test-isolation gotcha it works around:
  `SampleRecipes.all` are shared singleton `@Model` instances, and seeding two *different*
  in-memory contexts from them concurrently corrupts both (a test-process-only hazard, not a
  production one — a real launch only ever has one `ModelContainer`).
- **`PeerConnectionViewModelTests.swift`** — the host/join connection-screen logic: `host(as:)`/
  `join()` setting role and connection state, `cancel()` tearing down, `hostDidConnect()`'s
  synchronous handshake (including that it's a no-op before `host()` runs and for a joiner), and
  the `onRecipeSync` guard conditions that gate the joiner's handshake (wrong role, mismatched
  recipe id — see below for why only the guards, not the actual assignment, are covered). **Pass 7
  additions**: the host resolving its own chosen role immediately vs. the joiner resolving the
  opposite of whatever the host picked, and `partnerName` reflecting the exchanged name.

Notification *delivery* itself (`NotificationScheduler`/`NotificationDelegate`, both in the App
target) isn't unit-tested — `UNUserNotificationCenter` needs a real app process/authorization
state to do anything meaningful, so this is a manual-verification item, not something
`CookingAppCoreTests` could cover even if it lived in Core.

Why the timer's real 1-second countdown-to-zero isn't itself unit-tested: Foundation's `Timer`
needs an actively-spinning `RunLoop`, which the app's main run loop provides but a `swift test`
process's threading model doesn't reliably guarantee — a test that could silently hang isn't worth
the coverage. State transitions (`startTimer`/`cancelTimer`/stacking) are tested deterministically
instead; the actual countdown-to-alert behavior is a manual check (below). The same reasoning
applies to `PeerConnectionViewModel`'s joiner-side handshake: it flips `didHandshake` inside a
`DispatchQueue.main.async` block, which is likewise not reliably observable from a `swift test`
process with no spinning main run loop — `PeerConnectionViewModelTests` covers every synchronous
guard condition that gates that assignment instead of the assignment itself.

### Tooling note — full Xcode became available mid-session (pass 5)

Passes 1-4 had only Xcode Command Line Tools in this sandbox — no `xcodebuild`, no Simulator, so
the entire `CookingApp` iOS target (every SwiftUI view) was hand-reviewed but never actually
compiled. That changed partway through pass 5: full Xcode 26.6 turned out to be installed at
`/Applications/Xcode.app` (not there in earlier passes). Since global `xcode-select` in this
sandbox still points at Command Line Tools, verification here used a per-command
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` override rather than changing that
system-wide default — you won't need this yourself; opening the project in Xcode normally just
uses whichever Xcode you have.

With that available, this pass actually:
- Ran `swift build`/`swift test` for `CookingAppCore` with the real Xcode toolchain (needed
  specifically for SwiftData's `@Model` macro, whose plugin binary lives inside Xcode.app and
  isn't resolvable from Command Line Tools alone) — 67/67 tests passed.
- Ran `xcodebuild build` for the full `CookingApp` scheme against an iPhone 17 Simulator —
  **BUILD SUCCEEDED**, the first real compile of every SwiftUI file written across all five passes.
- Installed and launched the built app on that Simulator (`xcrun simctl install`/`launch`) and
  took a screenshot confirming the recipe list renders correctly with live, SwiftData-backed data
  — difficulty stars, spice flames, cook time, dietary tags, and the "Also for two" badge all
  showing as expected, recipes sorted by title via the `@Query`.
- Could **not** go further into automated UI interaction (tapping into a recipe, exercising the
  step screen) — that needs either `osascript`/System Events accessibility permission (not granted
  in this sandbox, and not something to grant non-interactively) or a proper XCUITest target
  (not set up). So the step-through screen, two-person flow, timers, hold-to-finish, and
  notifications are still exactly as before: hand-reviewed, not yet run.

### Pass 6 — filled the test-coverage gaps left by pass 5

Two whole source files had zero test coverage going into this pass: `RecipeSeeder.swift` (the
pass-5 persistence layer itself — the "memory" the previous pass's direction was explicitly built
around, yet nothing verified it actually seeds/doesn't-double-seed/doesn't-clobber-user-data
against a real SwiftData store) and `PeerConnectionViewModel.swift` (the host/join connection
screen's logic, present since pass 1). Added `RecipeSeederTests.swift` and
`PeerConnectionViewModelTests.swift` for both (see §3 above for what each covers), plus a batch of
edge-case regression guards spread across the four existing test files: recipe/step id uniqueness,
`track(for:)`'s `role: nil` and personB-fallback paths, `twoPersonCookTimeMinutes`/`twoPersonSteps`
nil-ness agreement, a single-step-recipe boundary case, `RecipeStep`/`Ingredient` Codable
round-trips, malformed/unknown-type `SyncMessage` decoding failing safely, host-side auto-reconnect
(previously only the joiner side was tested), and `partnerStep`/`partnerConnectionState` coverage
(previously only `partnerProgressFraction` was). Went from 67 to 99 tests, all passing, run several
times back-to-back to rule out flakiness from swift-testing's default parallel execution — that
default parallelism is exactly what surfaced the `RecipeSeederTests` isolation gotcha documented in
that file's header comment. Also reran `xcodebuild build` for the full `CookingApp` scheme against
an iPhone 17 Simulator to confirm the added test files didn't disturb anything — **BUILD
SUCCEEDED**, unchanged from pass 5. No production source under `CookingAppCore/Sources/` or
`CookingApp/CookingApp/` was modified this pass — test files only.

### Pass 7 — UX polish + two-person session overhaul

Prompted by real usage: no way back to the recipe overview once cooking started, a blocking timer
alert, a timer notification arriving *after* the recipe was already finished, inconsistent
mine/partner colors, no app icon, no sense of real step photography, and a cluster of two-person
problems — no names (partner shown as "Person A/B," MCPeerID defaulted to the device hostname), no
role choice (host always Person A), a partner who'd actually finished looking indistinguishable
from one who hadn't started, a rejoin not re-syncing current progress/timers, "leaving the recipe"
not showing up to the partner at all, and — the most concrete complaint — finishing didn't
auto-end a two-person session (it stayed resumable/joinable) and "End Session" didn't robustly
guarantee termination either. Decisions on the ambiguous parts were confirmed up front (see the
approved plan, `~/.claude/plans/reactive-mixing-balloon.md`): the **host** picks "I'll be: Person A
/ Person B" and the joiner gets the other; the cook-name prompt is a **one-time, first-launch**
sheet; and backing out to the recipe overview **keeps the session resumable** — the partner just
sees "stepped away," not silence or a hard disconnect.

Everything from that plan landed this pass — see §1 for the per-file specifics (all marked
"pass 7" above) — plus the timer-cancels-on-completion fix, which was reported mid-implementation
and folded in the same way. Added `RecipeSeederTests`-style coverage for every new piece of `Core`
logic (role/name resolution, presence, reconnect resync wiring, the stray-connection guard, the
finish-cancels-timers fix — see §3), went from 99 to 123 tests, and reran `xcodebuild build` for
the full `CookingApp` scheme — **BUILD SUCCEEDED**. Verified visually on the iPhone 17 Simulator by
temporarily auto-navigating past each screen from `RecipeListView.onAppear` (gated on an
env-var-only debug branch, added and then fully removed again before finishing — there's no
XCUITest target yet, so this was the only way to see the new screens render without
`osascript`/accessibility automation, which still isn't available in this sandbox): the
welcome-name sheet, the recipe list (new app icon), the recipe detail and step screens (placeholder
photo-card art, the un-grayed back button), and the host connect screen (the role toggle). Could
**not** visually verify the timer-finished banner, the "stepped away"/"finished" partner-status
text, or any real two-person handshake this way — those still need a live run (or two devices),
same limitation as every pass before this one.

**Manual verification checklist** (needs a real device/Xcode):

- Solo: tap-to-advance, swipe-to-advance/back, the back button at step one now goes to the recipe
  overview (never grayed out) rather than doing nothing, hold-to-finish on the last step, "Go Back"
  from the completion screen, starting/cancelling a timer, two timers stacked at once, a running
  timer getting silently cancelled (no notification) if you finish the recipe before it goes off,
  "Resume Cooking" after backgrounding and returning.
- The Solo/Two-Person picker: confirm it's **absent entirely** on the 5 solo-only recipes, and
  that switching it on the 3 dual-mode recipes changes both the displayed cook time and the steps
  list (no "Both:" phrasing or personA/personB hue tint in Solo mode).
- **Timer-finished banner**: confirm it doesn't block interaction (you can keep tapping/swiping
  through steps while it's showing), auto-dismisses after a few seconds, and dismisses early on tap.
- **Placeholder art**: confirm the step screen and recipe overview show the new gradient
  "photo card" treatment instead of a bare icon — purely a size/layout preview, not real
  photography (see §1's `PlaceholderPhotoView` note).
- **Cook name**: confirm the "What should we call you?" sheet appears once, on first launch only,
  and can't be dismissed without entering a name; confirm the name you enter is what shows up as
  your device's name in the other phone's "Nearby sessions" list during Join.
- Two-person: Local Network permission prompt, the "I'll be: Person A / Person B" toggle on the
  host's screen actually determining who's who (joiner gets the other role automatically — try it
  both ways), host/join handshake, each side seeing the other's real name (not "Person A/B") once
  connected, the dual progress slider moving as each phone advances, a timer started on one phone
  appearing (with its task label, in the partner's orange) on the other.
- **Leaving the recipe**: from the step screen, tap back at step one — confirm your partner's
  status flips to "stepped away" (not silence, not "disconnected"), and that tapping "Resume
  Cooking" and going back in shows your partner correctly again (not reset).
- **Reconnect resync**: toggle Airplane Mode on one phone mid-recipe (a few steps in, with a timer
  running) and back — confirm auto-reconnect happens, and that the partner's step/timer display
  updates to reflect where you actually are, not "just getting started."
- **Finishing together**: have both people reach the completion screen — confirm the session
  actually ends (peer connection torn down, "Resume Cooking" no longer offered for it, and a fresh
  Join attempt from a third device can't find it) rather than staying resumable/joinable
  indefinitely. Separately, confirm "End Session" also fully tears down (same joinability check).
- **Notifications**: accept the permission prompt at app launch (or check Settings →
  Notifications → Cooking App if it was missed/denied); start a timer, background the app or lock
  the phone, and confirm the notification arrives with the right step's text at roughly the right
  time; separately, start a timer and stay in the app until it finishes, and confirm you see
  *only* the in-app banner, not a system banner too.

### Pass 8 — real recipe hero photos, sourced from stock photography

Prompted by wanting to start incorporating real images, weighed against cost/consistency: AI
generation needs a paid external API and no image-gen tool exists in this environment either way;
self-shooting is authentic but slow; a community doesn't exist yet (still personal-use software).
Landed on the smallest useful scope — **recipe-level hero photos only** (8 recipes, not all
~60-90 steps) — sourced from **free stock photos**, since a generic-but-real finished-dish shot is
fine for a hero image in a way it wouldn't be for a specific step's mid-instruction state.

What shipped this pass:

- **`Recipe.heroImageName: String?`** (`Recipe.swift`) — deliberately per-recipe and optional, not
  all-or-nothing, so photos could land one recipe at a time rather than blocking on all 8 at once.
  All 8 sample recipes now have one set (see below).
- **`RecipeHeroImageView.swift`** (new) — renders `Image(recipe.heroImageName)` when set, else
  falls back to the existing `PlaceholderPhotoView`. `RecipeDetailView`'s header now uses this
  instead of always rendering the placeholder.
- **`RecipeListView.swift`**'s row thumbnail gained the same real-photo-or-fallback logic (new
  private `RecipeThumbnailView`) — but the *fallback* stayed the plain SF-Symbol tile it always
  was, not the gradient placeholder card, since that was already found not to read well at that
  size (pass 7 pitfall). Only recipes with an approved photo upgrade to a real cropped image there.
- **`Scripts/fetch_recipe_photos.py`** (new) — searches Pexels' free API (chosen over Unsplash:
  Pexels' license needs no attribution or download-tracking ping, Unsplash's does — real added
  complexity for a personal app with no credits screen) for each of the 8 recipes and downloads
  3-5 candidates per recipe into `Scripts/recipe_photo_candidates/<slug>/` for **human review** —
  it deliberately doesn't auto-pick one; stock-photo relevance needs a real look first. Run with
  your own `PEXELS_API_KEY`, then you hand-picked one winning candidate per recipe and deleted the
  rest yourself.
- **`Scripts/install_recipe_photo.py`** (new) — takes one approved candidate, center-crops it to
  the header's aspect ratio, writes it into `Assets.xcassets` as a new `.imageset` (declared at
  `3x` scale off a single high-res source file — same one-file trick `generate_app_icon.py` uses
  for the app icon, avoiding needing to generate separate 1x/2x/3x assets), and prints the exact
  `heroImageName` line to add in `SampleRecipes.swift`. Run for all 8 of your chosen candidates,
  producing 8 new imagesets: `recipe-photo-scrambled-eggs`, `recipe-photo-seared-steak`,
  `recipe-photo-weeknight-pasta`, `recipe-photo-avocado-toast`, `recipe-photo-grilled-cheese`,
  `recipe-photo-tomato-soup`, `recipe-photo-homemade-pizza`, `recipe-photo-taco-night`.
- **`SampleRecipes.swift`**: all 8 recipes now set `heroImageName` to their installed asset name.
- `RecipeModelTests.swift`: one new guard, `heroImageNameWhenPresentIsNonEmpty` — went from 123 to
  124 tests, all passing. Reran `xcodegen generate`, `swift test` (124/124), and `xcodebuild build`
  for the full `CookingApp` scheme — **BUILD SUCCEEDED**.
- **Visually verified** on the iPhone 17 Simulator: uninstalled + reinstalled the app first (the
  simulator already had the app installed from an earlier pass with its own SwiftData store —
  `RecipeSeeder` only seeds an *empty* store, so a stale install won't pick up new
  `heroImageName`s on the existing rows until the store itself is reset; a real device would need
  the same treatment, or a fresh install, to see this pass's photos). After that, the recipe list
  showed real, correctly-cropped food photography for every recipe instead of the SF-Symbol tiles.

### Pass 9 — real-device photo bug fix, favorites/rating/notes/cook-history, and 12 more recipes

Triggered by three things reported together: hero photos worked in the Simulator but not on a
real iPhone 17; a request for 20+ recipes; a request for a way to save/order/rate/note recipes.

**The real-device photo bug** turned out to be exactly the stale-store caveat called out at the
end of pass 8 — that device already had the app installed from before photos existed, and
`RecipeSeeder`'s old "only seed a completely empty store" guard meant it would *never* pick up a
`heroImageName` added to an already-seeded recipe, no matter how many times the app was rebuilt,
short of a full uninstall. That's a real bug, not just a documented caveat to live with — especially
now that this pass also adds 12 more bundled recipes, which have the exact same problem: they'd
never reach an existing install either. Fixed by rewriting `RecipeSeeder` to be **additive by id**:
it now inserts whichever bundled recipes the store doesn't already have (matched by their fixed
id), and leaves every already-present recipe — including all its user data — completely alone. A
recipe already in the store is skipped, not refreshed, so this fixes *new* recipes/fields reaching
old installs going forward, but doesn't retroactively add `heroImageName` to the original 8 on a
device that already has them seeded without photos — that part still needs the uninstall/reinstall
from pass 8's note (or, going forward, will simply resolve itself as those rows pick up whatever's
added next by id, same as any other addition). See `RecipeSeeder.swift`'s doc comment for the full
reasoning, including the one tradeoff this creates (a future delete feature will need a tombstone —
not a concern yet, since there's still no way to delete a recipe at all).

**Favorites, rating, notes, and cook history** — new user-data fields directly on `Recipe`
(`isFavorite: Bool`, `personalRating: Int?` 1...5, `personalNotes: String`, `timesCooked: Int`,
`lastCookedDate: Date?`, `sortOrder: Int`), each with an inline default so SwiftData's automatic
lightweight migration can backfill existing rows. `RecipeSeeder` never touches any of these on an
already-present recipe — see above.

- **`RecipeDetailView.swift`**: a heart-toggle in the toolbar (favorite), a new "My Notes" section
  with a `StarRatingView` (new, `CookingApp/Views/StarRatingView.swift` — tapping the already-set
  top star clears the rating), a "Cooked N times, last on <date>" readout, and a `TextEditor` bound
  to `personalNotes`. `recipe` changed from `let` to `@Bindable var` to support this. Every mutation
  saves immediately via `@Environment(\.modelContext)`.
- **`StepView.swift`**: `.onChange(of: session.isComplete)` increments `recipe.timesCooked` and
  sets `lastCookedDate` the moment my own track finishes (solo or two-person alike — independent of
  `bothFinished`, which only handles tearing down the shared connection). Going back from the
  completion screen and finishing again counts again; this isn't suppressed.
- **`RecipeListView.swift`**: a sort-mode menu (My Order / A–Z / Top Rated) and a favorites-only
  filter toggle in the toolbar. "My Order" is the only mode backed by `sortOrder` and the only one
  offering drag-to-reorder (`.onMove`, with the list in permanent edit mode while that sort is
  active) — the other two are always freshly derived, so dragging wouldn't mean anything durable in
  them. Turning on the favorites filter while reordering switches out of "My Order" automatically,
  since reordering a filtered subset would scramble the full sequence for whatever's hidden. Every
  row also gets a leading swipe action to toggle favorite without opening the recipe. `RecipeRow`
  now shows a small favorite heart, a compact read-only `StarRatingView`, and a "Cooked N×" badge
  when either applies.
- Sourcing note for photos on the 12 new recipes: none have a `heroImageName` yet — no Pexels key
  was available this pass, so they use the placeholder card, same as any recipe before pass 8.

**12 more recipes**, bringing the bundled total from 8 to 20 (fixed UUIDs `...0009` through
`...0020`, continuing the existing convention): Chicken Stir-Fry, Beef Chili, Caprese Salad, Banana
Pancakes, Shrimp Scampi, Vegetable Fried Rice, Chicken Caesar Salad, Baked Salmon with Asparagus,
French Onion Soup, Beef and Broccoli, Chicken Quesadillas, and Chocolate Chip Cookies (the first
dessert). 6 of the 12 got a curated two-person split, bringing the two-person-capable total to 9/20.

**Testing**: `RecipeSeederTests.swift` was rewritten around the new additive contract — see its own
doc comment for a real hazard hit while writing it: `SampleRecipes.all` are process-wide singleton
`@Model` instances, and once one is inserted and saved into a SwiftData container, inserting that
*same instance* into a second, different container silently fails to persist there at all (not just
a parallelism race — reproduced this doing it strictly sequentially too). So this file now runs
everything through exactly one test, one context, as a single continuous narrative, rather than
splitting scenarios across separate `@Test` functions the way most other test files here do.
`RecipeModelTests.swift` gained guards for "no bundled recipe hardcodes fake user data," title
uniqueness, and a `>= 20` count floor. 126/126 tests passing (up from 124), rerun twice back-to-back
to confirm no flakiness. `xcodebuild build` for the full `CookingApp` scheme — **BUILD SUCCEEDED**.

Visually verified on the iPhone 17 Simulator (fresh install, same stale-store lesson from pass 8
applied again): the favorites-filter and sort-mode controls render in the toolbar, "My Order" mode
shows drag handles on every row, and — using the same temporary, fully-reverted debug auto-nav
technique pass 7 established (there's still no XCUITest target or accessibility automation in this
sandbox) — `RecipeDetailView`'s new "My Notes" section renders correctly: favorite heart, star
rating, "Cooked: Not yet," and the notes editor with its placeholder, no crash or layout issue.
Could **not** visually verify the swipe-to-favorite gesture or actually dragging to reorder — both
need real touch input, which this sandbox has never had a way to inject.

Also hit and worked around, unrelated to the app itself: this project lives under `~/Desktop`,
which iCloud Desktop & Documents sync actively watches — partway through this pass, SwiftPM's test
bundle started failing to codesign with "resource fork, Finder information, or similar detritus not
allowed," caused by `com.apple.FinderInfo`/`com.apple.fileprovider.fpfs#P` extended attributes
iCloud was tagging onto freshly-written `.build` output *while* the build was still running —
`xattr -cr` on the bundle didn't stick since the tag reappeared immediately. Fixed by building with
`swift test --scratch-path /tmp/...` instead of the default `.build/` inside the synced folder.
Worth knowing if `swift build`/`swift test` starts failing the same way again in this repo.

### Pass 10 — in-app recipe creation/editing

Continuing the same extended, autonomous pass — the next item on §5's own next-steps list once
pass 9's three explicit requests were done: a way to add/edit recipes from inside the app, rather
than needing a Swift source change for every new recipe.

**Scope decision**: editing and deleting are both restricted to a recipe actually created through
this new editor, never a bundled `SampleRecipes` one. Two reasons, not one: editing a curated
recipe's hand-authored content (especially a two-person split — real divided labor, not something
a form can generate) is a different, bigger problem than adding a new solo recipe; and deleting a
bundled recipe would come back on the next launch under pass 9's additive `RecipeSeeder` without a
tombstone, which doesn't exist yet (see `RecipeSeeder`'s doc comment). A new `Recipe.isUserCreated`
field marks which recipes are safe for both — `false` for all 20 bundled recipes, `true` only for
one made through `RecipeEditorView`. Two-person splits are out of scope for this editor entirely, for
the "not something a form can generate" reason above — a recipe created here is always solo-only,
same as 11 of the 20 bundled recipes already are.

**`RecipeEditorView.swift`** (new) — one shared form for both add and edit, presented as a sheet:
title/summary/servings, difficulty/spice/cook-time, dietary tag toggles, a dynamic ingredients list
(add/remove rows), and a dynamic steps list (add/remove/reorder, each just plain instruction text —
no per-step timer/image configuration in this first cut, matching how simple the bundled recipes'
own step authoring already keeps those). Validates before allowing Save (non-empty title, a
positive cook time, at least one non-empty ingredient and step) and silently drops any blank
ingredient/step rows rather than saving them. A "Delete Recipe" option appears only when editing an
already-`isUserCreated` recipe.

Reachable from two places: a "+" button in `RecipeListView`'s toolbar (creates new), and an "Edit"
button in `RecipeDetailView`'s toolbar, shown only when `recipe.isUserCreated`. Deleting from the
edit sheet leaves `RecipeDetailView` holding a reference to a now-gone `Recipe` — handled by
`popBackIfRecipeWasDeleted()`, run in the sheet's `onDismiss`: it re-fetches by id, and pops back to
the recipe list if that comes back empty.

**A real model change this required**: `RecipeStep` and `Ingredient`'s stored properties changed
from `let` to `var`. Both are plain structs that were never mutated after construction anywhere in
the app before this — but SwiftUI's `Binding` dynamic member lookup (`ForEach($steps) { $step in
TextField(text: $step.instruction) }`, the mechanism the editor's ingredient/step rows are built on)
needs a settable property to produce a writable sub-binding at all, and won't compile against a
`let`. Low-risk change: nothing relies on these being immutable, and both are still just local
value types everywhere else they're used.

**Testing**: App-layer view logic (the form's validation, save/delete behavior) isn't unit-tested,
consistent with how every other SwiftUI view in this app is verified — see §3's tooling notes on
why that's a build+manual-verification concern, not a `CookingAppCoreTests` one. `RecipeModelTests`
gained one more assertion to its existing "no bundled recipe hardcodes fake user data" guard:
`isUserCreated` must be `false` for all 20. Still 126/126 tests passing after the `let`→`var`
changes (Codable/Hashable synthesis is unaffected by mutability). `xcodebuild build` for the full
`CookingApp` scheme — **BUILD SUCCEEDED**. Visually verified on the iPhone 17 Simulator with the
same temporary, fully-reverted debug auto-nav technique as pass 9: the "New Recipe" form renders
correctly end to end (toolbar, Basics fields, Dietary Tags toggles), no crash or layout issue.
Editing an existing recipe, deleting one, and the dynamic add/remove/reorder row interactions
weren't exercised this way — same real-touch-input limitation as pass 9's swipe/drag verification
gap.

### Pass 11 — curated two-person splits for 4 more recipes

Continuing the same session, per §5's item 7: went through the 11 solo-only recipes (5 original +
6 from pass 9) and hand-authored a two-person split for the 4 where dividing labor genuinely helps
— **Shrimp Scampi** (pasta boiling and shrimp/sauce are truly parallel stations), **Chicken Caesar
Salad** (searing chicken and prepping lettuce/croutons don't share a station), **Baked Salmon with
Asparagus** (brief parallel prep before a shared, unattended roast), and **Chicken Quesadillas**
(cooking the chicken and prepping toppings can happen side by side). Deliberately did **not** force
a split onto the other 7: Scrambled Eggs, Pan-Seared Steak, Grilled Cheese, Simple Tomato Soup,
Caprese Salad, Banana Pancakes, and Avocado Toast with Fried Egg are each single-station, too quick,
or (Avocado Toast, Grilled Cheese) a single serving to begin with — matching the project's existing
stance that a recipe simply has no two-person option until one is genuinely deliberately authored
for it, not guessed at (see the removed-mirror-mode pitfall). Two-person-capable recipes: 9 → 13 of
20. 126/126 tests still passing (the generic cross-recipe tests — contiguous step ordering, both
person tracks present, two-person time faster than solo — cover new splits automatically, no test
changes needed). `xcodebuild build` for the full `CookingApp` scheme — **BUILD SUCCEEDED**.

### Pass 12 — an XCUITest target (built and wired, but not successfully run in this sandbox)

Moved to §5's XCUITest item — every earlier pass's "verified via screenshot" note existed
specifically because there was no way to drive a real tap/swipe/drag, and passes 9/10 had
accumulated a real backlog of genuinely-unverified interactions (swipe-to-favorite, drag-reorder,
the recipe editor's dynamic rows) because of it.

**What was built**: a `CookingAppUITests` target (added to `project.yml`, wired into the
`CookingApp` scheme's test action) with 4 tests in `CookingAppUITests.swift` — recipe list → detail
navigation, the favorite toggle's immediate reactivity, swipe-to-favorite-from-the-list actually
persisting (checked by reopening detail), and the full add-recipe form flow (fill every field,
save, confirm the new recipe appears and looks user-created). Two small, permanent (not
temporary-and-reverted, unlike every earlier pass's screenshot hack) additions make this possible:
`CookingAppApp` uses an in-memory SwiftData store when launched with `-UITesting`, so every test
run starts from exactly the 20 bundled recipes with no leftover state from a previous run or
interference with a real user's data; `RecipeListView` skips requesting the system notification
permission under the same flag, since that system dialog can't be reliably dismissed from XCUITest.
Also added `accessibilityIdentifier`s to every element the tests need to address reliably (row
buttons keyed by recipe title, the add/favorite/save buttons, the editor's text fields).

**What actually happened running it**: the target built, compiled, linked, and code-signed
successfully — real confirmation the test code itself is correct Swift and the target is wired up
right. But `xcodebuild test` itself never got further than "loading Accessibility" during test-
runner bootstrap: it stalled for the full 70-second watchdog timeout and failed before a single
test ran, on the very first attempt — before memory pressure was ever a factor. A second attempt
(after a clean simulator reboot) was killed by the *host machine itself* running low on real
memory; since this is the actual laptop this session runs on, not a disposable sandbox, a third
attempt wasn't made rather than risk straining it further. The first failure's timing (immediate,
pre-memory-pressure) points to the sandboxed simulator here lacking full support for XCUITest's
accessibility-based automation — plausibly a headless/no-real-window-server limitation — rather
than something retrying would fix.

**So**: the target and tests are real, committed, and ready to run — just unverified in *this*
environment. Running them from Xcode directly (⌘U) or `xcodebuild test` on a normal interactive
Mac should work; if the same "loading Accessibility" stall happens there too, that'd be worth
reporting as a genuine Simulator/Xcode issue rather than an environment-sandbox one.

### Pass 13 — a self-review pass over everything from passes 9-12, and real fixes

With the XCUITest target un-runnable in this sandbox and the host machine having just shown real
memory pressure, switched to something that needed neither a simulator nor heavy compute: an
actual code-review pass (the `/code-review` skill, `high` effort) over the full diff since pass 9
began (`eaeef4e..HEAD`). It surfaced 10 findings; fixed the ones that were real bugs, left the
stylistic/premature-optimization ones alone with reasoning recorded here rather than just silently
skipped.

**Fixed:**
- **`sortOrder` corruption via the Sort menu, not just the favorites button.** The favorites-filter
  button was the only place guarding against "drag-reorder while filtered" — but switching to "My
  Order" directly from the sort Picker while the filter was already on reached the same bad state
  through a door that guard didn't cover. Fixed by replacing the imperative one-off check with a
  reactive `canReorder` computed property (`sortMode == .myOrder && !showFavoritesOnly`) that both
  the `List`'s edit-mode/`.onMove` wiring now read directly — correct no matter which control gets
  you into that combination, since it's evaluated fresh every time, not just when one specific
  button is tapped.
- **A real crash risk deleting a recipe from the edit sheet.** `RecipeDetailView` holds a live
  `@Bindable` reference to `recipe`; the old flow deleted it from inside the sheet and popped the
  nav stack only in `onDismiss` — after the dismiss animation, leaving a window where
  `RecipeDetailView`'s still-mounted body could read a model SwiftData had already removed.
  Restructured so `RecipeEditorView` no longer deletes directly: it calls a new `onDelete` closure
  instead, and `RecipeDetailView`'s implementation of that closure resets `path` *before* actually
  deleting — the screen is off the navigation stack before the model is gone, not after.
- **`RecipeEditorView.save()` had no guard of its own against editing a non-user-created recipe** —
  only reachable indirectly today (`RecipeDetailView`'s Edit button is itself gated), but the view's
  own doc comment claims this restriction, so it should enforce it, not just assume every caller
  will. Added an `assertionFailure` + early return.
- **Default sort mode changed from "My Order" to "A–Z."** Two independent reasons converged on the
  same fix: an install that had already seeded recipes before `sortOrder` existed would have every
  one of them migrate to the same value (SwiftData backfills a new field's inline default, which
  is `0` for all existing rows) — opening straight into "My Order" would show them in an arbitrary
  tied-at-zero order instead of the previous alphabetical one. Separately, `List` forced into edit
  mode by default (needed for "My Order"'s drag handles) may suppress the new leading swipe-to-
  favorite action — untestable in this sandbox, but defaulting away from edit mode sidesteps it for
  the common case regardless. "My Order" is still there, just opt-in now.
- **Servings had no validation** — `isValid` now also requires that if anything's been typed, it
  parses to a positive number, matching how cook time is already validated.
- **`nextSortOrder` was computed identically in two places** (`RecipeSeeder` and
  `RecipeEditorView`, both written this session) — extracted to `Recipe.nextSortOrder(after:)`, a
  shared static helper, with its own two unit tests.

128/128 tests passing (126 + 2 new for the shared helper); `xcodebuild build` for the full
`CookingApp` scheme — **BUILD SUCCEEDED** (a plain build only, not `test` — see pass 12's note on
why simulator-heavy operations were being used sparingly for the remainder of this session).

**Deliberately left alone, with reasoning:**
- **`RecipeSeeder` fetches every full `Recipe` row just to compute existing ids**, rather than a
  cheaper id-only fetch. At the realistic scale this app will ever reach (tens of recipes, not
  thousands), the decoding cost is genuinely negligible — fixing this now would be optimizing for a
  scale that will never occur, which is exactly the kind of premature work the project's own
  conventions steer away from.
- **`StarRatingView` duplicates the icon-row rendering pattern** already in
  `DifficultyStarsView`/`SpiceLevelView`. Real observation, but the three aren't identical (one's
  interactive with tap handling and a different symbol/fill count, two are static) — unifying them
  is a legitimate future cleanup, not urgent enough to do instead of the correctness fixes above.
- **`RecipeEditorView.save()`'s create/edit branches are two similar-but-not-identical field
  blocks**, which have to be kept in sync by hand for any future field. Restructuring into one
  shared code path is a bigger change with its own risk; noted as a real maintenance cost to keep
  in mind, not fixed this pass.

### Pass 14 — an unattended overnight autonomous pass: search, and keeping the screen awake while cooking

Kicked off with a standing instruction to run autonomously for an extended stretch (up to ~8 hours,
self-paced, stopping at each iteration boundary once context usage gets high), generating tests,
improving the everyday feel of the app, and drawing on general recipe-app/cooking-blog conventions
for what a "seamless" cook-along experience should include — rather than a single specific feature
request. Given no interactive user to check in with mid-run and this session sharing the real
laptop's resources (see pass 12's memory-pressure note), this pass deliberately stuck to
`swift test` and `xcodebuild build`/`build-for-testing` for verification — no `xcodebuild test`
against the Simulator, since that's the operation pass 12 found could stall or strain the host
machine, and nobody would be present to notice or intervene overnight.

Picked two independent, low-risk, high-value items — one pulled from a real gap (no way to find a
recipe by name/ingredient once you have 20+ of them, and it'll only grow) and one from the single
most common cooking-app UX convention this app was still missing:

- **`Recipe.matchesSearch(_:)`** (`Recipe.swift`) — case/diacritic-insensitive
  (`localizedStandardContains`) matching against title, summary, ingredient names, and dietary tag
  labels. Deliberately **excludes step instruction text** — matching on step wording would surface
  unrelated recipes on common cooking verbs ("stir," "pan," "boil") rather than helping find a dish
  by name or contents; a regression test (`doesNotMatchOnStepInstructionTextAlone`) pins this down
  by asserting a word that's *only* in a step ("colander") doesn't match. An empty/whitespace query
  matches everything.
- **`RecipeListView`** gained a `.searchable(text:)` search field. `displayedRecipes` now applies
  the search filter alongside the existing favorites filter, before sorting. `canReorder` was
  widened to also require `searchText.isEmpty` — reordering "My Order" against a search-filtered
  subset would corrupt `sortOrder` the exact same way the favorites-filter case already guarded
  against (see pass 13's `canReorder` fix), so this reuses that same reactive computed property
  rather than adding a second, separate guard.
- **Keep the screen awake while actively cooking** (`StepView.swift`) — `UIApplication.shared.
  isIdleTimerDisabled` is now set `true` in the step screen's `.onAppear` and reset to `false` in
  `.onDisappear`. This was a real, conspicuous gap: cooking is a glance-at-the-phone-with-messy-hands
  activity, and every mainstream recipe app (this is a near-universal convention worth calling out
  explicitly, per this pass's brief to check general cooking-app practice) disables auto-lock while
  a recipe is on screen for exactly that reason — a phone that locks itself mid-step while your
  hands are covered in flour is a real interruption, not a cosmetic one. Scoped tightly to
  `StepView` alone (not app-wide) so the device still sleeps normally everywhere else, including the
  recipe list and detail screens.

**Testing**: `RecipeModelTests.swift` gained a `matchesSearch` section — empty/whitespace query,
title (case-insensitive), summary, ingredient name, dietary tag label, the step-instruction
exclusion above, and a fully-unrelated query — all against one dedicated fixture recipe rather than
`SampleRecipes.all`, so the assertions are about the matching logic itself, not incidental to
whatever the bundled recipes happen to contain. 128 → **135/135 tests passing**. Also added
`testSearchFiltersByTitleAndByIngredientName` to `CookingAppUITests.swift` (search by title, clear,
search by an ingredient that belongs to a different recipe than the title search matched) — written
and built successfully (`xcodebuild build-for-testing` succeeded) but, consistent with every UI test
in this target since pass 12, **not run** in this sandbox (same Simulator-automation limitation, and
deliberately not attempted this pass for the resource reason above). The idle-timer change isn't
unit-tested, consistent with `NotificationScheduler`/`NotificationDelegate` and every other
`UIApplication`/UIKit-only behavior in this app (§3) — it needs a real device/manual check, added to
the manual-verification list below.
`xcodebuild build` for the full `CookingApp` scheme — **BUILD SUCCEEDED**.

**Added to the manual verification checklist** (§3): confirm the screen doesn't auto-lock while a
step is showing (leave the phone untouched on the step screen past its normal auto-lock timeout),
and confirm it locks normally again once you leave the step screen (recipe list/detail, or after
finishing) — the idle timer is a single shared `UIApplication`-wide flag, so a bug here would either
leave the phone unable to sleep everywhere or fail to keep it awake at all, not something subtler.

### Pass 15 — servings scaling for ingredient amounts

Second iteration of the same overnight autonomous run (pass 14). Picked up §6's own longstanding
observation — "nothing scales ingredient quantities to a different serving count" — which had been
sitting unaddressed because `Ingredient.amount` is a free-text string ("A pinch," "1/2 cup," "200g"),
not a structured `(value, unit)` pair, so naive "multiply the number" scaling risks corrupting
amounts that aren't numbers at all. Solved by parsing only the *leading* quantity and leaving
everything else untouched, rather than a bigger data-model migration to structured quantities across
all 20 bundled recipes' ingredients — the smaller, additive fix that doesn't touch existing content.

- **`Ingredient.scaledAmount(by:)`** (`Recipe.swift`) — parses a leading whole number ("2"),
  decimal ("1.5"), simple fraction ("1/2"), or mixed number ("1 1/2") off the front of `amount`,
  scales just that value by `factor`, and reattaches whatever followed it verbatim (a unit with or
  without a space, "small"/"large," or nothing). Amounts with no leading number at all ("A pinch,"
  "To taste," "As needed" — surveyed directly from `SampleRecipes.swift` before writing this, see
  the doc comment) come back completely unchanged rather than guessing. Scaled values are formatted
  back as a whole number when close to one, a common cooking fraction (halves/thirds/quarters/
  eighths) when that's a close match, or a trimmed decimal otherwise — so doubling "1/2 cup" reads
  as "1 cup," not "1.0 cup," and doubling "3/4 cup" reads as "1 1/2 cup," not "1.5 cup." Deliberately
  doesn't attempt unit conversion, unicode vulgar fractions (½, ¾), or ranges ("2-3") — none of
  those appear in this app's real ingredient data, so building for them now would be speculative.
- **`RecipeDetailView.swift`** — a servings +/- stepper next to the "Ingredients" header, shown only
  when `recipe.servings != nil` (the same "don't offer a control that has nothing to scale relative
  to" stance `modePicker` already takes for two-person mode). `targetServings` starts at the
  recipe's own `servings` and is purely ephemeral view state — it resets on reopening the recipe,
  the same as the existing solo/two-person `mode` picker, rather than being persisted; it describes
  "how many people am I cooking for today," not a durable fact about the recipe. Every ingredient
  row's displayed amount is `ingredient.scaledAmount(by: servingsScaleFactor)` instead of the raw
  `amount`; the metadata row's "Servings" tile now shows `targetServings` too, so it stays in sync
  with the stepper rather than showing a now-stale original count.

**Testing**: new `IngredientScalingTests.swift` — every amount *shape* actually present in
`SampleRecipes.swift` (plain whole numbers, spaced/unspaced units, decimals, simple fractions, and
every qualitative amount like "A pinch"/"To taste"), plus mixed numbers (not in the bundled data yet,
but the parser handles them), the identity case (`factor: 1` changes nothing), guard behavior for
non-positive/non-finite factors, and a broad sweep asserting every real bundled ingredient scales to
a non-empty string at both 2× and 0.5× without crashing. 135 → **153/153 CookingAppCoreTests
passing**. Added `testServingsStepperScalesIngredientAmountsLive` to `CookingAppUITests.swift`
(Classic Scrambled Eggs' "3" large eggs doubles to "6" and back) — built successfully via
`xcodebuild build-for-testing`, not run, same sandbox limitation as every UI test since pass 12.
`xcodebuild build`/`build-for-testing` for the full `CookingApp` scheme — both **SUCCEEDED**.

### Pass 16 — a VoiceOver accessibility pass over the step screen

Third iteration of the overnight autonomous run. This one was prompted directly by outside
research rather than the project's own backlog: a web search on current recipe-app UX conventions
(see this pass's sources) called out "screen readers must interpret ingredients, instructions, and
image descriptions — accessibility shouldn't be an afterthought" as a named best practice, which
prompted actually auditing this app against it rather than assuming the existing
`accessibilityIdentifier`s (added for XCUITest addressing, a different concern) meant VoiceOver
support existed too. It didn't: `StepView` — the screen this entire app is built around — had zero
`accessibilityLabel`/`accessibilityAction` usage before this pass, and several of its subcomponents
were no better.

Concretely broken for a VoiceOver user, before this pass:
- **No way to advance to the next step at all.** The tap-to-advance gesture is a real
  `.onTapGesture`, which VoiceOver intercepts for its own navigation rather than passing through —
  there was no accessible action standing in for it.
- **The back button** (an icon-only `chevron.left.circle.fill`) had no label, so VoiceOver would
  synthesize something like "chevron left circle fill" instead of saying what it does.
- **`HoldToFinishButton`** — the *only* way to finish a solo recipe — had no label or accessible
  action at all, and a long-press gesture has no dependable VoiceOver equivalent to begin with.
- **`StarRatingView`'s 5 rating buttons**, **`DifficultyStarsView`**, and **`SpiceLevelView`** all
  read as indistinguishable repeated "star"/"flame" fragments with no indication of what they
  represented or which one you'd just focused.
- **`TimerStackView`'s timer chips** and the running-timer cancel button in `StepTimerControl` read
  as disconnected fragments (an untitled icon, then instruction text, then bare digits) rather than
  one clear "Partner's timer: Sear the steak, 3:59 remaining."

Fixed all of these:
- The step-content area (illustration + instruction text, `StepView.swift`) is now one combined
  accessibility element labeled `"<progress>. <instruction>"` with an `.isButton` trait and a
  default `accessibilityAction` that advances — deliberately scoped to exclude `StepTimerControl`
  (kept as its own separately-focusable button) rather than combining the whole step, which would
  have swallowed it.
- The back button now labels itself "Back to recipe overview" or "Previous step" depending on
  which it actually does at the current index — matching, not just narrating, its real behavior.
- `HoldToFinishButton` gained a label ("Finish Recipe") and an `accessibilityAction` that calls
  `onFinish()` directly — a real alternate path around the hold gesture, added *alongside* it
  rather than replacing it, so the accidental-tap protection this button exists for (see its own
  doc comment) is unaffected for anyone not using VoiceOver.
- `StarRatingView` labels each interactive star ("3 stars") and, in its non-interactive readout
  mode (the recipe list row), combines all 5 into one "Rating: 4 out of 5 stars" — via a small
  `NonInteractiveSummary` `ViewModifier` rather than a conditional accessibility call, since the
  interactive mode's 5 buttons must stay individually focusable and the non-interactive mode's 5
  images must not. `DifficultyStarsView`/`SpiceLevelView` got the same combined-summary treatment
  unconditionally (they're always decorative, never individually interactive).
- `TimerStackView` chips and `StepTimerControl`'s cancel button now carry real
  `accessibilityLabel`/`accessibilityValue` text describing whose timer it is, what it's timing,
  and how much time is left (or that tapping cancels it).

**Testing**: this is view-layer-only, like every other SwiftUI-specific behavior in this app (§3) —
no `CookingAppCoreTests` coverage applies, and it can't be verified by `xcodebuild build` beyond
"compiles." No automated VoiceOver testing exists in this sandbox any more than XCUITest's own
touch automation does (see pass 12) — added to the manual verification checklist below instead.
135 → still 153/153 `CookingAppCoreTests` passing (no Core changes this pass); `xcodebuild build`
and `build-for-testing` for the full `CookingApp` scheme both **SUCCEEDED**.

**Added to the manual verification checklist** (§3): with VoiceOver on, confirm you can read
through and complete an entire solo recipe using only VoiceOver gestures — swipe to focus each
element, double-tap the step content to advance, double-tap the back button to go back a step or
leave, and use the Finish Recipe action (via the actions rotor) on the last step instead of the
hold gesture; separately confirm the star/difficulty/spice/timer-chip readouts announce a complete,
sensible sentence rather than a string of bare "star"/"flame"/digit fragments.

Sources consulted this pass:
- [User Experience Best Practices for Recipe Platforms](https://www.sidechef.com/business/recipe-platform/ux-best-practices-for-recipe-sites)
- [Best Features to Look for in Recipe Apps — OrganizEat](https://home.organizeat.com/blog/best-features-to-look-for-in-recipe-apps/)
- [Case Study: Perfect Recipes App — UX Design for Cooking and Shopping (Tubik Studio)](https://blog.tubikstudio.com/case-study-recipes-app-ux-design/)

### Pass 17 — dietary filter chips

Fourth iteration of the overnight autonomous run. Continuing the same web research that drove pass
16, "Advanced Filtering" was named directly — filtering by dietary preference, cooking time, or
skill level as an expected discovery feature. This app already gained free-text search in pass 14
(which does match dietary tag *labels*, e.g. typing "vegan" as a search term already worked), but a
one-tap, no-typing-required filter chip is the more standard, more discoverable form of that
specific check ("does this fit my restriction?") — search and chips solve different access
patterns, not the same one twice.

- **`Recipe.matchesDietaryFilter(_:)`** (`Recipe.swift`) — takes a `Set<DietaryTag>` and returns
  whether the recipe has *every* tag in it (`requiredTags.isSubset(of: Set(dietaryTags))`).
  Deliberately AND, not OR: someone filtering by both Vegan and Nut-Free has two real restrictions
  to satisfy together, not a preference for either one — OR semantics would surface a vegan recipe
  that isn't nut-free, which is exactly what this filter exists to prevent. An empty set matches
  every recipe (no filter applied).
- **`RecipeListView`** gained a horizontal row of toggleable chips (one per `DietaryTag`, always
  all 5 regardless of the current result set — standard filter-UI behavior, not narrowed to only
  tags something visible currently has), pinned above the list via `.safeAreaInset(edge: .top)` so
  it stays visible while scrolling rather than taking up a list row. `displayedRecipes` now applies
  this filter alongside favorites and search (favorites → search → dietary tags → sort, in that
  order); `canReorder` was widened again to also require `selectedDietaryTags.isEmpty`, the same
  "don't reorder against a filtered subset" guard as the favorites and search cases before it (see
  pass 14) — all three now flow through the identical `canReorder`/`displayedRecipes` pattern
  rather than each filter inventing its own variant of the same guard.

**Testing**: `RecipeModelTests.swift` gained a `matchesDietaryFilter` section — empty filter,
single-tag match/non-match, the AND-not-OR case (a recipe with only one of two required tags is
correctly excluded), and a recipe with extra tags beyond what's required still matching (superset is
fine). 153 → **158/158 CookingAppCoreTests passing**. Added
`testDietaryFilterChipHidesRecipesMissingTheTag` to `CookingAppUITests.swift` (selecting the
Vegetarian chip keeps Classic Scrambled Eggs, hides the non-vegetarian Pan-Seared Steak, and
un-hides it again on a second tap) — built successfully, not run, same sandbox limitation as every
UI test since pass 12. `xcodebuild build`/`build-for-testing` for the full `CookingApp` scheme —
both **SUCCEEDED**.

Sources consulted this pass (same search as pass 16 — see its write-up for the full list):
- [User Experience Best Practices for Recipe Platforms](https://www.sidechef.com/business/recipe-platform/ux-best-practices-for-recipe-sites)

### Pass 18 — an in-app shopping list

Fifth iteration of the overnight autonomous run, and the biggest single feature of it. The same web
research behind passes 16-17 named this directly: "automated grocery list generation is the feature
users consistently describe as the most practically useful" in a recipe app. Scoped down from
"automated" in the sense that research implies (parsing/merging quantities across units) to what
this app's ingredient data model can do honestly — see below — but the core value (don't retype your
ingredients onto a separate paper list) is the same.

- **`ShoppingListItem.swift`** (new, `CookingAppCore`) — a second `@Model` type alongside `Recipe`.
  Deliberately *not* a relationship back to the recipe it came from: a shopping list item is a
  snapshot of "I need to buy this," unaffected if the source recipe is later edited or deleted, so
  `sourceRecipeTitle` is plain display text, not a reference. `ShoppingListItem.itemsToAdd(for:
  scaleFactor:existingItems:)` is the actual logic: scales each ingredient by the recipe's current
  servings selection (reusing `Ingredient.scaledAmount(by:)` from pass 15 — the two features compose
  directly, so the list reflects what you'll actually buy for however many people you're cooking
  for) and skips any ingredient that already has an *unchecked* item on the list with the same name
  (case-insensitive) and amount, so re-tapping "Add to Shopping List" is idempotent rather than
  piling up duplicate rows. A checked-off item doesn't block a future re-add — once it's bought and
  checked, cooking the recipe again should let it back onto the list for next time. Deliberately
  does **not** attempt to merge different amounts of the same ingredient across recipes ("2 tbsp"
  from one recipe and "1/4 cup" from another stay two separate lines) — `Ingredient.amount` is free
  text (see its own doc comment, pass 15), and silently guessing a combined total would be dishonest
  in a way two separate correct lines aren't.
- **`ShoppingListView.swift`** (new) — a `@Query`-backed list, sectioned "To Buy" / "Checked Off",
  tapping a row toggles checked (strikethrough + secondary color), swipe-to-delete either section, a
  "Clear Checked" toolbar button. Presented as a sheet from a new cart toolbar button on
  `RecipeListView`, the same pattern `RecipeEditorView`/`WelcomeNameView` already use for a screen
  outside the core recipe-browsing/cooking navigation stack — not a `Route` case, since it doesn't
  need the `path` at all.
- **`RecipeDetailView.swift`** gained an "Add to Shopping List" toolbar button (cart-plus icon,
  briefly swaps to a checkmark for 1.5s as the only feedback that the tap did anything — the
  shopping list itself lives in a separate sheet, so without this there'd be no visible confirmation
  at all) that calls `ShoppingListItem.itemsToAdd` with the current `servingsScaleFactor`.
- **`CookingAppApp.swift`**: `ModelContainer` now also declares `ShoppingListItem.self` — needed for
  both the real on-device store and the `-UITesting` in-memory one.
- **A real environment gotcha hit and fixed this pass**: adding `ShoppingListView.swift` under
  `CookingApp/CookingApp/Views/` isn't enough by itself — this is an XcodeGen-generated project (see
  §2), so the new file didn't compile into the target until `xcodegen generate` was re-run from
  `CookingApp/`, exactly as §2's own instructions already say. Regenerating reset
  `project.pbxproj`'s `DEVELOPMENT_TEAM` signing setting (a locally-configured value, not tracked by
  `project.yml`) back to unset — caught by diffing the regenerated file against git before
  committing, and manually restored to its prior value. Worth remembering for next time: **any**
  `xcodegen generate` run in this repo will silently drop that local setting again, since
  `project.yml` doesn't declare it.

**Testing**: new `ShoppingListItemTests.swift` — empty-list add, scaling integration, same-recipe
re-add producing no duplicates, case-insensitive name dedup, a checked-off item not blocking re-add,
a different scale factor correctly *not* being treated as a duplicate, and the cross-recipe cases
(identical name+amount from two different recipes dedupes; different amounts of the same ingredient
from two different recipes do not merge or drop either one). 158 → **166/166 CookingAppCoreTests
passing**. Added `testAddToShoppingListAddsIngredientsAndClearingChecksThemOff` to
`CookingAppUITests.swift` — built successfully, not run, same sandbox limitation as every UI test
since pass 12. `xcodebuild build`/`build-for-testing` for the full `CookingApp` scheme — both
**SUCCEEDED**.

**Added to the manual verification checklist** (§3): add a recipe's ingredients to the shopping
list, change its servings first and confirm the added amounts reflect the new scale, check a few
items off, use "Clear Checked" and confirm only those disappear, and confirm re-adding the same
recipe at the same servings doesn't create duplicate rows while re-adding after clearing does.

### Pass 19 — food-safety content pass: citing safe internal temperatures for chicken

Sixth iteration of the overnight autonomous run, and the first to edit recipe *content* rather than
app code — directly acting on "look into recipes and cooking blogs to follow best practices" rather
than UX conventions this time. A web search confirmed current USDA safe minimum internal
temperatures (chicken/poultry 165°F, ground beef 160°F, whole-muscle beef/pork/lamb 145°F + a
3-minute rest, fish 145°F or "flakes easily/opaque"), then every bundled recipe's doneness wording
was checked against them.

**What was actually wrong**: every chicken-containing recipe (Chicken Stir-Fry — both its solo step
and its two-person Person B step, Chicken Caesar Salad — solo and Person A, Chicken Quesadillas —
solo and Person A) described doneness only as "cooked through," "until done," or "until browned,"
with no temperature at all. This isn't a style nitpick — color and texture are specifically *not*
reliable indicators for poultry doneness (unlike, say, a steak, where a thermometer is more about
hitting a preference than a hard safety line); USDA's own guidance is to always verify chicken with
a thermometer regardless of how it looks. Added "(165°F internal temperature)" (or equivalent
phrasing) to all 6 steps. Separately, `searedSteak`'s "Sear undisturbed, 3 minutes per side" got a
thermometer-check clause too ("...checking with a meat thermometer for your desired doneness (about
130°F for medium-rare, 145°F for medium)") — a fixed time alone doesn't account for steak thickness,
and a thermometer is strictly more reliable; this one cites a doneness-preference range rather than
a single safety minimum, since (unlike poultry) a seared whole-muscle steak has a legitimate
less-well-done range people actually want, and the recipe's own title/style (a quick garlic-butter
sear) targets exactly that. **Not touched**: `bakedSalmon`'s "roast until the salmon flakes easily"
— that's already the correct, standard USDA-endorsed alternative to a thermometer for fish, not a
gap.

**Testing**: added `chickenDonenessStepsCiteTheSafeInternalTemperature` to `RecipeModelTests.swift`
— scans every bundled recipe's solo and two-person steps for chicken + a doneness phrase
("cooked through"/"until done"/"until browned") and asserts "165" appears in that same instruction.
This is a real regression guard, not a one-off check: a future recipe added by copying an existing
step's phrasing (the way this app's content has always grown) will fail this test immediately if it
drops the temperature, rather than silently shipping a food-safety gap. 166 → **167/167
CookingAppCoreTests passing**. `xcodebuild build` for the full `CookingApp` scheme — **SUCCEEDED**
(content-only change; no view code touched, so `build-for-testing` wasn't re-run this pass).

One flaky, non-reproducing `swift test` run happened mid-pass (reported "failures" with 0 tests
executed and 0 actual failures shown) — matches the iCloud-sync build flakiness this repo hit before
(pass 9's note on building with `--scratch-path` outside the iCloud-synced folder); a second run
immediately after passed cleanly at 167/167. Worth knowing if a run ever reports a failure with no
failing test named: rerun once before assuming a real regression.

Sources consulted this pass:
- [Cooking Meat: Is It Done Yet? — USDA](https://www.usda.gov/about-usda/news/blog/cooking-meat-it-done-yet)
- [Safe Minimum Internal Temperature Chart — USDA Food Safety and Inspection Service](https://www.fsis.usda.gov/food-safety/safe-food-handling-and-preparation/food-safety-basics/safe-temperature-chart)

## 4. Known pitfalls

- **A "mirror mode" was tried and then removed.** An earlier pass let two-person mode work on
  *any* recipe by mirroring the full solo step list to both phones when there was no real split.
  On review this was the wrong call: it invited a two-person session that looked shared but wasn't
  (identical instructions on both phones, no actual division of labor), and switching a curated
  two-person recipe down to "one person" reused the two-person wording verbatim, including
  "Both:" phrasing and personA/personB hue tinting that made no sense for a lone cook. Replaced
  with two genuinely separate, independently-authored step lists (`soloSteps`/`twoPersonSteps`)
  and no toggle at all for recipes without a real split.
- **Local Network permission** must be accepted on both phones or discovery silently fails
  (Settings → Privacy & Security → Local Network → Cooking App).
- **Two-person mode can't be validated in the Simulator** (no Bluetooth radio) — needs two
  physical iPhones for real confidence.
- **Recipe IDs are fixed UUID literals**, not random — random per-launch IDs would break the
  host/joiner `recipeID` handshake. Give any new sample recipe a fixed ID too.
- **Reconnection doesn't survive real backgrounding** — auto-reconnect covers a brief drop while
  both apps stay foregrounded/backgrounded-but-alive, but iOS suspends most app networking within
  seconds of backgrounding; true background survival needs declared background modes (see Next
  Steps). "Resume Cooking" also only survives within one process's lifetime, not a force-quit.
- **Notification permission is requested at app start, not lazily.** If it's denied, timers
  silently fall back to in-app-only with no visible indication in the UI that the background case
  is being missed.
- **Only *my own* timers get notifications, not the partner's mirrored ones** — scoped this way
  deliberately, matching the stated problem ("I might miss my own timer," not "I want to be
  notified about my partner's").
- **The `leaveSession` message is best-effort** — sent right before disconnecting, with no
  ack/retry, so it isn't guaranteed to arrive if the connection is already degrading.
- **The system edge-swipe-back gesture is disabled specifically on `StepView`**
  (`SwipeBackDisabler.swift`) so an accidental edge swipe can't pop out of an active two-person
  session; restored automatically on leaving that screen.
- **SF Symbol names weren't visually verified** (no Xcode/SF Symbols app in this sandbox) — a
  wrong name renders blank at runtime rather than failing to build; spot-check icons, especially
  `frying.pan.fill` and the dietary-tag icons.
- **Free Apple ID signing expires** roughly every 7 days without a paid developer account.
- **"Stepped away" is a UI-only signal, not a real disconnect** *(pass 7)* — `presenceUpdate`
  travels over the same live connection; if the connection has *actually* dropped you'll see
  `.disconnected` (red), not "stepped away" (muted blue). Don't confuse the two when debugging.
- **The cook name defaults to `"Cook"`** *(pass 7)* if a connect screen is somehow reached with an
  empty `@AppStorage("cookName")` (shouldn't happen — the welcome sheet is non-dismissable without
  entering one — but there's no separate validation at the connect screen itself).
- **The app icon and step/recipe "photos" are both placeholder-quality** *(pass 7)* — the icon is a
  hand-drawn Pillow script (`Scripts/generate_app_icon.py`), and per-*step* art is still
  `PlaceholderPhotoView`'s gradient-plus-SF-Symbol card, not real photography — only recipe-level
  hero photos got real images, in pass 8. Both exist to make the *shape* of "a real icon"/"a real
  photo" visible where nothing real exists yet, not to be final assets everywhere.
- **A device that already had the original 8 recipes won't retroactively get their photos**
  *(pass 8, fixed differently in pass 9)* — pass 9's additive `RecipeSeeder` means a *new* bundled
  recipe (or one this device never had before) now reaches an existing install fine, but a recipe
  already present is still never refreshed — by design, since refreshing it would also wipe any
  favorite/rating/notes/cook-count the user had already set on it. A device that seeded the
  original 8 before photos existed still needs an uninstall/reinstall to see photos on *those*
  specific 8 rows; every recipe added from pass 9 onward arrives automatically.
- **Reordering only works with the favorites filter off** *(fixed more robustly in pass 13 — see
  its write-up in §3)* — turning on "Favorites only" while sorted by "My Order" hides the drag
  handles (rather than switching your sort mode away, as an earlier version of this did); dragging
  within a filtered subset would otherwise scramble the full ordering for whatever's hidden. Turn
  the filter off to reorder the complete list; the sort Picker still reads "My Order" the whole
  time.
- **Swipe-to-favorite, drag-to-reorder, and the recipe editor's row add/remove/reorder were never
  verified with a real touch** *(pass 9/10)* — all compiled and the surrounding UI (toolbar
  controls, drag handles, row content, the New Recipe form) was confirmed to render via
  screenshot, but none of the actual gestures could be exercised without accessibility automation
  or an XCUITest target, neither of which exists in this sandbox. Worth a deliberate check on a
  real device.
- **You can't edit a bundled recipe, or delete any recipe that isn't your own** *(pass 10)* — both
  are deliberate scope decisions, not oversights (see pass 10's write-up in §3 and §5's items 2/3
  for the reasons — curated content and the missing seeder tombstone, respectively), but worth
  knowing if you go looking for an edit/delete option on one of the original 20 and don't find it.
- **`RecipeStep`/`Ingredient` are mutable now** *(pass 10)* — changed from `let` to `var` stored
  properties so `RecipeEditorView`'s SwiftUI bindings could compile. Nothing relies on their
  immutability elsewhere today, but it's no longer enforced by the type system either — a future
  change that mutates a step/ingredient somewhere unexpected (rather than constructing a fresh one,
  the convention everywhere else in the codebase) wouldn't be caught at compile time.
- **`CookingAppUITests` exists but has never actually run** *(pass 12)* — it builds, compiles, and
  links correctly, but `xcodebuild test` stalls indefinitely at "loading Accessibility" during
  test-runner bootstrap in this sandbox, before any test executes. Looks like a sandbox/headless
  limitation (no real window server for the Simulator's UI-automation layer to hook into) rather
  than a problem with the test code — see pass 12's write-up in §3. Try running it from a normal
  interactive Mac (Xcode ⌘U) before assuming the tests themselves are broken.
- **Before pass 12, no automated UI testing existed at all** *(passes 1-11)* — verification for
  anything that couldn't be driven from `CookingAppCoreTests` relied on hand-review or a temporary,
  fully-reverted debug hack in `RecipeListView` to auto-navigate to a screen for a screenshot (see
  pass 7's note in §3) — there was no accessibility automation (`osascript`/System Events) or
  XCUITest target in this sandbox at all until pass 12 (see above for its current status).
- **VoiceOver support was never actually audited before pass 15/16** — this sandbox's own lack of
  accessibility automation (see above) meant the existing `accessibilityIdentifier`s (added starting
  pass 12, for XCUITest *element addressing*) could be mistaken for real screen-reader support, but
  they're a different concern entirely: an `accessibilityIdentifier` is invisible to VoiceOver users,
  only to test code. Pass 16 audited and fixed `StepView` and its subcomponents specifically (see its
  write-up in §3) — other screens (`RecipeListView`, `RecipeDetailView` outside the servings
  stepper/ingredients row, `PeerConnectionView`, `WelcomeNameView`, `RecipeEditorView`) haven't had
  the same audit yet and may have similar gaps.
- **`xcodegen generate` silently resets the local `DEVELOPMENT_TEAM` signing setting** *(hit in
  pass 18)* — it's a value someone sets locally in Xcode (see §2 step 2), not declared anywhere in
  `project.yml`, so every regeneration drops it back to unset. Necessary any time a new source file
  is added under `CookingApp/CookingApp/` (§2's own instructions already say this) or `project.yml`
  changes — after running it, check `git diff` on `project.pbxproj` for a removed `DEVELOPMENT_TEAM`
  line before committing, and re-add it (or just re-select your team in Xcode's Signing &
  Capabilities) if it's gone.

## 5. Next steps (explicitly deferred)

1. **~~More recipes~~ — done (pass 9), 8 → 20.** Still nothing stopping more being added the same
   way; since pass 10, this doesn't have to be a code change anymore either — see next item.
2. **~~In-app recipe creation/editing UI~~ — done (pass 10), for user-created recipes.** Still open:
   editing a *bundled* recipe's content, and deleting a bundled recipe at all — both need more than
   `RecipeEditorView` does today. Deletion specifically still needs `RecipeSeeder` to grow a
   tombstone (e.g. a stored set of deleted bundled ids) before it could safely apply to bundled
   recipes — pass 9's additive-by-id seeding means a deleted bundled recipe would otherwise just
   come back on the next launch. Not a problem yet, since deletion is scoped to user-created
   recipes only, which the seeder never looks at.
3. **A two-person split editor** — `RecipeEditorView` (pass 10) only creates solo recipes. A real
   split is hand-divided labor, not something to auto-generate from a solo step list; if this is
   ever wanted, it'd need a deliberately different editing flow, not an extension of the current
   form.
4. **AI-assisted recipe-to-two-person conversion** — flagged as a good idea for once there's
   budget for it; explicitly skipped for now since it costs money (see §6).
5. **Per-step photos** — recipe-level hero photos are done (pass 8), but every step still shows
   `PlaceholderPhotoView`'s gradient-plus-SF-Symbol card. Deliberately out of scope for pass 8's
   smaller first cut (~60-90 images vs. 8) — same fetch/install pipeline could extend to steps if
   it's worth the larger sourcing effort.
6. **True background reconnection** — declared background modes so a two-person session survives
   more than a brief backgrounding.
7. **~~Curated two-person splits~~ — done for 4 more recipes in pass 11 (9 → 13 of 20).** The
   remaining 7 solo-only recipes (Scrambled Eggs, Pan-Seared Steak, Grilled Cheese, Simple Tomato
   Soup, Caprese Salad, Banana Pancakes, Avocado Toast with Fried Egg) were deliberately left
   solo-only — each is single-station, too quick, or single-serving to begin with — not overlooked.
   Still true for any future recipe: no two-person option until one is genuinely worth authoring
   for it (see the removed-mirror-mode pitfall above for why).
8. **A sturdier leave/rejoin protocol** — an ack for `leaveSession`, and reusing a specific prior
   peer connection on reconnect rather than the current "any peer that shows up" auto-invite.
9. **CloudKit/iCloud sync**, for two-person mode over the internet and cross-device recipe sync —
   and now a more natural fit, since recipes already live in a real SwiftData store.
10. **Accounts, recipe sharing, Android** — still explicitly out of scope.
11. **~~An XCUITest target~~ — built in pass 12, but never successfully run in this sandbox** (see
    pass 12's write-up in §3 for why — looks like an environment limitation, not a code problem).
    Actually running `CookingAppUITests` (Xcode ⌘U, or `xcodebuild test`, on a normal interactive
    Mac) is the immediate next step, before writing more tests against it. Once it's confirmed
    working, the natural next expansion is coverage for the step screen (timers, hold-to-finish,
    swipe nav) and the two-person flow, which pass 12 didn't attempt.
12. **A real, designed app icon** *(pass 7)* — still hand-drawn placeholder quality (see the
    pitfalls list); swap in real branding whenever you have it. (Recipe hero photos are real now,
    as of pass 8 — see item 5 above for what's still placeholder-quality: per-step art.)
13. **Editable cook name / role after first launch** *(pass 7)* — the name is set once at first
    launch with no settings screen to change it later, and the host's Person A/B choice is made
    fresh each time you host rather than remembered from last time.
14. **Hero photos for the 12 recipes added in pass 9** — same `fetch_recipe_photos.py` /
    `install_recipe_photo.py` pipeline from pass 8, just not run yet for the new recipes (no
    Pexels key available this pass). They show the placeholder card in the meantime, same as
    every recipe did before pass 8.
15. **Verify real-touch interactions on a real device** *(pass 9/10)* — swipe-to-favorite,
    drag-to-reorder in "My Order," and the recipe editor's add/remove/reorder ingredient and step
    rows are all unverified beyond "the surrounding UI renders and compiles" (see the pitfalls
    list) — this sandbox has no way to inject a real touch/drag gesture.
16. **A settings/about screen for personal notes and ratings at a glance** — right now
    "My Notes" only exists per-recipe on the detail screen; there's no cross-recipe view like "all
    my 5-star recipes" beyond the Top Rated sort mode, and no way to see/edit notes without
    opening each recipe individually.

## 6. UX/product iteration ideas & direction


- **The step illustration is the same size/prominence for every step regardless of content** — a
  5-minute rest and a "sear 3 min per side, don't touch it" step have very different "what do I
  need to see" needs; the layout doesn't distinguish them.
- ~~**Nothing scales ingredient quantities to a different serving count**~~ — done (pass 15): a
  servings stepper on the detail screen scales each ingredient's leading numeric quantity live.
- **The partner's connection-state dot (green/yellow/red) has no explanation on tap.**
- **No confirmation before "Start Cooking" leaves the overview screen** — for an unfamiliar
  recipe, a brief "you won't see the full ingredient list again until you finish" nudge might help.
- **Difficulty and spice level are my own back-of-envelope calls**, not calibrated against
  anything — worth a real rubric (or user ratings) once there's more than 8 recipes.

### Product-direction interview (pass 4)

- **Real usage so far**: tried briefly / simulated a cook-through, went smoothly.
- **Hands-free control (Siri/Watch)**: explicitly not wanted right now — tap/swipe/hold stays the
  interaction model.
- **Long-term audience**: personal use for now, but might want to share it eventually — worth
  keeping in mind for later (signing/distribution, review-quality permission strings) without
  acting on it yet.
- **Top priority named**: timer notifications — implemented that same pass.

### Current direction (pass 5)

Explicitly requested, in order: build a real persistence layer ("the memory") — **done this
pass**, `Recipe` is now a SwiftData `@Model`, see §1 — *then* add more recipes next, with
AI-assisted recipe-to-two-person conversion flagged as a good idea for later but skipped now since
it'd cost money. Also asked directly whether generating step illustrations
is reasonable to ask of me — answered in-session: I have no image-generation tool available in
this environment, so I can't produce the artwork myself; I can build whatever asset pipeline is
needed to wire in real images once you have them (AI-generated elsewhere, stock, or your own),
same as the `imageSystemName` pipeline already works today.

### Current direction (pass 7)

Driven by a batch of concrete real-usage feedback rather than a single planned theme — see the
Pass 7 write-up in §3 for the full list and the three ambiguous points that were confirmed up front
(role-toggle mechanism, when to ask for a name, and whether "leaving the recipe" should end a
two-person session — it doesn't, by direction; it shows "stepped away" instead). Also asked
directly for a simple app icon and a placeholder for what real step images would look like —
same "no image-generation tool available" situation as pass 5, answered by hand-drawing a plain
icon with Pillow and a gradient-card placeholder view instead (see §1/§4) rather than not
delivering anything visual at all.

### Current direction (pass 8)

Wanted to start incorporating real images, but explicitly thought out loud first about sourcing
tradeoffs (AI generation vs. self-shot vs. community vs. stock) rather than picking one blind.
Decided, in order: recipe-level hero photos only for now (not per-step — a much bigger job, not
worth taking on before the smaller pipeline is proven out), sourced from free stock photos (Pexels)
rather than a paid AI image API or self-shooting. Confirmed up front via two questions before
building anything (scope, then source). The pipeline was built, then actually run the same pass:
you fetched candidates with your own Pexels key, hand-picked one winner per recipe, and all 8 are
now wired in and visually verified — see pass 8's write-up in §3 for the full detail.

### Current direction (pass 9)

Three things raised together: pass 8's photos not showing up on a real iPhone, a request for
20+ recipes, and a request for a way to save/order/rate/note recipes — then asked to work
autonomously and thoroughly for an extended stretch rather than checking in after each piece.
Treated as one pass covering all three, in dependency order: diagnosed and fixed the real-device
bug first (it turned out to be the exact stale-store caveat pass 8 had already flagged, but a
device having *ever* run an earlier build is a real scenario, not a hypothetical, so it needed an
actual fix — see the seeder rewrite above — not just a documented workaround), then built the
favorites/rating/notes/cook-history feature (a genuine product decision on data shape and UI that
needed real design, not just following an existing pattern), then added the 12 new recipes last,
since they were the most mechanical of the three and benefited from the seeder fix already being
in place. See pass 9's write-up in §3 for the full detail, including a real SwiftData
cross-container hazard hit while testing the seeder change, and an unrelated iCloud-sync build
issue hit and worked around along the way.

### Current direction (pass 10)

Same extended autonomous session as pass 9, continuing rather than stopping once pass 9's three
explicit requests were done — moved to the next item on §5's own next-steps list: in-app recipe
creation/editing, previously a "you'd have to edit Swift source" limitation ever since the pass-5
persistence layer was built specifically to remove exactly that limitation. Deliberately scoped
down from "full recipe CRUD" to "create/edit/delete a recipe you made in the app" — editing a
bundled recipe's authored content and deleting one at all were both left out, for reasons specific
to each (see §5's items 2/3 and pass 10's write-up in §3) rather than just running out of time for
them.

### Current direction (pass 11)

Same session again — moved to §5's next remaining item that didn't need an external dependency
(no Pexels key for more photos, no real device for background-mode/touch-gesture verification):
curated two-person splits for the recipes still missing one. Exercised the same judgment the
project has used since the mirror-mode removal — split where it genuinely helps, leave the rest
solo-only rather than mechanically splitting all 11. See pass 11's write-up in §3 for which 4 got
one and why the other 7 didn't.

### Current direction (pass 12)

Same session, moved to the XCUITest target next — explicitly on the roadmap since pass 7, and the
direct fix for a real, accumulating gap: every pass from 7 through 11 had at least one interaction
it could only confirm "renders correctly," never "actually works," for lack of any way to drive a
real touch. Built the target, wrote 4 tests covering exactly that backlog (swipe-to-favorite,
the add-recipe flow, favorite-toggle reactivity, list→detail navigation), and got it to build and
link correctly — then hit a wall actually running it: an immediate stall in the Simulator's own
accessibility/automation bootstrap, independent of (and before) a separate low-memory condition on
the host machine itself. Decided not to keep retrying a resource-intensive operation against a real
low-memory signal from the actual laptop this session runs on — landed the infrastructure as real,
usable groundwork instead, documented plainly as un-run rather than claimed as verified.

### Current direction (pass 13)

With the simulator having just shown real resource limits (pass 12), switched to work that needed
neither it nor heavy compute: an actual review of everything built across passes 9-12, rather than
more building. Fixed what the review found to be real (a data-corruption bug, a crash risk, two
smaller gaps) and explicitly declined to fix what wasn't worth the churn right now (a
premature-optimization suggestion, a stylistic duplication) — recorded with reasoning in pass 13's
write-up in §3 either way, so "why wasn't this fixed" has an answer instead of silence.

### Current direction (pass 14 — unattended overnight run)

Different framing from every pass before it: not a specific feature request or a targeted review,
but a standing instruction to keep making autonomous, iterative progress for an extended, unattended
stretch — self-pacing across multiple loop iterations, generating tests, improving day-to-day feel,
and drawing on general cooking-app/recipe-blog conventions for what to prioritize, with nobody
available to answer questions or notice a stalled/resource-heavy operation mid-run. That shaped the
approach as much as the specific features did: verification stayed to `swift test`/`xcodebuild
build`/`build-for-testing` only (see pass 12's memory-pressure note — this session shares the actual
laptop, not a disposable sandbox), and each iteration was picked to be small, independent, and
reversible rather than one large multi-part change. First iteration: recipe search (a real, growing
gap — nothing let you find a recipe by name or ingredient once there are 20+ of them) and disabling
the idle timer specifically on the step screen (an near-universal cooking-app convention this app
was missing, for the concrete reason that messy hands + an auto-locking screen mid-recipe is a real
interruption). See pass 14's write-up in §3 for what shipped and how it was verified. Later
iterations of this same overnight run, if any, continue below this entry rather than each getting
their own numbered pass — check git log for the granular history.

## 7. Git / repo

The project is a proper git repo, pushed to GitHub: https://github.com/yahiaelsamman/cooking-app
(private). `~/.gitignore` (a git repo rooted at the home directory, unrelated to this project)
excludes the whole `Desktop/` folder, so `cooking_app` wasn't tracked by *any* repo before this —
fixed by `git init`-ing a repo scoped to `cooking_app/` itself, with its own `.gitignore`
(`.build/`, `.swiftpm/`, Xcode user data), committing, and pushing via `gh repo create --push`.
The outer home-directory repo is untouched.
