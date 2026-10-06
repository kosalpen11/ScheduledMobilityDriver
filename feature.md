# Feature Specification

## Scheduled Mobility Driver App

Build a native iOS driver app for scheduled-mobility operations. The app prioritizes assigned scheduled trips, reliable driver status, and calm map-first workflows for iOS 15.0 and later.

## Phase 1 Feature: Home

Status: implemented with mock data.

The Home feature gives a driver an at-a-glance view of current availability and upcoming scheduled assignments.

Core behavior:

- Show a persistent map centered on the service area.
- Show pickup annotations for assigned scheduled trips.
- Show availability state: available or unavailable.
- Allow toggling availability through an injected use case.
- Show the next scheduled pickup time and pickup location.
- List today's upcoming assignments.
- Distinguish primary and backup assignments.
- Show the next domain-resolved action for each trip.
- Emit typed navigation outputs for trip detail and profile.

Implemented variants:

- UIKit Home screen in `DriverUIKit`.
- SwiftUI Home screen in `DriverSwiftUI`.
- Both variants reuse `HomeViewModel`, domain use cases, and repository protocols.
- The coordinator receives `HomeScreenFactory` and does not branch on UIKit or SwiftUI details.

Implemented visual baseline:

- Full-screen map with a stable bottom driver panel.
- Shared UIKit/SwiftUI design tokens for colors, spacing, card radius, and touch target sizing.
- Prominent availability action with haptic feedback.
- Glanceable next scheduled pickup card.
- Primary and backup assignments remain visible in every trip row.
- Dynamic Type, VoiceOver labels, dark mode colors, and Reduce Motion-aware SwiftUI animation.

## Driver Workflow Features

Phase 2 status: authentication and session restoration are implemented with verified backend DTOs and real staging runtime wiring by default.

Implemented:

- Session restoration.
- Phone login and OTP verification.
- SwiftUI phone and OTP screens hosted through `AuthScreenFactory`.
- Default Cambodia `+855` phone entry with normalization before backend requests.
- OTP autofill-compatible UIKit code entry.
- Paste-friendly numeric code filtering.
- Phone/code validation and loading states.
- Duplicate submission prevention.
- Token storage abstraction with Keychain implementation.
- Actor-based shared refresh coordination.
- Invalid refresh credentials clear the session.
- Transient refresh failures preserve credentials.
- Transient restoration failures show a retry path instead of clearing credentials.
- Logout clears the local session and returns to authentication.
- Staging is the default development runtime using origin `https://api.146-190-4-99.sslip.io` and API prefix `/api/v1`.
- Auth, session restoration, refresh, logout, driver profile, documents, and onboarding use real repositories by default.
- Mock runtime data is not used in staging mode and is only available through explicit `.mock` composition.
- URL construction normalizes endpoint paths so `/api/v1` appears exactly once for every verified auth and driver endpoint.

Phase 3 status: driver onboarding, profile, vehicle, and documents are implemented with verified backend DTOs and explicit mock/runtime wiring.

Verified backend contracts:

