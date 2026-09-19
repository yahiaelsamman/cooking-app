# Cooking App — Reference

A step-by-step recipe navigator for iOS (SwiftUI): a recipe is a sequence of full-screen steps,
tap/swipe to advance — built for cooking with messy hands, not scanning a wall of text. Some
recipes support **two-person mode**, splitting labor across two nearby iPhones synced live over
`MultipeerConnectivity` (no internet, no accounts, no backend).

Repo: https://github.com/yahiaelsamman/cooking-app

**This file describes current behavior only.** For *why* something is shaped the way it is, or a
history of what changed and when, read `git log` — every feature landed as its own commit with a
detailed message explaining the reasoning. This file is not that log; keep it short.

## Architecture

Two-package layout, deliberately split so all business logic is unit-testable without booting a
simulator:

- **`CookingAppCore/`** — a local Swift Package. All logic, zero UIKit/SwiftUI. This is where
  correctness lives and where nearly all tests live.
- **`CookingApp/`** — the iOS app target. Thin SwiftUI views over Core. View logic itself isn't
  unit-tested (see Testing below) — verified by compiling + manual/simulator checks.

### Core (`CookingAppCore/Sources/CookingAppCore/`)

| File | What it is |
|---|---|
| `Recipe.swift` | `Recipe` (a SwiftData `@Model`), `RecipeStep`, `Ingredient`, `StepAssignee`, `DietaryTag`. The central data model — start here. |
| `SampleRecipes.swift` | 20 bundled recipes, fixed `UUID` literals (never random — see Pitfalls). |
| `RecipeSeeder.swift` | Inserts missing bundled recipes by id and, on every launch, refreshes existing bundled recipes' curated content via `Recipe.updateBundledContent` (user fields and user-created recipes are never touched). |
| `SessionPersistence.swift` | Snapshots the active *solo* session (recipe id, step index, running timers) to `UserDefaults` so it survives a force-quit. |
| `ActiveSessionStore.swift` | Holds the in-memory `CookingSessionViewModel` currently in progress, independent of navigation — powers "Resume Cooking" and calls `SessionPersistence`. |
| `CookingSessionViewModel.swift` | Step navigation (`advance`/`goBack`), the timer engine, and (for two-person) partner progress/presence mirroring. |
| `CookExpertise.swift` | Beginner/intermediate/experienced — a presentation-only lever for how much hand-holding the step screen shows. |
| `SyncMessage.swift` | The wire protocol for two-person sync — a `Codable` enum, 7 message types. |
| `PeerSyncService.swift` | Wraps `MCSession`/advertiser/browser. Every delegate callback is a thin wrapper around an `internal` synchronous handler — that's what makes it unit-testable without real networking. Late connecting/notConnected callbacks after leave/stop are ignored (state stays `.idle`). |
| `PeerConnectionViewModel.swift` | Host/join connect-screen logic. |
| `ShoppingListItem.swift` | A second `@Model` type; snapshots ingredients (not a live relationship) onto a shopping list. |

### App (`CookingApp/CookingApp/`)

- `CookingAppApp.swift` — builds the `ModelContainer`, seeds it, and sets the notification delegate (the permission prompt is requested on first Start Cooking in `RecipeDetailView`, not at launch).
- `Views/` — one SwiftUI view per screen/component. `RecipeListView` (browse/search/filter/sort),
  `RecipeDetailView` (overview + solo/two-person picker + servings scaling), `StepView` (the core
  screen — timers, hold-to-finish, coach marks, doneness hints), `PeerConnectionView` (host/join),
  `RecipeEditorView` (create/edit a *user-created* recipe only), `ShoppingListView`.
