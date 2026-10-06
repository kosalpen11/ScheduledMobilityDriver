# Scheduled Mobility Driver — iOS

## Current status

Phase 1 Home, Phase 2 authentication, Phase 3 driver profile/onboarding, and Phase 4 mock trip details/actions are scaffolded in this repository:

- `ScheduledMobilityDriver.xcodeproj` contains the native UIKit app target.
- `DriverApp/App` owns app lifecycle, navigation, and dependency composition.
- `DriverModules` is a local Swift package with iOS 15 package targets.
- Home is implemented in both UIKit and SwiftUI through the same `HomeViewModel`.
- Authentication is implemented behind `AuthScreenFactory` with SwiftUI screens hosted in UIKit navigation, shared presentation state, staging URLSession requests, and Keychain-backed token storage.
- Driver profile, onboarding checklist, vehicle details, and documents are implemented behind `DriverProfileScreenFactory` with real staging repository wiring by default.
- Trip details and mock-authorized trip actions are implemented behind `TripScreenFactory`; staging uses explicit unavailable trip/availability repositories because the current backend still does not expose driver trip or availability APIs.
- The app uses staging by default for development. Staging origin is `https://api.146-190-4-99.sslip.io` and the API prefix is `/api/v1`, producing endpoints such as `https://api.146-190-4-99.sslip.io/api/v1/drivers/me`. Mock runtime data is not used unless `CompositionRoot` is intentionally initialized with `.mock`.

Open `ScheduledMobilityDriver.xcodeproj` in Xcode, select the `ScheduledMobilityDriver` scheme, set a development signing team if building to a device, then build or run on iOS 15.0 or later.

For step-by-step local setup, environment selection, simulator testing, and physical iPhone install notes, see [SETUP.md](/Users/kosalpen/Documents/scheduled-mobility-ios/SETUP.md).

Validation commands:

```sh
xcodebuild -project ScheduledMobilityDriver.xcodeproj -scheme ScheduledMobilityDriver -destination 'generic/platform=iOS Simulator' build
xcodebuild -project ScheduledMobilityDriver.xcodeproj -scheme ScheduledMobilityDriver -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
cd DriverModules && xcodebuild -scheme DriverModules-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' test
```

Home is currently composed with the SwiftUI renderer by default. The UIKit Home variant is preserved and remains injectable through `HomeScreenFactory`; the coordinator does not change.

Latest validation run:

- `xcodebuild -project ScheduledMobilityDriver.xcodeproj -scheme ScheduledMobilityDriver -destination 'generic/platform=iOS Simulator' build` passed after the National ID capture logging, overlay mapping, CoreMotion shake gate, focus steering, and upload preview/retake refinement.
- `xcodebuild -scheme DriverModules-Package -destination 'platform=iOS Simulator,id=617D7F10-00AE-4DDB-92BA-E30F1FB60B12' test` passed on an iPhone SE (3rd generation) iOS 17.0 simulator after the National ID geometry fix. The suite executed DriverData, DriverDomain, DriverPresentation, and DriverUIKit tests, including seven National ID geometry tests.
- `xcodebuild -project ScheduledMobilityDriver.xcodeproj -scheme ScheduledMobilityDriver -destination 'platform=iOS Simulator,id=8E235B8E-1C0B-43AE-807B-FE1E232B05CA' build` passed on Xcode 26.2 using an iPhone 17 simulator on iOS 26.2 after the Home layout/profile sheet refinement.
- `xcodebuild -project ScheduledMobilityDriver.xcodeproj -scheme ScheduledMobilityDriver -destination 'generic/platform=iOS Simulator' build` passed after the Driver Profile and document screen refinement.
- The refined profile was visually inspected on an iPhone SE (3rd generation) iOS 17.0 simulator using mock profile data reached through the Debug development bypass. The compact header, Next step, document progress, driver document rows, vehicle, help, and account sections were visible and readable on the small screen.
- Automated tests were not run for this Driver Profile/document refinement phase per instruction.
- Runtime OTP verification against staging was not performed in this phase; compilation only was verified.
- Live National ID auto-capture alignment was not verified on a physical device in this pass. Debug builds now emit `[NID][FRAME]`, `[NID] CAPTURE`, `[NID] FOCUS`, and `[NID][PROCESS]` logs to help tune frame fit, stability, focus steering, motion rejection, preview-space orientation, and processing quality on-device. Frame motion uses an EMA (`motionRaw` and `motionEMA`) so transient Vision jitter does not make the guidance message oscillate. Preview geometry now explicitly accounts for Vision `.right`, an explicitly configured portrait orientation on video, photo, and preview connections, bottom-left Vision coordinates, preview-layer aspect-fill conversion, mirroring, post-transform corner ordering, and long-pair quad normalization before tracking. National ID processing sharpness is logged as Sobel RMS (`scale=sobelRMS`) so the `0.085` floor is comparable to gradient magnitude rather than squared energy.
- Minimum-OS runtime behavior on an actual iOS 15 simulator/device remains unverified because the available concrete simulator was iOS 26.2.
- Additional simulator screenshots and broader device/dark-mode/Dynamic Type visual checks were blocked by low host disk space during this pass.

## Purpose

Build a native Swift driver app for scheduled-mobility, supporting **iOS 15.0 and later**. Prioritize scheduled trips, reliable driver workflows, and calm, map-first interactions inspired by established ride-hailing apps. Use original branding and layouts.

This README is an implementation contract for Codex, Claude Code, or another coding agent. It describes the intended client architecture, not a completed app. Inspect the backend source and OpenAPI before integrating: endpoints, OTP length, payloads, statuses, upload limits, and token lifetimes from earlier examples are provisional until verified.

