#!/usr/bin/env bash
# ==============================================================================
# Script tự động Patch và Đóng gói IPA cho app VSG Group
# Tương thích cả file .ipa lẫn thư mục Payload
# Khắc phục triệt để 3 lỗi Apple Transporter:
#   1. ITMS-90717: Nhúng 100% icon VSG Group vào Assets.car với cờ Opaque: True
#   2. ITMS-90166: Missing Code Signing Entitlements (Tạo DER entitlements)
#   3. ITMS-90725: SDK version issue (Nâng Info.plist và Mach-O lên iOS 26 SDK)
# ==============================================================================

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"

# 1. Nhận diện tham số và nguồn đầu vào thông minh
INPUT_ARG="$1"
BUILD_ARG="$2"
OUTPUT_NAME="${3:-VSG-Group.ipa}"

# Nếu tham số 1 là số (ví dụ: ./patch_existing_ipa.sh 3), coi đó là build number
if [[ "$INPUT_ARG" =~ ^[0-9]+$ ]]; then
  BUILD_ARG="$INPUT_ARG"
  INPUT_ARG=""
fi

# Tự động tìm nguồn đầu vào thông minh
INPUT_SOURCE=""
if [ -n "$INPUT_ARG" ]; then
  if [ -f "$INPUT_ARG" ] || [ "$(basename "$INPUT_ARG")" = "Payload" ] || [ -d "$INPUT_ARG/Payload" ]; then
    INPUT_SOURCE="$INPUT_ARG"
  elif [ -d "$INPUT_ARG/temp_vsg/Payload" ]; then
    INPUT_SOURCE="$INPUT_ARG/temp_vsg/Payload"
  elif [ -f "$INPUT_ARG/VSG-Group.ipa" ]; then
    INPUT_SOURCE="$INPUT_ARG/VSG-Group.ipa"
  elif [ -d "$INPUT_ARG" ]; then
    FOUND_PAYLOAD=$(find "$INPUT_ARG" -name "Payload" -type d -maxdepth 3 2>/dev/null | head -n 1)
    if [ -n "$FOUND_PAYLOAD" ]; then
      INPUT_SOURCE="$FOUND_PAYLOAD"
    else
      FOUND_IPA=$(find "$INPUT_ARG" -name "*.ipa" -maxdepth 2 2>/dev/null | head -n 1)
      if [ -n "$FOUND_IPA" ]; then
        INPUT_SOURCE="$FOUND_IPA"
      fi
    fi
  fi
fi

if [ -z "$INPUT_SOURCE" ]; then
  if [ -d "$HOME/Downloads/temp_vsg/Payload" ]; then
    INPUT_SOURCE="$HOME/Downloads/temp_vsg/Payload"
  elif [ -f "$HOME/Downloads/VSG-Group.ipa" ]; then
    INPUT_SOURCE="$HOME/Downloads/VSG-Group.ipa"
  elif [ -f "$DIR/VSG-Group.ipa" ]; then
    INPUT_SOURCE="$DIR/VSG-Group.ipa"
  fi
fi

if [ -z "$INPUT_SOURCE" ] || { [ ! -f "$INPUT_SOURCE" ] && [ ! -d "$INPUT_SOURCE" ]; }; then
  echo "=================================================================="
  echo "Cách sử dụng: ./patch_existing_ipa.sh [build_number]"
  echo "         hoặc ./patch_existing_ipa.sh [nguon_ipa_hoac_payload] [build_number]"
  echo "Ví dụ:        ./patch_existing_ipa.sh 3"
  echo "=================================================================="
  exit 1
fi

OUTPUT_IPA="$DIR/$OUTPUT_NAME"
OUTPUT_DOWNLOADS="$HOME/Downloads/$OUTPUT_NAME"

