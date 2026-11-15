#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "=== Kiểm tra công cụ Xcode ==="
if ! command -v xcodebuild >/dev/null 2>&1 || [ ! -d "$(xcode-select -p 2>/dev/null)/Platforms/iPhoneOS.platform" ]; then
  echo "LỖI: Máy Mac hiện tại chưa có ứng dụng Xcode.app (chỉ có CommandLineTools)."
  echo "Để build trực tiếp từ mã nguồn, bạn cần:"
  echo "1. Cài đặt Xcode từ Mac App Store hoặc developer.apple.com"
  echo "2. Chạy lệnh: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo ""
  echo "GỢI Ý:"
  echo "- Bạn có thể dùng GitHub Actions (đang chạy tự động trên repo) để lấy file test.ipa."
  echo "- Hoặc nếu đã có sẵn 1 file .ipa, dùng script: ./patch_existing_ipa.sh <file.ipa>"
  exit 1
fi

echo "=== 1. Tự động xóa kênh alpha trên toàn bộ Icon ==="
python3 scripts/strip_icon_alpha.py .

echo "=== 2. Chạy Bootstrap ==="
./bootstrap.sh firefox --force

echo "=== 3. Biên dịch và tạo Archive ==="
cd firefox-ios
xcodebuild archive \
  -project Client.xcodeproj \
  -scheme Firefox \
  -configuration Firefox \
  -destination "generic/platform=iOS" \
  -archivePath ../build/Firefox.xcarchive \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES

cd ..
echo "=== 4. Xử lý bundle và patch iOS 26 ==="
mkdir -p build/Payload
APP_PATH=$(find build/*.xcarchive/Products/Applications -name "*.app" | head -n 1)

if [ -d "$APP_PATH/PlugIns/Sticker.appex" ]; then
  rm -rf "$APP_PATH/PlugIns/Sticker.appex"
fi

find "$APP_PATH" -name "._*" -delete 2>/dev/null || true
dot_clean -m "$APP_PATH" 2>/dev/null || true

# Patch Info.plist
find "$APP_PATH" -name "Info.plist" | while read -r plist; do
  /usr/libexec/PlistBuddy -c "Set :DTPlatformVersion 26.0" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTPlatformVersion string 26.0" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :DTSDKName iphoneos26.0" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTSDKName string iphoneos26.0" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :DTSDKBuild 26A528" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTSDKBuild string 26A528" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :DTXcode 2600" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTXcode string 2600" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :DTXcodeBuild 26A528" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTXcodeBuild string 26A528" "$plist" 2>/dev/null || true
done

# Patch Mach-O
find "$APP_PATH" -type f -perm +111 | while read -r bin; do
  if file "$bin" | grep -q "Mach-O"; then
    if vtool -show-build "$bin" 2>/dev/null | grep -q "platform iOS"; then
      vtool -set-build-version ios 16.0 26.0 -replace -output "$bin.vtool" "$bin" 2>/dev/null && mv "$bin.vtool" "$bin" || true
    fi
  fi
done

# Sign
SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -E "Apple Distribution|iPhone Distribution|Apple Development|iPhone Developer" | head -n 1 | awk -F '"' '{print $2}')
if [ -n "$SIGNING_IDENTITY" ]; then
  echo "Ký ứng dụng bằng chứng chỉ: $SIGNING_IDENTITY"
  find "$APP_PATH" -depth \( -name "*.framework" -o -name "*.dylib" -o -name "*.appex" \) | while read -r item; do
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$item" || true
  done
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$APP_PATH"
else
  echo "Ký Ad-hoc test..."
  find "$APP_PATH" -depth \( -name "*.framework" -o -name "*.dylib" -o -name "*.appex" \) | while read -r item; do
    codesign --force --sign - "$item" || true
  done
  codesign --force --deep --sign - "$APP_PATH" || true
fi

echo "=== 5. Đóng gói test.ipa ==="
cp -r "$APP_PATH" build/Payload/
cd build
zip -r -y -q test.ipa Payload
cp test.ipa VSG-Group.ipa
echo "HOÀN TẤT! File test.ipa đã được tạo tại: $(pwd)/test.ipa"