## Core decisions

| Part | Choice | Why |
|---|---|---|
| Minimum OS | iOS 15.0 on every app/package target | Consistent baseline without accidental newer API dependencies |
| App shell | UIKit scene lifecycle and UINavigationController coordinator | Stable native navigation across UIKit and SwiftUI screens |
| Feature UI | Injected screen factories | Choose UIKit or SwiftUI per feature without changing business logic |
| Business logic | Foundation-only domain and use cases | Reusable, independently testable, UI independent |
| Presentation | MainActor ObservableObject and Published state | Shared state for SwiftUI and UIKit via Combine |
| Dependency injection | Explicit initializers and app composition root | Dependencies and lifetimes remain visible |
| Networking | URLSession with async/await | Native requests, cancellation, and testable transport |
| Maps/location | MKMapView and CoreLocation adapters | Stable iOS 15 map camera and tracking control |
| Modularization | Local Swift Package Manager targets | Enforce import boundaries without a large framework stack |

Do not add a dependency injection framework by default. Do not create a protocol for every struct: use protocols at replaceable boundaries such as repositories, clocks, location, token storage, and feature factories.

## Module layout

The repository starts with one local package containing focused targets; split into multiple packages only when ownership or reuse requires it.

```text
DriverApp/
  App/                    # SceneDelegate, AppCoordinator, CompositionRoot
  Configuration/          # xcconfig and environment selection
  DriverModules/
    Package.swift
    Sources/
      DriverDomain/       # Entities, repository contracts, use cases
      DriverData/         # Repository implementations, DTO mapping, cache
      PlatformServices/   # HTTP, Keychain, CoreLocation adapters
      FeatureContracts/   # UI factory protocols, routes, output callbacks
      DriverPresentation/ # Shared feature models and UI state
      DesignSystem/       # Semantic tokens and native components
      DriverUIKit/        # UIKit factory and feature screens
      DriverSwiftUI/      # SwiftUI factory and feature screens
    Tests/
      DriverDomainTests/
      DriverDataTests/
      DriverPresentationTests/
  DriverAppTests/
  DriverAppUITests/
```

Implemented Phase 1 responsibilities:

| Target | Responsibility |
|---|---|
| DriverDomain | Scheduled trip entities, repository contracts, use cases, and `TripActionResolver` |
| DriverData | Mock repositories, auth DTOs, backend auth repository, and DTO-to-domain mapping |
| PlatformServices | Environment config, URLSession HTTP transport, Problem Details decoding, Keychain token storage, and refresh coordination |
| FeatureContracts | Home/Auth output routes and screen factory protocols |
| DriverPresentation | `HomeViewModel`, `AuthViewModel`, screen states, and display formatting |
| DesignSystem | Shared semantic UIKit tokens usable from UIKit and SwiftUI |
| DriverUIKit | Native map-first Home screen, Auth screens, and factories |
| DriverSwiftUI | SwiftUI Home screen hosted in `UIHostingController` |
| App | Scene lifecycle, `UINavigationController` coordinator, and composition root |

## Verified authentication contract

The Phase 2 implementation was checked against `https://github.com/channrith/scheduled-mobility/`, including `docs/openapi.json` and the Spring controllers under `core-app/src/main/java/com/mobility/core/identity`.

Confirmed endpoints:

| Operation | Contract |
|---|---|
| Request OTP | `POST /api/v1/auth/otp/request` with `{"phone": String}`. Returns `202` and `{"expiresInSeconds": Int, "resendAfterSeconds": Int}` |
| Verify OTP | `POST /api/v1/auth/otp/verify` with `{"phone": String, "code": String}`. Returns `{"accessToken","tokenType","expiresIn","refreshToken","refreshExpiresIn"}` |
| Refresh | `POST /api/v1/auth/refresh` with `{"refreshToken": String}`. Rotates refresh token and returns the same token response shape |
| Logout | `POST /api/v1/auth/logout` with bearer access token and `{"refreshToken": String}`. Returns `204`; unknown tokens are ignored |
| Current user | `GET /api/v1/me` with bearer access token. Returns user id, phone, full name, preferred language, account status, and roles |
| Driver identity | `GET /api/v1/drivers/me` with bearer access token and `DRIVER` role. Returns driver id, user id, phone, full name, status, documents, vehicle, readiness, and history |
| Driver documents | `GET /api/v1/drivers/me/documents` with bearer access token. Returns current document metadata |

Confirmed rules:

- Phone OTP accepts Cambodian local formats such as `012 345 678` and E.164.
- OTP default length is 4 digits.
- OTP is valid for 5 minutes.
- Resend cooldown is 60 seconds.
- Request limit is 5 per phone per hour.
- Verify attempts are limited to 5 wrong codes per OTP.
- Access tokens last 15 minutes.
- Refresh tokens last 30 days.
- Refresh token replay revokes the session family; refresh retries must reuse the same `Idempotency-Key`.
- Mutating endpoints accept optional `Idempotency-Key`; a reused key with a different body returns `422 idempotency.key-reused`.
- Errors are RFC 7807 `application/problem+json` with a stable `code`, localized `title` and `detail`, and occasional extra properties.
- Missing/invalid access tokens return `401 auth.unauthorized`; forbidden role/scope returns `403 auth.forbidden`.

Implemented client behavior:

- `AuthAPIRepository` maps backend DTOs to domain models.
- `mobility-driver.postman_collection.json` was treated as API data only. It confirms relative paths under `{{BASE}}`, OTP sample phone `+85512000002`, sample OTP `1234`, bearer logout, `/drivers/me`, and `/drivers/me/documents`.
- `HTTPClient` decodes Problem Details and preserves transport versus server failures.
- `APIConfiguration.staging` stores origin `https://api.146-190-4-99.sslip.io` and API prefix `/api/v1`; endpoint paths are relative to that prefixed API base.
- `HTTPClient` normalizes endpoint construction so `/api/v1` appears exactly once even if a caller accidentally supplies a path with the prefix.
- `KeychainTokenStorage` stores access/refresh token payloads with device-only accessibility.
- `RefreshCoordinator` shares one in-flight refresh task and clears credentials only on confirmed invalid refresh credentials.
- Authenticated requests retry at most once after a successful refresh.
- `AuthViewModel` prevents duplicate submissions while a request is pending.
- `AppCoordinator` restores a session at launch, shows Auth when restoration is absent or invalid, shows a retryable restore failure state for transient errors, and never shows Home until driver eligibility is resolved.

## Staging login and driver entry flow

The development app now starts in `.staging` mode from `SceneDelegate` and uses `APIConfiguration.staging` with origin `https://api.146-190-4-99.sslip.io` plus prefix `/api/v1`.

Verified URL construction:

| Operation | Final URL |
|---|---|
| Request OTP | `https://api.146-190-4-99.sslip.io/api/v1/auth/otp/request` |
| Verify OTP | `https://api.146-190-4-99.sslip.io/api/v1/auth/otp/verify` |
| Refresh | `https://api.146-190-4-99.sslip.io/api/v1/auth/refresh` |
| Logout | `https://api.146-190-4-99.sslip.io/api/v1/auth/logout` |
| Current user | `https://api.146-190-4-99.sslip.io/api/v1/me` |
| Driver profile | `https://api.146-190-4-99.sslip.io/api/v1/drivers/me` |
| Driver documents | `https://api.146-190-4-99.sslip.io/api/v1/drivers/me/documents` |
| Submit onboarding | `https://api.146-190-4-99.sslip.io/api/v1/drivers/me/submit` |

Runtime wiring:

- Authentication, session restoration, token refresh, logout, driver profile, document listing, document upload, and onboarding submission use real URLSession-backed repositories in staging mode.
- Tokens are stored in Keychain through `KeychainTokenStorage`.
- Auth, Home, and driver entry status screens use SwiftUI hosted inside `UIViewController` factories; UIKit variants remain present for preserved features and injection.
- `AuthAPIRepository` loads `/me` after OTP verification or restoration. Driver profile/readiness is loaded separately through `DriverProfileAPIRepository` so missing profiles and non-driver accounts can be handled explicitly.
- `DriverEntryResolver` centralizes routing after `/me` and, when applicable, `/drivers/me`.

Routing rules:

| Backend-confirmed state | App route |
|---|---|
| User lacks `DRIVER` role | Non-driver access screen with change-account action |
| User has `DRIVER` role but `/drivers/me` returns missing profile | Missing driver profile screen; no self-registration is offered |
| `PENDING` | Onboarding checklist/documents screen |
| `DOCS_SUBMITTED` | Application review screen |
| `TRAINING` | Training status screen |
| `REJECTED` | Rejection/restricted screen with only refresh and sign-out actions |
| `SUSPENDED` | Suspended/restricted screen with refresh and sign-out actions |
| `APPROVED` with active vehicle and clean readiness | Home |
| `APPROVED` with missing/pending/expired readiness or no active vehicle | Readiness screen showing outstanding requirements |

Session behavior:

- Duplicate OTP request and verification submissions are ignored while a request is in flight.
- Cambodia phone numbers default to `+855` and are normalized before the staging OTP request.
- OTP verification uses the verified four-digit backend contract.
- Resend cooldown is driven by the server challenge response and enforced in presentation state.
- Actor-based refresh coordination is preserved and authenticated requests retry at most once after refresh.
- Confirmed invalid/revoked refresh credentials clear stored tokens.
- Temporary restore or driver lookup failures preserve credentials and show Retry plus explicit Sign Out.
- Logout cancels entry routing work, calls backend logout when tokens exist, clears Keychain tokens, and clears driver session-owned state.

Backend limitations honored in staging mode:

- Driver self-registration is not offered because the verified backend only exposes admin-side driver creation.
- Trip listing/detail/actions and availability retrieval/mutation are not wired to staging because no implemented backend endpoints were verified. Real mode uses explicit unavailable repositories and does not silently display mock operational data or simulate successful availability changes.

## Phase 5 HTTP logging

Phase 5 adds an injected `HTTPLogger` in `PlatformServices`. The app passes `ConsoleHTTPLogger` into `HTTPClient` only for Debug builds when the selected runtime is `.staging`; production builds and non-staging environments do not receive a logger.

How to view logs:

- Run the `ScheduledMobilityDriver` scheme in Xcode using the default staging runtime.
- Open the Xcode debug console.
- Trigger login, restore, refresh, profile, document, or onboarding requests.
- Logs are emitted as grouped request/response/error blocks with one logical request ID per operation.

Logging behavior:

