# Step 2: iPhone pilot scope and free development

Date: September 25, 2026  
Status: Planning baseline revised for the iPhone scope on October 26, 2026. Available-device inventory, benchmarks, and release approval remain pending.

## Decision

Deliver an invitation-only iPhone photo pilot for up to 20 participants, including at least 10 reviewers. Capture and review can be performed by the same participants, but comprehension is measured on at least 10 distinct people. Complete the watermark feasibility gate before setting a release date or building the full production service.

Armaan Singh is the accountable project owner by default as the repository owner and project sponsor. Codex performs implementation and documentation in the working repository when tasked; it is not an independent security reviewer or an ongoing service operator. No additional staff are assumed to have been hired.

## Frozen pilot scope

| Area | Included in the pilot | Deferred |
| --- | --- | --- |
| Capture | Native iPhone, rear main camera, single-shot SDR JPEG, portrait/landscape; normalized orientation and sRGB pixels | Front/auxiliary lenses, RAW, HDR exports, burst, video/audio, gallery certification |
| Export | One immutable export per capture; cap at 2048 pixels on the long edge, preserve aspect ratio, never upscale; pin JPEG encoder and quality after benchmark | Full sensor-resolution exports, user-selectable compression, editing |
| Watermark | Public random record ID embedded before final encode; conventional algorithms first; model/payload chosen at goal 7 | Mandatory AI dependency, universal survival promises |
| Registration | Per-installation signing, online challenges, server validation, signed certificates and local receipts | Manufacturer sensor certification, public arbitrary-file signing |
| Offline | Finalize and locally sign when possible, durable queue, restart recovery, pending-status sharing | Fresh-challenge claims for offline or expired sessions |
| Verification | Local iPhone extraction and file/pixel hashing; public record lookup; JPEG originals and JPEG/PNG screenshots; user-selected screenshot region; consented digest fallback | Browser interfaces, HEIC/RAW decoding, arbitrary document or video verification |
| Trust UI | Separate record signature, issuer, content, capture checks, and availability; versioned trust bundle and revocation behavior | Generic “real” or “AI-free” badge |
| Management | Accountless installation credentials, export/import receipts, recovery credential, authorized record removal, local deletion | Optional account linking, teams, paid subscriptions |
| Privacy | No default media uploads, no location feature or microphone permission, public records without stable device identity | Cloud photo backup, faces/descriptors in telemetry, advertising analytics |
| Distribution | Free personal-device provisioning for research; wider pilot distribution pending an eligible path | Paid store enrollment; unrestricted public launch before pilot evaluation |

The export cap is an engineering scope choice, not measured evidence that watermark targets can be achieved at that size. Original working data stays protected and temporary. File-size/dimension limits for verification and temporary-data cleanup are specified at the parser/privacy design steps. Do not silently discard a user's only recoverable capture.

## iPhone support policy

The current research app targets iOS 17+ and the available iPhone 16 Pro. This is a validation target, not a supported-device claim. Record exact hardware, OS, app revision, signing configuration, and available evidence for each run. Simulators provide functional coverage only; qualify camera behavior, Secure Enclave signing, screenshots, visual quality, latency, and memory on the physical phone.

Use Xcode and free Personal Team provisioning for initial personal-device testing. Wider pilot distribution remains pending an eligible distribution path. Optional App Attest requires eligible provisioning and cannot be activated by free Personal Team provisioning. Do not infer app-bound evidence or camera origin from local key protection.

## Free-development constraint

All development and pilot work must use existing resources or resources available at no charge. There is no purchasing allocation or paid-services plan.

- Use existing or freely borrowed iPhone phones and computers.
- Use free development tools and appropriately licensed libraries, models, and datasets; retain license and consent records.
- Run benchmarks and development services locally by default. Do not allocate paid GPU jobs, buy datasets, or subscribe to hosted tools.
- Use existing infrastructure or genuinely free hosting only after checking its terms and limits. Do not rely on expiring paid trials, automatic paid upgrades, or billable overages.
- Use free personal-device provisioning for research. Keep broader distribution and unavailable attestation capabilities pending; no paid enrollment is assumed.
- Plan local prototype signing separately from trusted public issuance. Free operation does not waive key protection, trust separation, privacy, or security requirements. If compliant public signing/hosting is unavailable at no cost, keep that capability local or pending and clearly label development records; do not represent it as a completed public deployment.
- Seek volunteer pilot participation and review. Record any missing independent review as an unmet release prerequisite.

Implementation can proceed on available resources. If a dependency requires payment, select a free alternative or explicitly defer the affected capability. Do not introduce a new paid allocation.

## Responsibility assignments

| Decision or workstream | Accountable owner | Execution / required evidence |
| --- | --- | --- |
| Scope, free-resource constraints, tradeoffs, participant recruitment | Armaan Singh | Review changes and provide recruitment or freely available device access |
| Product and engineering documents | Armaan Singh | Codex prepares versioned decisions and acceptance criteria |
| Watermark experiments and protocol/mobile/backend implementation | Armaan Singh | Codex implements when tasked; Armaan supplies physical-device runs/access where remote tools cannot |
| Dataset rights and privacy decisions | Armaan Singh | Record sources/consent and policy; Codex assists with inventory and checks |
| QA and security gate tracking | Armaan Singh | Reproducible test reports; independent reviewer to be appointed before release security sign-off |
| Production accounts, credentials, release, and support | Armaan Singh | Name any replacement operator before production deployment; do not assume Codex provides continuous monitoring |

This assigns accountability without inventing a staffed team. The independent reviewer and access to at least one actual test device are explicit later prerequisites. If the project owner changes, update this table before delegating credentials or release authority.

## Feasibility acceptance and sequencing

1. Goals 3–4 define the threat/privacy policy and user experience within this scope.
2. Goal 5 builds a reproducible harness, a separate tuning set, and a frozen evaluation plan. Final release evaluation still requires at least 1,000 held-out photos and 300,000 unmarked inputs under the recorded evaluation targets.
3. Goal 6 benchmarks conventional watermark candidates first. Assess net payload, screenshot/crop recovery, visual quality, latency, memory, and code/license suitability.
4. Goal 7 compares measured options on the freely available physical devices and records any untested tiers. If conventional candidates miss the required envelope, evaluate learned alternatives before narrowing scope or committing to implementation.
5. Exit feasibility with a pinned candidate, payload analysis, device measurements, declared recovery envelope, license decision, and explicit go/no-go record. Do not treat initial tuning results as final release validation.

Carry forward the documented strict integrity/privacy gates and photo recovery targets, including screenshots at 512 and 1024+ pixels. A 2048-pixel export does not eliminate lower-resolution recovery testing. Proposed device targets remain photo finalization p95 ≤2 seconds and incremental peak memory <512 MB. If these fail, document the tradeoff; do not quietly change a requirement or hide a failing tier in an average. Untested hardware is outside the declared pilot support matrix.

If no candidate provides useful screenshot recovery within acceptable visual quality and cost, stop the watermark-dependent release and present the measured options. Exact-file verification may remain technically useful but is a separate product-scope decision, not an automatic substitute.

## Completion record

Step 2 planning deliverables are complete: the pilot boundary, research OS target, reference device, accountable owner, free-development constraint, deferrals, and feasibility exit criteria are recorded. Actual hardware inventory, measurements, independent review, and deployment remain pending. Goal 3 is next.
