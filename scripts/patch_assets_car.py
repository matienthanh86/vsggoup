#!/usr/bin/env python3
import os, sys, ctypes, struct, zlib

def main():
    car_path = os.environ.get("ASSETS_CAR")
    vsg_light = os.environ.get("VSG_ICON_SRC")
    vsg_dark = os.environ.get("VSG_DARK_SRC")

    if not car_path or not os.path.exists(car_path):
        print(f"Assets.car not found at: {car_path}")
        return
    if not vsg_light or not os.path.exists(vsg_light):
        print(f"VSG_ICON_SRC not found at: {vsg_light}")
        return

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
        if not payload:
            continue
        pos = 0
        while True:
            p = car_data.find(target_name, pos)
            if p == -1:
                break
            istc = car_data.rfind(b"ISTC", max(0, p - 60), p)
            if istc != -1:
                old_plen = int.from_bytes(car_data[istc + 0xb4 : istc + 0xb8], "little")
                hdr_120 = bytearray(car_data[istc + 0xb8 : istc + 0xb8 + 120])
                hdr_120[0x6c] = 0x03 # Opaque = true
                new_payload = hdr_120 + payload
                new_plen = len(new_payload)
                if new_plen <= old_plen:
                    car_data[istc + 0xb8 : istc + 0xb8 + new_plen] = new_payload
                    if new_plen < old_plen:
                        car_data[istc + 0xb8 + new_plen : istc + 0xb8 + old_plen] = b"\x00" * (old_plen - new_plen)
                    total_patched += 1
            pos = p + len(target_name)

    with open(car_path, "wb") as f:
        f.write(car_data)
    print(f"Đã vá thành công {total_patched} renditions trong Assets.car sang icon VSG Group!")

if __name__ == "__main__":
    main()
