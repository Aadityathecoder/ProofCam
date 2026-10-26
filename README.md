# ProofCam

ProofCam is an iPhone camera project that lets recipients check whether an original photo still matches the cryptographic proof embedded inside its JPEG.

This folder is the project working directory. Product documentation, application code, backend code, and project tooling will live here as development proceeds.

For local setup and build commands, see [local development](docs/07-local-development.md). The app now opens to a camera-first interface with Capture, Verify and Settings tabs, plus a first-launch introduction; see [the camera experience](docs/08-camera-experience.md).

## Current milestone

Steps 1 and 2 are documented in the [product brief](docs/01-product-brief.md) and [pilot scope and free development](docs/02-pilot-scope-and-free-development.md). These are planning decisions; implementation and device validation remain pending.

The iPhone photo pilot uses existing hardware and free local development tools. Personal device testing is the initial distribution path; hardware support is limited to configurations actually validated.

Step 3 is defined in the [threat model, privacy rules, and assurance policy](docs/03-threat-model-and-privacy-policy.md). Security controls are specified but not yet implemented or audited.

Step 4 is documented in the [capture and verification screen design](docs/04-capture-and-verification-design.md), with a [clickable local prototype](design/prototype.html) and [opening instructions](design/README.md). All prototype behavior is simulated.

Step 5 now has a working [benchmark harness](benchmark/README.md), **11,200 distinct source images**, 53 native-2048+ resolution variants, and a 300,000-case negative stress recipe plan. The [readiness record](docs/05-benchmark-data-and-harness.md) remains **in progress**: local corpus approval, actual screenshots, and final evaluation eligibility remain pending. Stress variants are not independent new photographs.

Step 6: the [desktop study is complete](docs/06-conventional-watermark-final-report.md). The iPhone research app is prepared; physical-device validation and production candidate selection remain pending.

The product brief and pilot scope describe the planned product. Implemented research capabilities and remaining validation gates are documented below.

An [iPhone research port](ios-benchmark/README.md) is prepared for the available iPhone 16 Pro. Swift Debug and Release tests and raw-pixel cross-decoder checks pass; the unsigned Release app compiles against the iPhone simulator SDK. Physical iPhone validation remains pending. Physical iPhone validation is the next device milestone.

The iPhone experiment defaults to an [adaptive tiled v3 watermark](ios-benchmark/ADAPTIVE-V3.md), with v1/v2 retained for comparison. It recovers all 125 marked host simulation cases, including the six previous v2 misses. The broader search is slower; device validation and product quality gates remain pending.

Camera exports now contain two complementary layers: a resilient 128-bit identifier in the image signal and a signed SHA-256 manifest in a standards-compatible JPEG comment segment. The manifest hash excludes only its own container, so verification avoids a circular “hash inside itself” claim while still binding all JPEG image bytes. A separate JSON receipt remains exportable for compatibility, but it is no longer required to verify a new untouched ProofCam JPEG.

A [local provenance infrastructure prototype](provenance/README.md) now adds admitted device keys, signed requests, atomic registration, development certificates and independent exact-file verification. The iPhone app includes a camera-only capture path with Secure Enclave signing and durable request export, pending Apple/device validation. Capture origin and absence of AI remain **unverified**; production signing remains unimplemented. An optional [App Attest validation layer](provenance/APP-ATTEST.md) now checks app-bound request evidence; live Apple qualification and full receipt/risk handling remain pending. Free Personal Team provisioning cannot activate App Attest.
