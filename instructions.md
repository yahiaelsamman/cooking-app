# Cooking App — Implementation Notes

MVP of a step-by-step recipe navigator for iOS, built with SwiftUI. The core idea: a recipe is
a sequence of discrete steps shown one at a time, full-screen, tap-to-advance — easy to follow
mid-cook with messy hands, instead of scanning a wall of text. Some recipes also support a
**two-person mode**, splitting into a Person A track and a Person B track, with two nearby
iPhones syncing progress live over `MultipeerConnectivity` (no internet, no accounts, no backend).

Repo: https://github.com/yahiaelsamman/cooking-app

See `/Users/yahiaelsaman/.claude/plans/tranquil-wishing-deer.md` for the original approved plan
(the initial MVP build). This document covers five build passes since; where something from an
earlier pass was later changed, only the current behavior is described below — check git history
for the specifics of what changed when.

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
- **`SyncMessage.swift`** — wire protocol, 5 message types: `recipeSync`, `progressUpdate`,
  `timerStarted`, `timerCancelled`, `leaveSession`. Carries only indices/IDs, never text.
- **`PeerSyncService.swift`** — wraps `MCSession`/`MCNearbyServiceAdvertiser`/
  `MCNearbyServiceBrowser`. Auto-reconnects on an unexpected drop (restarts advertising/browsing);
  `leaveSession()` is a **deliberate** end — sends a best-effort `leaveSession` message, then
  `stop()`s with no auto-reconnect. Every delegate callback (`didChange:`, `didReceive:`,
  `foundPeer:`, `lostPeer:`) is a thin `DispatchQueue.main.async` wrapper around an `internal`
  synchronous handler (`handleSessionStateChange`, `handleReceivedMessage`, `handleFoundPeer`,
  `handleLostPeer`) — this is what makes `PeerSyncServiceTests` possible without any real
  networking (see §3).
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
- **`ActiveSessionStore.swift`** — holds a reference to whatever `CookingSessionViewModel` is
  currently in progress, independent of navigation. Lets the recipe list show a "Resume Cooking"
  button that jumps back into the *same* session object — see the "resume" note below for why
  that's what makes Person A/B role preservation work.
- **`PeerConnectionViewModel.swift`** — host/join connection screen logic.
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
  recipe or start a timer.
- **`RecipeDetailView.swift`** — a **Solo / Two-Person segmented picker** appears *only* when
  `recipe.supportsTwoPerson`; a recipe without a two-person version shows no toggle at all. The
  displayed cook time updates live with the picker (`recipe.cookTimeMinutes(forTwoPerson:)`), and
  the steps-overview section switches between the solo read-through and the Together/Person
  A/Person B grouping depending on the selection. `startCooking()` branches on the picker.
  Registers the new session with `ActiveSessionStore` before pushing (solo path).
- **`PeerConnectionView.swift`** — on a successful handshake, also registers the new session with
  `ActiveSessionStore` (the two-person equivalent of the above).
- **`StepView.swift`** —
  - **Hold-to-finish**: the final step no longer completes on a plain tap/swipe. A dedicated
    `HoldToFinishButton` (currently a 1-second hold, animated ring) appears instead; the ordinary
    back button stays available alongside it, not replaced by it. The completion screen still has
    "Go Back" for a genuine accidental hold.
  - **`TimerStackView`**: every timer running somewhere other than the currently-viewed step —
    yours (orange chips) and your partner's (blue chips) — each labeled with the task it's timing.
  - **"End Session"** toolbar button (two-person only, hidden once already ended), with a
    confirmation dialog; calls `session.endSharedSession()`.
  - An alert when `session.partnerDidLeave` flips true, clearing `ActiveSessionStore` and
    resetting the nav path back to the recipe list on acknowledgement.
  - Notification scheduling: wires `session.onTimerScheduled`/`onTimerUnscheduled` to
    `NotificationScheduler.schedule`/`cancel`; `onTimerFinished` also cancels the pending
    notification (the in-app alert already covers that case) alongside showing the alert/haptic.
- **`HoldToFinishButton.swift`**, **`DualProgressSliderView.swift`**, **`TimerStackView.swift`** —
  the controls described above.
- **`PartnerStatusView.swift`** — renders `DualProgressSliderView` beneath the partner-step
  readout whenever connected.
- **`StepTimerControl.swift`** — the per-step tappable timer icon, built on the stacking API
  (`activeTimer(for:)`/`cancelTimer(for:)`).
- **`Notifications/NotificationScheduler.swift`** — schedules/cancels a local notification per
  step timer, keyed by the step's own id (so stacked timers each get an independent notification).
- **`Notifications/NotificationDelegate.swift`** — a `UNUserNotificationCenterDelegate` that
  suppresses the system banner/sound while the app is foregrounded (`willPresent` →
  `completionHandler([])`), since that case already gets the in-app alert — stops you from seeing
  both for the same event.
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

**67/67 tests passed** when last run in this session (`swift test` from `CookingAppCore/`), across
four files:

- **`RecipeModelTests.swift`** — solo/two-person step-list integrity (contiguous ordering per
  list, solo steps never say "Both:"), track filtering, `supportsTwoPerson`, mode-specific cook
  time (including the "two-person is always faster than solo" regression guard), timer stacking,
  and recipe metadata range checks.