- Requests include logical request id, attempt number, method, sanitized URL, headers, and sanitized body.
- Authenticated retries reuse the same request id and increment `attempt`.
- Refresh requests get separate request ids and include `linked=<triggering-request-id>` when refresh is caused by a failed authenticated request.
- Responses include status, duration in milliseconds, and sanitized body.
- Errors include type, code, sanitized message, duration, request id, and attempt.
- Valid JSON bodies are pretty-printed and redacted before printing.
- Non-JSON bodies are safely summarized and truncated.
- Multipart logs show only field name, field/file kind, MIME type, and byte count; filenames and file bytes are never logged.
- The logger redacts `Authorization`, cookies, API keys, tokens, refresh tokens, OTP codes, phone numbers, personal data fields, and sensitive query parameters.
- Logger output is actor-serialized to keep each HTTP block grouped and avoid concurrent interleaving.

Verified contract fields used by the logger-aware staging flow:

| Operation | Fields |
|---|---|
| OTP request | request `phone`; response `expiresInSeconds`, `resendAfterSeconds` |
| OTP verify | request `phone`, `code`; response `accessToken`, `tokenType`, `expiresIn`, `refreshToken`, `refreshExpiresIn` |
| Refresh/logout | request `refreshToken`; refresh response matches token response |
| Current user | response `id`, `phone`, `fullName`, `preferredLang`, `status`, `roles` |
| Driver profile | response `id`, `userId`, `fullName`, `phone`, `status`, `nationalIdMasked`, `vehicle`, `documents`, `readiness`, `createdAt` |
| Document upload | multipart fields `type`, `file`, optional `expiresOn`, optional `vehicleId` |

## Verified driver profile, vehicle, and document contract

The Phase 3 implementation was checked against `docs/openapi.json`, `DriverSelfController`, `DriverViews`, `DocumentService`, and `mobility-driver.postman_collection.json`.

Confirmed endpoints:

| Operation | Contract |
|---|---|
| Driver profile | `GET /api/v1/drivers/me`. Requires bearer JWT with `DRIVER` role. Returns status, masked personal data, active vehicle, documents, readiness, and history |
| Driver documents | `GET /api/v1/drivers/me/documents`. Requires bearer JWT with `DRIVER` role. Returns current document metadata |
| Upload document | `POST /api/v1/drivers/me/documents`, `multipart/form-data`, optional `Idempotency-Key`. Fields: `type`, `file`, optional `expiresOn`, optional `vehicleId`. Returns `DocumentView` |
| Submit onboarding | `POST /api/v1/drivers/me/submit`, optional `Idempotency-Key`. Moves `PENDING` to `DOCS_SUBMITTED` when required personal documents are uploaded |

Confirmed statuses and rules:

- Driver statuses are `PENDING`, `DOCS_SUBMITTED`, `TRAINING`, `APPROVED`, `REJECTED`, and `SUSPENDED`.
- Only `APPROVED` drivers with clean dispatch readiness and an active vehicle are operationally eligible.
- Drivers can upload documents unless status is `REJECTED`; rejected drivers receive `409 document.upload-not-allowed`.
- Required personal onboarding documents are `NATIONAL_ID`, `DRIVING_LICENSE`, and `PROFILE_PHOTO`.
- Vehicle readiness documents are `VEHICLE_REGISTRATION` and `VEHICLE_INSURANCE` when an active vehicle is assigned.
- Document statuses are `PENDING_REVIEW`, `APPROVED`, `REJECTED`, and `SUPERSEDED`.
- Upload content is verified by magic bytes, not by declared MIME type. Supported content is JPEG, PNG, and PDF; `PROFILE_PHOTO` must be JPEG or PNG.
- Maximum upload size is 10 MB.
- All document types except `PROFILE_PHOTO` require an ISO `yyyy-MM-dd` expiry date, and past expiry dates are rejected.
- Vehicle documents require the driver's assigned active vehicle id; non-vehicle documents must not include `vehicleId`.
- Upload replaces the current document for the same type and vehicle.
- Mutating endpoints accept `Idempotency-Key`; reusing the same key with a different body returns `422 idempotency.key-reused`.
- Problem Details responses use stable codes including `document.empty`, `document.too-large`, `document.unsupported-type`, `document.expiry-required`, `document.expiry-in-past`, `document.vehicle-required`, `document.vehicle-not-allowed`, `document.upload-not-allowed`, `driver.documents-missing`, `driver.documents-not-approved`, `driver.documents-expired`, and `driver.vehicle-required`.

Implemented client behavior:

- `DriverProfileRepository` exposes profile retrieval, document listing, document upload, onboarding submission, and session cleanup.
- `DriverProfileAPIRepository` maps backend DTOs, including status history reasons, to domain models and sends multipart uploads using the verified field names.
- `MockDriverProfileRepository` keeps mock runtime behavior explicit and mirrors readiness, duplicate upload, submission, and logout cleanup behavior.
- `DriverDocumentUploadValidator` enforces local size, file type, expiry, and vehicle-field rules before network upload.
- `DriverEligibilityPolicy` centralizes operational eligibility and onboarding-submission checks.
- `DriverProfileViewModel` refreshes authoritative profile state after uploads and submission, prevents duplicate submissions/uploads, and preserves backend logic outside Views.
- `DriverProfileViewController` provides profile status, onboarding checklist, vehicle assignment, document status rows, photo library/camera/file upload flow, National ID Vision processing, loading/error feedback, haptics, Dynamic Type, VoiceOver labels, dark mode colors, and iOS 15-compatible native navigation.
- `AppCoordinator` opens Phase 3 through `DriverProfileScreenFactory`; logout clears driver session state before auth tokens.

## Home layout and profile access refinement