- **Interactive first-run walkthrough** (`AppTour.swift`, `TourSpotlight.swift`): a real
  spotlight tour, not a static explainer. `AppTour` (one instance per screen, `@State`) holds a
  queue of `TourStep`s; `TourSpotlight` draws a pulsing ring around the actual on-screen control
  (via `.tourAnchor(id)`, a `PreferenceKey` reading real button/section frames) plus a callout
  next to it. A step with a real target has no "Next" button — it only advances when that control
  is genuinely used, via a call to `tour.notify(id)` placed at the *real* action site (a `Button`'s
  own action, or an `.onChange` on the state a `Picker`/`Stepper` edits) — never a gesture bolted
  onto the overlay, which would risk competing with `StepView`'s already-audited tap/swipe/hold
  gestures. A step with no single control (e.g. "here's what this app is") shows its own "Next"
  button instead. `TourSpotlight` never blocks touches (`allowsHitTesting` stays off except on its
  own Skip/Next buttons), so the real UI underneath always keeps working normally.
  - Anchors *do* resolve correctly through `.toolbar` items and across `ScrollViewReader.scrollTo`
    — confirmed empirically in the Simulator, not assumed; both were real open questions in
    SwiftUI's anchor-preference propagation before being wired up everywhere.
  - `.tourAnchor` needs a view with a real frame — anchoring it to a `Group` only captures
    whichever child SwiftUI happens to report, not the union of all of them; use a real container
    (`VStack`/`HStack`) if you need one anchor to span several children (see `StepView`'s
    photo+instruction pairing).
  - Currently covers `RecipeListView` → `RecipeDetailView` → `StepView` (the core browse → decide
    → cook path), each gated by its own one-time `@AppStorage` flag
    (`hasSeenRecipeListTour`/`hasSeenRecipeDetailTour`/`hasSeenStepTour`), chained in that order.
    `StepView` additionally runs two dynamic one-off tips independent of that front-loaded tour —
    the first time a step has a timer (`hasSeenTimerTourTip`) and the first time you reach the
    last step (`hasSeenFinishTourTip`) — since those controls don't exist until you're actually
    there.
  - Deliberately not (yet) extended to `ShoppingListView`, `PeerConnectionView`,
    `RecipeEditorView`, or `IngredientChecklistView` — each is a plain list/form with
    self-explanatory controls (checkboxes, a "Done" button, labeled text fields), not a screen a
    first-time cook would get stuck on the way the three above are.
- `Notifications/` — local notification scheduling for step timers; not unit-tested (needs a real
  `UNUserNotificationCenter`/app process). Permission is requested on first Start Cooking, not at launch.

### Data model notes worth knowing before you change `Recipe`

- A `Recipe` carries **two independently-authored step lists** (`soloSteps`, always present;
  `twoPersonSteps`, `nil` unless a real split was hand-authored) — not one list with a derived
  variant. There is no generic fallback that mirrors solo steps into a fake two-person mode (tried
  once, removed — see Pitfalls).
- `RecipeStep`/`Ingredient` are plain `Codable` structs embedded on `Recipe`, not their own
  `@Model` types — they never need independent identity outside their parent recipe.
- New sample recipes need a **fixed UUID literal**, never `UUID()` — random ids would break the
  host/joiner handshake and the seeder's dedup-by-id logic.

## Running it

