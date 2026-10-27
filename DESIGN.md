# ProofCam design system

## Direction

ProofCam is a camera and image-integrity tool for people documenting their communities. The interface is calm and editorial: restrained slate-blue color, a display face for headlines, native controls everywhere else. Photography and verification results take priority over decoration.

The brand symbol is a print registration mark: an image and its proof lining up.

## Color

Colors adapt to the device's appearance through `ProofCamTheme` (`CameraScreen.swift`):

| Role | Token | Light | Dark |
| --- | --- | --- | --- |
| Background | `background` | `#F7F9FB` | `#12181F` |
| Atmosphere (gradient end) | `atmosphere` | `#E8EEF3` | `#161E27` |
| Surface | `surface` | `#FFFFFF` | `#1A222B` |
| Muted surface | `surfaceMuted` | `#EFF3F6` | `#222C36` |
| Primary text | `text` | `#202C38` | `#E7EDF3` |
| Secondary text | `secondary` | `#647587` | `#9DAEBF` |
| Border | `border` | `#DDE5EC` | `#2C3844` |
| Brand / primary button | `primary` | `#889EB5` | `#889EB5` |
| Label on brand fill | `onPrimary` | `#202C38` | `#202C38` |
| Brand light / pale | `brandLight`, `brandPale` | `#A8BBCD`, `#DCE6EE` | `#A8BBCD`, `#2A3644` |
| Controls and selection | `accent` | `#526A82` | `#A8BBCD` |
| Verified | `success` | `#397866` | `#6FB39E` |
| Mismatch / error | `warning` | `#B65A58` | `#E08A87` |

Only two gradients are used: `brandGradient` (`#889EB5 → #A8BBCD`) on hero artwork, and `atmosphereGradient` (background → atmosphere) behind Capture and the introduction. Status always pairs color with a symbol and text.

## Typography

- **Display:** Avenir Next Demi Bold via `ProofCamType.display`, scaled with Dynamic Type, for screen titles and result headlines.
- **UI:** SF Pro text styles.
- **Technical:** SF Mono (`ProofCamType.technical`) for SHA-256 digests and capture IDs.

Use sentence case. Avoid uppercase labels and heavy bold.

## Components

- `PrimaryButtonStyle`: brand fill, dark label, 14-point radius, press and disabled states. `SecondaryButtonStyle`: white surface with a 1-point border.
- `RecordRow`: label/value line used for evidence records in Verify and photo detail.
- `RegistrationMark` / `ProofCamMark`: brand symbol and wordmark.
- Radii: 8 small controls, 10 thumbnails, 14 cards and buttons, 20 viewfinder, 22 hero artwork.

## Screens

- **Capture:** viewfinder with corner marks, tap-to-focus indicator, 1×/2× zoom, flash, camera switch, readiness status. After capture, an outcome sheet shows the photo with the app's status message.
- **Verify:** grouped source list (Photos, Files, separate proof file). Results show the photo full-bleed, the status, an evidence record, both SHA-256 fingerprints with differing characters highlighted, and what the result does and doesn't confirm.
- **Settings:** native form with grid, haptics, save-to-Photos, signing explanation, permissions, and the introduction.

## Accessibility and behavior

Preserve system light/dark appearance, Dynamic Type, reduced motion, and safe-area-aware layouts. Touch targets are at least 44 points. The visual layer does not alter capture, signing, storage, or verification behavior.

The app exposes Capture, Verify, and Settings. Collections, Safe Copies, and Evidence Packet export are not implemented destinations.
