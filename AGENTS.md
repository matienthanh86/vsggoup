## Global instructions

- When refactoring existing code, check relevant files for existing tests and update them if necessary.
- When adding new code, prefer to write easily mockable and testable code, and include tests where applicable.
- Limit the amount of comments you put in the code to a strict minimum. You should almost never add comments, except sometimes on non-trivial code, function definitions if the arguments aren't self-explanatory, and class definitions and their members.
- Do not remove existing comments unless they are directly related to what you are changing.

## Repository Structure

This is a monorepo containing three main projects:

- `firefox-ios/` - Firefox for iOS (main app, scheme: `Fennec`)
- `focus-ios/` - Firefox Focus for iOS (scheme: `Focus`)
- `BrowserKit/` - Shared Swift Package mostly used in Firefox

## Common Commands

### Build & Test

```bash
# Build for testing (Firefox)
fxios test
```

### JavaScript User Scripts

Needed to be ran whenever we make JavaScript changes.

```bash
npm run build   # production build
npm run dev     # watch mode with source maps
```

### Linting

SwiftLint runs automatically via Xcode build phases on the Client target. Install via `brew install swiftlint`. Configuration is in `.swiftlint.yml`.
SwiftLint also runs whenever code is pushed to the remote, using hooks.

### Pull requests

Pull requests needs to be opened with the provided `PULL_REQUEST_TEMPLATE`. Update relevant section. 
GitHub ticket number can be found at the bottom of the JIRA ticket.

## Runbooks

- **Xcode version upgrade.** When bumping the Xcode version used by CI/local builds, follow [docs/xcode-upgrade.md](docs/xcode-upgrade.md).

## VSG AgentNoti Rules
- Backend API: Only use `https://agent-dev-api.dino.top` as the backend endpoint. Never use ngrok, emulator fallbacks, or local endpoints.
- Push Notification Provider: Uses Apple Push Notification service (APNs) provider `apns` with device push address.
- Git Push & Remote Operations: NEVER run `git push` automatically. Always provide the exact command line for the user to push code themselves.
- Domain & Policy Compliance: Ensure all user-facing documentation, support, privacy, and terms links route to `https://vsg.top` and keep Mozilla Accounts / Sync hidden from UI.

## Language & Communication
- **Ngôn ngữ:** Luôn luôn trả lời, giải thích và giao tiếp với người dùng bằng **Tiếng Việt**. Giữ nguyên các thuật ngữ kỹ thuật, tên biến, tên hàm, đường dẫn file và lệnh git/bash bằng tiếng Anh để đảm bảo độ chính xác kỹ thuật.

## Swift Build & Concurrency Guidelines
- **Swift Version & Concurrency Mode:** Dự án `firefox-ios` và toàn bộ target extensions (`CredentialProvider`, `WidgetKitExtension`, `NotificationService`, `ShareTo`, `Client`) bắt buộc dùng `SWIFT_VERSION = 5.0` và `SWIFT_STRICT_CONCURRENCY = minimal`. Không bật các cờ thử nghiệm Swift 6 upcoming feature (`GLOBAL_CONCURRENCY`, `REGION_BASED_ISOLATION`, v.v.).
- **@MainActor Default Parameter Isolation:** Không bao giờ gọi hàm khởi tạo bị cô lập trên `@MainActor` làm giá trị tham số mặc định (ví dụ: `appAuthenticator: AppAuthenticator = AppAuthenticator()`). Luôn dùng `param: Type? = nil` và khởi tạo bên trong thân hàm `init` (`self.param = param ?? Type()`).
- **iOS 26+ SDK Shims:** Với các API SwiftUI/UIKit chỉ có từ iOS 26+ (như `prominentClearGlass`, `UIGlassEffect`, `UIBarButtonItem.Style.prominent`), luôn duy trì shims tương thích trong `BrowserKit/Sources/Common/Extensions/UIViewExtension.swift`.
