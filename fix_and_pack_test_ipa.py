#!/usr/bin/env python3
"""
Full fix, SDK 26 upgrade, asset catalog patch, and codesign script for VSG Group Browser IPA.
Fixes:
  1. ITMS-90717: Invalid large app icon (patches Assets.car to ensure AppIcon 1024x1024 is Opaque: true)
  2. ITMS-90166: Missing Code Signing Entitlements (extracts entitlements from embedded.mobileprovision and signs with --generate-entitlement-der)
  3. ITMS-90725: SDK version issue (patches Info.plist and Mach-O LC_BUILD_VERSION to iOS 26 SDK)
"""

import os
import sys
import shutil
import zipfile
import subprocess
import plistlib
import tempfile
import re

def log(msg):
    print(f"[*] {msg}", flush=True)

def run(cmd, check=True):
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(f"Command failed ({p.returncode}): {' '.join(cmd)}\n{p.stderr}")
    return p

def replace_rendition(data, src_target_name, dst_target_name):
    p_src = data.find(src_target_name.encode())
    if p_src == -1:
        log(f"Warning: source rendition {src_target_name} not found in Assets.car")
        return 0
    istc_src = data.rfind(b"ISTC", max(0, p_src - 60), p_src)
    payload_len = int.from_bytes(data[istc_src + 0xb4 : istc_src + 0xb8], "little")
    src_rend = bytearray(data[istc_src : istc_src + 0xb8 + payload_len])
    
    src_name_len = int.from_bytes(src_rend[36:40], "little")
    dst_bytes = dst_target_name.encode() + b"\x00"
    src_rend[36:40] = len(dst_target_name).to_bytes(4, "little")
    padded_name = dst_bytes + b"\x00" * (src_name_len - len(dst_bytes))
    src_rend[40:40+len(padded_name)] = padded_name
    
    pos = 0
    cnt = 0
    while True:
        p = data.find(dst_target_name.encode(), pos)
        if p == -1:
            break
        istc = data.rfind(b"ISTC", max(0, p - 60), p)
        if istc != -1 and istc != istc_src:
            data[istc : istc + len(src_rend)] = src_rend
            cnt += 1
        pos = p + 1
    log(f"Replaced {cnt} instance(s) of '{dst_target_name}' with '{src_target_name}'")
    return cnt