1. Open `CookingApp/CookingApp.xcodeproj` in Xcode (generated by
   [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `CookingApp/project.yml`; depends on the
   local `CookingAppCore` package via a relative path — keep both folders as siblings).
2. `CookingApp` target → Signing & Capabilities → set your Apple ID as the team.
3. Solo recipes run fine in Simulator. Two-person mode needs two physical iPhones (no Bluetooth
   radio in Simulator).
4. Added a new source file under `CookingApp/CookingApp/`, or changed `project.yml`? Re-run
   `xcodegen generate` from inside `CookingApp/`. `DEVELOPMENT_TEAM` is set in `project.yml` itself
   (both targets), so regenerating no longer wipes your signing team — if you ever switch to a
   different team, update it there rather than just in Xcode, or the next regenerate will revert it.

### Building/testing from the CLI

This machine's global `xcode-select` points at Command Line Tools, which can't resolve SwiftData's
`@Model` macro plugin. Prefix build/test commands with the full Xcode toolchain:

```
cd CookingAppCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
cd CookingApp && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme CookingApp -destination 'platform=iOS Simulator,name=iPhone 17' build
```

If `swift test` reports a failure with 0 tests actually failing, it's iCloud Desktop-sync
interfering with `.build/` mid-compile (this repo lives under `~/Desktop`) — rerun, or use
`swift test --scratch-path /tmp/some-path` to build outside the synced folder entirely.

Avoid `xcodebuild test` (full UI-automation test run) in an unattended/background session — it can
stall indefinitely at Simulator accessibility bootstrap and has caused real memory pressure on this
machine before. `build` and `build-for-testing` (compiles the UI test target without running it)
are safe; save an actual `test` run for an interactive session where you can watch it.

## Testing

- `CookingAppCoreTests` (`swift test`): the real test suite — 210 tests as of the last pass,
  covering every Core file. Run this after any Core change.
- `CookingAppUITests` (XCUITest, in the app target): exists, builds, and links, but has never
  successfully *run* in this sandboxed environment — `xcodebuild test` stalls at "loading
  Accessibility" before any test executes. Looks like a headless-Simulator limitation, not a test
  bug. Try it from an interactive Mac (Xcode ⌘U) if you want to actually run it.
- View-layer behavior with no Core equivalent (notification delivery, VoiceOver, real touch
  gestures like drag-to-reorder or swipe-to-favorite, the idle-timer/screen-awake behavior) has no
  automated coverage here — verify by hand on a device/Simulator.

## Known pitfalls

- **A "mirror mode"** (fake two-person split by mirroring solo steps to both phones) was tried and
  removed — don't reintroduce it. A recipe has no two-person option until one is genuinely
  hand-authored for it.
- **Local Network permission** must be accepted on both phones or peer discovery silently fails.
- **Recipe IDs must be fixed UUID literals** — see above.
- **Step ids are stable across launches only via `Recipe.preservingStepIDs`**, which carries stored ids forward by instruction text (then by position if the timer matches) so saved timers still resolve after a re-seed. Don't key anything durable on a step id that doesn't pass through `updateBundledContent`.
- **Session persistence:** a completed solo session is cleared, not persisted (`ActiveSessionStore.persist`), and replacing the active session detaches the old one's `onMutated` so it can't overwrite the snapshot.
- **Tour details:** the `Skip Walkthrough` chip sits at the bottom (about 72pt above the safe area) to clear the nav bar/search bar, and the step-change VoiceOver announcement is suppressed while a tour callout is speaking.
- **Two-person session state isn't persisted** — only solo sessions survive a force-quit
  (`SessionPersistence`); a killed two-person session is gone. Reconnection after backgrounding is
  best-effort and doesn't survive true iOS background suspension.
- **You can't edit a bundled recipe or delete any recipe that isn't user-created** — deliberate
  (curated content; deleting a bundled recipe would need a seeder tombstone, which doesn't exist).
- **VoiceOver accessibility has been audited across every screen** (`StepView`,
  `PartnerStatusView`, `DualProgressSliderView`, `RecipeListView`, `ShoppingListView`,
  `PeerConnectionView`, `WelcomeNameView`, `RecipeEditorView`) — combined-element treatment for
  list rows, decorative icons hidden, icon-only buttons labeled, step-change/timer-finish/partner-state announcements, an adjustable star rating, and Voice Control input labels. Not verified with a real
  VoiceOver run (see the sandbox limitation below); if you add a new row/card-style view, follow
  the same pattern (`.accessibilityElement(children: .combine)` + hide purely decorative icons).
- **Swipe-to-favorite, drag-to-reorder, and the recipe editor's dynamic rows** have never been
  exercised with a real touch in this environment (no accessibility automation here) — only
  confirmed to render and compile.
- **The interactive tour (`TourSpotlight`) has basic accessibility, not the same audited rigor**
  as the rest of the app: the ring is hidden (`accessibilityHidden`) and each callout is one
  combined element with a label/hint, but a step that waits on a real control being used has no
  VoiceOver-specific affordance beyond that control's own existing accessibility action — never
  verified with a real screen reader. `Skip Walkthrough` is reachable and labeled either way.

## Open next steps

- Editing a bundled recipe's content, or deleting one — needs a seeder tombstone first.
- A two-person split editor (today `RecipeEditorView` only creates solo recipes).
- Per-step photos (only recipe-level hero photos exist; steps still use a placeholder card).
- True background reconnection for two-person mode (declared background modes).
- CloudKit/iCloud sync — for two-person over the internet and cross-device recipe sync.
- Verify the VoiceOver audit with a real screen-reader run on a device (never done — see Testing).
- Actually get `CookingAppUITests` running (on an interactive Mac) and expand its coverage.

## Git / repo

Private GitHub repo, `git init`-ed scoped to `cooking_app/` itself (the outer `~/` directory has
its own unrelated repo that ignores `Desktop/` entirely — don't confuse the two).

---

## Understanding this codebase (for a CS grad reading it cold)

If you're picking this up fresh, read in this order:

1. **`CookingAppCore/Sources/CookingAppCore/Recipe.swift`** — the entire domain model in one file.
   Once you understand `Recipe`/`RecipeStep`/`Ingredient` and the solo-vs-two-person step lists,
   everything else is UI or plumbing around this.
2. **`CookingAppCore/Tests/CookingAppCoreTests/RecipeModelTests.swift`** — tests double as
   executable documentation here; reading them tells you the *contracts* (e.g. "two-person cook
   time is always shorter than solo") more precisely than prose would.
3. **`CookingApp/CookingApp/Views/StepView.swift`** — the one screen this whole app exists to
   serve. Everything else (list, detail, editor, shopping list) is secondary to "show me one step
   at a time."
4. **`CookingAppCore/Sources/CookingAppCore/PeerSyncService.swift`** + `SyncMessage.swift` — only
   once you want to understand two-person mode. Notice the internal/external split (public
   MultipeerConnectivity delegate callbacks vs. `internal` synchronous handlers) — that pattern is
   what makes networking code testable without a real network, and is worth recognizing since
   it recurs any time you'd otherwise need to mock a system framework.

**Architectural decisions worth noticing, not just the code itself:**

- **Package boundary as a testability boundary.** `CookingAppCore` has zero UIKit/SwiftUI imports.
  This isn't just "clean architecture" for its own sake — it's the concrete reason 210 tests run in
  under half a second with `swift test`, no simulator needed, while the app target's view code is
  verified by compiling + eyeballing it. When you add a feature, ask "does this belong in Core?"
  before reaching for a View — if the answer is logic/state/decisions, it almost always does.
- **SwiftData `@Model` for one real store, not a mock/hardcoded-data split.** `SampleRecipes.swift`
  are Swift value literals used only as seed data (`RecipeSeeder`) — the actual running app always
  reads from one real on-device SwiftData store via `@Query`. There's no separate "test mode with
  fake data" vs "prod mode with real data" branch to keep in sync.
- **Additive-by-id seeding, not idempotent-overwrite seeding.** `RecipeSeeder` inserts whichever
  bundled recipes the store doesn't already have; for existing bundled ones it re-syncs curated content only (user fields such as favorites, notes and ratings are preserved). This is the kind
  of decision that looks like extra complexity until you trace through *why* — the naive version
  (wipe and reseed) would destroy user data (favorites, notes, ratings) on every app update.
- **Snapshot, not a live reference, for the shopping list.** `ShoppingListItem` copies ingredient
  text rather than holding a relationship to its source `Recipe`. Look for this pattern —
  "reference vs. snapshot" — anywhere a feature described as "add X to Y" shows up; it's usually a
  deliberate choice, not an oversight, and the choice usually hinges on whether Y should track
  future edits to X or not.

## Working on this project with Claude Code

- **Treat `instructions.md` as living documentation, not a running log.** It should always
  describe *only* what's true right now. When you finish a feature, update the relevant section
  (architecture table, pitfalls, next-steps) in place — don't append a "pass N" narrative here.
  Detailed reasoning belongs in the commit message; this file should stay small enough to read in
  one sitting.
- **Commit messages are the changelog.** This project's history is a sequence of descriptive
  commits (`git log`), each explaining what changed and why. That's the right place for "what was
  tried and rejected," not this file.
- **Verification discipline, in order of cost:** `swift test` (Core) after any logic change →
  `xcodebuild build`/`build-for-testing` (full app) after any view/wiring change → manual
  Simulator/device check for anything view-layer-only. Don't skip straight to "looks right" for a
  Core change — the test suite is fast and exists precisely so you don't have to.
- **Don't run `xcodebuild test` unattended.** It can hang or strain this machine — safe to run
  interactively where you'll notice a stall, not as a background/overnight step.
- **When working autonomously for an extended stretch,** pick small, independent, reversible
  changes; verify each one fully (build + test) before moving to the next; and stop to update
  `instructions.md` and commit at natural boundaries rather than batching a huge diff. Concrete,
  low-risk gaps (an untested edge case, a missing accessibility label, a UX convention every
  competitor app has) are better use of unsupervised time than a single large, hard-to-verify
  feature.
- **If you're about to add complexity, look for the existing pattern first.** This codebase
  consistently favors small, explicit, additive changes over generic/configurable ones (see the
  architectural notes above) — matching that style is usually more valuable than a more "elegant"
  abstraction.
