# Cooking App — Implementation Notes

MVP of a step-by-step recipe navigator for iOS, built with SwiftUI. The core idea: a recipe is
a sequence of discrete steps shown one at a time, full-screen, tap-to-advance — easy to follow
mid-cook with messy hands, instead of scanning a wall of text. It also supports a **two-person
mode**, where a recipe is split into a Person A track and a Person B track and two nearby
iPhones sync progress live over `MultipeerConnectivity` (no internet, no accounts, no backend).

Repo: https://github.com/yahiaelsamman/cooking-app

See `/Users/yahiaelsaman/.claude/plans/tranquil-wishing-deer.md` for the original approved plan
(the initial MVP build). This document has been updated to also cover a second pass that added:
step illustrations, ingredient/overview screens, difficulty/dietary/cook-time metadata, a real
running timer, swipe navigation, reconnection handling, and five more sample recipes.

## 1. What was built

The project is split into two pieces:

### `CookingAppCore/` — a local Swift Package (all the testable logic)

- **`Recipe.swift`** — `Recipe`, `RecipeStep`, `StepAssignee` (`.solo` / `.shared` / `.personA` /
  `.personB`), `DietaryTag`, `Ingredient`. A recipe is one flat, ordered step list;
  `Recipe.track(for:)` derives a person's visible steps by filtering for their assignee plus any
  `.shared` steps — no dependency graph between Person A's and Person B's steps, coordination is
  informational (via the partner-status UI), not enforced. Each `Recipe` now also carries
  `iconSystemName`, `difficulty` (1...3), `cookTimeMinutes`, `dietaryTags`, and `ingredients`; each
  `RecipeStep` carries `imageSystemName` — its step illustration.
- **`SampleRecipes.swift`** — **8 recipes**: 5 solo (*Classic Scrambled Eggs*, *Pan-Seared Steak*,
  *Avocado Toast with Fried Egg*, *Classic Grilled Cheese*, *Simple Tomato Soup*) and 3 two-person
  (*Weeknight Pasta for Two*, *Homemade Pizza Night*, *Taco Tuesday for Two*), all fairly granular
  (7–11 steps each). Recipe IDs are **fixed UUID literals**, not the default random `UUID()` — see
  the pitfalls below for why that matters.
- **`SyncMessage.swift` / `ConnectionState.swift` / `PeerRole.swift`** — the wire protocol and
  small state enums. Messages carry only indices/IDs, never instruction text, since both phones
  have identical bundled recipe data and resolve display text locally.
- **`PeerSyncService.swift`** — wraps `MCSession`/`MCNearbyServiceAdvertiser`/
  `MCNearbyServiceBrowser`. Host advertises and is always Person A; joiner browses and is always
  Person B (no role-swap UI in this MVP). Sends a `recipeSync` message once connected, then a
  `progressUpdate` per step change. **Now auto-reconnects**: if the peer drops after a session had
  already connected once, it automatically restarts advertising (host) or browsing + auto-invites
  (joiner) so the two phones reconnect on their own if they come back in range — see the
  reconnection pitfall below on what this does and doesn't cover.
- **`CookingSessionViewModel.swift`** — drives the step-through screen: `advance()`/`goBack()`
  with bounds checking, `isComplete`, `progressText`, `partnerStep` resolved locally from the
  partner's synced index, and now a **timer engine** (`startTimer`/`cancelTimer`,
  `runningTimerStepID`, `timerRemainingSeconds`, `onTimerFinished` callback) built on Foundation's
  `Timer`. The running timer is tracked independently of `currentIndex`, so it keeps counting down
  even if you navigate to a different step.
- **`PeerConnectionViewModel.swift`** — drives the host/join connection screen.

### `CookingApp/` — the iOS app target (thin SwiftUI views over Core)

