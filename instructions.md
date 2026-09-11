# Cooking App — Implementation Notes

MVP of a step-by-step recipe navigator for iOS, built with SwiftUI. The core idea: a recipe is
a sequence of discrete steps shown one at a time, full-screen, tap-to-advance — easy to follow
mid-cook with messy hands, instead of scanning a wall of text. It also supports a **two-person
mode**, where a recipe can split into a Person A track and a Person B track, and two nearby
iPhones sync progress live over `MultipeerConnectivity` (no internet, no accounts, no backend).

Repo: https://github.com/yahiaelsamman/cooking-app

See `/Users/yahiaelsaman/.claude/plans/tranquil-wishing-deer.md` for the original approved plan
(the initial MVP build). This document now covers three passes:
1. The initial MVP (recipe list → step-through → two-person sync).
2. Illustrations, an ingredients/overview screen, difficulty/dietary/cook-time metadata, a real
   timer, swipe navigation, basic reconnection, and five more sample recipes.
3. Timer task-labeling and stacking, hold-to-confirm completion, a partner-vs-me progress slider,
   spice level, session resume/rejoin with role preservation, graceful two-person session ending,
   and the solo/two-person mode toggle (including "mirror mode" for recipes with no task split).

## 1. What was built

### `CookingAppCore/` — a local Swift Package (all the testable logic)

- **`Recipe.swift`** — `Recipe`, `RecipeStep`, `StepAssignee`, `DietaryTag`
  (`vegetarian`/`vegan`/`glutenFree`/`lactoseFree`/`nutFree`), `Ingredient`. A recipe is one flat,
  ordered step list. `Recipe.hasCuratedSplit` reports whether it has real Person A/B steps.
  `Recipe.track(for:)` derives a person's visible steps:
  - `role: nil` → the full list (solo).
  - `role: .personA/.personB` on a **curated** recipe → that person's steps + `.shared` steps.
  - `role: .personA/.personB` on a **non-curated** recipe → the **full list, mirrored to both**
    (see "mode toggle" below) — so two people can still cook any recipe together side by side
    even when there's no sensible way to divide its steps.

  Each `Recipe` also carries `iconSystemName`, `difficulty` (1...3), `spiceLevel` (0...3),
  `cookTimeMinutes`, `dietaryTags`, `ingredients`; each `RecipeStep` carries `imageSystemName`.
- **`SampleRecipes.swift`** — **8 recipes**, fixed `UUID(uuidString:)` literals (not random
  `UUID()` — see pitfalls): 5 solo, 3 with a curated two-person split (all 8 now support
  two-person *mode*, per the mirror-mode fallback above).
- **`SyncMessage.swift`** — wire protocol, now 5 message types: `recipeSync`, `progressUpdate`,
  `timerStarted`, `timerCancelled`, `leaveSession`. Still carries only indices/IDs, never text.
- **`PeerSyncService.swift`** — wraps `MCSession`/`MCNearbyServiceAdvertiser`/
  `MCNearbyServiceBrowser`. Auto-reconnects on an unexpected drop (restarts advertising/browsing);
  `leaveSession()` is a **deliberate** end — sends a best-effort `leaveSession` message, then
  `stop()`s with no auto-reconnect. Refactored so every delegate callback (`didChange:`,
  `didReceive:`, `foundPeer:`, `lostPeer:`) is a thin `DispatchQueue.main.async` wrapper around an
  `internal` synchronous handler (`handleSessionStateChange`, `handleReceivedMessage`,
  `handleFoundPeer`, `handleLostPeer`) — this is what makes `PeerSyncServiceTests` possible
  without any real networking (see §3).
- **`CookingSessionViewModel.swift`** — `advance()`/`goBack()`, `isComplete`, `isLastStep`,
  `progressText`/`progressFraction`, `partnerStep`, and now:
  - **Stacking timers**: `activeTimers: [ActiveTimer]` (mine) and `partnerActiveTimers`
    (mirrored from the partner's `timerStarted`/`timerCancelled` messages, ticked locally by the
    same 1Hz `Timer` rather than needing a message every second). `ActiveTimer` carries the full
    `RecipeStep`, not just an id, so any timer — including a partner's or one on a step you've
    navigated away from — can always show what task it belongs to.
  - **`partnerProgressFraction`** — the partner's progress through *their own* track as a 0...1
    fraction, directly comparable to `progressFraction` even when the two tracks have different
    lengths (curated splits are rarely equal-length).
  - **`endSharedSession()`** — calls `peerSync.leaveSession()`; local navigation keeps working
    afterward exactly like a solo recipe.
  - **`partnerDidLeave`** — flips true when the partner explicitly ends (wired to
    `peerSync.onPartnerLeft`), distinct from a connection just dropping.
