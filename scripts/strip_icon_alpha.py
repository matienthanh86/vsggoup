#!/usr/bin/env python3
"""
Strips alpha channels and tRNS chunks from PNG icons in .appiconset, AppIcons.xcassets, and .stickersiconset
to satisfy Apple App Store ITMS-90717 requirement.
Works in pure Python (no external dependencies required).
"""
import os, sys, zlib, struct

def paeth_predictor(a, b, c):
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    elif pb <= pc:
        return b
    else:
        return c

def make_chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)

def strip_alpha_from_png(path):
    with open(path, 'rb') as f:
        data = f.read()

    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return False, 'not_png'

    idx = 8
    chunks = []
    ihdr = None
    plte = None
    idat_parts = []
    has_alpha = False
    has_trns = False

    while idx < len(data):
        length = struct.unpack('>I', data[idx:idx+4])[0]
        ctype = data[idx+4:idx+8]
        cdata = data[idx+8:idx+8+length]
        idx += 12 + length

        if ctype == b'IHDR':
            ihdr = bytearray(cdata)
        elif ctype == b'PLTE':
            plte = cdata
        elif ctype == b'IDAT':
            idat_parts.append(cdata)
        elif ctype == b'tRNS':
            has_trns = True
            has_alpha = True
            continue  # Drop tRNS chunk
        elif ctype == b'IEND':
            break
        else:
            chunks.append((ctype, cdata))

    w, h, bit_depth, color_type, comp, filt, interlace = struct.unpack('>IIBBBBB', ihdr[:13])
    if color_type in (4, 6):
        has_alpha = True

    if not has_alpha:
        return False, 'no_alpha'

    is_dark = 'dark' in os.path.basename(path).lower()
    bg_color = (0, 0, 0) if is_dark else (255, 255, 255)

    if color_type == 6 and bit_depth == 8 and interlace == 0:
        raw = zlib.decompress(b''.join(idat_parts))
        stride_in = 1 + w * 4
        stride_out = 1 + w * 3
        out_raw = bytearray(h * stride_out)

        prev_recon = bytearray(w * 4)
        for y in range(h):
            filter_type = raw[y * stride_in]
            in_scanline = raw[y * stride_in + 1 : (y + 1) * stride_in]
            recon = bytearray(w * 4)

            for i in range(w * 4):
                val = in_scanline[i]
                a = recon[i - 4] if i >= 4 else 0
                b = prev_recon[i]
                c = prev_recon[i - 4] if i >= 4 else 0

                if filter_type == 0:
                    recon[i] = val
                elif filter_type == 1:
                    recon[i] = (val + a) & 0xff
                elif filter_type == 2:
                    recon[i] = (val + b) & 0xff
                elif filter_type == 3:
                    recon[i] = (val + ((a + b) // 2)) & 0xff
                elif filter_type == 4:
                    recon[i] = (val + paeth_predictor(a, b, c)) & 0xff

            prev_recon = recon

            out_raw[y * stride_out] = 0  # Filter 0 None
            for x in range(w):
                r = recon[x * 4]
                g = recon[x * 4 + 1]
                b_val = recon[x * 4 + 2]
                alpha = recon[x * 4 + 3]
                if alpha != 255:
                    inv_a = 255 - alpha
                    r = (r * alpha + bg_color[0] * inv_a) // 255
                    g = (g * alpha + bg_color[1] * inv_a) // 255
                    b_val = (b_val * alpha + bg_color[2] * inv_a) // 255
                out_raw[y * stride_out + 1 + x * 3] = r
                out_raw[y * stride_out + 1 + x * 3 + 1] = g
                out_raw[y * stride_out + 1 + x * 3 + 2] = b_val

        new_idat = zlib.compress(bytes(out_raw), level=9)
        ihdr[9] = 2  # Set color type to 2 (RGB)

        new_png = bytearray(b'\x89PNG\r\n\x1a\n')
        new_png.extend(make_chunk(b'IHDR', bytes(ihdr)))
        for ct, cd in chunks:
            if ct not in (b'bKGD',):
                new_png.extend(make_chunk(ct, cd))
        new_png.extend(make_chunk(b'IDAT', new_idat))
        new_png.extend(make_chunk(b'IEND', b''))

        with open(path, 'wb') as f:
            f.write(new_png)
        return True, 'converted_rgba_to_rgb'

    elif color_type in (2, 3) and has_trns:
        new_png = bytearray(b'\x89PNG\r\n\x1a\n')
        new_png.extend(make_chunk(b'IHDR', bytes(ihdr)))
        if plte:
            new_png.extend(make_chunk(b'PLTE', plte))
        for ct, cd in chunks:
            if ct not in (b'bKGD',):
                new_png.extend(make_chunk(ct, cd))
        for idat in idat_parts:
            new_png.extend(make_chunk(b'IDAT', idat))
        new_png.extend(make_chunk(b'IEND', b''))
        with open(path, 'wb') as f:
            f.write(new_png)
        return True, 'removed_trns'

    return False, f'unsupported_format_{color_type}'

def main():
    target_dir = sys.argv[1] if len(sys.argv) > 1 else '.'
    count = 0
    for root, dirs, files in os.walk(target_dir):
        for f in files:
            if f.endswith('.png'):
                p = os.path.join(root, f)
                if ('.appiconset' in p or 'appicon' in p.lower() or '.stickersiconset' in p):
                    success, msg = strip_alpha_from_png(p)
                    if success:
                        count += 1
                        print(f'Fixed ({msg}): {p}')
    print(f'Done. Stripped alpha from {count} icon(s).')

if __name__ == '__main__':
    main()
