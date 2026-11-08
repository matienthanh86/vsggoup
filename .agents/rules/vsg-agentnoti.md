# VSG AgentNoti Development Rules

- Backend API: Only use `https://agent-dev-api.dino.top` as the backend endpoint. Never use ngrok, emulator fallbacks (10.0.2.2), or local endpoints.
- APK Installation & Build: NEVER execute build commands (`./mach gradle :fenix:assembleDebug`) or APK installation commands (`adb install` or `./mach gradle :fenix:installDebug`) automatically. Always provide the exact command line for the user to execute themselves.
- Git Push & Remote Operations: NEVER run `git push` automatically. Always provide the exact command line for the user to push code themselves. The project Git repository is `https://git.vsg.top/thanhmt/vsggroup.git` (remote `vsg` or `origin`). Never push or instruct to push to upstream `mozilla-firefox/firefox.git`.
- Target Environment: Exclusively target standard Android SDK Emulators (AVD, e.g. `emulator-5554` with `sdk_gphone64_*`). Completely exclude LDPlayer from all testing, installation commands, device targeting, and documentation workflows. Disable ADB debugging in LDPlayer settings or close LDPlayer to prevent port 5555 collision.
- Compose XML Drawables: In Jetpack Compose, `painterResource` only supports `<vector>` or rasterized image formats (PNG/WebP/JPG). NEVER wrap images in `<bitmap>` XML tags, as this causes runtime crashes.
- Domain & Policy Compliance: Ensure all user-facing documentation, support, privacy, and terms links route to `https://vsg.top` and keep Mozilla Accounts / Sync hidden from UI.