- **`ActiveSessionStore.swift`** *(new)* — holds a reference to whatever `CookingSessionViewModel`
  is currently in progress, independent of navigation. Lets the recipe list show a "Resume
  Cooking" button that jumps back into the *same* session object — see §1's "resume" note below
  for why this is what makes role preservation work.
- **`PeerConnectionViewModel.swift`** — unchanged from pass 2 (host/join connection screen logic).

### `CookingApp/` — the iOS app target (thin SwiftUI views over Core)

- **`RecipeListView.swift`** — rows now show a spice-level flame row (only when `spiceLevel > 0`)
  alongside difficulty stars, and the two-person badge now reads "Task-split for two" and only
  appears for `hasCuratedSplit` recipes (two-person *mode* itself is available on every recipe via
  mirroring, so it's no longer a meaningful distinguishing badge). A bottom-right floating
  **"Resume Cooking"** button appears whenever `ActiveSessionStore.hasActiveSession` — tapping it
  pushes straight to `StepView` with the *existing* `CookingSessionViewModel`, skipping the
  recipe/connect flow entirely.
- **`RecipeDetailView.swift`** — added a **Solo / Two-Person segmented picker**, shown for every
  recipe (with a caption explaining task-split vs. mirrored behavior depending on
  `hasCuratedSplit`); `startCooking()` branches on the picker, not a fixed recipe property.
  Registers the new session with `ActiveSessionStore` before pushing, for solo recipes.
- **`PeerConnectionView.swift`** — on a successful handshake, also registers the new session with
  `ActiveSessionStore` (the two-person equivalent of the above).
- **`StepView.swift`** —
  - **Hold-to-finish**: the final step no longer completes on a plain tap/swipe — that was too
    easy to trigger by accident with no undo. A dedicated `HoldToFinishButton` (2-second hold,
    animated ring) appears instead; the ordinary back button stays available alongside it. The
    completion screen still has "Go Back" for a genuine accidental hold.
  - **`TimerStackView`**: shows every timer running somewhere other than the currently-viewed
    step — your own (orange chips) and your partner's (blue chips) — each labeled with the task
    it's timing, exactly what "stacking" needed to stay legible.
  - **"End Session"** toolbar button (two-person only, hidden once already ended) with a
    confirmation dialog; calls `session.endSharedSession()`.
  - An alert when `session.partnerDidLeave` flips true, clearing `ActiveSessionStore` and
    resetting the nav path back to the recipe list on acknowledgement.
- **`HoldToFinishButton.swift`** *(new)* — the 2-second hold-to-confirm control described above.
- **`DualProgressSliderView.swift`** *(new)* — one shared capsule track with two markers (you,
  your partner), each positioned by their own progress fraction — shown inside
  `PartnerStatusView` whenever connected.
- **`TimerStackView.swift`** *(new)* — the stacked-timer chip list described above.
- **`PartnerStatusView.swift`** — now also renders `DualProgressSliderView` beneath the existing
  partner-step readout.
- **`StepTimerControl.swift`** — updated for the stacking API (`activeTimer(for:)`/
  `cancelTimer(for:)` instead of a single scalar running-timer id).
- **`CookingAppApp.swift`** — now creates one `ActiveSessionStore` and injects it via
  `.environment(_:)`; every view above reads it with `@Environment(ActiveSessionStore.self)`.

### On "resume" and role preservation

The request that motivated `ActiveSessionStore`: previously, leaving the step screen and coming
back meant re-choosing Host or Join, which could flip who's Person A vs. B if you picked
differently than last time. The store sidesteps that by holding a reference to the *same*
`CookingSessionViewModel` (and, for two-person sessions, its already-connected `PeerSyncService`)
— "Resume Cooking" re-enters that exact object rather than reconstructing one, so role, step
index, and any running timers all come back exactly as they were. This only survives within one
app process's lifetime (backgrounding is fine, an actual force-quit is not — there's still no disk
persistence in this MVP; see Next Steps).

## 2. How to run it

This sandbox only has Xcode **Command Line Tools** installed, not full Xcode, so `xcodebuild`/the
iOS Simulator wasn't available here — see §3's tooling note. On a Mac with full Xcode installed:

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

**59/59 tests passed** when last run in this session (`swift test` from `CookingAppCore/`), across
four files:

- **`RecipeModelTests.swift`** — sample-data integrity, track filtering (including the new
  mirror-mode fallback for non-curated recipes, and a regression check that curated recipes are
  unaffected by that fallback), timer stacking (two independent timers, restarting one doesn't
  duplicate it), and metadata range checks (difficulty, spice level, cook time).
