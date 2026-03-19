---
description: Flutter development preview workflow — always use hot reload, never rebuild APKs during development
---

# Flutter Development Preview Workflow

// turbo-all

## Rules

1. **Always use debug mode** for development preview — run `flutter run` on the connected device.
2. **Use Hot Reload / Hot Restart** so UI updates appear instantly after code changes.
3. **Never build a release APK** (`flutter build apk --release`) unless the user explicitly says the app is complete and ready for final build.
4. **Keep the dev server running** — use `flutter run` once, then apply changes via hot reload.
5. **Focus on fast iteration** — live preview on device, not repeated APK builds.

## How to Start

1. Launch the app on the connected device:
   ```
   flutter run -d <device_id>
   ```
   Or use the MCP `launch_app` tool.

2. After making code changes, use MCP `hot_reload` or `hot_restart` to push changes live.

3. Only when the user says "build the APK" or "app is complete", run:
   ```
   flutter build apk --release
   ```

## Summary

**Live preview during development → single final APK build at the end.**