- `GET /api/v1/drivers/me` returns masked driver profile, approval state, active vehicle, current documents, readiness, history, and created timestamp. Requires bearer JWT and `DRIVER` role.
- `GET /api/v1/drivers/me/documents` returns current document metadata. Requires bearer JWT and `DRIVER` role.
- `POST /api/v1/drivers/me/documents` uploads multipart fields `type`, `file`, optional `expiresOn`, and optional `vehicleId`. It accepts optional `Idempotency-Key`.
- `POST /api/v1/drivers/me/submit` moves `PENDING` to `DOCS_SUBMITTED` when `NATIONAL_ID`, `DRIVING_LICENSE`, and `PROFILE_PHOTO` are uploaded.
- Driver statuses are `PENDING`, `DOCS_SUBMITTED`, `TRAINING`, `APPROVED`, `REJECTED`, and `SUSPENDED`.
- Operational eligibility requires `APPROVED`, active vehicle, no missing documents, no pending-review documents, and no expired documents.
- Document types are `NATIONAL_ID`, `DRIVING_LICENSE`, `PROFILE_PHOTO`, `VEHICLE_REGISTRATION`, and `VEHICLE_INSURANCE`.
- Document statuses are `PENDING_REVIEW`, `APPROVED`, `REJECTED`, and `SUPERSEDED`.
- Uploads support JPEG, PNG, and PDF by content magic bytes; `PROFILE_PHOTO` must be JPEG or PNG.
- Upload limit is 10 MB.
- All documents except `PROFILE_PHOTO` require a non-past expiry date.
- Vehicle documents require the assigned active vehicle id; non-vehicle documents reject `vehicleId`.
- Driver profile editing, driver-side vehicle assignment, and remote document preview/download are not exposed by the verified driver app API.

Implemented:

- Driver domain models for approval state, readiness, vehicle details, document metadata, upload payloads, and eligibility.
- Repository contracts for profile retrieval, document listing, upload, onboarding submission, and session-state cleanup.
- DTO-to-domain mapping for `DriverDetail`, `VehicleView`, `DocumentView`, and `ReadinessView`.
- Real API repository using authenticated JSON and multipart requests with one coordinated refresh retry.
- Mock repository with explicit runtime wiring for local development and testable duplicate upload/session cleanup behavior.
- Upload validation for size, magic-byte MIME detection, profile-photo type, expiry, and vehicle field rules.
- UIKit profile/onboarding screen injected through `DriverProfileScreenFactory`.
- Profile status card, onboarding checklist, vehicle assignment card, document status list, photo library/camera/file upload flow, selected-file confirmation, loading states, alerts, and logout.
- Backend-derived eligibility policy for operational readiness and submit availability.
- Authoritative profile refresh after upload and submit mutations.
- Native navigation, large touch targets, restrained colors, rounded cards, haptics, VoiceOver labels, Dynamic Type, dark mode, and iOS 15-compatible APIs.

Phase 7 profile/onboarding experience:

- Driver identity shows full name, masked phone number, and friendly account status copy instead of raw backend enums.
- The full Driver Profile screen now uses a compact identity header with name, masked phone number, and friendly account status.
- Profile content is organized as one Next step section, a Documents section, a Vehicle section, Help, and a separate Account section for Sign out.
- Repeated status guidance and nested card layers were reduced so the screen reads as a short driver checklist instead of a dense form.
- Document progress is calculated from the actual required document rows, for example “2 of 3 required documents approved.”
- Status guidance matches backend rules:
  - `PENDING`: “Complete your application.”
  - `DOCS_SUBMITTED`: “Your application is under review.”
  - `TRAINING`: “Training is required before you can drive.”
  - `APPROVED`: shows either “You’re ready to drive” or the outstanding readiness requirement.
  - `REJECTED`: shows the backend status-history reason when available and no unsupported appeal action.
  - `SUSPENDED`: shows the backend status-history reason when available and no unsupported reinstatement action.