- SwiftUI and UIKit Home keep the map full-screen and use a stable, safe-area-aware bottom panel with responsive horizontal margins and a 760-point maximum width on larger screens.
- The panel hierarchy is explicit: Driver availability, Next scheduled trip, Today's assignments, then empty or unavailable feedback. Trip rows remain full-width and use friendly assignment/action labels.
- The SwiftUI next-trip card opens trip details with one clear View trip action when an assigned trip exists. Empty and unavailable states never create fake trips.
- Home profile buttons use native person symbols in both renderers and emit the existing typed `HomeOutput.showProfile` route.
- `AppCoordinator` presents an injected compact profile summary sheet from `DriverProfileScreenFactory`, backed by the existing `DriverProfileViewModel`. The sheet shows driver name, masked phone, friendly status, readiness, vehicle summary, View profile, and Sign out.
- View profile continues into the existing full profile screen; profile loading and logout remain outside Home Views.
- The sheet uses iOS 15 page-sheet detents, shared colors/spacing, Dynamic Type, VoiceOver labels, dark mode, and native reduced-motion-friendly presentation.
- The Debug staging login bypass opens Home with an explicit mock Home factory so trips, primary/backup assignments, availability, and trip actions can be reviewed without a staging account. It does not change normal staging runtime wiring.
- Home uses FloatingPanel 3.2.4 through Swift Package Manager for the panel interaction. UIKit and SwiftUI share `.tip`, `.half`, and `.full` anchors, native grabber behavior, and scroll tracking; the map remains stable underneath.

Remaining UI limitations:

- The map remains the existing MapKit surface with the current default region; live driver location tracking is outside this phase.
- Trip and availability data remain explicitly unavailable in real staging until verified backend endpoints are deployed.

## Phase 7 driver profile and onboarding experience

Phase 7 refines the existing driver profile and onboarding UI without adding backend trip or availability APIs.

Implemented behavior:

- Driver identity shows full name, masked phone number, and a friendly account status. Raw backend enums are not shown.
- Account guidance uses backend status and readiness:
  - `PENDING`: complete your application.
  - `DOCS_SUBMITTED`: application under review.
  - `TRAINING`: training is required before driving.
  - `APPROVED`: either ready to drive or the remaining readiness blocker.
  - `REJECTED`: backend status-history reason when provided, with no unsupported in-app appeal action.
  - `SUSPENDED`: backend status-history reason when provided, with no unsupported reinstatement action.
- “What you need to do” prioritizes one next action: submit application, upload/replace the most important document, wait for review, contact the operator, or no action when ready.
- “You’re ready to drive” appears only when backend readiness confirms approved status, active vehicle, and clean document readiness. This remains separate from online availability, which is still unavailable until backend APIs exist.
- Documents use driver-friendly names and statuses: Not uploaded, Under review, Approved, Needs replacement, Expired.
- Document detail dialogs show backend rejection reasons and expiry dates where present.
- Upload/replacement actions are offered only when supported by profile status and document state.
- Selected-file confirmation, local validation, upload loading state, recoverable error alerts, and authoritative profile refresh after upload/submit are preserved.
- Remote document preview is still not offered because no driver document content endpoint is exposed.
- Vehicle assignment remains read-only and explains that assignment is operator-managed when missing.
- Help and account is separated from operational actions; sign out lives there. Support options are shown only when configured; no support contact is invented.

Remaining Phase 7 limitations:

- No configured support-contact API or local configuration exists yet, so the Help section falls back to the driver’s normal operator channel.
- Driver profile editing, vehicle assignment changes, and remote document preview remain unavailable because verified driver APIs do not support them.

Unavailable or intentionally mocked contract areas:

- Driver self profile editing is not exposed by the verified driver app API; Phase 3 presents profile as read-only.
- Vehicle assignment mutation is admin-side only; Phase 3 presents assigned vehicle state as read-only.
- Driver-side remote document preview/download is not exposed; Phase 3 supports local selected-file confirmation before upload and server metadata listing after upload.
- Real trip-operation availability gating is still limited by the mocked Home availability repository; the verified eligibility policy is implemented for driver state and documented for later trip backend wiring.

## Phase 4 trip and availability contract status

The backend was inspected in `core-app/src/main/java`, `docs/openapi.json`, and `mobility-driver.postman_collection.json`. Phase 6 repeated this inspection against a fresh clone of `https://github.com/channrith/scheduled-mobility` at commit `7d12c29`.

Verified unavailable backend areas:

- No driver assigned-trip listing endpoint is exposed.
- No driver trip detail endpoint is exposed.
- No driver trip action or transition endpoint is exposed.
- No driver availability retrieval or mutation endpoint is exposed.
- No trip status, trip assignment, cancellation, reassignment, version/conflict, or driver permission API contract exists in the current backend implementation.
- The backend has empty `booking` and `dispatch` module packages plus database schemas, but no implemented controllers or domain classes for driver trips/availability.
- The Postman collection still contains auth, refresh, logout, `/drivers/me`, and `/drivers/me/documents`; it does not contain trip or availability requests.

Implemented client behavior:

- `TripScreenFactory` injects trip detail screens as `UIViewController`.
- `TripDetailViewModel` loads details, derives one primary action from `TripActionResolver`, prevents duplicate action submissions, uses a stable idempotency key per trip/action/version in mock mode, preserves content through recoverable errors, and refreshes authoritative state after conflicts.
- `TripActionResolver` centralizes action rules. Primary assignments can advance through scheduled, en route, arrived, in progress, and completed states; backup, cancelled, reassigned, and completed trips are view-only.
- `MockTripRepository` supports listing, detail, state transitions, version conflicts, backup permission rejection, and reassignment-style missing trip failures.
- `UnavailableTripRepository` and `UnavailableAvailabilityRepository` are used outside mock mode so staging/production never silently display mock operational data or report a local toggle as server-confirmed.
- In staging, unavailable trip and availability repositories now throw explicit `TripFailure.unavailable` errors instead of returning a fake empty/available operational state.
- UIKit and SwiftUI Home show the backend-unavailable message, disable availability actions, and provide Retry affordances for recoverable reload attempts.
- SwiftUI Home refreshes when the app returns to the foreground while avoiding overlapping requests through `HomeViewModel`.
- UIKit trip detail UI uses the existing map-first style, native navigation, rounded cards, shared color/spacing tokens, Dynamic Type, VoiceOver-friendly labels, and haptics.
- Home refreshes when returning from trip details; SwiftUI Home keeps its existing renderer and shared view model behavior.

Phase 6 backend work required before real wiring:

| Required backend contract | Needed by iOS client |
|---|---|
| Driver assigned trip listing endpoint | Load Home assignments without mock data |
| Driver trip detail endpoint | Open authoritative trip detail screens |
| Driver availability get/update endpoints | Show server-confirmed availability and allow online/offline changes |
| Trip action endpoint with permitted transitions | Execute pickup/arrival/start/complete actions from `TripActionResolver` |
| Primary/backup permission model | Disable actions for backup assignments unless backend authorizes promotion |
| Trip status enum and action response DTOs | Map server state to `TripStatus`, `TripAssignment`, and `ScheduledTrip` |
| Optimistic version or ETag/conflict behavior | Refresh authoritative state on conflicts without losing visible content |
| Cancellation and reassignment errors/events | Preserve content while explaining removed or changed assignments |
| Idempotency-Key requirements for trip/availability mutations | Reuse stable keys for retries of the same operation |
| Privacy guidance for logs | Ensure passenger details and precise coordinates stay out of HTTP logs |

Group files inside Domain, Data, Presentation, and UI targets by feature: Auth, Home, Trips, Profile, Documents, and Vehicle. Add Earnings only when a driver-facing backend contract exists.

Allowed dependencies:

- DriverDomain imports Foundation only; no UIKit, SwiftUI, HTTP DTOs, or persistence.
- PlatformServices contains platform adapters; it may depend on narrow domain contracts when implementing them.
- DriverData imports DriverDomain and PlatformServices.
- DriverPresentation imports DriverDomain and Combine; no UIKit or SwiftUI.
- FeatureContracts imports UIKit for its controller boundary and DriverDomain for typed identifiers.
- DriverUIKit and DriverSwiftUI import presentation, contracts, and design system; neither imports DriverData.
- App imports implementations and connects them. Features never import App or sibling feature internals.

Declare `.iOS(.v15)` in Package.swift. Keep the graph acyclic. Make only intentional module APIs public; keep implementation types internal where possible.

## Inject UI independently from business logic

Use a UIViewController as the app shell boundary. A SwiftUI factory wraps its view with UIHostingController; a UIKit factory returns a native controller. Neither factory performs navigation itself.

Example factory contract (illustrative; adapt models to verified backend contracts):

```swift
import UIKit

public enum HomeOutput {
    case showTrip(UUID)
    case showProfile
}

@MainActor
public protocol HomeScreenFactory {
    func makeHome(
        onOutput: @escaping (HomeOutput) -> Void
    ) -> UIViewController
}
```

Factories receive repositories/use cases through their initializers. Each screen construction creates its own presentation model. A HomeSwiftUIScreenFactory can implement:

```swift
@MainActor
func makeHome(
    onOutput: @escaping (HomeOutput) -> Void
) -> UIViewController {
    let model = HomeViewModel(loadUpcomingTrips: loadUpcomingTrips)
    return UIHostingController(
        rootView: HomeView(model: model, onOutput: onOutput)
    )
}
```

HomeUIKitScreenFactory constructs HomeViewController using the same HomeViewModel and output callback. The coordinator receives `any HomeScreenFactory` and calls `makeHome`; it does not branch on concrete UI types.

In the app composition root:

```swift
@MainActor
func makeHomeFactory(useSwiftUI: Bool) -> any HomeScreenFactory {
    if useSwiftUI {
        return HomeSwiftUIScreenFactory(loadUpcomingTrips: loadUpcomingTrips)
    }
    return HomeUIKitScreenFactory(loadUpcomingTrips: loadUpcomingTrips)
}
```

Apply the same pattern to AuthScreenFactory, TripScreenFactory, and ProfileScreenFactory. Inject typed outputs for completion, logout, and navigation. Avoid a giant factory with every screen or an AnyView-based global registry.

For reusable controls, use UIViewRepresentable/UIViewControllerRepresentable to embed UIKit in SwiftUI. Use correct child-controller containment when embedding UIHostingController in a UIKit container. These adapters only translate presentation and callbacks.

## Shared presentation state

- Use `@MainActor final class …ViewModel: ObservableObject` with `@Published private(set)` state and explicit action methods.
- Expose screen-specific states such as initial, loading, content, empty, and failure. Preserve existing trip content during refresh failures.
- UIKit subscribes to Published values and stores AnyCancellable instances for the screen lifetime.
- A SwiftUI view observes an externally owned model with ObservedObject; use StateObject when the view itself creates and owns the model.
- Use async tasks with explicit cancellation and lifetimes. Cancel screen-owned work when its owner is released; retain session tracking independently of screen visibility.
- Keep validation, trip transitions, and eligibility in domain use cases. Presentation formats domain results for display.
- Do not put HTTP requests, token refresh, navigation, or state transitions inside SwiftUI body or UIKit layout callbacks.

