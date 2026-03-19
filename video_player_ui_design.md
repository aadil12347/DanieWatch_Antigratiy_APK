# LINE Video Player UI Design Specification

This document serves as the comprehensive guide for implementing the video player UI based on the LINE Design System (LDSG). AI systems should use this as the primary reference for building and maintaining video player features.

## 1. Core Anatomy

The video player is composed of five primary layers:

1.  **Container**: The base background layer (Solid Black #000000).
2.  **Headline (Optional)**: Top-aligned layer containing metadata and top-level actions.
3.  **Center Area (Theme A/Mobile)**: Centered core controls (Play, Pause, Replay).
4.  **Toolbar**: Bottom-aligned layer containing progress tracking and secondary controls.
5.  **Dimmer**: Semi-transparent black overlay (40% opacity) that appears when controls are visible.

## 2. Platform Themes

### Theme A: Mobile-Optimized (Touch)
*   **Core Controls**: Play/Pause/Replay are placed in the **Center Area**.
*   **Interaction**: Optimized for large touch targets.
*   **Gestures**: Double-tap on the left/right screen to skip 15s backward/forward.

### Theme B: PC/Web-Optimized (Mouse)
*   **Core Controls**: Play/Pause are integrated into the **Toolbar** (bottom-left).
*   **Interaction**: Hover-based visibility.

## 3. Component Details

### Headline Elements
*   **Profile Image**: Circular avatar (follows Avatar rules).
*   **Title**: Bold, 16px white text.
*   **Description**: Regular, 14px white text (opacity can be reduced to 70%).
*   **Tags**: `LIVE` (Green background), `REPLAY` (Gray background), or `SPONSOR` labels.

### Toolbar Elements
*   **Seek Bar**:
    *   **Track**: 30% white.
    *   **Buffer**: 50% white.
    *   **Progress**: Solid White or Brand Green.
    *   **Thumb**: Appears on hover/scrubbing.
*   **Time Display**: `Current Time / Duration` (e.g., `00:35 / 02:00`).
*   **Controls**: Volume/Mute, Resolution Picker, Subtitles (CC), PIP Mode Toggle, Fullscreen Toggle.

## 4. Interaction & Behavior

### Visibility Logic
*   **Show**: Tap/Click anywhere or Move Mouse (PC).
*   **Auto-Hide**: Controls should fade out after 3 seconds of inactivity during playback.
*   **Locking**: If a settings menu is open, the auto-hide should be suspended.

### Picture-in-Picture (PIP)
*   **Layout**: Controls are simplified in PIP mode (Close, Play/Pause, Maximize).
*   **Sizing**: Recommend 100% width and 70% height of the device safe area (mobile specific).

## 5. Visual Specifications

| Item | Color | Opacity | Typography |
| :--- | :--- | :--- | :--- |
| Background | #000000 | 100% | - |
| Dimmer | #000000 | 40% | - |
| Icons | #FFFFFF | 100% | - |
| Title | #FFFFFF | 100% | Bold, 16px |
| Info Text | #FFFFFF | 70-100% | Regular, 14px |
| Seek Track | #FFFFFF | 30% | - |
| Buffer | #FFFFFF | 50% | - |

## 6. Functional Scenes (States)

1.  **Before Playing**: Shows Thumbnail + Large Play Button.
2.  **AD**: Shows "Ad" label + Skip timer if applicable.
3.  **Playing**: Standard playback view with auto-hiding controls.
4.  **Seeking**: Seek bar thumb is active, Dimmer visible.
5.  **Ended**: Shows Replay button + Recommended/Next videos.
6.  **Setting/Subtitle**: Overlays or Modals for selection.
7.  **Error**: Dimmer visible + Error Message + "Retry" Button.
8.  **Loading**: Spinner/Skeleton state.

## 7. AI Implementation Guide

When asked to implement a feature, refer to the corresponding section above:
- **UI Tweaks**: Refer to Section 5 (Visual Specs) and Section 3 (Components).
- **New Behaviors**: Refer to Section 4 (Visibility/gestures).
- **Screen Adaptation**: Refer to Section 2 (Themes A vs B).
- **Error/Loading**: Refer to Section 6 (Scenes).

### Visual Reference (Internal)
- Anatomy: [video_player_anatomy_1773496756706.png](file:///C:/Users/mdani/.gemini/antigravity/brain/6e713c3e-bf52-40bb-b3e7-f30d11c32d3c/video_player_anatomy_1773496756706.png)
- Child Elements: [video_player_child_elements_table_1773496979375.png](file:///C:/Users/mdani/.gemini/antigravity/brain/6e713c3e-bf52-40bb-b3e7-f30d11c32d3c/video_player_child_elements_table_1773496979375.png)
- Styles: [video_player_styles_section_1773497169304.png](file:///C:/Users/mdani/.gemini/antigravity/brain/6e713c3e-bf52-40bb-b3e7-f30d11c32d3c/video_player_styles_section_1773497169304.png)