- “What you need to do” chooses one primary supported next action from backend readiness: submit, upload/replace a document, wait for review, contact operator, or no action.
- Account readiness stays distinct from online availability.
- Document names are driver-friendly: National ID, Driving licence, Profile photo, Vehicle registration, Vehicle insurance.
- Document statuses are plain text: Not uploaded, Under review, Approved, Needs replacement, Expired.
- Documents are grouped into Driver documents and Vehicle documents. Vehicle documents are shown only when an active assigned vehicle makes them relevant.
- Document rows are full-width tappable rows with SF Symbols, plain text status, expiry/rejection context where relevant, and disclosure indicators.
- Document details now use a native pushed detail screen instead of an overloaded alert.
- Document details show document name, text status, expiry date when present or required, backend rejection reason when present, one short next-step sentence, accepted formats, and the 10 MB upload limit.
- Upload and replacement actions open from document details only when supported. Drivers can choose an image from the photo library, capture a camera photo when available, or use Files for supported document files; remote preview is still shown as unavailable because no verified document-content endpoint exists.
- National ID photo capture uses a custom Vision camera path instead of the generic system camera. The live frame tracker scores candidate rectangles with `0.15c + 0.15a + 0.20cov + 0.15g + 0.30cont + 0.05anch - motionPenalty`, smooths corners with a rolling mean, applies CoreMotion shake rejection, steers focus/exposure to the detected card center, and auto-captures with flash off only after stable ready frames.
- National ID physical shape is measured from actual quad edge distances in oriented pixel space: top, bottom, left, and right edges are averaged into two axes, then `min(edgeA, edgeB) / max(edgeA, edgeB)` is compared against the NID target aspect of approximately `0.631`.
- Vision quads are normalized before tracking and preview work: the longer opposite edge pair becomes normalized top/bottom, the shorter pair becomes normalized left/right, and the same four physical points are preserved. Raw and normalized edge lengths plus corner labels are logged for device diagnosis.
- Invalid document shape, preview-space wrong orientation, too-small, unstable, and align/reposition states are separate decisions. Wrong orientation is now based only on the quad after converting all four corners into preview coordinates. The conversion explicitly handles Vision `.right` using the proven capture mapping `(1 - visionY, 1 - visionX)`, explicitly sets portrait orientation on video, photo, and preview connections, handles Vision bottom-left coordinates, preview-layer aspect-fill conversion, mirroring, and reorders transformed corners before measuring preview edges. Frame-to-frame motion is exposed as raw and EMA-smoothed values (`motionRaw` and `motionEMA`); the smoothed signal drives the stability gate while each status keeps a clear driver-facing message.
- Debug National ID capture logs now include throttled live frame score components, rejection/status reason, stable-frame count, rectangle motion, device motion, motion penalty, Vision corners, preview-space corner samples, focus points, auto-capture events, final photo byte count, and processing quality gates under `[NID][FRAME]`, `[NID] FOCUS`, `[NID] CAPTURE`, and `[NID][PROCESS]`.
- Live National ID guidance now uses plain rejection reasons such as move closer, move back, hold steady, reduce glare, turn the card to landscape, and align the card.
- The live camera overlay now converts Vision rectangle points into preview-layer coordinates through an explicit helper before drawing the guide, which makes frame-fit tuning easier to verify on device.
- National ID gallery/photo input runs rectangle detection, 10% corner expansion, Core Image perspective correction, canonical ID-1 aspect cleanup, sharpness/glare gates, highlight/shadow plus contrast enhancement, and OCR/MRZ expiry extraction with rotation retry. The sharpness gate logs Sobel RMS (`scale=sobelRMS`) so a prior squared-energy reading such as `0.012` is interpreted as approximately `0.109` RMS before comparison with the `0.085` floor.
- Expired National ID MRZ dates are rejected before upload. When a valid expiry is read, it is used automatically for the upload payload; otherwise the driver is asked to enter the expiry date manually.
- Upload confirmation now presents a native preview screen. Image documents show the selected photo; National ID shows the processed cropped/enhanced image that will be uploaded and offers a Retake photo action before upload.
- Expiry is requested only for document types that require it. Vehicle document uploads automatically use the assigned vehicle id from the profile and never ask the driver to enter it.
- Selected-file confirmation, validation, upload loading state, recoverable errors, and authoritative profile refresh remain intact.
- Refresh failures preserve already loaded profile content and show a retryable message instead of blanking the screen.
- Vehicle assignment is read-only and explains missing assignment as operator-managed.
- Help and account is separated from operational actions; Sign out appears there.
- Support options are shown only if configured; none are invented by the app.

Home layout and profile access refinement:

- UIKit and SwiftUI Home retain a full-screen map and stable bottom panel, with responsive safe-area margins and a wider max-width panel on larger devices.
- Bottom-panel hierarchy is Driver availability, Next scheduled trip, Today's assignments, then empty/unavailable feedback.
- The next-trip card provides one View trip action when an assigned trip exists; unavailable staging data is never replaced with mock content.
- Native profile buttons remain typed Home outputs in both renderers. The coordinator presents an injected iOS 15 page-sheet profile summary using the existing `DriverProfileViewModel` and repository flow.
- The compact sheet shows driver identity, masked phone, friendly account status, readiness, vehicle summary, View profile, and Account/Sign out. View profile opens the existing full profile screen.
- Shared styling and accessibility behavior remain consistent across renderers, including Dynamic Type, VoiceOver, dark mode, and reduced-motion-friendly native transitions.
- The Debug staging login bypass uses an explicit mock Home factory for UI review of scheduled trips, primary/backup roles, availability, and mock trip actions. Real staging login continues to use real repositories and never falls back to these mocks.
- Home uses FloatingPanel 3.2.4 through Swift Package Manager. UIKit and SwiftUI share `.tip`, `.half`, and `.full` anchors plus scroll tracking while keeping the map persistent.

Remaining limitations:

- Home availability is unavailable in real staging mode until trip/availability backend endpoints are verified; staging does not simulate successful availability mutations.
- Driver profile is read-only because no driver self-edit endpoint was verified.
- Vehicle assignment is read-only because assignment is not exposed through driver self-service endpoints.
- Remote server document preview is unavailable because no driver document content endpoint was verified.
- Support contact details are not yet backed by verified API or local configuration.

Planned after deeper feature contract work:

- Active-trip location tracking.
- Recoverable offline and reconnect behavior.
- Server-confirmed payment outcome after trip completion.

Phase 4 status: scheduled trip details and mock-authorized actions are implemented. Real trip and availability networking is intentionally unavailable because the actual backend does not expose driver trip or availability endpoints yet.

Verified backend inspection:

- `docs/openapi.json` exposes 21 paths: authentication, current user, driver self profile/documents/submit, and admin driver/vehicle operations.
- `core-app/src/main/java/com/mobility/core/dispatch` contains only `package-info.java`; no trip or availability controller/service/domain implementation exists.
- The backend contains `booking` and `dispatch` database schemas, but no implemented driver trip listing, trip detail, trip transition, cancellation, reassignment, or availability API.
- `mobility-driver.postman_collection.json` includes auth, refresh, logout, `/drivers/me`, and `/drivers/me/documents`; it does not include trip or availability requests.
- Phase 6 rechecked a fresh backend clone at commit `7d12c29`; assigned trips, trip details, availability, action transitions, conflicts, cancellation, reassignment, and driver trip permissions are still absent from OpenAPI and implementation source.

Implemented:

- Trip detail repository operations in the domain contract: assigned listing, detail lookup, and action submission.
- `TripScreenFactory` returning a `UIViewController`.
- Shared `TripDetailViewModel` with loading, content, action-in-flight, recoverable error, and failure states.
- Centralized `TripActionResolver` with primary versus backup assignment permissions.
- Mock trip repository with details, state transitions, version conflict handling, backup action rejection, reassignment-style missing trip errors, and version increments.
- Stable mock idempotency keys derived from trip id, action, and expected version.
- Duplicate trip action submission prevention.
- Recoverable errors preserve existing trip content.
- Conflict/reassignment/cancellation-style errors trigger authoritative refresh before showing the message.
- UIKit trip detail screen with map, pickup, destination, scheduled time, passenger notes, assignment role, status, and one primary action.
- Home refresh after returning from trip details.
- Real mode uses explicit unavailable trip and availability repositories; it does not display mock trips or present local availability toggles as server-confirmed backend state.
- Phase 6 changed real-mode unavailable repositories to throw explicit unavailable errors instead of returning fake empty trips or a fake unavailable status.
- UIKit and SwiftUI Home now show clear unavailable/error copy, keep availability actions disabled without authoritative state, and expose Retry controls.
- SwiftUI Home refreshes when the app returns to the foreground and relies on `HomeViewModel` request guards to avoid overlapping loads.