`RecipeListView` → `RecipeDetailView` (now an **overview screen**) → (solo) `StepView`, or
(two-person) `PeerConnectionView` → `StepView`. Navigation is a single `NavigationPath` owned by
`RecipeListView` and threaded down as a `Binding`, so "Recipe Complete → Back to Recipes" is just
`path = NavigationPath()` regardless of how deep the stack is.

- **`RecipeListView.swift`** — each row now shows the recipe's icon, 1–3 difficulty stars
  (`DifficultyStarsView`, shared with the detail screen), a cook-time label, dietary-tag chips,
  and the two-person badge.
- **`RecipeDetailView.swift`** — rewritten into a proper **overview screen**: recipe icon,
  difficulty/cook-time/servings/two-person metadata row, dietary tags, a prominent "Start Cooking"
  button, a full **ingredients list**, and a **step read-through** (grouped into Together / Person
  A / Person B for two-person recipes) — so you can decide whether to cook something before
  committing to the one-step-at-a-time screen.
- **`StepView.swift`** — the core screen. Each step now shows its `imageSystemName` illustration
  above the instruction text (text is never cropped or overlapped by the image — see the layout
  note below), a `StepTimerControl` in place of the old static timer label, and a banner when a
  timer is running on a *different* step than the one currently shown. Tap-to-advance is still
  primary; a left/right **swipe gesture** does the same thing as a convenience, never required.
  The completion screen now has a **"Go Back"** button alongside "Back to Recipes," for when the
  last tap/swipe past the final step was an accident.
- **`StepTimerControl.swift`** — the tappable timer icon: tap to start a real countdown (shows
  `M:SS`, tap again to cancel); `StepView` shows a system alert + haptic when it finishes.
- **`SwipeBackDisabler.swift`** — a small `UIViewControllerRepresentable` helper that disables the
  system's edge-swipe-to-pop gesture specifically on `StepView`, so an accidental edge swipe
  during a two-person session can't pop back to the connect screen. SwiftUI has no first-party API
  for this — `navigationBarBackButtonHidden` only hides the button, not the gesture.
- **`PartnerStatusView.swift`** — the compact partner-progress strip shown only in two-person
  sessions, now also showing a small icon preview of the partner's current step (their instruction
  text is still the primary readout — the icon is a glance-only accent). It carries its own empty
  `.onTapGesture` purely to *absorb* taps, so tapping it never falls through to `StepView`'s
  full-screen advance gesture underneath.
- **`PeerConnectionView.swift`** — host/join UI, peer discovery list, and the handshake trigger
  that pushes into `StepView` once actually connected.

## 2. How to run it

This sandbox only has Xcode **Command Line Tools** installed, not full Xcode, so `xcodebuild`/the
iOS Simulator wasn't available here — see the tooling note below for what that means for how this
was verified. On a Mac with full Xcode installed:

1. Open `CookingApp/CookingApp.xcodeproj` in Xcode. It's generated by
   [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `CookingApp/project.yml`, and depends
   on the local `CookingAppCore` package via a relative path (`../CookingAppCore`) — both folders
   need to stay siblings.
2. Select the `CookingApp` target → **Signing & Capabilities** → set your personal Apple ID as
   the team (Automatic signing is already configured).
3. **Solo recipes**: pick an iOS Simulator and Run — no networking involved, fastest iteration
   loop.
4. **Two-person recipe**: needs two physical iPhones (see the manual verification steps below);
   plug in one via cable, pair the second for wireless debugging in Xcode's Devices window so you
   don't need two cables at once.
5. If you ever change `project.yml` or add new source files under `CookingApp/CookingApp/`,
   re-run `xcodegen generate` from inside `CookingApp/` to regenerate the `.xcodeproj` (installed
   via Homebrew in this session: `brew install xcodegen`).

## 3. How the tests were run

Automated tests live in `CookingAppCore/Tests/CookingAppCoreTests/` (Swift Testing framework,
`@Test`/`#expect`) and cover everything that's pure logic:

- **`RecipeModelTests.swift`** — sample-recipe ordering/content integrity, per-role track
  filtering, `CookingSessionViewModel` navigation logic (advance/back bounds checking, completion
  detection, progress text), the **timer's deterministic state transitions**
  (`startTimer`/`cancelTimer` — see the note below on why the real 1-second countdown itself
  isn't unit-tested), and regression guards for the new recipe metadata (difficulty range, cook
  time, ingredients, icons all present across all 8 sample recipes).
- **`SyncMessageCodingTests.swift`** — `SyncMessage` Codable round-trips for both message types,
  including the `stepIndex: 0` edge case and both-optional-fields-nil case.

Run from `CookingAppCore/`:

```
swift test
```

**Result when last run in this session: 25/25 tests passed.**

Why the timer's real countdown isn't unit-tested: Foundation's `Timer` needs an actively-spinning
`RunLoop` to fire — the app's main run loop provides that, but a `swift test` process's threading
model doesn't reliably guarantee it, and a test that silently hangs or flakes on that isn't worth
the coverage. The tests instead verify `startTimer`/`cancelTimer`'s state transitions
deterministically; the actual countdown-to-zero-then-alert behavior is a manual check (see below).

### Tooling note — no full Xcode in this sandbox

This environment has Xcode Command Line Tools but not the full Xcode app, so `xcodebuild`
(and therefore the iOS Simulator / `xcodebuild test`) wasn't available to actually run here. To
still ship a real, openable Xcode project and actually verify logic rather than just writing it:

- The non-UI logic lives in `CookingAppCore`, a local Swift Package with no SwiftUI/UIKit
  dependency (only `Foundation` and `MultipeerConnectivity`, both available on macOS), and its
  tests ran for real with `swift test` — genuinely executed, not hand-waved.
- `CookingApp.xcodeproj` is *generated* by `xcodegen` from `project.yml` rather than hand-authored
  (`project.pbxproj` is a notoriously fragile format to get right without Xcode to validate
  against), and both the generated `project.pbxproj` and `Info.plist` were validated with
  `plutil -lint`.
- The SwiftUI view files (`CookingApp/CookingApp/Views/*.swift`) could **not** be compiled in this
  sandbox (no iOS SDK). They were reviewed by hand for correctness, but **the very first thing to
  do is open the project in Xcode and build once** to catch anything a real compiler would flag
  that a manual read couldn't — this is doubly true after this second pass, since it added several
  new SwiftUI-specific mechanisms (custom gestures, `UIViewControllerRepresentable`, alerts,
  haptics) that lean more heavily on iOS-only APIs than the first pass did.

## 4. Known pitfalls

- **Local Network permission.** `NSLocalNetworkUsageDescription` is set, but on first launch iOS
  shows a system permission prompt on *both* phones — if it's denied (or dismissed without
  answering), peer discovery silently fails with no error shown in the app. Check
  Settings → Privacy & Security → Local Network → Cooking App if hosting/joining seems stuck.
- **Two-person mode can't be validated in the Simulator.** The Simulator has no Bluetooth radio,
  so `MultipeerConnectivity` there only has the WiFi/Bonjour path. Two Simulator instances can
  sometimes discover each other as a rough sanity check during development, but real confidence
  needs two physical iPhones.
- **Recipe IDs had to be hardcoded, not random.** `SampleRecipes` originally used the default
  `UUID()` initializer, which generates a *new* random ID every app launch — meaning the host's
  and joiner's copies of a recipe would never actually agree on a `recipeID`, silently breaking
  the handshake. Fixed with fixed `UUID(uuidString:)` literals. If you add more sample recipes,
  give them fixed IDs too.
