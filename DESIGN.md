# ProofCam design system

## Product idea

ProofCam is a small proof workshop: a photograph is handled like an archive print, given a signed record, and kept with care. Warmth belongs in the editorial framing; capture and security states remain calm and explicit.

## Visual language

- **Palette:** warm paper `#F2EEDD`, soft ink `#1F2924`, olive `#4D634F`, clay `#BD5E3D`, straw `#D4B066`. Values are defined in `ProofCamTheme` and are original design choices, not copied from references. The control tint and success state adapt for dark appearance; the illustrated photo stays warm paper in either mode.
- **Surfaces:** paper canvas with subtle hairline borders. No generic gradients, glass panels, or large floating shadows.
- **Type:** system serif for a few editorial headlines; native text styles for instructions, controls, and settings. Labels use restrained tracking and uppercase only for small section markers.
- **Illustration:** original vector-drawn archive print, small landscape, and seal made with SwiftUI shapes. It is decorative and VoiceOver-hidden; controls keep their own accessible labels.
- **Iconography:** SF Symbols for standard actions and states, kept visually subordinate to text.

## Components and layout

`ProofCamTheme` provides color tokens. `ProofCamMark` is the compact wordmark. `ProofWorkshopIllustration` supplies the original illustration. `WorkshopEyebrow` handles section labels. Screens use native `NavigationStack`, `TabView`, `PhotosPicker`, `fileImporter`, `ShareLink`, and system forms.

Use consistent 16–20 point surface corners, 20–24 point major section spacing, and 44-point minimum control targets. Camera controls remain over the dark live preview. Editorial content uses leading alignment and short explanatory copy. Avoid forcing utility flows into identical cards.

## Motion and accessibility

No feature depends on animation. Keep system Reduce Motion behavior. Keep text scalable by using system text styles wherever content is not display type; allow headline wrapping. Status communicates in text and symbols as well as color. Preserve system appearance selection and use adaptive canvas, ink, paper, and border tokens. Use safe-area-aware native containers and one-handed primary actions.

## Implemented feature boundary

The checked-in app currently exposes Capture, Verify, and Settings. It does not implement Photo Collections, screenshot-to-original discovery, Safe Copies, or Evidence Packet export. Those destinations are intentionally absent. The legacy watermark research form exists in `ResearchView` but is not the launch screen.