- **`SyncMessageCodingTests.swift`** — Codable round-trips for all 5 message types.
- **`PeerSyncServiceTests.swift`** *(new)* — connection state transitions, auto-reconnect
  triggering after a prior successful connection vs. *not* triggering on a first-ever drop or
  after a deliberate `leaveSession()`, every inbound message type's handling, and peer
  discovery/loss bookkeeping. This is real coverage of logic that had **zero** direct tests before
  this pass — made possible by refactoring each `MCSessionDelegate`/`MCNearbyServiceBrowserDelegate`
  method into a thin dispatch wrapper around an `internal` synchronous handler, which tests call
  directly with plain `MCPeerID`/`SyncMessage` values — no real MultipeerConnectivity session
  needed. (One real bug this caught while writing the tests: `MCPeerID` equality isn't just
  display-name comparison — two separately-constructed instances with the same name aren't `==`.
  Every test constructs its peer id exactly once and reuses that instance, never a fresh one.)
- **`CookingSessionViewModelTests.swift`** *(new)* — partner-timer mirroring resolved against the
  partner's own track (not mine), `partnerProgressFraction`'s track-length normalization,
  `partnerDidLeave` firing only from an *incoming* leave (not from my own `endSharedSession()`),
  local navigation continuing after ending a shared session, and `ActiveSessionStore`.

