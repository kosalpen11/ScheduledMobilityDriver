# Codex Project Notes

## Project

This repository contains the native iOS driver app for the scheduled-mobility backend. It targets iOS 15.0 and later.

Phase 1 is implemented:

- Native UIKit app shell with scene lifecycle and `UINavigationController`.
- Local Swift package in `DriverModules`.
- Mock scheduled-trip data and availability state.
- Home implemented in both UIKit and SwiftUI.
- UIKit and SwiftUI Home variants share `HomeViewModel`, domain use cases, repositories, and navigation outputs.

## Architecture Rules

- Keep `DriverDomain` Foundation-only.
- Keep DTOs and concrete repositories out of views.
- UI modules must not import `DriverData`.
- The app composition root wires implementations together.
- Use initializer injection; do not introduce service locators or global mutable singletons.
- Keep navigation in `AppCoordinator`; screens emit typed outputs.
- Maintain iOS 15 compatibility. Do not require `NavigationStack`, SwiftUI `presentationDetents`, `PhotosPicker`, `@Observable`, or newer SwiftUI Map APIs.

## Important Paths

- App shell: `DriverApp/App`
- Configuration: `DriverApp/Configuration`
- Package manifest: `DriverModules/Package.swift`
- Domain: `DriverModules/Sources/DriverDomain`
- Presentation: `DriverModules/Sources/DriverPresentation`
- UIKit Home: `DriverModules/Sources/DriverUIKit`
- SwiftUI Home: `DriverModules/Sources/DriverSwiftUI`
- Xcode project: `ScheduledMobilityDriver.xcodeproj`

## Validation

Build the app:

```sh
xcodebuild -project ScheduledMobilityDriver.xcodeproj -scheme ScheduledMobilityDriver -destination 'generic/platform=iOS Simulator' build
```

Run package tests on a concrete simulator:

```sh
(cd DriverModules && xcodebuild -scheme DriverModules-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' test)
```

Plain `swift test` is not suitable for the current package because UIKit-backed targets compile for iOS, not macOS.

## Next Phase

Before real backend integration, inspect the scheduled-mobility backend controllers, DTOs, validation, security configuration, and OpenAPI. Do not invent endpoints, statuses, OTP length, upload limits, token lifetimes, or trip transition names.