## Native behavior on iOS 15

| Need | Baseline implementation |
|---|---|
| Navigation | UINavigationController and injected feature factories |
| SwiftUI inside shell | UIHostingController |
| UIKit inside SwiftUI | UIViewRepresentable or UIViewControllerRepresentable |
| Shared observable state | ObservableObject, Published, Combine |
| Map | MKMapView; optionally wrapped for SwiftUI |
| Native sheet | UISheetPresentationController with medium and large detents |
| OTP autofill | UITextField or SwiftUI TextField with oneTimeCode content type |
| Photo selection | PHPickerViewController |
| Camera/photo/document selection | UIImagePickerController / PHPickerViewController / UIDocumentPickerViewController |
| National ID live camera | AVCaptureSession + Vision rectangle detection |
| National ID gallery processing | Vision rectangle detection, Core Image perspective correction, quality gates, OCR/MRZ expiry extraction |
| Concurrency | async/await, Task, actors |
| Localization | Localizable.strings and stringsdict where needed |

NavigationStack, SwiftUI presentationDetents, PhotosPicker, custom UIKit sheet detents, and UIHostingConfiguration require iOS 16+. Observation's Observable macro and the newer SwiftUI Map APIs require iOS 17+. Do not use them on the baseline path. Add availability-guarded enhancements only when the iOS 15 fallback remains complete.

For an idle compact panel on iOS 15, use an anchored child panel; expand details into a native medium/large sheet. A compact draggable detent is not supplied by the iOS 15 native sheet. Implement a custom accessible container only if that interaction is essential.

Use one navigation owner. Hosted SwiftUI screens emit outputs to the coordinator; they do not nest an independent navigation stack. Choose one owner for navigation titles and toolbar items to avoid duplicate bars.

## Driver workflow

1. Restore session without artificial splash delays.
2. Phone login and OTP verification using backend-defined OTP length, resend rules, and error responses.
3. Resolve driver onboarding/approval status and permitted actions.
4. Show map, availability, next scheduled trip, and today's assignments.
5. Show trip details, primary/backup role, pickup notes, and the next allowed action.
6. Track location when required by availability or an active trip.
7. Complete the trip and display the backend-confirmed payment outcome.

Backend state is authoritative. Map backend statuses to a domain state model and a centralized TripActionResolver. Do not invent status names or transition endpoints. Handle stale versions, rejected transitions, cancelled trips, and reassignment by refreshing authoritative state. Never show a trip as completed until the server confirms it.

Prioritize scheduled work over generic nearby ride requests. Hide unsupported features rather than wiring them to invented APIs.

## Backend integration and security

- Inspect backend controllers, DTOs, validation, security configuration, and OpenAPI first. Document each client operation and confirmed request/response contract.
- Put base URLs in environment configuration. Support mock, local, staging, and production. A physical iPhone's localhost is the phone itself; use the development machine's reachable address.
- Use HTTPS in production. Scope any local HTTP ATS exception to development configuration.
- Keep DTOs in DriverData and map them to domain entities; Views never reference URLs or raw backend enums.
- Inject URLSession/HTTP transport and repositories. Decode structured Problem Details when the backend provides it, with safe fallbacks for other errors.
- Store session tokens in Keychain with suitable device-only accessibility; never in UserDefaults or logs. Choose accessibility deliberately if locked-device background requests are required.
- Coordinate refresh using an actor and one shared in-flight task. Retry an authenticated request at most once after refresh; exclude login/refresh endpoints from interception.
- Logout on confirmed invalid/revoked refresh credentials. Temporary network failure must preserve credentials and show a recoverable state.
- For operations supporting idempotency, generate one key per logical operation and reuse it across retries. Do not regenerate it for the retry or assume every endpoint accepts it.
- Clear account-specific caches on logout. Bound location buffering and protect any persisted sensitive trip data.
- Redact phone numbers, tokens, passenger details, and precise GPS from routine diagnostics.

## Location and maps

Create an injected LocationTrackingService independent of UI. Model authorization, tracking policy, accuracy, connectivity, and upload status separately.

- Request When In Use contextually; request Always only for a verified operational requirement with clear explanation.
- Configure purpose strings and background location capability only when implemented.
- Filter stale/poor-accuracy samples and invalid speed/heading values. Derive cadence and distance thresholds from field testing, not arbitrary fixed assumptions.
- Track availability and active-trip sessions; stop tracking when the policy no longer requires it.
- Upload to the verified location-service contract. A reconnect queue must be bounded and discard stale GPS instead of replaying an unlimited backlog.
- Use a persistent MKMapView, stable annotations, and route overlays. Pan disables follow mode; recenter restores it. Do not reset the camera on each update or sheet resize.
- Verify live transport, authentication, subscriptions, and reconnect behavior before choosing WebSocket or another protocol.

## Design and accessibility

Use system fonts, semantic colors, SF Symbols, 8-point spacing, readable contrast, and at least 44-point targets. Support Dynamic Type, VoiceOver, Reduce Motion, dark mode, safe areas, and keyboard avoidance. Show status in words as well as color.

Keep one primary trip action visible. Use native Form/List behavior for profile/settings. Use subtle haptics for meaningful transitions. Prevent duplicate actions while pending. Preserve swipe-back and standard dismissal behavior except where an operation truly requires confirmation.

Document uploads require verified MIME types and size limits, preview, progress, cancellation, retry, and rejection feedback. Use native pickers and temporary-file cleanup. Do not assume the earlier 10 MB example is the server limit.