Remaining limitations:

- Trip listing/detail/actions are mock-backed until backend endpoints exist.
- Availability retrieval/mutation is mock-backed only in `.mock`; real mode reports unavailable behavior.
- Cancellation and reassignment are modeled as recoverable failure states in mocks because no backend contract exists yet.

Phase 6 backend requirements before real integration:

- `GET` endpoint for assigned driver trips scoped to the authenticated driver.
- `GET` endpoint for driver trip details.
- `GET` and mutation endpoints for driver availability.
- Backend-authorized trip action endpoint for pickup, arrival, trip start, and trip completion.
- Primary versus backup assignment permissions in trip DTOs or action authorization responses.
- Server trip status and assignment enums matching documented transitions.
- Version, ETag, or equivalent conflict contract for trip and availability mutations.
- Cancellation and reassignment error/event semantics.
- Required `Idempotency-Key` behavior for every mutating trip/availability operation.
- Privacy contract for passenger data and coordinates so HTTP logs can avoid sensitive details.

## Driver Login and Entry Flow

Status: implemented for real staging APIs with SwiftUI auth and entry screens. Phase 5 adds readable Debug staging HTTP logging.

Implemented flow:

- Launch restores a Keychain-backed session with coordinated token refresh when needed.
- No valid session routes to phone login.
- Phone login requests OTP from staging through `POST https://api.146-190-4-99.sslip.io/api/v1/auth/otp/request`.
- OTP verification sends the actual four-digit contract to `POST https://api.146-190-4-99.sslip.io/api/v1/auth/otp/verify`.
- Successful verification stores access and refresh tokens securely in Keychain.
- The app fetches `GET https://api.146-190-4-99.sslip.io/api/v1/me`, then fetches `GET https://api.146-190-4-99.sslip.io/api/v1/drivers/me` only when the backend user has the `DRIVER` role.
- `DriverEntryResolver` centralizes all post-login routing before Home is shown.
- Temporary restoration and driver lookup failures preserve credentials and show Retry plus explicit Sign Out.
- Logout cancels entry-owned work, calls backend logout when possible, clears tokens, clears account-specific driver state, and returns to phone login.

Routing:

- Operationally eligible `APPROVED` drivers route to Home.
- `PENDING` drivers route to onboarding checklist and required documents.
- `DOCS_SUBMITTED` drivers route to application review.
- `TRAINING` drivers route to training status.
- `REJECTED` drivers route to a restricted rejection screen with only backend-supported refresh/sign-out actions.
- `SUSPENDED` drivers route to a restricted status screen.
- `APPROVED` drivers without active vehicle or clean readiness route to readiness requirements.
- Non-driver accounts receive a clear driver-role-required message and can change account.
- Missing driver profiles are handled explicitly; no client registration or automatic `DRIVER` role assignment is offered because the verified backend only exposes admin driver creation.

SwiftUI implementation:

- `AuthSwiftUIScreenFactory` returns a `UIHostingController` for phone and OTP screens through the existing `AuthScreenFactory`.
- `DriverEntrySwiftUIScreenFactory` returns status screens through `DriverEntryScreenFactory`.
- Home uses the SwiftUI renderer by default while preserving the UIKit Home variant and shared `HomeViewModel`.
- UIKit profile/documents and trip detail screens remain preserved and injectable.
- Screens use shared design tokens, bold system headings, restrained colors, large touch targets, VoiceOver labels, Dynamic Type-friendly text, native navigation, and iOS 15-compatible SwiftUI APIs.

Staging safeguards:

- Staging mode uses real auth/session/profile/document/onboarding repositories.
- Staging mode does not fall back to mock auth, mock profile, mock documents, mock trips, or mock availability.
- Trip and availability repositories are explicit unavailable implementations in real mode because implemented backend endpoints were not verified.
- Runtime OTP delivery and end-to-end staging login were not manually exercised in this phase; compilation was verified only.

HTTP logging:

- `HTTPLogger` is injected into `HTTPClient` from the composition root.
- `ConsoleHTTPLogger` is enabled only in Debug `.staging` builds.
- Production builds receive no logger.
- Logs include request id, retry attempt, linked refresh request id, method, sanitized URL, status, duration, and body summary.
- Valid JSON is pretty-printed after redaction.
- Multipart logs include only field names, field/file kind, MIME type, and byte counts.
- Authorization headers, cookies, API keys, tokens, refresh tokens, OTP values, phone numbers, filenames, personal fields, and sensitive query parameters are redacted.
- Body output is length-limited and marks truncation.
- Actor serialization keeps each HTTP log block grouped.
- Authenticated retries reuse the same logical request id and increment the attempt number.
- Refresh requests use separate ids and include a link to the triggering request when applicable.

Phase 5 verified backend contract fields:

- OTP request: `phone`.
- OTP request response: `expiresInSeconds`, `resendAfterSeconds`.
- OTP verification: `phone`, `code`.
- Token response: `accessToken`, `tokenType`, `expiresIn`, `refreshToken`, `refreshExpiresIn`.
- Refresh/logout request: `refreshToken`.
- Current user response: `id`, `phone`, `fullName`, `preferredLang`, `status`, `roles`.
- Driver profile response: `id`, `userId`, `fullName`, `phone`, `status`, `nationalIdMasked`, `vehicle`, `documents`, `readiness`, `createdAt`.
- Document upload multipart fields: `type`, `file`, optional `expiresOn`, optional `vehicleId`.

Corrected staging endpoint construction:

- Origin: `https://api.146-190-4-99.sslip.io`.
- API prefix: `/api/v1`.
- Request paths in repositories remain relative, for example `auth/otp/request`, `me`, and `drivers/me`.
- `HTTPClient` strips accidental duplicate leading `api/v1` path components before appending endpoint paths.
- Driver profile resolves to exactly `https://api.146-190-4-99.sslip.io/api/v1/drivers/me`.

## Backend Integration Features

Do not implement real requests until the scheduled-mobility backend has been inspected.

Contracts to verify:

- Auth endpoints and token lifetimes. Verified: `/auth/otp/request`, `/auth/otp/verify`, `/auth/refresh`, `/auth/logout`, `/me`, `/drivers/me`.
- OTP length, resend policy, and error responses. Verified: 4 digits, 5 minute TTL, 60 second resend cooldown, 5 requests/hour, 5 wrong attempts/code, Problem Details errors.
- Driver profile, approval, vehicle, and document DTOs. Verified for `/drivers/me`, `/drivers/me/documents`, `/drivers/me/documents` upload, and `/drivers/me/submit`.
- Scheduled trip states and transition endpoints. Not available in the verified backend implementation.
- Upload MIME types and size limits. Verified: JPEG, PNG, PDF by magic bytes; profile photo image-only; 10 MB max.
- Location upload or live transport contract.
- Problem Details response shape. Verified as RFC 7807 with stable `code`.
- Idempotency support per operation. Verified for mutating endpoints; refresh requires stable key reuse across retries.

## Non-Functional Requirements

- Minimum deployment target: iOS 15.0.
- Native UIKit scene lifecycle and `UINavigationController` shell.
- Local Swift Package Manager modules with explicit boundaries.
- Foundation-only domain layer.
- `ObservableObject`, `@Published`, Combine, and `@MainActor` presentation state.
- URLSession, Keychain, and CoreLocation adapters for later real integration.
- Dark mode, Dynamic Type, VoiceOver, safe areas, and large touch targets.
- No unnecessary third-party dependencies.