- **`SyncMessageCodingTests.swift`** — Codable round-trips for all 5 message types.
- **`PeerSyncServiceTests.swift`** — connection state transitions, auto-reconnect triggering after
  a prior successful connection vs. *not* triggering on a first-ever drop or after a deliberate
  `leaveSession()`, every inbound message type's handling, and peer discovery/loss bookkeeping —
  all via the `internal` synchronous handlers, no real MultipeerConnectivity session needed. (One
  real bug this caught while writing the tests: `MCPeerID` equality isn't just display-name
  comparison — two separately-constructed instances with the same name aren't `==`. Every test
  constructs its peer id exactly once and reuses that instance, never a fresh one.)
- **`CookingSessionViewModelTests.swift`** — partner-timer mirroring resolved against the
  partner's own track (not mine), `partnerProgressFraction`'s track-length normalization,
  `partnerDidLeave` firing only from an *incoming* leave, local navigation continuing after ending
  a shared session, `ActiveSessionStore`, and the notification-scheduling hooks.

Notification *delivery* itself (`NotificationScheduler`/`NotificationDelegate`, both in the App
target) isn't unit-tested — `UNUserNotificationCenter` needs a real app process/authorization
state to do anything meaningful, so this is a manual-verification item, not something
`CookingAppCoreTests` could cover even if it lived in Core.

Why the timer's real 1-second countdown-to-zero isn't itself unit-tested: Foundation's `Timer`
needs an actively-spinning `RunLoop`, which the app's main run loop provides but a `swift test`
process's threading model doesn't reliably guarantee — a test that could silently hang isn't worth
the coverage. State transitions (`startTimer`/`cancelTimer`/stacking) are tested deterministically
instead; the actual countdown-to-alert behavior is a manual check (below).

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

**Manual verification checklist** (needs a real device/Xcode):

- Solo: tap-to-advance, swipe-to-advance/back, back button, hold-to-finish on the last step,
  "Go Back" from the completion screen, starting/cancelling a timer, two timers stacked at once,
  "Resume Cooking" after backgrounding and returning.
- The Solo/Two-Person picker: confirm it's **absent entirely** on the 5 solo-only recipes, and
  that switching it on the 3 dual-mode recipes changes both the displayed cook time and the steps
  list (no "Both:" phrasing or personA/personB hue tint in Solo mode).
- Two-person: Local Network permission prompt, host/join handshake, the dual progress slider
  moving as each phone advances, a timer started on one phone appearing (with its task label) as
  a blue chip on the other, "End Session" tearing down both sides, auto-reconnect after toggling
  Airplane Mode on one phone and back, resuming a two-person session via "Resume Cooking" with
  roles intact.
- **Notifications**: accept the permission prompt at app launch (or check Settings →
  Notifications → Cooking App if it was missed/denied); start a timer, background the app or lock
  the phone, and confirm the notification arrives with the right step's text at roughly the right
  time; separately, start a timer and stay in the app until it finishes, and confirm you see
  *only* the in-app alert, not a system banner too.

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
- **Host is always Person A, joiner is always Person B** — no role-swap UI.
- **Free Apple ID signing expires** roughly every 7 days without a paid developer account.

## 5. Next steps (explicitly deferred)

1. **More recipes**, now that they land in a real store rather than needing new Swift code per
   recipe — explicitly next, per the direction in §6.
2. **In-app recipe creation/editing UI** — the persistence layer (§1) supports it; there's no UI
   for it yet, since this pass only seeded seed data, it didn't add a way to add/edit from the app.
3. **AI-assisted recipe-to-two-person conversion** — flagged as a good idea for once there's
   budget for it; explicitly skipped for now since it costs money (see §6).
4. **Real illustrations/photos** — SF Symbols were a deliberate MVP choice; swapping in real art
   is a data-shape change (`imageSystemName: String` → an asset name or URL) plus a pipeline, not
   just new files. Also see §6 — you asked directly whether this is reasonable to hand to me.
5. **True background reconnection** — declared background modes so a two-person session survives
   more than a brief backgrounding.
6. **Curated two-person splits for the 5 currently-solo recipes**, if any turn out to split
   sensibly in practice — not guessed at; a recipe simply has no two-person option until one is
   deliberately authored for it (see the removed-mirror-mode pitfall above for why).
7. **Role selection UI** — let two people swap who's "Person A."
8. **A sturdier leave/rejoin protocol** — an ack for `leaveSession`, and reusing a specific prior
   peer connection on reconnect rather than the current "any peer that shows up" auto-invite.
9. **CloudKit/iCloud sync**, for two-person mode over the internet and cross-device recipe sync —
   and now a more natural fit, since recipes already live in a real SwiftData store.
10. **Accounts, recipe sharing, Android** — still explicitly out of scope.
11. **An XCUITest target**, now that full Xcode is available (§3) — the natural next step for
    verification is tapping through the actual app (recipe → detail → step screen → timers →
    hold-to-finish) rather than only confirming it builds and the list screen renders.

## 6. UX/product iteration ideas & direction

- **The hold-to-finish duration (1s) and the swipe threshold (40pt) are unvalidated guesses** —
  exactly the kind of thing that should change based on actually cooking with the app, not be
  locked in from a first implementation.
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

## 7. Git / repo

The project is a proper git repo, pushed to GitHub: https://github.com/yahiaelsamman/cooking-app
(private). `~/.gitignore` (a git repo rooted at the home directory, unrelated to this project)
excludes the whole `Desktop/` folder, so `cooking_app` wasn't tracked by *any* repo before this —
fixed by `git init`-ing a repo scoped to `cooking_app/` itself, with its own `.gitignore`
(`.build/`, `.swiftpm/`, Xcode user data), committing, and pushing via `gh repo create --push`.
The outer home-directory repo is untouched.