## Local development

Once the app target exists:

1. Open the Xcode project/workspace on macOS; select the development signing team.
2. Confirm all targets and local package platforms support iOS 15.0.
3. Set the development API/location URLs using an untracked local configuration file with a committed example.
4. Resolve packages and start with mock repositories; both UI factories must render the same sample workflow.
5. Run backend infrastructure and applications using the backend repository's current README.
6. Switch to real repositories and exercise login, onboarding, scheduled trips, and reconnect behavior.
7. Build for the iOS 15 deployment target and test the minimum OS on an available runtime/device, plus a newer OS.

Do not commit secrets. Do not claim a build passed without running it. If Xcode or an iOS 15 runtime is unavailable, report that limitation and the exact remaining verification.

## Implementation phases

| Phase | Deliverable | Acceptance |
|---|---|---|
| 1 | App shell, package targets, composition root, mock Home factories | UIKit and SwiftUI variants switch through injection; no domain changes |
| 2 | HTTP, Keychain, OTP, refresh, session restoration | Verified contracts; concurrent 401s share refresh; transient failure preserves session |
| 3 | Profile, onboarding, documents | Backend eligibility controls access; upload validation matches server |
| 4 | Map home, availability, scheduled trips | Stable camera; native panel/sheet; correct loading/empty/error states |
| 5 | Trip actions and authoritative state | Allowed transitions, conflict handling, idempotent retries, primary/backup rules |
| 6 | Location uploads and live updates | Permission handling, background policy, bounded buffering, reconnect |
| 7 | Accessibility, localization, device validation | Both UI renderers preserve workflow and minimum-OS compatibility |

Build one phase at a time. First inspect existing code, summarize the changes, then implement the requested phase. Compile and resolve new warnings/errors; test meaningful business behavior. End with changed files, validation results, limitations, and the next phase.

## Verification

- Domain tests: allowed trip actions, approval eligibility, scheduling/time-zone formatting boundaries, and invalid transition handling.
- Data tests: DTO mapping, Problem Details, refresh coordination, revoked versus transient refresh errors, and reuse of idempotency keys.
- Presentation tests: loading/empty/content/failure, stale content during reconnect, duplicate submission prevention, and task cancellation.
- Integration/UI checks: run equivalent login and trip flows through each UI factory; verify navigation outputs and sheet dismissal.
- Device checks: permissions denied/restricted, background/foreground transitions, poor GPS, network loss, large text, VoiceOver, and battery impact.

Keep financial values in backend-specified precise representations rather than floating-point arithmetic. Store timestamps as instants and display them in the intended local time zone.

## Instructions for the coding agent

Implement this guide with iOS 15 as the minimum version. Preserve existing project conventions when compatible. Start with Phase 1 unless instructed otherwise. Keep the app composition root responsible for selecting UIKit or SwiftUI factories, and keep domain/data logic reusable by both. Implement one representative Home screen in both UI frameworks to prove injection; use the selected renderer for subsequent screens instead of duplicating every screen by default.

Before backend integration, inspect the backend repository and replace provisional assumptions with verified contracts. If access is unavailable, keep integration behind mocks and list missing contracts. Do not invent APIs, OTP lengths, state transitions, or upload constraints. Avoid global service locators, mutable singleton services, massive ViewModels, circular package dependencies, and unnecessary third-party libraries.

## Apple references

- [UIHostingController](https://developer.apple.com/documentation/swiftui/uihostingcontroller)
- [UIKit integration](https://developer.apple.com/documentation/swiftui/uikit-integration)
- [Customize and resize sheets in UIKit — WWDC21](https://developer.apple.com/videos/play/wwdc2021/10063/)
- [UISheetPresentationController](https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller)
# ScheduledMobilityDriver

### NID tracking recovery (2026-10-06)

Performance follow-up: scan animations no longer restart on unchanged layout; status text is updated only when it changes. Sharpness downsampling uses scale 1 to respect its pixel budget. `[NID][PROCESS] durationMs=...` records total still-processing time. These corrections compiled for iOS Simulator; physical-device latency has not been measured.

The centered 0.631 NID guide includes a repeating scan line, disabled under Reduce Motion. Live quality sampling explicitly uses full-range bi-planar luminance and measures the selected card bounding region after detection. Final highlight checks render grayscale pixels and log the clipped fraction before enhancement. These are clipping heuristics, not proof of glare-free readability. Simulator compilation passed; physical-camera glare calibration and automated tests were not performed for this update.

Preview smoothing uses elapsed-time EMA (120 ms time constant), resetting after gaps over 500 ms or bounding-box IoU below 0.5. Reduce Motion displays current corners directly. This filter only affects presentation. Still correction preserves all corrected pixels and uses one common boundary-limited expansion margin; no final aspect-ratio trimming is applied. The NID geometry target remains 0.631. Simulator build passed for this update; automated tests and device camera checks were not run.

The tracker preserves the existing short-dropout recovery but restarts stability evidence after missing detections, motion precheck rejection, or luma precheck rejection. Repositioning releases the old anchor. Capture requires five consecutive stable evaluations and at least 450 ms of dwell; raw corner motion also gates capture. Aspect calculation and thresholds are unchanged.

Validation: simulator compilation passed using `xcodebuild -project ScheduledMobilityDriver.xcodeproj -scheme ScheduledMobilityDriver -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ScheduledMobilityDriver-NID-Status-DD CODE_SIGNING_ALLOWED=NO -quiet build`. Automated tests and physical camera verification were not performed for this correction.