Why the timer's real 1-second countdown-to-zero isn't itself unit-tested: Foundation's `Timer`
needs an actively-spinning `RunLoop`, which the app's main run loop provides but a `swift test`
process's threading model doesn't reliably guarantee — a test that could silently hang isn't worth
the coverage. State transitions (`startTimer`/`cancelTimer`/stacking) are tested deterministically
instead; the actual countdown-to-alert behavior is a manual check (§3's manual list, and above).

### Tooling note — no full Xcode in this sandbox

Same constraint as passes 1 and 2: no `xcodebuild`/iOS Simulator here. `CookingAppCore` (all
non-UI logic) is genuinely built and tested with `swift test`. `CookingApp.xcodeproj` is
generated via `xcodegen` and validated with `plutil -lint`, not hand-authored. The SwiftUI files
under `CookingApp/CookingApp/Views/` were reviewed by hand — including catching and fixing one
real bug this way (see the hold-to-finish pitfall below) — but **open the project in Xcode and
build once before relying on it**; this pass added more iOS-only surface area than the last one
(custom drag gestures alongside tap, `onLongPressGesture`, `.toolbar`/`.confirmationDialog`,
`Environment`-injected Observable state) that a manual read can't fully substitute for a compiler.

**Manual verification checklist** (needs a real device/Xcode):

- Solo: tap-to-advance, swipe-to-advance/back, back button, hold-to-finish on the last step,
  "Go Back" from the completion screen, starting/cancelling a timer, two timers stacked at once,
  the "Resume Cooking" button after backgrounding and returning.
- Two-person: Local Network permission prompt, host/join handshake, the dual progress slider
  moving as each phone advances, a timer started on one phone appearing (with its task label) as
  a blue chip on the other, "End Session" tearing down both sides, auto-reconnect after toggling
  Airplane Mode on one phone and back, and resuming a two-person session via "Resume Cooking"
  with roles intact.

## 4. Known pitfalls

- **Local Network permission** must be accepted on both phones or discovery silently fails
  (Settings → Privacy & Security → Local Network → Cooking App).
- **Two-person mode can't be validated in the Simulator** (no Bluetooth radio) — needs two
  physical iPhones for real confidence.
- **Recipe IDs are fixed UUID literals**, not random — random per-launch IDs would break the
  host/joiner `recipeID` handshake. Give any new sample recipe a fixed ID too.
- **Reconnection doesn't survive real backgrounding** — `PeerSyncService` auto-reconnects after a
  brief drop while both apps stay foregrounded/backgrounded-but-alive, but iOS suspends most app
  networking within seconds of backgrounding; true background survival needs declared background
  modes (see Next Steps). "Resume Cooking" (via `ActiveSessionStore`) also only survives within one
  process's lifetime, not an actual force-quit.
- **A caught-and-fixed layout bug**: the hold-to-finish control was originally going to *replace*
  the back button on the last step entirely — on review, that would have left the last step with
  no button-based way to go back (only an undiscoverable swipe), so the back button now stays
  alongside it always.
- **The `leaveSession` message is best-effort.** It's sent right before disconnecting, but if the
  connection is already degrading there's no guarantee it arrives — the receiving side would then
  just see a plain drop and try to auto-reconnect instead of recognizing a deliberate end. No
  ack/retry protocol was built for this (would be real added complexity for an edge case).
- **The system edge-swipe-back gesture is disabled specifically on `StepView`**
  (`SwipeBackDisabler.swift`) so an accidental edge swipe can't pop out of an active two-person
  session; restored automatically on leaving that screen.
- **SF Symbol names weren't visually verified** (no Xcode/SF Symbols app in this sandbox) — a
  wrong name renders blank at runtime rather than failing to build, so spot-check icons,
  especially `frying.pan.fill` and the dietary-tag icons.
- **Host is always Person A, joiner is always Person B** — no role-swap UI.
- **Free Apple ID signing expires** roughly every 7 days without a paid developer account.

## 5. Next steps (explicitly deferred)

1. **Real illustrations/photos** — SF Symbols were this pass's deliberate choice; swapping in
   real art is a data-shape change (`imageSystemName: String` → an asset name or URL) plus a
   pipeline, not just new files.
2. **True background reconnection** — declared background modes so a two-person session survives
   more than a brief backgrounding.
3. **Disk persistence** — recipe history, in-progress session state that survives a force-quit
   (today's "Resume Cooking" only survives within one process lifetime), user-created recipes.
4. **Recipe import** (URL scraping or AI generation) beyond the 8 hardcoded samples.
5. **Curated two-person splits for the 5 currently-solo recipes**, if any of them turn out to
   split sensibly in practice — deliberately not guessed at this pass; mirror mode covers them for
   now.
6. **Role selection UI** — let two people swap who's "Person A."
7. **A sturdier leave/rejoin protocol** — an ack for `leaveSession`, and reusing a specific prior
   peer connection on reconnect rather than the current "any peer that shows up" auto-invite.
8. **CloudKit/iCloud sync**, for two-person mode over the internet and cross-device recipe sync.
9. **Accounts, recipe sharing, Android** — still explicitly out of scope.
10. **An Xcode-level UI test target**, once full Xcode is available, for the tap/swipe/hold
    gesture flows that `CookingAppCoreTests` deliberately doesn't cover.

## 6. UX/product iteration ideas

Requested explicitly as a "how do we make this better" pass, separate from what's already
scheduled above as deferred engineering work:

- **The hold-to-finish duration (2s) and the swipe threshold (40pt) are unvalidated guesses.**
  Both are exactly the kind of thing that should change based on actually cooking with the app a
  few times, not be locked in from a first implementation.
- **Timer notifications don't reach you if the phone is asleep or you've switched apps** — a
  local notification (not just an in-app alert) would matter a lot for anything with a timer
  longer than a minute or two, which is most of them.
- **The step illustration is the same size/prominence for every step regardless of content** — a
  step like "let it rest for 5 minutes" and a step like "sear undisturbed, 3 minutes per side"
  have very different "what do I actually need to see" needs; the layout doesn't distinguish them.
- **Nothing currently scales a recipe's ingredient quantities to a different serving count** —
  `servings` is displayed but not adjustable, which is a common real want in a recipe app.
- **The partner's connection-state dot (green/yellow/red) has no explanation on tap** — a first-time
  two-person user has to already know what it means.
- **"Mirror mode" for a non-curated recipe cooked two-person doesn't distinguish the two phones'
  content at all** — both show identical instructions with no assignee tint, which may read as
  "why bother," compared to a curated split's clear division. Worth revisiting whether mirror mode
  should feel more like "cooking together" (e.g. showing both people's names/avatars more
  prominently) rather than just "two copies of solo mode."
- **No confirmation before "Start Cooking" leaves the overview screen** — for a long or unfamiliar
  recipe, a brief "you won't see the full ingredient list again until you finish" nudge might
  reduce having to back out mid-cook to double-check something.
- **Difficulty and spice level are currently my own back-of-envelope calls, not calibrated against
  anything** — worth a real rubric (or user-submitted ratings) once there's more than 8 recipes.

## 7. Git / repo

The project is a proper git repo, pushed to GitHub: https://github.com/yahiaelsamman/cooking-app
(private). `~/.gitignore` (a git repo rooted at the home directory, unrelated to this project)
excludes the whole `Desktop/` folder, so `cooking_app` wasn't tracked by *any* repo before this —
fixed by `git init`-ing a repo scoped to `cooking_app/` itself, with its own `.gitignore`
(`.build/`, `.swiftpm/`, Xcode user data), committing, and pushing via `gh repo create --push`.
The outer home-directory repo is untouched.
