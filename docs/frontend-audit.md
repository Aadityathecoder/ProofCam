# Frontend audit

## Target and architecture

The checkout contains `ios-benchmark/ProofCamResearch.xcodeproj`, an iOS 17+ SwiftUI application targeted to iPhone. `ProofCamResearchApp` launches `CameraRootView`; onboarding leads to a three-tab `TabView` for Capture, Verify, and Settings. The target uses explicit source-file references in the Xcode project and has no third-party UI dependencies.

## Existing working paths in source

- Capture uses AVFoundation camera preview and photo capture, focus, flash, zoom, and optional grid/haptics.
- Capture finalization creates a watermark and signs the resulting image with a Secure Enclave key; saved image/request data is persisted locally. Optional Photos save and sharing are present.
- Verify accepts Photos or Files images, checks embedded or supplied local proof, and presents a clear no-match/error result.
- Settings controls grid, haptics, and Photos saving and describes local signing/privacy behavior.
- App Attest is conditional and disabled in the default build unless eligible provisioning configuration enables it.
- A separate legacy `ResearchView` supports watermark benchmarking and screenshot recovery. It is explicitly not the launch flow.

## Not implemented in this app target

Photo Collections, supported screenshot original-finding as a user workflow, privacy-redacted Safe Copies, and Evidence Packet export are not present in the current three-tab UI. No placeholder destinations were added.

## Integrity constraints

The redesign leaves `CaptureProvenance.swift`, `Core`, signing, receipt formats, watermark algorithms, local storage, and verification logic untouched. Only view composition and visual tokens are changed.

## This revision's checks

- Release app target compiled successfully for the iOS Simulator SDK with code signing disabled. The same target is open in Xcode with the iPhone 17 Pro simulator selected.
- The app was installed and launched on iPhone 17 Pro, iOS 26.5. Onboarding, Capture, Verify, Settings, and the empty saved-photo archive were visually inspected in Simulator. Capture and Verify were also inspected in dark appearance.
- Actual simulator screenshots are in `screenshots/`.
- Existing Core package suite: 54 tests executed, 4 optional fixture/diagnostic tests skipped, 0 failures.
- The Simulator correctly reports that the camera preview needs a physical iPhone. No physical-device capture/signing, App Attest qualification, large Dynamic Type pass, or compact-iPhone pass was performed. The simulator screenshots do not depict an operational camera preview.
