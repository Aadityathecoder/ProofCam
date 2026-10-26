# Camera-first iPhone experience

The app opens with a three-page introduction on first launch. It explains the audience, capture and sharing workflow, local signature verification, and the limits of a signature. Completion is stored on the device. Later launches open Capture directly; Settings can reopen the guide.

## Tabs

- **Capture:** portrait camera viewfinder, tap-to-focus/expose, 1×/2× digital zoom, flash toggle on supported cameras, front/rear switch, shutter, and recent-photo thumbnail. The thumbnail opens ProofCam's captured-photo library, with image review, photo/signature sharing, registration-request export, and manual save-to-Photos retry.
- **Verify:** select a photo through the system photo picker or choose its original JPEG/PNG file. The app verifies the exact file hash and P-256 signature against a local receipt, or a separately imported JSON receipt. A supplied receipt establishes a valid self-signature, not independent trust in the key owner. Changed, unknown, and invalid inputs never receive a positive result. No image is uploaded.
- **Settings:** persistent camera grid, shutter haptics, and automatic save-to-Photos preferences; permissions shortcut; signing explanation; app version; and the introductory guide. Signing is always required for completed captures.

## Capture and saving

The AVFoundation camera callback feeds the existing watermark/final-JPEG pipeline. A protected local photo is written before later signing steps so interrupted processing can retain an incomplete image. After final encoding, the file is reopened, hashed, signed with the Secure Enclave key, and checked against its signature. The app persists `photo.jpg`, the compatible `request.cbor`, and a portable `receipt.json` together in app-private, backup-excluded storage.

When automatic Photos saving is enabled (the default), the same JPEG bytes are submitted as a Photos resource with add-only permission. No unsigned capture is automatically added. Permission or save failures retain the signed local copy and offer a manual retry. Incomplete captures remain visibly incomplete in the local library. Disabling automatic saving does not disable signing or the protected local copy.

Photos and its system file providers may sync through services configured by the user. ProofCam has no automatic photo-upload service. A signature does not prove sensor origin, scene truth, capture time, absence of AI, or server registration. Public issuer certificates and independent server verification remain separate from local signature checks.

## Current limits

The retained research watermark pipeline exports JPEGs at a **1024-pixel long edge**; this UI change does not establish full sensor-resolution capture or Apple's Camera feature set. The UI offers still photos, not Live Photos, video, portrait processing, or optical lens selection. The 2× control is digital zoom on the selected wide-angle camera.

Simulator can exercise onboarding, tab navigation, settings, gallery navigation, and file selection. It cannot take a real camera photo or use this Secure Enclave capture path. No software signing fallback is provided. Physical iPhone capture, Photos-permission denial/recovery, saved-resource byte equality, front/rear orientation, interruption recovery, accessibility at large text sizes, and camera performance still require device validation.

## Validation — October 26, 2026

Debug and Release Swift suites each discover 53 tests: 49 pass, four optional fixture tests skip, zero failures. Four new receipt tests cover portable JSON round trips and rejection of altered photo bytes, requests, identifiers, signatures, keys, and malformed key data. The unsigned arm64 Release simulator build passes.

Manual iPhone 17 Pro simulator checks cover all three onboarding pages, opening Capture on completion, skipping onboarding on relaunch, Capture/Verify/Settings navigation, gallery empty state, persistent grid preference, and reopening the introduction from Settings. These are simulator UI checks, not physical capture evidence.
