# ProofCam design system

## Direction

ProofCam is a professional camera and image-integrity tool. The interface uses restrained color, clear hierarchy, and direct language. Photography and verification results take priority over decoration.

## Color

Colors adapt to the device's appearance through `ProofCamTheme`:

| Role | Light | Dark |
| --- | --- | --- |
| Background | Cool gray `#F2F4F7` | Charcoal `#0D131C` |
| Surface | White `#FFFFFF` | Slate `#17212E` |
| Primary text | Ink `#18212D` | Cool white `#E6EBF2` |
| Primary button | Navy `#233F60` | Steel navy `#304F73` |
| Control accent | Navy `#264C77` | Pale steel blue `#A6C2E2` |
| Border | Gray `#D9DFE7` | Slate gray `#303D4D` |
| Verified state | Green `#216E51` | Light green `#8CC7AC` |
| Warning | Rust `#A14B27` | Muted orange `#E1A27E` |

Success and warning colors convey status with accompanying text and symbols. Ordinary controls use navy or neutral colors. White labels are used on the dark primary button fills in both appearances.

## Typography and components

Use native system sans-serif text with semibold headlines. Monospaced text is limited to short technical labels. Keep copy literal: “Verify a photo,” “Photo library,” and “No captured photos.”

Use 10–12 point surface corners, thin borders, generous spacing, and 44-point minimum control targets. Native forms, navigation, tab bars, system pickers, and share sheets remain the interaction foundation. Camera controls stay legible against the viewfinder.

`ProofCamMark` combines a simple viewfinder symbol and system-type wordmark. `ProofDocumentIllustration` uses a restrained photo/signature diagram; `SectionLabel` provides neutral section labels. Decorative archive prints, seals, landscape art, and workshop language have been removed.

## Accessibility and behavior

Preserve system light/dark appearance, scalable native text styles, and safe-area-aware layouts. Status must be understandable without color. The visual refresh does not alter capture, signing, storage, or verification behavior.

The app exposes Capture, Verify, and Settings. Collections, Safe Copies, and Evidence Packet export are not implemented destinations.