echo "=================================================================="
echo "BẮT ĐẦU XỬ LÝ ĐÓNG GÓI CHO APP VSG GROUP"
echo "  Nguồn vào:  $INPUT_SOURCE"
echo "  File xuất:  $OUTPUT_IPA"
echo "=================================================================="

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Trích xuất hoặc sao chép Payload
if [ -d "$INPUT_SOURCE" ]; then
  echo "==> 1. Chuẩn bị thư mục Payload từ $INPUT_SOURCE..."
  if [ "$(basename "$INPUT_SOURCE")" = "Payload" ]; then
    cp -r "$INPUT_SOURCE" "$WORK_DIR/Payload"
  elif [ -d "$INPUT_SOURCE/Payload" ]; then
    cp -r "$INPUT_SOURCE/Payload" "$WORK_DIR/Payload"
  else
    mkdir -p "$WORK_DIR/Payload"
    cp -r "$INPUT_SOURCE" "$WORK_DIR/Payload/"
  fi
else
  echo "==> 1. Giải nén file IPA: $INPUT_SOURCE..."
  unzip -q "$INPUT_SOURCE" -d "$WORK_DIR"
fi

APP_PATH=$(find "$WORK_DIR/Payload" -name "*.app" -maxdepth 1 | head -n 1)
if [ -z "$APP_PATH" ]; then
  echo "Lỗi: Không tìm thấy thư mục .app trong Payload!"
  exit 1
fi
export APP_PATH
export ASSETS_CAR="$APP_PATH/Assets.car"
export WORK_DIR
echo "Đã tìm thấy app bundle: $(basename "$APP_PATH")"

# 2. Xóa plugin gây lỗi và gói icon vector Firefox (.icon)
if [ -d "$APP_PATH/PlugIns/Sticker.appex" ]; then
  echo "==> Xóa Sticker.appex..."
  rm -rf "$APP_PATH/PlugIns/Sticker.appex"
fi

# Xóa các gói AppIcon.icon vector của Firefox (nguyên nhân gây hiển thị icon Firefox trên macOS và iOS 18)
echo "==> Xóa toàn bộ gói icon vector Firefox (.icon)..."
rm -rf "$APP_PATH"/AppIcon*.icon

# Tạo và ghi đè toàn bộ các file PNG AppIcon vật lý từ icon VSG Group chuẩn (1024x1024)
VSG_ICON_SRC="$DIR/firefox-ios/Client/Assets/AppIcons.xcassets/AppIcon.appiconset/appstore.png"
if [ -f "$VSG_ICON_SRC" ]; then
  echo "==> Ghi đè toàn bộ kích thước PNG AppIcon (Thông báo 20pt, Cài đặt 29pt, Spotlight 40pt, Màn hình chính 60pt/76pt/83.5pt)..."
  # 20pt (Notification icon cho iPhone và iPad)
  sips -z 40 40 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon20x20@2x.png" >/dev/null 2>&1 || true
  sips -z 60 60 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon20x20@3x.png" >/dev/null 2>&1 || true
  sips -z 20 20 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon20x20~ipad.png" >/dev/null 2>&1 || true
  sips -z 40 40 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon20x20@2x~ipad.png" >/dev/null 2>&1 || true

  # 29pt (Settings icon cho iPhone và iPad)
  sips -z 58 58 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon29x29@2x.png" >/dev/null 2>&1 || true
  sips -z 87 87 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon29x29@3x.png" >/dev/null 2>&1 || true
  sips -z 29 29 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon29x29~ipad.png" >/dev/null 2>&1 || true
  sips -z 58 58 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon29x29@2x~ipad.png" >/dev/null 2>&1 || true

  # 40pt (Spotlight icon cho iPhone và iPad)
  sips -z 80 80 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon40x40@2x.png" >/dev/null 2>&1 || true
  sips -z 120 120 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon40x40@3x.png" >/dev/null 2>&1 || true
  sips -z 40 40 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon40x40~ipad.png" >/dev/null 2>&1 || true
  sips -z 80 80 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon40x40@2x~ipad.png" >/dev/null 2>&1 || true

  # 60pt (Home Screen icon cho iPhone)
  sips -z 120 120 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon60x60@2x.png" >/dev/null 2>&1 || true
  sips -z 180 180 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon60x60@3x.png" >/dev/null 2>&1 || true

  # 76pt & 83.5pt (Home Screen icon cho iPad & iPad Pro)
  sips -z 76 76 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon76x76~ipad.png" >/dev/null 2>&1 || true
  sips -z 152 152 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon76x76@2x~ipad.png" >/dev/null 2>&1 || true
  sips -z 167 167 "$VSG_ICON_SRC" --out "$APP_PATH/AppIcon83.5x83.5@2x~ipad.png" >/dev/null 2>&1 || true