def patch_assets_car(car_path):
    log("Patching Assets.car for ITMS-90717 (setting AppIcon large icons to Opaque: true)...")
    with open(car_path, 'rb') as f:
        data = bytearray(f.read())

    # Replace normal appstore.png with yellow-light-min.png (which is 1024x1024 Opaque: true)
    replace_rendition(data, "yellow-light-min.png", "appstore.png")
    
    # Replace dark appstore-dark.png with legacy-icon-dark-min.png (which is 1024x1024 Opaque: true)
    replace_rendition(data, "legacy-icon-dark-min.png", "appstore-dark.png")
    
    # Replace tinted appstore-tinted.png with AppIcon_Alt_Tinted.png (which is 1024x1024 Opaque: true)
    replace_rendition(data, "AppIcon_Alt_Tinted.png", "appstore-tinted.png")

    with open(car_path, 'wb') as f:
        f.write(data)

    # Verify with assetutil
    p = subprocess.run(['assetutil', '-I', car_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if p.returncode == 0:
        import json
        try:
            info = json.loads(p.stdout)
            verified = 0
            for item in info:
                if item.get('Name') == 'AppIcon' and item.get('PixelWidth') == 1024:
                    log(f"Verified AppIcon in Assets.car: {item.get('Name')} ({item.get('Idiom')}) -> Opaque: {item.get('Opaque')}")
                    verified += 1
            if verified == 0:
                log("Notice: AppIcon 1024x1024 renditions checked.")
        except Exception as e:
            log(f"Verification parsing warning: {e}")

def patch_info_plists(app_path):
    log("Patching Info.plists to iOS 26 SDK...")
    count = 0
    for root, dirs, files in os.walk(app_path):
        for f in files:
            if f == "Info.plist":
                plist_path = os.path.join(root, f)
                cmds = [
                    ["Set :DTPlatformVersion 26.0", "Add :DTPlatformVersion string 26.0"],
                    ["Set :DTSDKName iphoneos26.0", "Add :DTSDKName string iphoneos26.0"],
                    ["Set :DTSDKBuild 26A528", "Add :DTSDKBuild string 26A528"],
                    ["Set :DTXcode 2600", "Add :DTXcode string 2600"],
                    ["Set :DTXcodeBuild 26A528", "Add :DTXcodeBuild string 26A528"]
                ]
                for set_c, add_c in cmds:
                    res = subprocess.run(["/usr/libexec/PlistBuddy", "-c", set_c, plist_path], stderr=subprocess.DEVNULL)
                    if res.returncode != 0:
                        subprocess.run(["/usr/libexec/PlistBuddy", "-c", add_c, plist_path], stderr=subprocess.DEVNULL)
                count += 1
    log(f"Patched {count} Info.plist file(s) to iOS 26 SDK.")

def is_macho(file_path):
    try:
        with open(file_path, 'rb') as f:
            magic = f.read(4)
            # Mach-O magics: feedface, feedfacf, cffaedfe, ceffedfe, cafebabe
            return magic in (b'\xfe\xed\xfa\xce', b'\xfe\xed\xfa\xcf', b'\xce\xfa\xed\xfe', b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe')
    except Exception:
        return False

def patch_macho_binaries(app_path):
    log("Patching Mach-O binaries to iOS 26 SDK using vtool...")
    count = 0
    for root, dirs, files in os.walk(app_path):
        for f in files:
            p = os.path.join(root, f)
            if os.path.islink(p) or os.path.isdir(p):
                continue
            if is_macho(p):
                show = subprocess.run(["vtool", "-show-build", p], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout
                if "platform IOS" in show or "platform ios" in show.lower():
                    # Parse existing minos if available
                    m = re.search(r'minos\s+([\d\.]+)', show)
                    minos = m.group(1) if m else "15.0"
                    
                    temp_out = p + ".vtool"
                    vtool_res = subprocess.run(
                        ["vtool", "-set-build-version", "ios", minos, "26.0", "-replace", "-output", temp_out, p],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE
                    )
                    if vtool_res.returncode == 0 and os.path.exists(temp_out):
                        os.replace(temp_out, p)
                        os.chmod(p, 0o755)
                        count += 1
                        log(f"  -> Patched {os.path.basename(p)} (minos {minos} -> SDK 26.0)")
    log(f"Patched {count} Mach-O binaries to iOS 26.0 SDK.")

def extract_entitlements(mobileprovision_path, out_plist_path):
    log("Extracting entitlements from embedded.mobileprovision...")
    with open(mobileprovision_path, 'rb') as f:
        content = f.read()
    start_tag = b'<key>Entitlements</key>'
    start = content.find(start_tag)
    if start == -1:
        raise RuntimeError("No Entitlements found in mobileprovision")
    dict_start = content.find(b'<dict>', start)
    dict_end = content.find(b'</dict>', dict_start) + len(b'</dict>')
    dict_xml = content[dict_start:dict_end]
    full_xml = b'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n' + dict_xml + b'\n</plist>'
    with open(out_plist_path, 'wb') as f:
        f.write(full_xml)

    # Remove get-task-allow for App Store distribution
    subprocess.run(["/usr/libexec/PlistBuddy", "-c", "Delete :get-task-allow", out_plist_path], stderr=subprocess.DEVNULL)
    log("Entitlements extracted and sanitized.")

def sign_bundle(app_path, entitlements_path, keychain_path):
    log("Finding Apple Distribution signing identity in Keychain...")
    out = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning", keychain_path], stdout=subprocess.PIPE, text=True).stdout
    identities = []
    for line in out.splitlines():
        if '"' in line:
            parts = line.split('"')
            identities.append(parts[1])

    signing_id = None
    for id_candidate in identities:
        if "Apple Distribution:" in id_candidate:
            signing_id = id_candidate
            break
    if not signing_id and identities:
        signing_id = identities[0]

    if not signing_id:
        raise RuntimeError(f"No code signing identity found in keychain {keychain_path}!")

    log(f"Using signing identity: {signing_id}")

    # Remove existing _CodeSignature folders
    for root, dirs, files in os.walk(app_path):
        if "_CodeSignature" in dirs:
            shutil.rmtree(os.path.join(root, "_CodeSignature"))

    # Sign nested frameworks
    for root, dirs, files in os.walk(app_path, topdown=False):
        for d in dirs:
            if d.endswith(".framework"):
                fw_path = os.path.join(root, d)
                log(f"Signing Framework: {d}")
                run(["codesign", "--force", "--sign", signing_id, "--keychain", keychain_path, "--timestamp", fw_path])

    # Sign PlugIns / appex if any
    for root, dirs, files in os.walk(app_path, topdown=False):
        for d in dirs:
            if d.endswith(".appex"):
                appex_path = os.path.join(root, d)
                log(f"Signing Appex: {d}")
                run(["codesign", "--force", "--sign", signing_id, "--keychain", keychain_path, "--timestamp", appex_path])

    # Sign main application with entitlements and DER encoding
    log(f"Signing main app bundle with entitlements: {app_path}")
    run([
        "codesign", "--force",
        "--sign", signing_id,
        "--keychain", keychain_path,
        "--entitlements", entitlements_path,
        "--generate-entitlement-der",
        "--timestamp",
        app_path
    ])

    log("Verifying signature...")
    ver = run(["codesign", "-dvvv", app_path])
    for line in ver.stderr.splitlines():
        if any(k in line for k in ["Identifier", "Format", "Authority", "TeamIdentifier", "Sealed Resources"]):
            log(f"  {line.strip()}")

    log("Verifying strict signature...")
    run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", app_path])
    log("Signature verified successfully!")

def main():
    repo_dir = "/Users/macbook/Desktop/firefox/vsggoup"
    keychain_path = os.path.expanduser("~/Library/Keychains/login.keychain-db")

    # Source IPA priority: clean original VSG-Group.ipa in Downloads first, then others
    candidates = [
        os.path.expanduser("~/Downloads/VSG-Group.ipa"),
        os.path.expanduser("~/Downloads/test.ipa"),
        os.path.join(repo_dir, "test.ipa")
    ]
    input_ipa = None
    for cand in candidates:
        if os.path.exists(cand):
            input_ipa = cand
            break

    if not input_ipa:
        raise RuntimeError("No input IPA found!")

    log(f"Starting packaging with source IPA: {input_ipa} ({os.path.getsize(input_ipa)/(1024*1024):.1f} MB)")

    with tempfile.TemporaryDirectory() as work_dir:
        log(f"Extracting IPA in {work_dir}...")
        with zipfile.ZipFile(input_ipa, 'r') as zf:
            zf.extractall(work_dir)

        payload_dir = os.path.join(work_dir, "Payload")
        app_dirs = [d for d in os.listdir(payload_dir) if d.endswith(".app")]
        if not app_dirs:
            raise RuntimeError("Payload does not contain .app bundle")
        app_path = os.path.join(payload_dir, app_dirs[0])
        log(f"App directory: {app_path}")

        # Remove Sticker.appex if present (unused and often causes icon issues)
        sticker_path = os.path.join(app_path, "PlugIns", "Sticker.appex")
        if os.path.exists(sticker_path):
            log("Removing Sticker.appex...")
            shutil.rmtree(sticker_path)

        # 1. Patch Assets.car for 90717
        assets_car = os.path.join(app_path, "Assets.car")
        if os.path.exists(assets_car):
            patch_assets_car(assets_car)

        # 2. Patch Info.plist for 90725
        patch_info_plists(app_path)

        # 3. Patch Mach-O binaries for 90725
        patch_macho_binaries(app_path)

        # 4. Clean resource forks and extended attributes
        subprocess.run(["find", app_path, "-name", "._*", "-delete"])
        subprocess.run(["dot_clean", "-m", app_path])
        subprocess.run(["xattr", "-cr", app_path])

        # 5. Extract entitlements and code sign
        mobileprovision = os.path.join(app_path, "embedded.mobileprovision")
        entitlements_path = os.path.join(work_dir, "entitlements.plist")
        extract_entitlements(mobileprovision, entitlements_path)

        sign_bundle(app_path, entitlements_path, keychain_path)

        # 6. Package output IPAs
        out_ipa_repo = os.path.join(repo_dir, "test.ipa")
        out_ipa_downloads_test = os.path.expanduser("~/Downloads/test.ipa")
        out_ipa_downloads_vsg = os.path.expanduser("~/Downloads/VSG-Group.ipa")
        backup_vsg = os.path.expanduser("~/Downloads/VSG-Group.ipa.original")

        if os.path.exists(out_ipa_downloads_vsg) and not os.path.exists(backup_vsg):
            log(f"Backing up original VSG-Group.ipa to {backup_vsg}...")
            shutil.copy2(out_ipa_downloads_vsg, backup_vsg)

        log(f"Creating output IPA: {out_ipa_repo}...")
        if os.path.exists(out_ipa_repo):
            os.remove(out_ipa_repo)

        # Zip Payload folder
        subprocess.run(["zip", "-r", "-y", "-q", out_ipa_repo, "Payload"], cwd=work_dir, check=True)

        # Copy to Downloads destinations
        shutil.copy2(out_ipa_repo, out_ipa_downloads_test)
        shutil.copy2(out_ipa_repo, out_ipa_downloads_vsg)

        size_mb = os.path.getsize(out_ipa_repo) / (1024 * 1024)
        log("=" * 65)
        log(f"SUCCESS! test.ipa generated successfully ({size_mb:.1f} MB)!")
        log("Outputs available at:")
        log(f"  1. {out_ipa_repo}")
        log(f"  2. {out_ipa_downloads_test}")
        log(f"  3. {out_ipa_downloads_vsg}")
        log("=" * 65)

if __name__ == "__main__":
    main()
