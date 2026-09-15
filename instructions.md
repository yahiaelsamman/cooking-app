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
- **Reordering ("My Order") always operates on the full recipe list, not the filtered one** —
  turning on the favorites-only filter while sorted by "My Order" switches you to "A–Z" instead of
  letting you drag within the filtered subset, since that would scramble the full ordering for
  whatever's hidden. Switch favorites off to reorder the complete list.
- **Swipe-to-favorite and drag-to-reorder were never verified with a real touch** *(pass 9)* — both
  compiled and the surrounding UI (toolbar controls, drag handles, row content) was confirmed to
  render via screenshot, but neither gesture itself could be exercised without accessibility
  automation or an XCUITest target, neither of which exists in this sandbox. Worth a deliberate
  check on a real device.
- **No automated UI testing exists** *(all passes)* — verification for anything that can't be
  driven from `CookingAppCoreTests` (a full app build, screen-by-screen rendering) has relied each
  pass on either hand-review or a temporary, fully-reverted debug hack in `RecipeListView` to
  auto-navigate to a screen for a screenshot (see pass 7's note in §3) — there's still no
  accessibility automation (`osascript`/System Events) or XCUITest target in this sandbox (see
  Next Steps).

## 5. Next steps (explicitly deferred)

1. **~~More recipes~~ — done (pass 9), 8 → 20.** Still nothing stopping more being added the same
   way; still no in-app authoring UI (see next item), so any further additions are still a code
   change, not something done from the app itself.
2. **In-app recipe creation/editing/deletion UI** — the persistence layer (§1) supports it; there's
   still no UI for it. Whichever pass adds *deletion* specifically needs to also give
   `RecipeSeeder` a tombstone (e.g. a stored set of deleted bundled ids) — pass 9 made seeding
   additive-by-id specifically so new bundled recipes reach existing installs, but that same
   change means a deleted bundled recipe would silently come back on the next launch without a
   tombstone to check against. Harmless today only because deletion doesn't exist yet.
3. **AI-assisted recipe-to-two-person conversion** — flagged as a good idea for once there's
   budget for it; explicitly skipped for now since it costs money (see §6).
4. **Per-step photos** — recipe-level hero photos are done (pass 8), but every step still shows
   `PlaceholderPhotoView`'s gradient-plus-SF-Symbol card. Deliberately out of scope for pass 8's
   smaller first cut (~60-90 images vs. 8) — same fetch/install pipeline could extend to steps if
   it's worth the larger sourcing effort.
5. **True background reconnection** — declared background modes so a two-person session survives
   more than a brief backgrounding.
6. **Curated two-person splits for the 5 currently-solo recipes**, if any turn out to split
   sensibly in practice — not guessed at; a recipe simply has no two-person option until one is
   deliberately authored for it (see the removed-mirror-mode pitfall above for why).
7. **A sturdier leave/rejoin protocol** — an ack for `leaveSession`, and reusing a specific prior
   peer connection on reconnect rather than the current "any peer that shows up" auto-invite.
8. **CloudKit/iCloud sync**, for two-person mode over the internet and cross-device recipe sync —
   and now a more natural fit, since recipes already live in a real SwiftData store.
9. **Accounts, recipe sharing, Android** — still explicitly out of scope.
10. **An XCUITest target**, now that full Xcode is available (§3) — the natural next step for
    verification is tapping through the actual app (recipe → detail → step screen → timers →
    hold-to-finish) rather than only confirming it builds and the list screen renders, and would
    replace pass 7's temporary-debug-hack approach to screenshotting new screens.
11. **A real, designed app icon** *(pass 7)* — still hand-drawn placeholder quality (see the
    pitfalls list); swap in real branding whenever you have it. (Recipe hero photos are real now,
    as of pass 8 — see item 4 above for what's still placeholder-quality: per-step art.)
12. **Editable cook name / role after first launch** *(pass 7)* — the name is set once at first
    launch with no settings screen to change it later, and the host's Person A/B choice is made
    fresh each time you host rather than remembered from last time.
13. **Hero photos for the 12 recipes added in pass 9** — same `fetch_recipe_photos.py` /
    `install_recipe_photo.py` pipeline from pass 8, just not run yet for the new recipes (no
    Pexels key available this pass). They show the placeholder card in the meantime, same as
    every recipe did before pass 8.
14. **Verify swipe-to-favorite and drag-to-reorder on a real device** *(pass 9)* — both are
    unverified beyond "the surrounding UI renders and compiles" (see the pitfalls list) — this
    sandbox has no way to inject a real touch/drag gesture.
15. **A settings/about screen for personal notes and ratings at a glance** — right now
    "My Notes" only exists per-recipe on the detail screen; there's no cross-recipe view like "all
    my 5-star recipes" beyond the Top Rated sort mode, and no way to see/edit notes without
    opening each recipe individually.

## 6. UX/product iteration ideas & direction


- **The step illustration is the same size/prominence for every step regardless of content** — a
  5-minute rest and a "sear 3 min per side, don't touch it" step have very different "what do I
  need to see" needs; the layout doesn't distinguish them.
- **Nothing scales ingredient quantities to a different serving count** — `servings` is displayed
  but not adjustable.
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

## 7. Git / repo

The project is a proper git repo, pushed to GitHub: https://github.com/yahiaelsamman/cooking-app
(private). `~/.gitignore` (a git repo rooted at the home directory, unrelated to this project)
excludes the whole `Desktop/` folder, so `cooking_app` wasn't tracked by *any* repo before this —
fixed by `git init`-ing a repo scoped to `cooking_app/` itself, with its own `.gitignore`
(`.build/`, `.swiftpm/`, Xcode user data), committing, and pushing via `gh repo create --push`.
The outer home-directory repo is untouched.