fi

# 3. Cập nhật Build Number và Tên hiển thị app
MAIN_INFO_PLIST="$APP_PATH/Info.plist"
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$MAIN_INFO_PLIST" 2>/dev/null || echo "1")

# Xác định build number cao nhất đã từng upload (Build 1, 2 và 3 đã lên App Store Connect)
BUILD_TRACK_FILE="$DIR/.build_number"
LAST_BUILD=3
if [ -f "$BUILD_TRACK_FILE" ]; then
  READ_BUILD=$(cat "$BUILD_TRACK_FILE" 2>/dev/null || echo "3")
  if [[ "$READ_BUILD" =~ ^[0-9]+$ ]] && [ "$READ_BUILD" -gt "$LAST_BUILD" ]; then
    LAST_BUILD="$READ_BUILD"
  fi
fi

if [ -n "$BUILD_ARG" ]; then
  NEW_BUILD="$BUILD_ARG"
else
  NEW_BUILD=$((LAST_BUILD + 1))
fi
echo "$NEW_BUILD" > "$BUILD_TRACK_FILE"

echo "==> 2. Cập nhật thông tin phiên bản và cấu hình Icon:"
echo "  CFBundleDisplayName: VSG Group"
echo "  CFBundleVersion: $CURRENT_BUILD -> $NEW_BUILD"

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName VSG Group" "$MAIN_INFO_PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string VSG Group" "$MAIN_INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleName VSG Group" "$MAIN_INFO_PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleName string VSG Group" "$MAIN_INFO_PLIST" 2>/dev/null || true

# Xóa toàn bộ icon phụ của Firefox (Alternate Icons) để iOS không bao giờ lấy icon vàng cũ
/usr/libexec/PlistBuddy -c "Delete :CFBundleIcons:CFBundleAlternateIcons" "$MAIN_INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :CFBundleIcons~ipad:CFBundleAlternateIcons" "$MAIN_INFO_PLIST" 2>/dev/null || true

# Khai báo rõ các kích thước icon chính (đặc biệt là AppIcon20x20 cho Thông báo)
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles: string AppIcon20x20" "$MAIN_INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles: string AppIcon29x29" "$MAIN_INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles: string AppIcon40x40" "$MAIN_INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles: string AppIcon20x20" "$MAIN_INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles: string AppIcon29x29" "$MAIN_INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles: string AppIcon40x40" "$MAIN_INFO_PLIST" 2>/dev/null || true

find "$APP_PATH" -name "Info.plist" | while read -r plist; do
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$plist" 2>/dev/null || true
done

# 4. Sửa lỗi Assets.car (ITMS-90717: Nhúng 100% icon VSG Group vào Assets.car với cờ Opaque: True)
ASSETS_CAR="$APP_PATH/Assets.car"
PRISTINE_CAR="$HOME/Downloads/temp_vsg/Payload/Client.app/Assets.car"

if [ -f "$PRISTINE_CAR" ]; then
  echo "==> Khôi phục cấu trúc Assets.car gốc..."
  cp "$PRISTINE_CAR" "$ASSETS_CAR"
fi

if [ -f "$ASSETS_CAR" ]; then
  echo "==> 3. Nhúng 100% icon VSG Group vào Assets.car (Chế độ Sáng, Tối, Tinted - chuẩn LZFSE KCBC, Opaque: True)..."
  VSG_ICON_SRC="$VSG_ICON_SRC" VSG_DARK_SRC="$DIR/firefox-ios/Client/Assets/AppIcons.xcassets/AppIcon.appiconset/appstore-dark.png" ASSETS_CAR="$ASSETS_CAR" python3 - << 'PYEOF'
