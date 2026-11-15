#!/usr/bin/env bash
set -e

IPA_INPUT="$1"

if [ -z "$IPA_INPUT" ] || [ ! -f "$IPA_INPUT" ]; then
  echo "=========================================================="
  echo "Cách sử dụng: ./patch_existing_ipa.sh <duong-dan-file.ipa>"
  echo "Ví dụ:        ./patch_existing_ipa.sh ~/Downloads/app.ipa"
  echo "=========================================================="
  exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> 1. Giải nén IPA: $IPA_INPUT"
unzip -q "$IPA_INPUT" -d "$WORK_DIR"

APP_PATH=$(find "$WORK_DIR/Payload" -name "*.app" -maxdepth 1 | head -n 1)
if [ -z "$APP_PATH" ]; then
  echo "Lỗi: Không tìm thấy thư mục .app trong file IPA!"
  exit 1
fi
echo "Tìm thấy App: $APP_PATH"

echo "==> 2. Gỡ bỏ kênh Alpha trên toàn bộ icon..."
python3 "$DIR/scripts/strip_icon_alpha.py" "$APP_PATH"

echo "==> 3. Xóa các extension gây lỗi (Sticker.appex nếu có)..."
if [ -d "$APP_PATH/PlugIns/Sticker.appex" ]; then
  rm -rf "$APP_PATH/PlugIns/Sticker.appex"
fi

echo "==> 4. Xóa tệp ẩn rác macOS (._*)..."
find "$APP_PATH" -name "._*" -delete 2>/dev/null || true
dot_clean -m "$APP_PATH" 2>/dev/null || true

echo "==> 5. Cập nhật SDK lên iOS 26 trong Info.plist..."
find "$APP_PATH" -name "Info.plist" | while read -r plist; do
  /usr/libexec/PlistBuddy -c "Set :DTPlatformVersion 26.0" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTPlatformVersion string 26.0" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :DTSDKName iphoneos26.0" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTSDKName string iphoneos26.0" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :DTSDKBuild 26A528" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTSDKBuild string 26A528" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :DTXcode 2600" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTXcode string 2600" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :DTXcodeBuild 26A528" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTXcodeBuild string 26A528" "$plist" 2>/dev/null || true
done

echo "==> 6. Cập nhật Mach-O SDK version lên 26.0 bằng vtool..."
find "$APP_PATH" -type f -perm +111 | while read -r bin; do
  if file "$bin" | grep -q "Mach-O"; then
    if vtool -show-build "$bin" 2>/dev/null | grep -q "platform iOS"; then
      vtool -set-build-version ios 16.0 26.0 -replace -output "$bin.vtool" "$bin" 2>/dev/null && mv "$bin.vtool" "$bin" || true
    fi
  fi
done

echo "==> 7. Ký lại ứng dụng (Re-signing)..."
# Tìm chứng chỉ Apple trong Keychain (nếu có)
SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -E "Apple Distribution|iPhone Distribution|Apple Development|iPhone Developer" | head -n 1 | awk -F '"' '{print $2}')

if [ -n "$SIGNING_IDENTITY" ]; then
  echo "Phát hiện chứng chỉ: $SIGNING_IDENTITY"
  find "$APP_PATH" -depth \( -name "*.framework" -o -name "*.dylib" -o -name "*.appex" \) | while read -r item; do
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$item" || true
  done
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$APP_PATH"
else
  echo "Không tìm thấy chứng chỉ nhà phát triển Apple, thực hiện ký Ad-hoc (-)..."
  find "$APP_PATH" -depth \( -name "*.framework" -o -name "*.dylib" -o -name "*.appex" \) | while read -r item; do
    codesign --force --sign - "$item" || true
  done
  codesign --force --deep --sign - "$APP_PATH" || true
fi

echo "==> 8. Đóng gói test.ipa..."
OUTPUT_IPA="$DIR/test.ipa"
cd "$WORK_DIR"
zip -r -y -q "$OUTPUT_IPA" Payload
echo "=========================================================="
echo "THÀNH CÔNG! Đã đóng gói xong file: $OUTPUT_IPA"
echo "Kích thước: $(ls -lh "$OUTPUT_IPA" | awk '{print $5}')"
echo "=========================================================="
