# Repository Guidelines

## Project Structure & Module Organization
This repository is an iOS SwiftUI app. The main app code lives in `iESP32/` (current directory), while the Xcode project file is `../iESP32.xcodeproj`.

Key folders:
- `Views/`: UI components (for example `TerminalMessageView.swift`, `DevicePickerView.swift`).
- `Settings/`: settings state and settings screens.
- `Search/`: filtering and search UI.
- `Stats/`: connection/statistics views.
- `Models/`: app data models.
- `Extensions/`: focused extensions.
- `Assets.xcassets/`: app icons and color assets.

Keep new files in the closest feature folder; avoid large multi-purpose files.

## Build, Test, and Development Commands
Run commands from `iESP32/`.

- `xcodebuild -project ../iESP32.xcodeproj -scheme iESP32 -configuration Debug build -derivedDataPath ./DerivedData`
Builds the app from CLI with local derived data.

- `xcodebuild -project ../iESP32.xcodeproj -scheme iESP32 -destination 'platform=iOS Simulator,name=iPhone 16' test -derivedDataPath ./DerivedData`
Runs tests once test targets exist.

- `xed ..`
Opens the project in Xcode for iterative UI/device testing.

## Coding Style & Naming Conventions
Use Swift defaults and existing project style:
- 4-space indentation; no tabs.
- `UpperCamelCase` for types (`BluetoothManager`), `lowerCamelCase` for properties/functions.
- Organize long files with `// MARK:` sections.
- Prefer small, feature-specific `View` structs and manager classes.

No formatter/linter config is currently committed; keep formatting consistent with surrounding files.

## Testing Guidelines
There is currently no committed test target. Add one in Xcode (for example `iESP32Tests`) for new logic-heavy work.
- Name tests by behavior, e.g. `testSendMessage_AppendsNewline()`.
- Focus tests on filtering, parsing, and settings defaults/reset behavior.
- Run tests with Xcode or the `xcodebuild ... test` command above.

## Commit & Pull Request Guidelines
Current history uses short commit subjects (for example `Initial Commit`, `new updates`). Keep commits concise but more descriptive:
- Use imperative, scoped messages when possible (example: `Settings: add scan duration validation`).
- One logical change per commit.

For pull requests:
- Summarize user-facing impact and technical changes.
- Link related issues.
- Include screenshots for UI changes (settings, terminal, stats screens).
- Confirm local build success before requesting review.
