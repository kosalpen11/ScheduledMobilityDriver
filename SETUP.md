# Project Setup

This guide walks through opening, configuring, building, testing, and running the Scheduled Mobility Driver iOS app.

## 1. Requirements

- macOS with Xcode 26.2 or newer.
- iOS Simulator runtime installed.
- iOS 15.0 or later for simulator/device runs.
- Apple Developer Team selected in Xcode when installing on a physical iPhone.

## 2. Open the project

Open the Xcode project from the repository root:

```sh
open ScheduledMobilityDriver.xcodeproj
```

In Xcode:

1. Select the `ScheduledMobilityDriver` scheme.
2. Select an iOS Simulator or a connected iPhone.
3. Let Xcode resolve the local `DriverModules` Swift package.

## 3. Choose API environment

The app is currently wired to mock data by default so it can run without backend access.

The active environment is set in:

`DriverApp/App/SceneDelegate.swift`

Default:

```swift
let compositionRoot = CompositionRoot(configuration: .mock)
```

Use staging:

```swift
let compositionRoot = CompositionRoot(configuration: .staging)
```

Available configurations are defined in:

`DriverModules/Sources/PlatformServices/Environment.swift`

Current values:

- Mock: no backend, local fake auth and Home data.
- Local: `http://localhost:8080/api/v1`
- Staging: `https://api.146-190-4-99.sslip.io/api/v1`

For a physical iPhone, `localhost` means the phone itself. Use staging or a development-machine address reachable from the phone.

## 4. Run with mock data

Keep `.mock` in `SceneDelegate.swift`, then press Run in Xcode.

Mock auth accepts:

- Phone: any non-empty phone string.
- OTP code: `1234`.

After successful mock login, the app shows the Home screen with mock scheduled trips.

## 5. Run against staging

Change `SceneDelegate.swift` to:

```swift
let compositionRoot = CompositionRoot(configuration: .staging)
```

Then run the app. The auth flow uses:

- `POST /auth/otp/request`
- `POST /auth/otp/verify`
- `POST /auth/refresh`
- `POST /auth/logout`
- `GET /me`
- `GET /drivers/me`

The Postman sample uses phone `+85512000002` and OTP `1234`, but staging behavior depends on backend configuration.

## 6. Build from Terminal

Simulator build:

```sh
xcodebuild -project ScheduledMobilityDriver.xcodeproj \
  -scheme ScheduledMobilityDriver \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Generic device build without signing:

```sh
xcodebuild -project ScheduledMobilityDriver.xcodeproj \
  -scheme ScheduledMobilityDriver \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 7. Run package tests

Use a concrete installed simulator. This project was last verified with `iPhone 17, iOS 26.2`.

```sh
cd DriverModules
xcodebuild -scheme DriverModules-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  test
```

If that simulator is not installed, list available destinations:

```sh
xcrun simctl list devices available
```

Then replace the destination name and OS in the test command.

## 8. Switch Home UI renderer

UIKit Home is the default.

To run SwiftUI Home:

1. Open the app target build settings.
2. Find `Swift Active Compilation Conditions`.
3. Add `SWIFTUI_HOME`.
4. Build and run again.

Both UIKit and SwiftUI Home screens use the same `HomeViewModel` and are selected through the composition root.

## 9. Physical iPhone setup

In Xcode:

1. Select the `ScheduledMobilityDriver` target.
2. Open `Signing & Capabilities`.
3. Select your development team.
4. Confirm the bundle identifier is `com.scheduledmobility.driver`.
5. Select the connected iPhone and press Run.

If install fails with an invalid bundle or missing identifier, clean DerivedData and rebuild:

```sh
rm -rf ~/Library/Developer/Xcode/DerivedData/ScheduledMobilityDriver-*
xcodebuild -project ScheduledMobilityDriver.xcodeproj \
  -scheme ScheduledMobilityDriver \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Then retry from Xcode with signing enabled.

## 10. Expected validation

Before handing off changes, run:

```sh
xcodebuild -project ScheduledMobilityDriver.xcodeproj -scheme ScheduledMobilityDriver -destination 'generic/platform=iOS Simulator' build
(cd DriverModules && xcodebuild -scheme DriverModules-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' test)
```

Current expected result:

- App build succeeds.
- `DriverModules-Package` tests pass with 8 tests and 0 failures.
