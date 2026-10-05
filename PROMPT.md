# Coding Agent Prompt — Scheduled Mobility Driver

Build a native Swift Driver App for the scheduled-mobility backend, supporting **iOS 15.0 and later**.

First read the provided README.md and inspect the existing project. Follow its architecture and adapt to existing conventions.

## Product and design

- Create a polished, map-first driver experience inspired by Uber’s clarity and native interactions, using original branding and layouts.
- Prioritize scheduled trips: availability, next trip, pickup time, destination, and primary/backup assignment.
- Use system typography, SF Symbols, semantic colors, large touch targets, and subtle haptics.
- Support dark mode, Dynamic Type, VoiceOver, Reduce Motion, safe areas, and proper keyboard behavior.
- Preserve native navigation, swipe-back, sheets, alerts, and dismissal behavior.

## Modular architecture

Use local Swift Package Manager targets with explicit dependency boundaries:

- DriverDomain: entities, use cases, repository protocols; Foundation only.
- DriverData: backend DTOs, mappings, repositories, and caching.
- PlatformServices: URLSession, Keychain, and CoreLocation adapters.
- DriverPresentation: shared ViewModels and screen state using Combine.
- FeatureContracts: typed navigation outputs and screen factory protocols.
- DriverUIKit: UIKit screens and factories.
- DriverSwiftUI: SwiftUI screens and factories.
- DesignSystem: shared semantic tokens and UI components.
- App: composition root, lifecycle, and coordinators.

Keep dependencies acyclic. UI modules must not import concrete data implementations.

## Injectable UIKit and SwiftUI

- Use a UIKit coordinator and UINavigationController as the app shell.
- Inject feature screen factories through protocols.
- Factories return UIViewController.
- UIKit factories return native view controllers.
- SwiftUI factories return UIHostingController.
- Select the UI implementation in the composition root, independently for each feature.
- Both implementations must reuse the same domain use cases, repositories, and presentation models.
- Screens emit typed outputs; the coordinator owns navigation.
- Build Home in both UIKit and SwiftUI to demonstrate interchangeability. Do not duplicate every screen unless requested.
- Use initializer injection; avoid service locators and global mutable singletons.

## iOS 15 compatibility

- Set every app and package target to iOS 15.
- Use ObservableObject, @Published, and @MainActor for presentation.
- Use MKMapView directly or through UIViewRepresentable.
- Use UISheetPresentationController with medium/large detents.
- Use an anchored compact home panel when needed.
- Do not require NavigationStack, SwiftUI presentationDetents, PhotosPicker, @Observable, or newer SwiftUI Map APIs.
- Any newer API must have an availability guard and a complete iOS 15 fallback.

## Backend integration

Inspect the scheduled-mobility backend source and OpenAPI before implementing real requests:
https://github.com/channrith/scheduled-mobility/

Verify endpoints, payloads, OTP length, driver states, trip transitions, upload limits, and location transport. Do not invent contracts. If unavailable, use injected mocks and document missing contracts.

Implement:

- Environment-based API configuration.
- URLSession networking with async/await and cancellation.
- DTO-to-domain mapping.
- Keychain token storage.
- Actor-based refresh coordination sharing one in-flight refresh operation.
- One authenticated retry after refresh.
- Recoverable handling of temporary network failures.
- Problem Details decoding where supported.
- Stable idempotency keys across retries where the backend supports them.
- Redacted logging.

## Driver workflow

- Session restoration.
- Phone and OTP login with autofill and paste support.
- Driver onboarding and approval status.
- Profile, documents, and vehicle.
- Availability and upcoming scheduled trips.
- Trip details and backend-authorized actions.
- Location tracking and reconnect behavior.

Use a centralized TripActionResolver. Treat backend state as authoritative. Handle rejected transitions, version conflicts, cancellation, and reassignment.

## Map and location behavior

- Keep the map instance and camera stable.
- Manual panning disables follow mode; recenter restores it.
- Do not recenter on every GPS update.
- Keep tracking independent of screen lifetime.
- Request permissions contextually.
- Filter stale and inaccurate samples.
- Use bounded buffering and discard stale location updates.
- Preserve active-trip content during network loss.

## Implementation process

Start with Phase 1:

1. Create the app shell and package targets.
2. Establish dependency injection and navigation contracts.
3. Create mock scheduled-trip data.
4. Implement Home in UIKit and SwiftUI.
5. Demonstrate switching factories without changing business logic.
6. Build and verify iOS 15 compatibility.

Create or update README.md with setup instructions, module responsibilities, dependency rules, UI injection examples, and validation steps.

For each phase, implement the work, run available builds and meaningful tests, fix errors, and report changed files and validation results. If Xcode is unavailable, clearly state what remains unverified.

Keep the implementation practical: small cohesive types, explicit ownership, minimal abstractions, and no unnecessary third-party dependencies.