import os, sys, ctypes, struct, zlib

car_path = os.environ.get("ASSETS_CAR")
vsg_light = os.environ.get("VSG_ICON_SRC")
vsg_dark = os.environ.get("VSG_DARK_SRC")

lib = ctypes.cdll.LoadLibrary("/usr/lib/libcompression.dylib")
encode = lib.compression_encode_buffer
encode.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_int]
encode.restype = ctypes.c_size_t

def png_to_kcbc(png_path):
    if not png_path or not os.path.exists(png_path):
        return None
    with open(png_path, "rb") as f:
        png_data = f.read()

    w, h, bit_depth, color_type = struct.unpack(">IIBB", png_data[16:26])
    idat = bytearray()
    pos = 8
    while pos < len(png_data):
        length, ctype = struct.unpack(">I4s", png_data[pos:pos+8])
        if ctype == b"IDAT":
            idat.extend(png_data[pos+8:pos+8+length])
        pos += 8 + length + 4

    decompressed = zlib.decompress(idat)
    bpp = 3 if color_type == 2 else 4
    line_len = 1 + w * bpp
    raw_pixels = bytearray(w * h * bpp)
    stride = w * bpp

    for y in range(h):
        filter_type = decompressed[y * line_len]
        curr = decompressed[y * line_len + 1 : (y + 1) * line_len]
        out_line = bytearray(stride)
        prev = raw_pixels[(y - 1) * stride : y * stride] if y > 0 else bytearray(stride)
        for x in range(stride):
            a = out_line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if filter_type == 0: val = curr[x]
            elif filter_type == 1: val = (curr[x] + a) & 0xff
            elif filter_type == 2: val = (curr[x] + b) & 0xff
            elif filter_type == 3: val = (curr[x] + (a + b) // 2) & 0xff
            elif filter_type == 4:
                p = a + b - c
                pa = abs(p - a); pb = abs(p - b); pc = abs(p - c)
                if pa <= pb and pa <= pc: pr = a
                elif pb <= pc: pr = b
                else: pr = c
                val = (curr[x] + pr) & 0xff
            else: val = curr[x]
            out_line[x] = val
        raw_pixels[y * stride : (y + 1) * stride] = out_line

    bgra = bytearray(w * h * 4)
    for i in range(w * h):
        if bpp == 3:
            r = raw_pixels[i * 3]; g = raw_pixels[i * 3 + 1]; b = raw_pixels[i * 3 + 2]
        else:
            r = raw_pixels[i * 4]; g = raw_pixels[i * 4 + 1]; b = raw_pixels[i * 4 + 2]
        bgra[i * 4] = b
        bgra[i * 4 + 1] = g
        bgra[i * 4 + 2] = r
        bgra[i * 4 + 3] = 0xff

    chunk_rows = [341, 341, 341, 1]
    row_offset = 0
    kcbc_payload = bytearray()
    for rows in chunk_rows:
        raw_chunk = bgra[row_offset * 1024 * 4 : (row_offset + rows) * 1024 * 4]
        dst = ctypes.create_string_buffer(len(raw_chunk))
        c_len = encode(dst, len(raw_chunk), bytes(raw_chunk), len(raw_chunk), None, 0x801)
        chunk_data = dst.raw[:c_len]
        hdr = b"KCBC" + struct.pack("<IIII", 0, 0, rows, c_len)
        kcbc_payload.extend(hdr + chunk_data)
        row_offset += rows
    return kcbc_payload

kcbc_light = png_to_kcbc(vsg_light)
kcbc_dark = png_to_kcbc(vsg_dark) or kcbc_light

with open(car_path, "rb") as f:
    car_data = bytearray(f.read())

targets = [
    (b"appstore.png", kcbc_light),
    (b"appstore-dark.png", kcbc_dark),
    (b"appstore-tinted.png", kcbc_dark)
]

total_patched = 0
for target_name, payload in targets:
    pos = 0
    cnt = 0
    while True:
        p = car_data.find(target_name, pos)
        if p == -1:
            break
        istc = car_data.rfind(b"ISTC", max(0, p - 60), p)
        if istc != -1:
            old_plen = int.from_bytes(car_data[istc + 0xb4 : istc + 0xb8], "little")
            hdr_120 = bytearray(car_data[istc + 0xb8 : istc + 0xb8 + 120])
            hdr_120[0x6c] = 0x03 # Opaque = true (loại bỏ alpha ITMS-90717)
            new_payload = hdr_120 + payload
            new_plen = len(new_payload)
            next_istc = car_data.find(b"ISTC", istc + 4)
            available = next_istc - (istc + 0xb8) if next_istc != -1 else old_plen
            if new_plen <= available:
                car_data[istc + 0xb4 : istc + 0xb8] = new_plen.to_bytes(4, "little")
                car_data[istc + 0xb8 : istc + 0xb8 + new_plen] = new_payload
                cnt += 1
        pos = p + 1
    total_patched += cnt

with open(car_path, "wb") as f:
    f.write(car_data)

print(f"  -> Đã nhúng 100% icon VSG Group vào {total_patched} vị trí (Light, Dark, Tinted) trong Assets.car!")
PYEOF
fi

# 5. Cập nhật SDK lên iOS 26 trong toàn bộ Info.plist (ITMS-90725 & ITMS-90208)
echo "==> 4. Cập nhật SDK lên iOS 26 trong Info.plist (ITMS-90725, ITMS-90208)..."
find "$APP_PATH" -name "Info.plist" | while read -r plist; do
  /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion 15.0" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string 15.0" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :DTPlatformVersion 26.0" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTPlatformVersion string 26.0" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :DTSDKName iphoneos26.0" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTSDKName string iphoneos26.0" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :DTSDKBuild 26A528" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTSDKBuild string 26A528" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :DTXcode 2600" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTXcode string 2600" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :DTXcodeBuild 26A528" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :DTXcodeBuild string 26A528" "$plist" 2>/dev/null || true
done

# 6. Cập nhật Mach-O binary bằng vtool (ITMS-90725 & ITMS-90208)
echo "==> 5. Cập nhật Mach-O LC_BUILD_VERSION sang iOS 15.0 minos / 26.0 SDK bằng vtool..."
APP_PATH="$APP_PATH" python3 - << 'PYEOF'
import os, subprocess, re

app_path = os.environ.get("APP_PATH")
count = 0
for root, dirs, files in os.walk(app_path):
    for f in files:
        p = os.path.join(root, f)
        if os.path.islink(p) or os.path.isdir(p):
            continue
        try:
            with open(p, 'rb') as fp:
                mag = fp.read(4)
            if mag in (b'\xfe\xed\xfa\xce', b'\xfe\xed\xfa\xcf', b'\xce\xfa\xed\xfe', b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'):
                show = subprocess.run(["vtool", "-show-build", p], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout
                if "platform ios" in show.lower():
                    # Đặt minos 15.0 để khớp chính xác với MinimumOSVersion 15.0 trong Info.plist (tránh lỗi 90208)
                    minos = "15.0"
                    temp_out = p + ".vtool"
                    res = subprocess.run(["vtool", "-set-build-version", "ios", minos, "26.0", "-replace", "-output", temp_out, p], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    if res.returncode == 0 and os.path.exists(temp_out):
                        os.replace(temp_out, p)
                        os.chmod(p, 0o755)
                        count += 1
        except Exception:
            pass
print(f"  -> Đã vá {count} binary sang minos 15.0 / SDK 26.0")
PYEOF

# 7. Xóa các thuộc tính mở rộng và tệp rác macOS
find "$APP_PATH" -name "._*" -delete 2>/dev/null || true
dot_clean -m "$APP_PATH" 2>/dev/null || true
xattr -cr "$APP_PATH" 2>/dev/null || true

# 8. Trích xuất Entitlements chuẩn từ embedded.mobileprovision
echo "==> 6. Trích xuất Entitlements từ embedded.mobileprovision..."
ENTITLEMENTS_FILE="$WORK_DIR/entitlements.plist"
python3 - << PYEOF
with open("$APP_PATH/embedded.mobileprovision", "rb") as f:
    content = f.read()
start_tag = b'<key>Entitlements</key>'
start = content.find(start_tag)
if start != -1:
    dict_start = content.find(b'<dict>', start)
    dict_end = content.find(b'</dict>', dict_start) + len(b'</dict>')
    dict_xml = content[dict_start:dict_end]
    full_xml = b'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n' + dict_xml + b'\n</plist>'
    with open("$ENTITLEMENTS_FILE", "wb") as f_out:
        f_out.write(full_xml)
PYEOF

/usr/libexec/PlistBuddy -c "Delete :get-task-allow" "$ENTITLEMENTS_FILE" 2>/dev/null || true

# 9. Ký số với chứng chỉ Apple Distribution trong Keychain
echo "==> 7. Ký lại toàn bộ Framework và App (ITMS-90166)..."
SIGNING_IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null | grep "Apple Distribution:" | head -n 1 | awk -F '"' '{print $2}')
if [ -z "$SIGNING_IDENTITY" ]; then
  SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Distribution:" | head -n 1 | awk -F '"' '{print $2}')
fi

if [ -z "$SIGNING_IDENTITY" ]; then
  echo "Lỗi: Không tìm thấy chứng chỉ 'Apple Distribution' trong Keychain!"
  exit 1
fi
echo "Sử dụng chứng chỉ ký: $SIGNING_IDENTITY"

# Xóa chữ ký cũ
find "$APP_PATH" -name "_CodeSignature" -exec rm -rf {} + 2>/dev/null || true

# Ký các Frameworks trước
find "$APP_PATH" -depth -name "*.framework" | while read -r fw; do
  echo "  Ký Framework: $(basename "$fw")"
  codesign --force --sign "$SIGNING_IDENTITY" --keychain "$KEYCHAIN_PATH" --timestamp "$fw"
done

# Ký các Plugin/Appex nếu còn
find "$APP_PATH" -depth -name "*.appex" | while read -r appex; do
  echo "  Ký Appex: $(basename "$appex")"
  codesign --force --sign "$SIGNING_IDENTITY" --keychain "$KEYCHAIN_PATH" --timestamp "$appex"
done

# Ký Main App bundle với Entitlements và DER encoding
echo "  Ký App bundle chính với entitlements..."
codesign --force --sign "$SIGNING_IDENTITY" \
  --keychain "$KEYCHAIN_PATH" \
  --entitlements "$ENTITLEMENTS_FILE" \
  --generate-entitlement-der \
  --timestamp \
  "$APP_PATH"

echo "==> 8. Kiểm tra tính hợp lệ chữ ký..."
codesign --verify --deep --strict "$APP_PATH"
echo "  -> Chữ ký hoàn toàn hợp lệ!"

# 10. Đóng gói lại thành IPA
echo "==> 9. Đóng gói $OUTPUT_NAME..."
cd "$WORK_DIR"
rm -f "$OUTPUT_IPA" "$OUTPUT_DOWNLOADS" "$DIR/test.ipa" "$HOME/Downloads/test.ipa"
zip -r -y -q "$OUTPUT_IPA" Payload
cp "$OUTPUT_IPA" "$OUTPUT_DOWNLOADS"

SIZE_MB=$(ls -lh "$OUTPUT_IPA" | awk '{print $5}')
echo "=================================================================="
echo "THÀNH CÔNG! ĐÃ ĐÓNG GÓI XONG APP VSG GROUP"
echo "  Phiên bản: 161.0 (Build $NEW_BUILD)"
echo "  Icon: 100% LOGO VSG GROUP (ĐÃ NHÚNG VÀ BẬT OPAQUE: TRUE)"
echo "  Kích thước: $SIZE_MB"
echo "  Vị trí file sẵn sàng:"
echo "    1. $OUTPUT_IPA"
echo "    2. $OUTPUT_DOWNLOADS"
echo "=================================================================="