## Acceptance Checks

Phase 1 is acceptable when:

- The app builds with the `ScheduledMobilityDriver` scheme.
- `DriverModules-Package` tests pass on a concrete iOS simulator.
- UIKit Home and SwiftUI Home can be swapped from the composition root.
- UI modules do not import concrete data implementations.
- The app remains compatible with iOS 15 APIs.

Phase 2 is acceptable when:

- Auth UI is injectable through `AuthScreenFactory`.
- Session restoration chooses Auth or Home without artificial delay.
- OTP request and verify use backend request/response field names.
- Refresh coordination shares one in-flight refresh.
- Authenticated requests retry at most once after refresh.
- Invalid refresh clears stored tokens while transient refresh failures preserve them.
- Meaningful tests cover restoration, OTP validation, duplicate submission prevention, and refresh behavior.

Phase 3 is acceptable when:

- Driver profile UI is injectable through `DriverProfileScreenFactory`.
- Mock and real driver repositories are selected explicitly from the composition root.
- Profile, readiness, vehicle, and documents are mapped from verified backend DTOs.
- Upload validation rejects unsupported MIME, oversized files, missing expiry, past expiry, duplicate in-flight upload, and invalid vehicle fields.
- Onboarding submit uses backend-derived readiness and prevents duplicate submission.
- Mutations refresh authoritative driver state after success.
- Logout clears driver session-owned state.
- iOS 15 API compatibility remains clean.

Phase 4 is acceptable when:

- Trip detail UI is injectable through `TripScreenFactory`.
- Home still supports both UIKit and SwiftUI renderers.
- Real mode does not silently display mock trip or availability data.
- Mock trip actions use centralized action resolution and assignment permissions.
- Duplicate trip action submissions are ignored while a request is in flight.
- Conflict, cancellation, and reassignment-style failures preserve content and refresh authoritative state.
- Home refreshes after returning from trip details.
- Tests cover action resolution, assignment permissions, conflicts, reassignment, duplicate submissions, and mock transition behavior.

Latest validation:

- NID performance correction: scan animation survives status-triggered layout passes and only restarts for changed geometry, camera reappearance, or Reduce Motion changes. Sharpness thumbnails use pixel scale 1 instead of display scale. Processing duration is logged as `durationMs`. Device performance remains unmeasured.

- NID scanning/glare UI: vertical scan-line sweep inside the centered landscape guide, responsive to Reduce Motion. Live luma-plane sampling and selected-card quality measurement replace whole-frame byte assumptions; still highlights use grayscale rendering. Flash remains off. Generic simulator build passed; device glare calibration and automated tests were not run.

- NID overlay/crop refinement: time-based presentation EMA with stale/target-change resets and Reduce Motion support; uniform boundary-limited crop expansion; removed destructive final aspect trimming. NID target remains 0.631. Generic iOS Simulator build passed. Automated tests and physical camera alignment/crop completeness checks were not performed. Live-to-still candidate matching remains incomplete.

- NID recovery correction (2026-10-06): failed stability attempts release their anchor so repositioning can recover. Missing detections and rejected motion/luma prechecks restart the stable window. Five consecutive stable evaluations, raw-motion validation, and 450 ms dwell gate capture. Existing short-dropout geometry retention is preserved. Simulator compilation passed with the generic iOS Simulator destination; automated tests and physical camera verification were not performed for this correction.

- App build passed after the Home layout/profile sheet refinement: `xcodebuild -project ScheduledMobilityDriver.xcodeproj -scheme ScheduledMobilityDriver -destination 'platform=iOS Simulator,id=8E235B8E-1C0B-43AE-807B-FE1E232B05CA' build`.
- Automated tests were not run for this Home refinement phase per instruction.
- Runtime OTP delivery, live staging sign-in, and physical device install were not verified in this phase.
- Live staging trip/availability runtime checks were not performed because no verified backend endpoints exist.
