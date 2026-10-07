# Contributing

Thanks for taking a look. Development is paused-ish, but issues and PRs are welcome.

## Setup
- Full **Xcode 26+** must be the active developer directory (`sudo xcode-select -s /Applications/Xcode.app`), otherwise `swift test` fails on SwiftData macros.
- `brew install xcodegen`. The `.xcodeproj` is generated from `CookingApp/project.yml`; run `xcodegen generate` inside `CookingApp/` after adding or removing files.
- Set your own `DEVELOPMENT_TEAM` and bundle id in `project.yml` to run on a device. Simulator builds don't need signing.

## Checks before a PR
- `cd CookingAppCore && swift test` must pass.
- Keep business logic in `CookingAppCore` (no SwiftUI/UIKit there) and add unit tests with it.
- Build the app: `xcodebuild build -project CookingApp/CookingApp.xcodeproj -scheme CookingApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- UI tests (`CookingAppUITests`) are run manually from Xcode (Cmd+U); they aren't run in CI.
