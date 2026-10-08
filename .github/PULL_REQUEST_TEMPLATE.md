## What and why

## Checks
- [ ] `cd CookingAppCore && swift test` passes
- [ ] The app builds for the Simulator (command in CONTRIBUTING.md)
- [ ] Business logic lives in `CookingAppCore` with unit tests; no SwiftUI/UIKit there
- [ ] Ran `xcodegen generate` in `CookingApp/` if files or `project.yml` changed
- [ ] UI tests run locally if the change touches views (they are not run in CI)
