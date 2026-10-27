# ProofCam for the web

A browser version of the iPhone app with the same three tabs (Capture, Verify, Settings), the first-launch introduction, the captured-photo library, and the research lab. It has no build step and no server code: open `index.html` from any static host.

```bash
python3 -m http.server 8765 --directory web
```

Then open http://localhost:8765. The camera needs a secure context: `localhost` or HTTPS.

## Same formats as the iPhone app

| Piece | Web file | Swift source |
| --- | --- | --- |
| Watermarks v1, v2, v3 (v3 is the capture default) | `js/core/watermark.js`, `js/core/image.js` | `DCTCore`, `TiledCandidate`, `AdaptiveCandidate`, `GrayPlane` |
| Deterministic CBOR, signed requests, enrollment | `js/core/proof.js` | `ProvenanceWire` |
| JPEG comment-segment proof, portable receipt | `js/core/proof.js` | `EmbeddedProof`, `LocalCaptureReceipt` |

The ports keep Swift's round-half-to-even arithmetic. On a 641 × 487 test image, the JavaScript embed for v1, v2 and v3 matched Swift pixel for pixel. A web capture passes `LocalCaptureReceipt.verifies` in Swift, including the request bytes. A Swift capture passes the web verifier, both with the proof embedded and with a separate JSON receipt. Each side recovers the other's v3 watermark ID from the JPEG.

## Where the web version differs

- **Signing key.** It is a non-extractable P-256 WebCrypto key stored in IndexedDB, not a Secure Enclave key. Browsers don't promise hardware protection, and clearing site data deletes the key and saved photos. The interface says "this browser" wherever the app says "this iPhone".
- **Saving.** "Save to Photos" becomes "Download each photo", which is off by default so captures don't trigger unexpected downloads. The photo viewer offers Share (Web Share API with files, where supported) and Download.
- **Camera.** It uses `getUserMedia` and grabs what the viewfinder shows, cropped and zoomed, at a 1024-pixel long edge, like the app's export. 2× is digital zoom, as in the app. Flash uses the torch where the browser exposes it. Tap-to-focus sends a focus point only where the browser supports one. Front-camera shots are mirrored to match the preview.
- **Haptics.** These use `navigator.vibrate`, which works on Android browsers and does nothing on iPhone Safari. Settings says so.
- **Lab.** It covers benchmarks, screenshot recovery, JSON export, enrollment and per-capture export. App Attest is iPhone-only and is not offered.
- **Extras.** You can drop files onto Verify on desktop, use a left-rail layout on wide screens, install it as a web app, and use it offline after the first load (served over HTTPS).

Watermark work runs in a module worker (`js/worker.js`). v3 screenshot recovery runs the full angle search and can take several seconds per image.