- **Reconnection has a real limit: it doesn't survive backgrounding.** `PeerSyncService` now
  auto-restarts advertising/browsing if the peer drops mid-session (e.g. briefly out of
  Bluetooth/WiFi range), so two phones that come back in range reconnect without either person
  navigating back to the connect screen. What this **doesn't** do is keep the session alive while
  the app is backgrounded for any real length of time — iOS suspends most app networking within
  seconds of backgrounding, and keeping `MultipeerConnectivity` alive longer than that needs
  declared background modes and is a meaningfully bigger feature (see Next Steps). In practice:
  don't background the app mid-cook; if you do and the session drops, the auto-reconnect logic
  above will pick it back up as soon as both apps are foregrounded and back in range.
- **The system edge-swipe-back gesture is disabled specifically on `StepView`**
  (`SwipeBackDisabler.swift`), to stop an accidental swipe from popping out of an active two-person
  session. It's restored automatically when you leave that screen. If a future screen also needs
  this, reuse the `.disablesInteractiveSwipeBack()` modifier rather than duplicating the
  `UIViewControllerRepresentable`.
- **SF Symbol names weren't visually verified.** Illustrations and icons (`imageSystemName`,
  `iconSystemName`, dietary-tag icons) are SF Symbol name strings chosen from memory without
  Xcode's SF Symbols app available to confirm them — `Image(systemName:)` never fails to *build*
  on a wrong name, it just renders blank at runtime, so a few (particularly `dietaryFree`/
  `nutFree`'s icons, and a couple of recipe-level icons like `frying.pan.fill`) are worth spot
  checking in Xcode and swapping if they don't render.
- **A real handshake-timing bug was caught and fixed in the first pass.** The host's
  `didHandshake` flag was originally set `true` the instant "Host a two-person session" was
  tapped, before any peer had actually connected. It's driven by `PeerSyncService.connectionState`
  actually reaching `.connected` (`PeerConnectionViewModel.hostDidConnect()`), guarded so a later
  disconnect/reconnect never re-triggers navigation into `StepView` a second time.
- **Free Apple ID signing expires.** Without a paid Apple Developer account, a direct Xcode
  install needs re-signing/rebuilding roughly every 7 days to keep running on-device.
- **Host is always Person A, joiner is always Person B.** There's no role-swap UI.

## 5. Next steps (explicitly deferred)

1. **Real illustrations/photos.** Step and recipe images are SF Symbols for now (your choice for
   this MVP pass) — swapping in real artwork/photography is a data-shape change
   (`imageSystemName: String` → something like an asset-catalog name or remote URL) plus an asset
   pipeline, not just new files.
2. **Recipe import** — URL/blog scraping, or AI-generated recipes, so you're not limited to the
   8 hardcoded samples.
3. **Persistence** — currently everything is static in-memory data; there's no saved cook history,
   no way to add/edit a recipe, and no state survives a relaunch.
4. **True background reconnection** — declared background modes so a two-person session can
   survive the app being backgrounded for more than a few seconds, not just a brief out-of-range
   moment while foregrounded (see the pitfall above).
5. **Role selection UI** — let two people swap which one is "Person A."
6. **CloudKit/iCloud sync** — would let two-person mode work over the internet, not just when both
   phones are physically nearby, and would enable syncing a user's own recipes across devices.
7. **Accounts, recipe sharing, Android** — still explicitly out of scope.
8. **An Xcode-level UI test target** — once full Xcode is available, worth adding a lightweight UI
   test (e.g. via `XCTest`/Simulator) for the tap-to-advance and swipe flows, since
   `CookingAppCoreTests` deliberately only covers non-UI logic.

## 6. Git / repo

The project is now a proper git repo, pushed to GitHub:
https://github.com/yahiaelsamman/cooking-app (private).

Note on how this was set up: `~/.gitignore` (from a git repo rooted at the home directory, likely
unrelated to this project) excludes the whole `Desktop/` folder, so `cooking_app` wasn't tracked
by *any* repo before this. Fixed by `git init`-ing a repo scoped to `cooking_app/` itself (with
its own `.gitignore` for `.build/`, `.swiftpm/`, Xcode user data, etc.), committing, and pushing
to a new GitHub repo via `gh repo create --push`. The outer home-directory repo is untouched.
