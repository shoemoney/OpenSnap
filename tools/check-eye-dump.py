#!/usr/bin/env python3
"""G7: assert that a screenshot-harness output folder is sound. Python standard library only.

Usage: check-eye-dump.py DIR [--strict] [--strict-contrast] [--jobs N]
       check-eye-dump.py --self-test
DIR is a raw harness run (raw-sf/*.png with raw-sf/layout/*.json) or a packed evidence folder (*.png, layout/*.json,
manifest.json); every *.png below it is checked, and a layout JSON is paired to its PNG by file stem.

Hard checks (a failure exits 1):
  png        every PNG decodes (signature, chunk CRCs, zlib stream, scanline length, filter bytes) and is not one flat colour;
             with a manifest.json beside it the decoded size equals storedPixelSize, every listed file exists and none is unlisted
  clip       in every layout JSON, every visible control lies inside its group, every group and the status / zoom / checkbox row
             inside its bar, every bar and the viewport inside the window, all within 0.5 pt (2 pt for a text field, checkbox or
             popup against its stack or holder, whose AppKit frame is larger than the alignment rect); nothing in a bar overlaps
             (the harness's own slack.overlaps and frameHole.controlsOverlappingHole must be empty too)
  size       a main-editor capture (one that records a topBar) is at least the minimum window: width from
             minimumWindowWidth in Sources/ModernEditorChrome.swift (980), height 640 (the window's minSize)
  gap        a menu capture the harness could not take (gapsraw/*.json or the manifest's gaps) fails the run unless a capture of the
             same id, appearance and icon mode or an `explained` note covers it
  rail       where the layout JSON has a `rail` field it is "absent", railChecks report nothing retired or stray, and the
             viewport's trailing margin is 12 +/- 0.5 measured from its recorded rect against the window width, not just the
             harness's own boolean
  glass      the glass-choice surfaces (S50-S60, tools/eye-dump-audit.sh --groups glass): every surface the run asked for (its
             requested-surfaces.jsonl, else every glass surface seen) must have every required capture for each appearance and icon mode
             (GLASS_SURFACES), and each capture's `glassPanel` record must show: one glass container per panel, nested glass 0, the minimum
             text size >= 18 pt, and the variant's own proof -- hover names a hovered row, focus a focused row, chosen a chosen row,
             disabled a disabled row that never took focus, dismissed a panel that is gone with focus back on its opener. A glass gap
             (a panel that never appeared) always fails.
  selected   text on a selected fill (a saturated block of one colour: the Settings destination row, a History tile, a segment) reads at
             >= 4.5:1 in every line, so the secondary label ("S3-compatible", "Exported") cannot fall short unnoticed; the PNG is sampled
             (no layout needed) and the self-test seeds a 3.5:1 secondary line that must fail.
Advisory check (printed as ADVISORY; exits 1 only under --strict or --strict-contrast):
  contrast   the layout JSON does not record text or background colours, so for the text-bearing controls whose frames it does
             record (status text, zoom popup, Original size checkbox) the checker samples the PNG inside the frame: the
             background is the dominant colour, the text colour the mean of the 10% of pixels furthest from it, and the WCAG
             ratio must be at least 4.5. Packed PNGs are downscaled and anti-aliased, so thin glyphs under-read; that is why this is
             advisory. It is skipped (and says so) when the PNG's aspect does not match the window, or the region is translucent.
Coordinates: layout frames are window points, origin top-left, the window including its title bar; the PNG scale is derived per
axis from the decoded size and the recorded window size.
"""
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
import argparse, json, os, re, struct, subprocess, sys, tempfile, zlib

root = Path(__file__).resolve().parent.parent
TOLERANCE = 0.5
# AppKit text fields, checkboxes and popups report a frame up to 2 pt larger per side than the alignment rect their stack or holder
# lays out (measured: status text 2 pt wider each side than its stack; the zoom popup 1 pt left of its holder). Frames of those
# controls are compared with their parent at this slack, and with the bar row / window at the strict 0.5 pt.
ALIGNMENT_SLACK = 2.0
MIN_HEIGHT = 640
CONTRAST_FLOOR = 4.5
SIGNATURE = b"\x89PNG\r\n\x1a\n"


# ---------------------------------------------------------------- PNG

class PNGError(Exception):
    pass


class Image:
    """A decoded PNG: width, height and rows of 8-bit RGBA bytes (4 per pixel)."""

    def __init__(self, width, height, rows, flat):
        self.width, self.height, self.rows, self.flat = width, height, rows, flat


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else b if pb <= pc else c


def unfilter(kind, raw, previous, bpp):
    if kind == 0:
        return raw
    out = bytearray(raw)
    n = len(raw)
    if kind == 1:
        for i in range(bpp, n):
            out[i] = (raw[i] + out[i - bpp]) & 255
    elif kind == 2:
        for i in range(n):
            out[i] = (raw[i] + previous[i]) & 255
    elif kind == 3:
        for i in range(n):
            left = out[i - bpp] if i >= bpp else 0
            out[i] = (raw[i] + ((left + previous[i]) >> 1)) & 255
    else:
        for i in range(n):
            left = out[i - bpp] if i >= bpp else 0
            upleft = previous[i - bpp] if i >= bpp else 0
            out[i] = (raw[i] + paeth(left, previous[i], upleft)) & 255
    return bytes(out)


def unpack_bits(row, depth, count):
    """Samples of a packed 1/2/4-bit scanline."""
    per = 8 // depth
    mask = (1 << depth) - 1
    return bytes((row[i // per] >> (8 - depth * (i % per + 1))) & mask for i in range(count))


def decode_png(data):
    """Image from PNG bytes; raises PNGError on anything malformed."""
    if data[:8] != SIGNATURE:
        raise PNGError("not a PNG (bad signature)")
    pos, chunks, seen_end = 8, [], False
    while pos < len(data):
        if pos + 12 > len(data):
            raise PNGError("truncated chunk header")
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if len(body) != length or pos + 12 + length > len(data):
            raise PNGError(f"truncated {kind.decode('latin1')} chunk")
        crc = struct.unpack(">I", data[pos + 8 + length:pos + 12 + length])[0]
        if zlib.crc32(kind + body) & 0xFFFFFFFF != crc:
            raise PNGError(f"CRC mismatch in {kind.decode('latin1')} chunk")
        chunks.append((kind, body))
        pos += 12 + length
        if kind == b"IEND":
            seen_end = True
            break
    if not chunks or chunks[0][0] != b"IHDR":
        raise PNGError("IHDR is not the first chunk")
    if not seen_end:
        raise PNGError("no IEND chunk")
    width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunks[0][1])
    if width == 0 or height == 0:
        raise PNGError("zero-size image")
    if compression or filtering:
        raise PNGError("unknown compression or filter method")
    if interlace:
        raise PNGError("interlaced PNGs are not supported by this checker")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color)
    if channels is None or depth not in {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8), 4: (8, 16), 6: (8, 16)}[color]:
        raise PNGError(f"unsupported colour type {color} at {depth} bits")
    palette = next((body for kind, body in chunks if kind == b"PLTE"), None)
    trns = next((body for kind, body in chunks if kind == b"tRNS"), b"")
    if color == 3 and palette is None:
        raise PNGError("palette image without PLTE")
    try:
        stream = zlib.decompress(b"".join(body for kind, body in chunks if kind == b"IDAT"))
    except zlib.error as error:
        raise PNGError(f"corrupt zlib stream: {error}")
    bits = channels * depth
    stride = (width * bits + 7) // 8
    bpp = max(1, bits // 8)
    if len(stream) != height * (stride + 1):
        raise PNGError(f"scanline data is {len(stream)} bytes, expected {height * (stride + 1)}")
    rows, previous = [], bytes(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind = stream[start]
        if kind > 4:
            raise PNGError(f"row {y} has filter type {kind}")
        previous = unfilter(kind, stream[start + 1:start + 1 + stride], previous, bpp)
        rows.append(previous)
    return Image(width, height, [to_rgba(row, width, depth, color, palette, trns) for row in rows], None)


def to_rgba(row, width, depth, color, palette, trns):
    if depth == 16:
        row = row[0::2]
        depth = 8
    if depth < 8:
        row = unpack_bits(row, depth, width)
        if color == 0:
            scale = 255 // ((1 << depth) - 1)
            row = bytes(v * scale for v in row)
    if color == 6:
        return bytes(row)
    out = bytearray(width * 4)
    if color == 2:
        out[0::4], out[1::4], out[2::4], out[3::4] = row[0::3], row[1::3], row[2::3], b"\xff" * width
    elif color == 0:
        out[0::4] = out[1::4] = out[2::4] = row[:width]
        out[3::4] = b"\xff" * width
    elif color == 4:
        out[0::4] = out[1::4] = out[2::4] = row[0::2]
        out[3::4] = row[1::2]
    else:
        entries = [(palette[3 * i], palette[3 * i + 1], palette[3 * i + 2], trns[i] if i < len(trns) else 255) for i in range(len(palette) // 3)]
        lookup = [entries[i] if i < len(entries) else (0, 0, 0, 255) for i in range(256)]
        for plane in range(4):
            out[plane::4] = bytes(lookup[i][plane] for i in row[:width])
    return bytes(out)


def is_flat(image):
    first = image.rows[0]
    return first == first[:4] * image.width and all(row == first for row in image.rows)


def foreign_fraction(image):
    """Share of pixels differing from the commonest pixel colour (a near-blank capture scores close to 0)."""
    counts = {}
    for row in image.rows:
        for pixel in zip(row[0::4], row[1::4], row[2::4]):
            counts[pixel] = counts.get(pixel, 0) + 1
    return 1 - max(counts.values()) / (image.width * image.height)


# ---------------------------------------------------------------- contrast

def channel(value):
    value /= 255
    return value / 12.92 if value <= 0.03928 else ((value + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    return 0.2126 * channel(rgb[0]) + 0.7152 * channel(rgb[1]) + 0.0722 * channel(rgb[2])


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def sample_contrast(image, box):
    """(ratio, text rgb, background rgb) for a pixel box (x0, y0, x1, y1), or (None, reason)."""
    x0, y0, x1, y1 = (max(0, int(box[0])), max(0, int(box[1])), min(image.width, int(box[2]) + 1), min(image.height, int(box[3]) + 1))
    if x1 - x0 < 3 or y1 - y0 < 3:
        return None, "region too small"
    pixels, alpha = [], 0
    for y in range(y0, y1):
        row = image.rows[y]
        for x in range(x0, x1):
            r, g, b, a = row[4 * x:4 * x + 4]
            pixels.append((r, g, b))
            alpha += a
    if alpha / len(pixels) < 250:
        return None, "region is translucent, background unknown"
    counts = {}
    for pixel in pixels:
        counts[pixel] = counts.get(pixel, 0) + 1
    background = max(counts, key=counts.get)
    distinct = sorted((p for p in pixels if p != background), key=lambda p: ratio(p, background), reverse=True)
    if len(distinct) < 3:
        return None, "no text-like pixels in the region"
    top = distinct[:max(3, len(distinct) // 10)]
    text = tuple(sum(p[i] for p in top) // len(top) for i in range(3))
    return ratio(text, background), text, background


# ---------------------------------------------------------------- layout

def rect(frame):
    return (frame[0], frame[1], frame[0] + frame[2], frame[1] + frame[3])


def inside(inner, outer, tolerance=TOLERANCE):
    return inner[0] >= outer[0] - tolerance and inner[1] >= outer[1] - tolerance and inner[2] <= outer[2] + tolerance and inner[3] <= outer[3] + tolerance


def overlap(a, b, tolerance=TOLERANCE):
    return a[0] < b[2] - tolerance and b[0] < a[2] - tolerance and a[1] < b[3] - tolerance and b[1] < a[3] - tolerance


def visible(node):
    return isinstance(node, dict) and isinstance(node.get("frame"), list) and len(node["frame"]) == 4 and not node.get("hidden")


def minimum_width():
    source = root / "Sources" / "ModernEditorChrome.swift"
    if source.is_file():
        found = re.search(r"minimumWindowWidth\s*(?::\s*CGFloat\s*)?=\s*([0-9.]+)", source.read_text(errors="replace"))
        if found:
            return float(found.group(1))
    return 980.0


def check_layout(layout, min_width):
    """[problem] for one layout JSON dict."""
    problems = []
    size = layout.get("windowSize")
    if not (isinstance(size, list) and len(size) == 2):
        return ["layout has no windowSize"]
    window = (0, 0, size[0], size[1])
    main_editor = "topBar" in layout
    if main_editor and (size[0] < min_width or size[1] < MIN_HEIGHT):
        problems.append(f"size: window {size[0]:g} x {size[1]:g} is below the minimum {min_width:g} x {MIN_HEIGHT}")
    for bar_name in ("topBar", "bottomBar"):
        bar = layout.get(bar_name)
        if not isinstance(bar, dict):
            continue
        row = bar.get("row")
        if visible(row) and not inside(rect(row["frame"]), window):
            problems.append(f"clip: {bar_name}.row {row['frame']} leaves the {size[0]:g} x {size[1]:g} window")
        bounds = rect(row["frame"]) if visible(row) else window
        placed, placed_groups = [], []
        for group_name, group in sorted((bar.get("groups") or {}).items()):
            if not visible(group):
                continue
            box = rect(group["frame"])
            if not inside(box, bounds):
                problems.append(f"clip: {bar_name}.{group_name} {group['frame']} leaves its row")
            placed.append((group_name, box))
            placed_groups.append((group_name, box))
            for index, control in enumerate(group.get("controls") or []):
                if visible(control) and not inside(rect(control["frame"]), box):
                    label = control.get("contentLabel") or control.get("content") or index
                    problems.append(f"clip: {bar_name}.{group_name}[{label}] {control['frame']} leaves its group {group['frame']}")
        checkbox_parent = None
        for key in ("statusRow", "status", "originalSizeCheckbox"):
            node = bar.get(key)
            if visible(node):
                box = rect(node["frame"])
                if not inside(box, bounds):
                    problems.append(f"clip: {bar_name}.{key} {node['frame']} leaves its row")
                if key == "originalSizeCheckbox":
                    # The Original size toggle is a glass choice on a footer plate: when its centre sits in a group it belongs to that group, must lie
                    # inside it, and may overlap it. Otherwise (the older checkbox beside the status text) it belongs to the status row.
                    centre = ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2)
                    checkbox_parent = next((name for name, group in placed_groups if group[0] <= centre[0] <= group[2] and group[1] <= centre[1] <= group[3]), None)
                    if checkbox_parent is not None and not inside(box, dict(placed_groups)[checkbox_parent], ALIGNMENT_SLACK):
                        problems.append(f"clip: {bar_name}.originalSizeCheckbox {node['frame']} leaves its group {checkbox_parent} by more than {ALIGNMENT_SLACK:g} pt")
                placed.append((key, box))
        status_row = bar.get("statusRow")
        if visible(status_row):
            for key in ("status", "originalSizeCheckbox"):
                node = bar.get(key)
                if key == "originalSizeCheckbox" and checkbox_parent is not None:
                    continue
                if visible(node) and not inside(rect(node["frame"]), rect(status_row["frame"]), ALIGNMENT_SLACK):
                    problems.append(f"clip: {bar_name}.{key} {node['frame']} leaves the status row {status_row['frame']} by more than {ALIGNMENT_SLACK:g} pt")
        popup = bar.get("zoomPopup")
        parent = None
        if visible(popup):
            box = rect(popup["frame"])
            if not inside(box, bounds):
                problems.append(f"clip: {bar_name}.zoomPopup {popup['frame']} leaves its row")
            centre = ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2)
            parent = next((name for name, group in placed_groups if group[0] <= centre[0] <= group[2] and group[1] <= centre[1] <= group[3]), None)
            if parent is None:
                problems.append(f"clip: {bar_name}.zoomPopup {popup['frame']} sits in none of the bar's groups")
            else:
                group_box = dict(placed_groups)[parent]
                if not inside(box, group_box, ALIGNMENT_SLACK):
                    problems.append(f"clip: {bar_name}.zoomPopup {popup['frame']} leaves its group {parent} by more than {ALIGNMENT_SLACK:g} pt")
            placed.append(("zoomPopup", box))
        for i, (first, a) in enumerate(placed):
            for second, b in placed[i + 1:]:
                # The status row is the parent of the status text and the checkbox, and the zoom popup lives inside its group.
                if "statusRow" in (first, second) and {first, second} <= {"statusRow", "status", "originalSizeCheckbox"}:
                    continue
                if "zoomPopup" in (first, second) and parent in (first, second):
                    continue
                if "originalSizeCheckbox" in (first, second) and checkbox_parent is not None and checkbox_parent in (first, second):
                    continue
                if overlap(a, b):
                    problems.append(f"clip: {bar_name}.{first} overlaps {bar_name}.{second}")
        if (bar.get("slack") or {}).get("overlaps"):
            problems.append(f"clip: {bar_name}.slack.overlaps is not empty: {bar['slack']['overlaps']}")
    viewport = layout.get("viewport")
    if isinstance(viewport, dict) and isinstance(viewport.get("rect"), list) and not inside(rect(viewport["rect"]), window):
        problems.append(f"clip: viewport.rect {viewport['rect']} leaves the window")
    hole = layout.get("frameHole")
    if isinstance(hole, dict) and hole.get("controlsOverlappingHole"):
        problems.append(f"clip: frameHole.controlsOverlappingHole is not empty: {hole['controlsOverlappingHole']}")
    if "rail" in layout:
        if layout["rail"] != "absent":
            problems.append(f"rail: rail is {layout['rail']!r}, expected 'absent'")
        checks = layout.get("railChecks") or {}
        if checks.get("retiredGroupsFound"):
            problems.append(f"rail: retired groups still present: {checks['retiredGroupsFound']}")
        if checks.get("trailingStrayViews"):
            problems.append(f"rail: stray views in the trailing margin: {checks['trailingStrayViews']}")
        if checks.get("trailingMarginIs12") is not True:
            problems.append("rail: railChecks.trailingMarginIs12 is not true")
        if isinstance(viewport, dict) and isinstance(viewport.get("rect"), list):
            trailing = size[0] - (viewport["rect"][0] + viewport["rect"][2])
            if abs(trailing - 12) > TOLERANCE:
                problems.append(f"rail: trailing margin measured from viewport.rect is {trailing:g}, expected 12 +/- {TOLERANCE}")
            if "trailingMargin" in viewport and abs(viewport["trailingMargin"] - 12) > TOLERANCE:
                problems.append(f"rail: viewport.trailingMargin is {viewport['trailingMargin']:g}, expected 12 +/- {TOLERANCE}")
        elif main_editor:
            problems.append("rail: no viewport.rect to measure the trailing margin from")
    elif main_editor:
        problems.append("rail: main-editor layout has no `rail` field")
    return problems


def contrast_targets(layout):
    """[(name, frame)] of text-bearing controls the layout records a frame for."""
    bar = layout.get("bottomBar") or {}
    targets = []
    status = bar.get("status")
    if visible(status) and layout.get("status"):
        targets.append(("status text", status["frame"]))
    popup = bar.get("zoomPopup")
    if visible(popup) and bar.get("zoomTitle"):
        targets.append(("zoom popup", popup["frame"]))
    checkbox = bar.get("originalSizeCheckbox")
    if visible(checkbox):
        targets.append(("Original size checkbox", checkbox["frame"]))
    return targets


def check_contrast(layout, image):
    """([advisory], [note]) from sampling the PNG under each recorded text frame."""
    size = layout.get("windowSize")
    if not size:
        return [], []
    sx, sy = image.width / size[0], image.height / size[1]
    if abs(sx - sy) / sx > 0.02:
        return [], [f"contrast skipped: PNG {image.width} x {image.height} does not match the {size[0]:g} x {size[1]:g} window aspect"]
    advisories, notes = [], []
    for name, frame in contrast_targets(layout):
        outcome = sample_contrast(image, (frame[0] * sx, frame[1] * sy, (frame[0] + frame[2]) * sx, (frame[1] + frame[3]) * sy))
        if outcome[0] is None:
            notes.append(f"contrast skipped for {name}: {outcome[1]}")
        elif outcome[0] < CONTRAST_FLOOR:
            advisories.append(f"contrast: {name} samples {outcome[0]:.2f}:1 (text {outcome[1]} on {outcome[2]}), below {CONTRAST_FLOOR}:1")
    return advisories, notes


# ---------------------------------------------------------------- text on a selected fill

SELECTED_MIN_BOX = (60, 30)      # px: a selected row, tile or segment is at least this big
SELECTED_MIN_CHROMA = 24         # an accent tint is saturated; the window, plates and greys are not
BACKDROP_SHADE_DISTANCE = 24    # L1 distance between neighbouring gradient bands after palette quantisation
SELECTED_MAX_LINE = 56           # px: a text line band is shorter than this (a preview image is not)


def selected_fill_regions(image):
    """[(x0, y0, x1, y1, fill rgb)] for each block of one saturated colour that is large enough to be a selected row, tile or segment."""
    counts = {}
    for row in image.rows:
        for pixel in zip(row[0::4], row[1::4], row[2::4]):
            if max(pixel) - min(pixel) >= SELECTED_MIN_CHROMA:
                counts[pixel] = counts.get(pixel, 0) + 1
    regions = []
    for fill, count in sorted(counts.items(), key=lambda item: -item[1])[:6]:
        if count < SELECTED_MIN_BOX[0] * SELECTED_MIN_BOX[1] // 2:
            break
        # A palette-quantised packed capture turns the smooth backdrop gradient into flat bands of near-identical colours; a selected
        # fill is one colour with no equally common neighbour shades, so a colour with two or more is the backdrop, not a selection.
        shades = sum(1 for other, n in counts.items() if other != fill and sum(abs(a - b) for a, b in zip(other, fill)) <= BACKDROP_SHADE_DISTANCE and n * 4 >= count)
        if shades >= 2:
            continue
        rows = []
        for y, row in enumerate(image.rows):
            run, best, start, bx = 0, 0, 0, 0
            for x in range(image.width):
                if tuple(row[4 * x:4 * x + 3]) == fill:
                    if run == 0:
                        start = x
                    run += 1
                    if run > best:
                        best, bx = run, start
                else:
                    run = 0
            rows.append((best, bx))
        y = 0
        while y < len(rows):
            if rows[y][0] < SELECTED_MIN_BOX[0]:
                y += 1
                continue
            top = y
            while y < len(rows) and rows[y][0] >= SELECTED_MIN_BOX[0] // 2:
                y += 1
            span = rows[top:y]
            x0 = min(bx for _, bx in span if _ >= SELECTED_MIN_BOX[0])
            x1 = max(bx + width for width, bx in span if width >= SELECTED_MIN_BOX[0])
            if y - top >= SELECTED_MIN_BOX[1] and not any(a[0] <= x0 and x1 <= a[2] and a[1] <= top and y <= a[3] for a in (r[:4] for r in regions)):
                regions.append((x0, top, x1, y, fill))
    return regions


def check_selected_text(image):
    """[problem] for every line of text on a selected fill below 4.5:1: the secondary label (S3-compatible, Exported) is the one that falls short.
    A band is a run of rows holding pixels that are not the fill; one taller than a text line (a preview image) is skipped."""
    problems = []
    for x0, y0, x1, y1, fill in selected_fill_regions(image):
        # A wide row keeps its trailing pill (Default) on the right, taller than a text line and beside both lines: read the label column only.
        inner = (x0 + 6, y0 + 3, x0 + 6 + min(x1 - x0 - 12, 400), y1 - 3)
        bands, start = [], None
        for y in range(inner[1], inner[3]):
            row = image.rows[y]
            ink = any(abs(row[4 * x] - fill[0]) + abs(row[4 * x + 1] - fill[1]) + abs(row[4 * x + 2] - fill[2]) > 24 for x in range(inner[0], inner[2]))
            if ink and start is None:
                start = y
            elif not ink and start is not None:
                bands.append((start, y))
                start = None
        if start is not None:
            bands.append((start, inner[3]))
        for top, bottom in bands:
            if not 8 <= bottom - top <= SELECTED_MAX_LINE:
                continue
            outcome = sample_contrast(image, (inner[0], top, inner[2], bottom))
            if outcome[0] is not None and outcome[0] < CONTRAST_FLOOR:
                problems.append(f"selected: text at y {top}-{bottom} on the selected fill rgb{fill} (block {x0},{y0}-{x1},{y1}) samples {outcome[0]:.2f}:1 (text {outcome[1]}), below {CONTRAST_FLOOR}:1")
    return problems


# ---------------------------------------------------------------- folder

def analyse(task):
    """Worker: (png path, layout path or None, min width) -> dict of problems, advisories and notes for that capture."""
    png, layout_path, min_width = task
    result = {"png": str(png), "problems": [], "advisories": [], "notes": [], "size": None}
    try:
        image = decode_png(Path(png).read_bytes())
    except (PNGError, OSError) as error:
        result["problems"].append(f"png: {error}")
        return result
    result["size"] = [image.width, image.height]
    if is_flat(image):
        result["problems"].append("png: the image is a single flat colour")
    else:
        share = foreign_fraction(image)
        if share < 0.001:
            result["notes"].append(f"near-blank: only {share:.4%} of pixels differ from the dominant colour")
    result["problems"] += check_selected_text(image)
    if layout_path:
        try:
            layout = json.loads(Path(layout_path).read_text())
        except (OSError, ValueError) as error:
            result["problems"].append(f"layout: unreadable JSON ({error})")
            return result
        result["problems"] += check_layout(layout, min_width)
        advisories, notes = check_contrast(layout, image)
        result["advisories"] += advisories
        result["notes"] += notes
    return result


def pair_layouts(folder):
    """({png path: layout path or None}, [layout paths with no PNG])"""
    pngs = sorted(folder.rglob("*.png"))
    layouts = {}
    for path in sorted(folder.rglob("*.json")):
        if path.parent.name == "layout" or path.parent.name.startswith("layout"):
            layouts.setdefault(path.stem, []).append(path)
    pairs, used = {}, set()
    for png in pngs:
        candidates = layouts.get(png.stem, [])
        near = [c for c in candidates if c.parent in (png.parent / "layout", png.parent, png.parent.parent / "layout")]
        chosen = (near or candidates or [None])[0]
        pairs[png] = chosen
        if chosen:
            used.add(chosen)
    orphans = [path for paths in layouts.values() for path in paths if path not in used]
    return pairs, orphans


def check_manifest(folder, results):
    """[problem] comparing a manifest.json beside the PNGs with what was decoded."""
    manifest_path = folder / "manifest.json"
    if not manifest_path.is_file():
        return []
    try:
        manifest = json.loads(manifest_path.read_text())
    except ValueError as error:
        return [f"manifest: unreadable JSON ({error})"]
    problems, listed = [], set()
    by_path = {Path(r["png"]).resolve(): r for r in results}
    for entry in manifest.get("captures", []):
        name = entry.get("file")
        if not name:
            continue
        candidates = [folder / name] + [p for p in by_path if p.name == Path(name).name]
        path = next((Path(c).resolve() for c in candidates if Path(c).is_file()), None)
        if path is None:
            problems.append(f"manifest: {name} is listed but missing")
            continue
        listed.add(path)
        result = by_path.get(path)
        want = entry.get("storedPixelSize") or entry.get("pixelSize")
        if result and result["size"] and want and result["size"] != list(want):
            problems.append(f"manifest: {name} decodes as {result['size']}, manifest says {list(want)}")
    if "captureCount" in manifest and manifest["captureCount"] != len(manifest.get("captures", [])):
        problems.append(f"manifest: captureCount {manifest['captureCount']} but {len(manifest.get('captures', []))} entries")
    for path in sorted(set(by_path) - listed):
        problems.append(f"manifest: {path.name} is on disk but not listed")
    return problems


MENU_GAP = "menu tracking returned before the capture timer fired"


def check_menu_gaps(folder):
    """[problem] one per menu capture the harness could not take and nothing explains (F-R-004).

    A gap is a record the harness wrote instead of a PNG (a raw run's gapsraw/*.json, or the gaps of a packed manifest.json). A menu gap
    is explained when the same capture exists in the folder (same id, appearance and icon mode, and the gap names its state: a re-run
    filled it) or when the record carries an `explained` note. A dropped menu capture otherwise looks like a pass in a count of PNGs.
    """
    gaps, captures = [], []
    manifest_path = folder / "manifest.json"
    if manifest_path.is_file():
        try:
            manifest = json.loads(manifest_path.read_text())
            gaps += manifest.get("gaps", [])
            captures += manifest.get("captures", [])
        except ValueError:
            pass
    for path in sorted(folder.glob("raw-*/gapsraw/*.json")) + sorted(folder.glob("gapsraw/*.json")):
        gaps += json.loads(path.read_text())
    for path in sorted(folder.glob("raw-*/meta/*.json")) + sorted(folder.glob("meta/*.json")):
        captures.append(json.loads(path.read_text()))
    problems = []
    for gap in gaps:
        if MENU_GAP not in str(gap.get("reason", "")) or gap.get("explained"):
            continue
        filled = any(c.get("id") == gap.get("id") and c.get("appearance") == gap.get("appearance") and c.get("iconMode", gap.get("iconMode")) == gap.get("iconMode")
                     and str(c.get("state", "")) and str(c.get("state", "")) in str(gap.get("surface", "")) for c in captures)
        if not filled:
            problems.append(f"gap: {gap.get('id')} {gap.get('appearance')} {gap.get('surface')}: the menu never opened and no capture or note explains it")
    return problems


# ---------------------------------------------------------------- glass choices

READABLE_MINIMUM = 18.0
GLASS_PANEL_PREFIX = "GlassChoicePanel."
# Required captures per glass surface (slug suffixes; the same strings are in Sources/EyeDumpAuditGlass.swift, and
# tools/test-eye-dump-audit-guard.py fails if the two drift). Every one is taken in light and dark and in each icon mode that ran.
GLASS_SURFACES = {
    "S50": ["toolbox-rest", "toolbox-hover", "toolbox-focus", "toolbox-disabled", "toolbox-chosen", "toolbox-dismissed"],
    "S51": ["zoom-rest", "zoom-hover", "zoom-focus", "zoom-chosen", "zoom-actual-size", "zoom-dismissed"],
    "S52": ["upload-rest", "upload-hover", "upload-focus", "upload-chosen", "upload-busy", "upload-empty", "upload-dismissed"],
    "S53": ["color-rest", "color-hover", "color-focus", "color-custom", "color-dismissed"],
    "S54": ["size-rest", "size-hover", "size-focus", "size-pressed", "size-dismissed"],
    "S55": ["history-category-rest", "history-category-hover", "history-category-focus",
            "history-date-rest", "history-date-hover", "history-date-focus", "history-date-chosen", "history-date-dismissed",
            "history-dragas-rest", "history-dragas-hover", "history-dragas-focus", "history-dragas-chosen", "history-dragas-dismissed"],
    "S56": ["settings-tabs-rest", "settings-tabs-hover", "settings-tabs-focus",
            "settings-radios-rest", "settings-radios-hover", "settings-radios-focus",
            "settings-toggles-rest", "settings-toggles-hover", "settings-toggles-focus",
            "settings-actions-rest", "settings-actions-hover", "settings-actions-focus", "settings-actions-disabled"],
    "S57": ["resize-groups-rest", "resize-groups-hover", "resize-groups-focus", "resize-anchor-rest", "resize-anchor-hover", "resize-anchor-focus",
            "resize-preset-rest", "resize-preset-hover", "resize-preset-focus", "resize-preset-chosen", "resize-preset-dismissed"],
    "S58": ["destination-protocol-rest", "destination-protocol-hover", "destination-protocol-focus", "destination-protocol-dismissed",
            "destination-source-rest", "destination-source-hover", "destination-source-focus", "destination-source-dismissed",
            "destination-acl-off", "destination-acl-on", "destination-width-640", "destination-width-560"],
    "S59": ["footer-original-on", "footer-original-off", "footer-original-hidden"],
    "S60": ["capture-enable-on", "capture-enable-off", "capture-modifiers-chosen", "capture-modifiers-disabled", "capture-clear-all",
            "capture-key-rest", "capture-key-focus", "capture-key-chosen", "capture-key-scroll", "capture-key-dismissed"],
}
GLASS_VARIANTS = ("rest", "hover", "focus", "chosen", "disabled", "dismissed", "busy", "pressed", "hidden", "scroll")
# The variant a capture's slug promises; the record must say the same and carry that variant's own proof.
SLUG_VARIANTS = {"enable-on": "chosen", "enable-off": "rest", "clear-all": "rest", "key-scroll": "scroll", "width-640": "rest", "width-560": "rest", "acl-off": "rest", "acl-on": "chosen", "original-off": "rest", "original-on": "chosen", "original-hidden": "hidden", "actual-size": "chosen", "custom": "chosen", "empty": "disabled", "busy": "busy", "pressed": "pressed"}


def promised_variant(slug):
    for suffix, variant in SLUG_VARIANTS.items():
        if slug.endswith("-" + suffix):
            return variant
    return slug.rsplit("-", 1)[-1]


def load_captures(folder):
    """[capture dict] with `_mode` (icon mode): raw runs' meta/*.json first, else the packed manifest's captures."""
    captures = []
    for path in sorted(folder.glob("raw-*/meta/*.json")):
        try:
            record = json.loads(path.read_text())
        except ValueError:
            continue
        record["_mode"] = path.parent.parent.name.removeprefix("raw-")
        captures.append(record)
    if not captures:
        manifest_path = folder / "manifest.json"
        if manifest_path.is_file():
            try:
                for record in json.loads(manifest_path.read_text()).get("captures", []):
                    record = dict(record)
                    record["_mode"] = record.get("iconMode", "sf")
                    captures.append(record)
            except ValueError:
                pass
    return captures


def toggle_problems(label, glass, rows, needle, want_on):
    """[problem] unless the row naming `needle` is among the rows and its chosen state is `want_on`."""
    toggle = next((i for i, title in enumerate(rows) if needle in str(title).lower()), None)
    if toggle is None:
        return [f"glass: {label} shows no {needle} toggle among its rows"]
    if (toggle in (glass.get("chosenIndexes") or [])) != want_on:
        return [f"glass: {label} {needle} toggle is {'off' if want_on else 'on'}, the capture is named for {'on' if want_on else 'off'}"]
    return []


PLACEMENT_TOLERANCE = 1.0


def placement_problems(label, glass):
    """[problem] when a panel is not where it belongs. Frames are screen rectangles [x, y, width, height] with a bottom-left origin.

    The product reports `containmentReported` ("parent": inside the on-screen part of the window it was opened from, "screenFallback": not), but it is
    not trusted: this decides on its own whether the panel FITS its parent, from the frames. A panel opening above or below its opener fits when it is no
    wider than the parent's visible part (`parentVisibleFrame`). When it fits it must lie horizontally inside that part (1 pt tolerance), must not reach
    into the parent's title bar (if it is no taller than the parent's content), and must not have been reported as a screen fallback. When it does not fit
    (wider than the visible parent, or the screen shows too little of the parent) it may not be reported as contained, is not failed for overhanging the
    parent, and must lie wholly inside the screen's visible frame. A panel beside its opener (clear of it horizontally and level with it) is exempt from the parent rule and must
    lie wholly on screen.
    """
    panel, parent, content, opener, visible_parent, screen = (glass.get(key) for key in (
        "panelFrame", "parentFrame", "parentContentFrame", "openerFrame", "parentVisibleFrame", "screenVisibleFrame"))
    reported = glass.get("containmentReported")

    def good(frame):
        return isinstance(frame, list) and len(frame) == 4 and all(isinstance(v, (int, float)) for v in frame)

    if not (good(panel) and good(parent)) or reported not in ("parent", "screenFallback"):
        return [f"glass: {label} records no panel frame, parent window frame and reported containment, so its placement was not checked"]
    problems = []
    tol = PLACEMENT_TOLERANCE
    p_left, p_right = panel[0], panel[0] + panel[2]
    p_bottom, p_top = panel[1], panel[1] + panel[3]

    def on_screen():
        if not good(screen):
            return [f"glass: {label} needs to lie on screen but records no screen visible frame"]
        s_left, s_right, s_bottom, s_top = screen[0], screen[0] + screen[2], screen[1], screen[1] + screen[3]
        if p_left < s_left - tol or p_right > s_right + tol or p_bottom < s_bottom - tol or p_top > s_top + tol:
            return [f"glass: {label} panel (x {p_left:g}..{p_right:g}, y {p_bottom:g}..{p_top:g}) is clipped by the screen's visible frame "
                    f"(x {s_left:g}..{s_right:g}, y {s_bottom:g}..{s_top:g})"]
        return []

    beside = False
    if good(opener):
        o_left, o_right, o_bottom, o_top = opener[0], opener[0] + opener[2], opener[1], opener[1] + opener[3]
        # Beside: clear of the opener horizontally and level with it (a panel below or above an opener may be offset sideways, but is not level with it).
        beside = (p_right <= o_left + 2 * tol or p_left >= o_right - 2 * tol) and p_bottom < o_top - tol and p_top > o_bottom + tol
    if beside:
        return on_screen()
    area = visible_parent if good(visible_parent) else parent
    a_left, a_right = area[0], area[0] + area[2]
    fits = panel[2] <= area[2] + tol
    if not fits:
        if reported == "parent":
            problems.append(f"glass: {label} is reported contained in its parent but is {panel[2]:g} pt wide, wider than the visible part of it ({area[2]:g} pt)")
        return problems + on_screen()
    if reported == "screenFallback":
        problems.append(f"glass: {label} reported a screen fallback but the panel ({panel[2]:g} pt) fits the visible part of its parent window ({area[2]:g} pt)")
    if p_left < a_left - tol or p_right > a_right + tol:
        out = max(a_left - p_left, p_right - a_right)
        problems.append(f"glass: {label} panel (x {p_left:g}..{p_right:g}) hangs {out:g} pt outside the visible part of its parent window (x {a_left:g}..{a_right:g}) "
                        "although it fits")
    if good(content) and good(opener):
        o_bottom, o_top = opener[1], opener[1] + opener[3]
        below = p_top <= o_bottom + 2 * tol
        above = p_bottom >= o_top - 2 * tol
        content_top, window_top = content[1] + content[3], parent[1] + parent[3]
        tall_fits = panel[3] <= content[3] + tol
        horizontal = p_left < parent[0] + parent[2] and p_right > parent[0]
        if (below or above) and tall_fits and horizontal and window_top - content_top > tol:
            if p_top > content_top + tol and p_bottom < window_top:
                problems.append(f"glass: {label} panel (y {p_bottom:g}..{p_top:g}) overlaps its parent's title bar (y {content_top:g}..{window_top:g})")
    return problems


def check_glass_record(label, record):
    """[problem] for one capture's `glassPanel` record (what the harness measured on the real panel or groups)."""
    glass = record.get("glassPanel")
    promised = promised_variant(str(record.get("slug", "")))
    if not isinstance(glass, dict):
        return [f"glass: {label} has no glassPanel record"]
    problems = []
    variant = glass.get("variant")
    rows = glass.get("rowTitles") or []
    if variant not in GLASS_VARIANTS:
        problems.append(f"glass: {label} variant {variant!r} is not one of {', '.join(GLASS_VARIANTS)}")
    elif variant != promised:
        problems.append(f"glass: {label} is named for a {promised} capture but records variant {variant!r}")
    if glass.get("kind") == "panel":
        if glass.get("glassContainerCount") != 1 and variant != "dismissed":
            problems.append(f"glass: {label} panel holds {glass.get('glassContainerCount')} glass containers, expected exactly 1")
        if variant != "dismissed" and not glass.get("plateCount"):
            problems.append(f"glass: {label} panel has no glass plate")
    if glass.get("kind") == "panel" and variant != "dismissed":
        problems += placement_problems(label, glass)
    if glass.get("nestedGlassCount") != 0:
        problems.append(f"glass: {label} has nested glass (nestedGlassCount {glass.get('nestedGlassCount')!r}, expected 0)")
    if variant not in ("dismissed", "hidden"):
        if not rows:
            problems.append(f"glass: {label} lists no choice rows")
        font = glass.get("minFontSize")
        if not isinstance(font, (int, float)):
            problems.append(f"glass: {label} recorded no minFontSize for its {len(rows)} row(s)")
        elif font < READABLE_MINIMUM:
            problems.append(f"glass: {label} has text at {font:g} pt, below the {READABLE_MINIMUM:g} pt floor")
    if variant not in ("dismissed", "hidden"):
        # No truncation: every GlassChoiceButton title and every pop-up face needs no more room (fittingSize) than the frame it was given, and the
        # harness's own verdict agrees. A record that has choices or faces and an empty (or short) metrics list measured nothing and fails.
        metrics = glass.get("labelMetrics")
        classes = glass.get("rowClasses") or []
        choices = sum(1 for name in classes if name == "GlassChoiceButton")
        faces = glass.get("faceTitles") or []
        if not isinstance(metrics, list):
            problems.append(f"glass: {label} recorded no labelMetrics, so truncation was not measured")
        else:
            titled = [m for m in metrics if m.get("kind") in ("choice title", None)]
            measured_faces = [m for m in metrics if m.get("kind") == "pop-up face"]
            if choices and len(titled) < choices:
                problems.append(f"glass: {label} has {choices} glass choice rows but only {len(titled)} title measurements")
            if faces and len(measured_faces) < len(faces):
                problems.append(f"glass: {label} shows {len(faces)} pop-up faces but only {len(measured_faces)} face measurements")
            for item in metrics:
                fitting, frame = item.get("fittingSize") or [0, 0], item.get("frameSize") or [0, 0]
                name = item.get("kind") or "label"
                if not (isinstance(fitting, list) and isinstance(frame, list) and len(fitting) == 2 and len(frame) == 2):
                    problems.append(f"glass: {label} {name} {item.get('title')!r} has unreadable metrics")
                elif fitting[0] > frame[0] + 0.5 or fitting[1] > frame[1] + 0.5 or item.get("fits") is not True:
                    problems.append(f"glass: {label} {name} {item.get('title')!r} is cut off (needs {fitting[0]:g} x {fitting[1]:g}, drawn in {frame[0]:g} x {frame[1]:g})")
        unmeasured = glass.get("unmeasuredText")
        if not isinstance(unmeasured, list) or not unmeasured:
            problems.append(f"glass: {label} does not list the text it leaves unmeasured, so the no-truncation claim is not bounded")
    if variant != "dismissed" and glass.get("truncatedRows"):
        problems.append(f"glass: {label} has choice titles cut off with an ellipsis: {glass['truncatedRows']}")
    if variant == "hover" and glass.get("hoveredRow") is None:
        problems.append(f"glass: {label} is a hover capture but no row is hovered")
    if variant == "focus" and glass.get("focusedRow") is None:
        problems.append(f"glass: {label} is a focus capture but no row has keyboard focus")
    if variant == "chosen" and not glass.get("chosenIndexes"):
        problems.append(f"glass: {label} is a chosen capture but no row is chosen")
    if variant == "disabled":
        if not glass.get("disabledRows"):
            problems.append(f"glass: {label} is a disabled capture but no row is disabled")
        if glass.get("disabledTookFocus") is not False:
            problems.append(f"glass: {label} a disabled row took (or was not proven not to take) keyboard focus")
    slug = str(record.get("slug", ""))
    if slug.endswith(("-acl-off", "-acl-on")):
        # The destination sheet's "Make uploads public-read" checkbox toggle, S3-compatible protocol selected: its chosen state is the proof.
        problems += toggle_problems(label, glass, rows, "public-read", slug.endswith("-acl-on"))
        if glass.get("protocol") != "S3":
            problems.append(f"glass: {label} was not taken with the S3-compatible protocol selected (protocol {glass.get('protocol')!r})")
    if slug.endswith(("-original-off", "-original-on")):
        # The footer's "Original size" toggle on a large shot: visible, and chosen or not as the capture says.
        problems += toggle_problems(label, glass, rows, "original size", slug.endswith("-original-on"))
        if glass.get("originalSizeVisible") is not True or glass.get("largeShot") is not True:
            problems.append(f"glass: {label} must show the Original size toggle on a large shot (visible {glass.get('originalSizeVisible')!r}, largeShot {glass.get('largeShot')!r})")
    if slug.endswith(("-width-640", "-width-560")):
        # The destination sheet at its normal and its minimum width, S3-compatible with the Keychain key source; its faces were measured too.
        expected = 560 if slug.endswith("-width-560") else 640
        # Neither the form nor the window around it may be narrower than the width asked for, nor wider than that plus a 20 pt scroller allowance.
        for what, key in (("form", "formWidth"), ("sheet window", "sheetWidth")):
            value = glass.get(key)
            if not isinstance(value, (int, float)) or not expected - 1 <= value <= expected + 20:
                problems.append(f"glass: {label} {what} is {value!r} pt wide, expected {expected} (plus at most a 20 pt scroller)")
        if glass.get("protocol") != "S3":
            problems.append(f"glass: {label} was not taken with the S3-compatible protocol (protocol {glass.get('protocol')!r})")
        faces = glass.get("faceTitles") or []
        if glass.get("sourceTitle") != "Access key stored in Keychain":
            problems.append(f"glass: {label} does not have the Keychain key source chosen (source {glass.get('sourceTitle')!r})")
        if len(faces) < 2 or not any(str(face).startswith("S3") for face in faces):
            problems.append(f"glass: {label} must show and measure the S3-compatible protocol face and the key source face (faces {faces})")
    if slug.endswith(("-enable-on", "-enable-off")):
        # Settings > Capture: the Enable global capture shortcuts toggle on and off.
        problems += toggle_problems(label, glass, rows, "enable global capture shortcuts", slug.endswith("-enable-on"))
    if slug.endswith("-modifiers-chosen"):
        chosen = glass.get("chosenIndexes") or []
        if len(rows) < 4 or not 1 <= len(chosen) < len(rows):
            problems.append(f"glass: {label} must show the modifier toggles with some, not none or all, chosen (rows {len(rows)}, chosen {chosen})")
    if slug.endswith("-modifiers-disabled"):
        if len(glass.get("disabledRows") or []) < 4:
            problems.append(f"glass: {label} must show all four modifier toggles disabled (disabled rows {glass.get('disabledRows')})")
    if slug.endswith("-clear-all") and not any("clear all" in str(title).lower() for title in rows):
        problems.append(f"glass: {label} shows no Clear All action among its rows")
    if slug.startswith("capture-key-") and variant != "dismissed":
        # The key panel's height cap: how many rows it has, how many are in view, and whether the host scrolls.
        total, visible = glass.get("totalRows"), glass.get("visibleRows")
        if not isinstance(total, int) or not isinstance(visible, int) or glass.get("hostScrolls") not in (True, False):
            problems.append(f"glass: {label} does not state its visible and total row counts and whether the host scrolls")
    if variant == "scroll":
        total, visible = glass.get("totalRowsAtScroll"), glass.get("visibleRowsAtScroll")
        if not isinstance(total, int) or not isinstance(visible, int) or total <= visible:
            problems.append(f"glass: {label} is a scroll capture but every row is in view, so nothing scrolled (total {total!r}, visible {visible!r})")
        if glass.get("hostScrollsAtScroll") is not True:
            problems.append(f"glass: {label} is a scroll capture but the host does not scroll")
        if glass.get("scrolledToEnd") is not True:
            problems.append(f"glass: {label} did not scroll to the last key")
    if slug == "capture-key-dismissed" and glass.get("firstResponderIsOpener") is not True:
        problems.append(f"glass: {label} the first responder after Escape is {glass.get('firstResponderIdentifier')!r}, not the key face")
    if slug.endswith("zoom-actual-size"):
        if glass.get("actualSizeOn") is not True or glass.get("faceTitleNow") != "Actual":
            problems.append(f"glass: {label} must show Actual Size on with the face reading Actual (on {glass.get('actualSizeOn')!r}, face {glass.get('faceTitleNow')!r})")
        if glass.get("zoomEnabledByApp") is None or (glass.get("zoomEnabledByApp") is False and glass.get("openedDirectly") is not True):
            problems.append(f"glass: {label} must state whether the app left the zoom pop-up enabled in Actual Size, and if not that the panel was presented directly")
        actual_row = next((i for i, title in enumerate(rows) if "actual size" in str(title).lower()), None)
        if actual_row is None or actual_row not in (glass.get("chosenIndexes") or []):
            problems.append(f"glass: {label} must show the Actual Size toggle row chosen (rows {rows}, chosen {glass.get('chosenIndexes')})")
    if variant == "hidden":
        if glass.get("originalSizeVisible") is not False:
            problems.append(f"glass: {label} is the reflow capture but the Original size toggle is still visible")
        if glass.get("uploadActive") is not True:
            problems.append(f"glass: {label} is the reflow capture but no upload state was active")
        if not isinstance(glass.get("windowWidth"), (int, float)) or glass["windowWidth"] > 980.5:
            problems.append(f"glass: {label} must be taken in the 980 pt window (windowWidth {glass.get('windowWidth')!r})")
    if variant == "busy" and "Cancel Upload" not in rows:
        problems.append(f"glass: {label} is a busy capture but offers no Cancel Upload row")
    if variant == "pressed" and glass.get("trackPressed") is not True:
        problems.append(f"glass: {label} is a pressed capture but the track was not pressed")
    if variant == "dismissed":
        if glass.get("panelGone") is not True:
            problems.append(f"glass: {label} the panel is still on screen after Escape")
        if glass.get("focusReturned") is not True:
            problems.append(f"glass: {label} focus did not return to the opener (first responder {glass.get('firstResponder')!r})")
        if glass.get("openerHadFocus") is not True:
            problems.append(f"glass: {label} the opener never had focus before the panel opened, so the return proves nothing")
    return problems


def requested_runs(folder):
    """[{mode, appearance, surfaces}] the run was asked for: tools/eye-dump-audit.sh's requested-surfaces.jsonl (one JSON record per
    harness launch, surfaces comma-separated), else the `requested` list a packed manifest.json carries."""
    runs = []
    path = folder / "requested-surfaces.jsonl"
    if path.is_file():
        for line in path.read_text().splitlines():
            if line.strip():
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                runs.append(record)
    elif (folder / "manifest.json").is_file():
        try:
            runs = json.loads((folder / "manifest.json").read_text()).get("requested", [])
        except ValueError:
            runs = []
    out = []
    for record in runs:
        surfaces = record.get("surfaces", [])
        if isinstance(surfaces, str):
            surfaces = [part.strip().upper() for part in surfaces.split(",") if part.strip()]
        out.append({"mode": record.get("mode", "sf"), "appearance": record.get("appearance"), "surfaces": surfaces})
    return out


def check_glass(folder):
    """[problem] for the glass-choice surfaces of a raw run or packed folder (see the module docstring)."""
    captures = load_captures(folder)
    glass_ids = set(GLASS_SURFACES)
    problems = []
    # What the run was asked to capture: its requested-surfaces.jsonl, else every glass surface that appears in it.
    wanted = set()
    for run in requested_runs(folder):
        for surface in run["surfaces"]:
            if surface in glass_ids:
                wanted.add((run["mode"], run["appearance"], surface))
    for record in captures:
        if record.get("id") in glass_ids:
            wanted.add((record["_mode"], record.get("appearance"), record["id"]))
    have = {(c["_mode"], c.get("appearance"), c.get("id"), c.get("slug")): c for c in captures}
    for mode, appearance, surface in sorted(wanted, key=str):
        for slug in GLASS_SURFACES[surface]:
            if (mode, appearance, surface, slug) not in have:
                problems.append(f"glass: {surface} {slug} was never captured ({appearance}, icons {mode})")
    for (mode, appearance, surface, slug), record in sorted(have.items(), key=str):
        if surface in glass_ids and slug in GLASS_SURFACES[surface]:
            problems += check_glass_record(f"{surface}/{slug} ({appearance}, icons {mode})", record)
    gaps = []
    manifest_path = folder / "manifest.json"
    if manifest_path.is_file():
        try:
            gaps += json.loads(manifest_path.read_text()).get("gaps", [])
        except ValueError:
            pass
    for path in sorted(folder.glob("raw-*/gapsraw/*.json")) + sorted(folder.glob("gapsraw/*.json")):
        try:
            gaps += json.loads(path.read_text())
        except ValueError:
            pass
    seen = set()
    for gap in gaps:
        key = (gap.get("id"), gap.get("appearance"), gap.get("surface"), gap.get("reason"))
        if gap.get("id") in glass_ids and not gap.get("explained") and key not in seen:
            seen.add(key)
            problems.append(f"glass: gap in {gap.get('id')} {gap.get('appearance')} {gap.get('surface')}: {gap.get('reason')}")
    return problems


OVERLAY_CLASSES = ("Popover", "GlassChoiceWindow")
PAINT_FLOOR = 0.05
PANEL_INK_FLOOR = 0.02


def overlay_problems(record):
    """Problems with one capture's claim to show a popover or a panel (F-S-popover, F-S10-blank). The claim comes from the capture's own slug;
    the proof comes from the harness's measurements: the popover window in the capture's window list AND painted into its pixels, or the
    export panel's image carrying real content. A record without the measurements fails, so the harness cannot stop recording them."""
    slug, windows = record.get("slug", ""), record.get("windows")
    if not slug or not isinstance(windows, list):
        return []
    label = f"{record.get('id', '?')}/{slug} ({record.get('appearance', '?')})"
    classes = [str(w.get("class", "")) for w in windows if isinstance(w, dict)]
    problems = []
    if "popover" in slug or "palette" in slug:
        is_overlay = lambda name: any(token in name for token in OVERLAY_CLASSES)
        if not classes or not any(is_overlay(name) for name in classes):
            problems.append(f"{label}: claims a popover but no popover window is in its window list {classes}")
        elif not is_overlay(classes[0]):
            painted = record.get("overlayPainted")
            if not isinstance(painted, list) or not painted:
                problems.append(f"{label}: a popover over its window with no overlayPainted measurement")
            elif min(float(item.get("paintedFraction", 0)) for item in painted if isinstance(item, dict)) < PAINT_FLOOR:
                problems.append(f"{label}: the popover window is listed but is not painted into the image (painted {painted})")
    if slug.startswith("export-panel"):
        wait = record.get("panelContentWait")
        if not isinstance(wait, dict) or not wait.get("reachedContent") or float(wait.get("inkFraction", 0)) < PANEL_INK_FLOOR:
            problems.append(f"{label}: claims the export panel but its image never carried content (panelContentWait {wait})")
        elif float(record.get("inkFraction", 0)) < PANEL_INK_FLOOR:
            problems.append(f"{label}: the export panel image is blank (inkFraction {record.get('inkFraction')})")
    return problems


def sheet_order_problems(record):
    """A capture whose slug names a sheet or the destination sheet must record its composite order (bottom to top) and every sheet in it must
    sit above its parent, with overlays above all plain windows. A sheet painted behind Settings shows as a sliver (F-R3-sheet-behind-parent)."""
    slug, windows = record.get("slug", ""), record.get("windows")
    if not slug or not isinstance(windows, list) or not ("sheet" in slug or "destination" in slug):
        return []
    label = f"{record.get('id', '?')}/{slug} ({record.get('appearance', '?')})"
    order = record.get("compositeOrder")
    if len(windows) < 2 and order is None:
        return []
    if not isinstance(order, list) or not order:
        return [f"{label}: names a sheet but records no compositeOrder, so its sheet-above-parent order is unproven"]
    position = {entry.get("window"): index for index, entry in enumerate(order) if isinstance(entry, dict)}
    problems = []
    for index, entry in enumerate(order):
        if not isinstance(entry, dict):
            continue
        parent = entry.get("sheetParent")
        if entry.get("isSheet") and parent in position and index < position[parent]:
            problems.append(f"{label}: sheet window {entry.get('window')} ({entry.get('class')}) is ordered below its parent {parent} in the composite {[e.get('class') for e in order]}")
    first_overlay = next((i for i, e in enumerate(order) if isinstance(e, dict) and e.get("isOverlay")), None)
    if first_overlay is not None and any(isinstance(e, dict) and not e.get("isOverlay") for e in order[first_overlay:]):
        problems.append(f"{label}: a plain window is painted over an overlay in the composite {[e.get('class') for e in order]}")
    return problems


def check_overlays(folder):
    problems = []
    for record in load_captures(folder):
        problems += overlay_problems(record)
        problems += sheet_order_problems(record)
    # S24: the status-item states are rendered, so each state and each appearance must be a different picture.
    seen = {}
    for path in sorted(folder.glob("raw-*/S24-*.png")) + sorted(folder.glob("S24-*.png")):
        seen[path.name] = path.read_bytes()
    groups = {}
    for name, data in seen.items():
        match = re.match(r"S24-statusitem-(normal|highlighted)-(light|dark)", name)
        if match:
            groups.setdefault(match.group(1), {})[match.group(2)] = data
            groups.setdefault(match.group(2), {})[match.group(1)] = data
    for key, pair in groups.items():
        if len(pair) == 2 and len(set(pair.values())) == 1:
            problems.append(f"S24: the two {'appearances' if key in ('normal', 'highlighted') else 'states'} of status item '{key}' are pixel-identical")
    return problems


def run(folder, jobs, strict, strict_contrast):
    folder = folder.resolve()
    pairs, orphans = pair_layouts(folder)
    if not pairs:
        print(f"check-eye-dump: no PNG files under {folder}", file=sys.stderr)
        return 2
    min_width = minimum_width()
    tasks = [(png, layout, min_width) for png, layout in pairs.items()]
    with ProcessPoolExecutor(max_workers=jobs) as pool:
        results = list(pool.map(analyse, tasks, chunksize=1))
    problems, advisories, notes = [], [], []
    for result in results:
        name = Path(result["png"]).name
        problems += [f"{name}: {p}" for p in result["problems"]]
        advisories += [f"{name}: {a}" for a in result["advisories"]]
        notes += [f"{name}: {n}" for n in result["notes"]]
    problems += check_manifest(folder, results)
    problems += check_menu_gaps(folder)
    problems += check_glass(folder)
    problems += check_overlays(folder)
    problems += [f"layout: {path.relative_to(folder)} has no PNG" for path in orphans]
    laid_out = sum(1 for layout in pairs.values() if layout)
    for line in problems:
        print("  FAIL " + line)
    for line in advisories:
        print("  ADVISORY " + line)
    skipped = sum(1 for n in notes if "skipped" in n)
    print(f"check-eye-dump: {len(pairs)} PNG(s), {laid_out} with a layout JSON, {len(problems)} failure(s), {len(advisories)} contrast advisor(y/ies)"
          + (f", {skipped} contrast sample(s) skipped" if skipped else "") + (f", {len(notes) - skipped} note(s)" if len(notes) > skipped else ""))
    if "-v" in sys.argv or "--verbose" in sys.argv:
        for line in notes:
            print("  note " + line)
    return 1 if problems or ((strict or strict_contrast) and advisories) else 0


# ---------------------------------------------------------------- self-test

def png_bytes(width, height, pixel_for, color=6):
    """A valid 8-bit RGBA (color=6) or RGB (color=2) PNG built from pixel_for(x, y) -> (r, g, b[, a]); filter 0, plus Sub/Up/Paeth rows for coverage."""
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    channels = 4 if color == 6 else 3
    raw, previous = bytearray(), bytes(width * channels)
    for y in range(height):
        row = bytes(v for x in range(width) for v in (tuple(pixel_for(x, y)) + (255,))[:channels])
        kind = y % 5 if y % 5 else 0
        if kind == 1:
            filtered = bytes((row[i] - (row[i - channels] if i >= channels else 0)) & 255 for i in range(len(row)))
        elif kind == 2:
            filtered = bytes((row[i] - previous[i]) & 255 for i in range(len(row)))
        elif kind == 3:
            filtered = bytes((row[i] - (((row[i - channels] if i >= channels else 0) + previous[i]) >> 1)) & 255 for i in range(len(row)))
        elif kind == 4:
            filtered = bytes((row[i] - paeth(row[i - channels] if i >= channels else 0, previous[i], previous[i - channels] if i >= channels else 0)) & 255 for i in range(len(row)))
        else:
            filtered = row
        raw += bytes([kind]) + filtered
        previous = row
    return SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b"")


def sample_layout(**overrides):
    layout = {
        "windowSize": [980, 640], "rail": "absent", "status": "Unsaved changes",
        "railChecks": {"retiredGroupsFound": [], "trailingMarginIs12": True, "trailingStrayViews": []},
        "viewport": {"rect": [12, 88, 956, 492], "trailingMargin": 12},
        "topBar": {"row": {"frame": [12, 36, 956, 44]}, "groups": {"A": {"frame": [12, 40, 102, 36], "controls": [{"frame": [12, 40, 48, 36]}, {"frame": [66, 40, 48, 36]}]}}},
        "bottomBar": {"row": {"frame": [12, 588, 956, 44]}, "groups": {"B": {"frame": [12, 592, 102, 36], "controls": [{"frame": [12, 592, 48, 36]}]}},
                      "statusRow": {"frame": [130, 596, 300, 28]}, "status": {"frame": [130, 599, 200, 21]},
                      "zoomPopup": {"frame": [14, 599, 79, 21]}, "zoomTitle": "100%"},
    }
    layout.update(overrides)
    return layout


def self_test():
    """The folder check must exit 0 on a sound capture and 1 on each seeded fault."""
    script = str(Path(__file__).resolve())

    def picture(x, y):
        return (240, 240, 240) if (x // 4 + y // 4) % 2 else (20, 20, 20)

    def mutate(layout, *path, value):
        node = layout
        for key in path[:-1]:
            node = node[key]
        node[path[-1]] = value
        return layout

    good = png_bytes(24, 20, picture)

    def selected_row(primary, secondary):
        """A selected row on a dark window: fill rgb(106,87,34), a primary line (y 16-28) and a secondary line (y 42-54) of stroke-like pixels."""
        def pixel(x, y):
            if 20 <= x < 220 and 10 <= y < 70:
                for top, colour in ((16, primary), (42, secondary)):
                    if top <= y < top + 12 and 30 <= x < 130 and (x // 2 + y // 2) % 2:
                        return colour
                return (106, 87, 34)
            return (30, 30, 30)
        return png_bytes(240, 80, pixel)

    def banded_backdrop():
        """A quantised purple gradient (flat bands 4 apart) with a grey document window over it: backdrop, not a selected fill."""
        def pixel(x, y):
            if 90 <= x < 200 and 20 <= y < 70 and (x // 2 + y // 2) % 2:
                return (150, 150, 150)
            band = x // 60
            return (70 + 4 * band, 50 + 2 * band, 78 + 3 * band)
        return png_bytes(240, 80, pixel)

    cases = [
        ("quantised gradient backdrop is not a selected fill", banded_backdrop(), None, 0),
        ("selected row, secondary text at 4.5:1 or better", selected_row((235, 232, 224), (235, 232, 224)), None, 0),
        ("selected row, secondary text at about 3.5:1 (the 0.34 dark fill regression)", selected_row((235, 232, 224), (160, 152, 135)), None, 1),
        ("selected row, primary text weak", selected_row((140, 132, 115), (235, 232, 224)), None, 1),
        ("sound capture", good, sample_layout(), 0),
        ("flat colour image", png_bytes(24, 20, lambda x, y: (200, 10, 10)), sample_layout(), 1),
        ("flat colour image, no layout", png_bytes(24, 20, lambda x, y: (200, 10, 10)), None, 1),
        ("corrupt CRC", good[:60] + bytes([good[60] ^ 0xFF]) + good[61:], None, 1),
        ("truncated file", good[:len(good) // 2], None, 1),
        ("not a PNG", b"GIF89a-not-a-png", None, 1),
        ("control leaves its group", good, mutate(sample_layout(), "topBar", "groups", "A", "controls", 1, "frame", value=[90, 40, 48, 36]), 1),
        ("group leaves its row", good, mutate(sample_layout(), "bottomBar", "groups", "B", "frame", value=[12, 592, 102, 60]), 1),
        ("row leaves the window", good, mutate(sample_layout(), "bottomBar", "row", "frame", value=[12, 620, 956, 44]), 1),
        ("clip just inside the 0.5 pt tolerance", good, mutate(sample_layout(), "topBar", "groups", "A", "controls", 1, "frame", value=[66.4, 40, 48, 36]), 0),
        ("clip just outside the 0.5 pt tolerance", good, mutate(sample_layout(), "topBar", "groups", "A", "controls", 1, "frame", value=[66.6, 40, 48, 36]), 1),
        ("hidden control is ignored", good, mutate(sample_layout(), "topBar", "groups", "A", "controls", 1, value={"frame": [900, 40, 48, 36], "hidden": True}), 0),
        ("zoom popup 1 pt past its group edge", good, mutate(sample_layout(), "bottomBar", "zoomPopup", "frame", value=[36, 599, 79, 21]), 0),
        ("zoom popup 3 pt past its group edge", good, mutate(sample_layout(), "bottomBar", "zoomPopup", "frame", value=[38, 599, 79, 21]), 1),
        ("zoom popup in no group", good, mutate(sample_layout(), "bottomBar", "zoomPopup", "frame", value=[400, 599, 79, 21]), 1),
        ("status 1.5 pt wider than its row", good, mutate(sample_layout(), "bottomBar", "status", "frame", value=[128.5, 599, 203, 21]), 0),
        ("status 3 pt wider than its row", good, mutate(sample_layout(), "bottomBar", "status", "frame", value=[127, 599, 200, 21]), 1),
        ("Original size toggle inside its footer plate", good, mutate(mutate(sample_layout(), "bottomBar", "originalSizeCheckbox", value={"frame": [450, 596, 100, 28]}), "bottomBar", "groups", "C", value={"frame": [440, 592, 150, 36]}), 0),
        ("Original size toggle straddling its footer plate", good, mutate(mutate(sample_layout(), "bottomBar", "originalSizeCheckbox", value={"frame": [520, 596, 100, 28]}), "bottomBar", "groups", "C", value={"frame": [440, 592, 150, 36]}), 1),
        ("Original size checkbox beside the status text, outside every group", good, mutate(sample_layout(), "bottomBar", "originalSizeCheckbox", value={"frame": [335, 599, 90, 21]}), 0),
        ("Original size checkbox past the status row, outside every group", good, mutate(sample_layout(), "bottomBar", "originalSizeCheckbox", value={"frame": [420, 599, 100, 21]}), 1),
        ("groups overlap", good, mutate(sample_layout(), "bottomBar", "statusRow", "frame", value=[100, 596, 300, 28]), 1),
        ("window narrower than 980", good, mutate(sample_layout(), "windowSize", value=[900, 640]), 1),
        ("window shorter than 640", good, mutate(sample_layout(), "windowSize", value=[980, 600]), 1),
        ("rail present", good, mutate(sample_layout(), "rail", value="present"), 1),
        ("rail trailing margin 16", good, mutate(sample_layout(), "viewport", "rect", value=[12, 88, 952, 492]), 1),
        ("rail trailing margin 12.4", good, mutate(sample_layout(), "viewport", "rect", value=[12, 88, 955.6, 492]), 0),
        ("rail boolean lies", good, mutate(sample_layout(), "railChecks", "trailingMarginIs12", value=False), 1),
        ("retired group found", good, mutate(sample_layout(), "railChecks", "retiredGroupsFound", value=["GlassRail"]), 1),
        ("no rail field, non-editor layout", good, {"windowSize": [300, 200]}, 0),
    ]
    failed = False
    with tempfile.TemporaryDirectory() as workdir:
        for label, data, layout, expected in cases:
            folder = Path(workdir) / re.sub(r"\W+", "-", label)
            (folder / "layout").mkdir(parents=True)
            (folder / "case.png").write_bytes(data)
            if layout is not None:
                (folder / "layout" / "case.json").write_text(json.dumps(layout))
            got = subprocess.run([sys.executable, script, str(folder), "--jobs", "1"], capture_output=True).returncode
            print(f"  self-test {label}: exit {got} (expected {expected})")
            failed |= got != expected
        # manifest faults
        folder = Path(workdir) / "manifest-good"
        folder.mkdir()
        (folder / "case.png").write_bytes(good)
        manifest = {"captureCount": 1, "captures": [{"file": "case.png", "storedPixelSize": [24, 20]}]}
        for label, edit, expected in [
            ("manifest agrees", lambda m: m, 0),
            ("manifest size disagrees", lambda m: m["captures"][0].update(storedPixelSize=[25, 20]) or m, 1),
            ("manifest lists a missing file", lambda m: m["captures"].append({"file": "gone.png"}) or m.update(captureCount=2) or m, 1),
            ("manifest omits a PNG", lambda m: m.update(captures=[]) or m.update(captureCount=0) or m, 1),
        ]:
            (folder / "manifest.json").write_text(json.dumps(edit(json.loads(json.dumps(manifest)))))
            got = subprocess.run([sys.executable, script, str(folder), "--jobs", "1"], capture_output=True).returncode
            print(f"  self-test {label}: exit {got} (expected {expected})")
            failed |= got != expected
        # menu gaps (F-R-004): a dropped menu capture fails the run unless a capture or a note explains it
        gap = {"id": "S42", "surface": "menus / Toolbox menu open", "appearance": "light", "iconMode": "sf", "reason": MENU_GAP + " (menu did not open), twice"}
        taken = {"id": "S42", "slug": "toolbox-menu-open", "state": "Toolbox menu open", "appearance": "light", "iconMode": "sf"}
        for label, gaps, captures, expected in [
            ("no gap", [], [], 0),
            ("unexplained menu gap", [gap], [], 1),
            ("menu gap filled by a re-run capture", [gap], [taken], 0),
            ("menu gap, the capture is another appearance", [gap], [dict(taken, appearance="dark")], 1),
            ("menu gap with an explained note", [dict(gap, explained="the sandbox refuses the pop-up here")], [], 0),
            ("a different gap is not this check's business", [dict(gap, reason="the sheet did not attach to its parent window")], [], 0),
        ]:
            folder = Path(workdir) / re.sub(r"\W+", "-", "gaps " + label)
            (folder / "raw-sf" / "gapsraw").mkdir(parents=True)
            (folder / "raw-sf" / "meta").mkdir()
            (folder / "case.png").write_bytes(good)
            (folder / "raw-sf" / "gapsraw" / "gaps.json").write_text(json.dumps(gaps))
            (folder / "raw-sf" / "meta" / "S42.json").write_text(json.dumps(captures[0] if captures else {}))
            got = subprocess.run([sys.executable, script, str(folder), "--jobs", "1"], capture_output=True).returncode
            print(f"  self-test {label}: exit {got} (expected {expected})")
            failed |= got != expected
        # popovers and panels: a capture that claims one must really contain it (S30/S31/S06 popover, S10 export panel, S24 distinct states)
        popover = {"id": "S30", "slug": "size-popover-w980", "appearance": "dark", "windows": [{"class": "NSWindow"}, {"class": "GlassChoiceWindow"}],
                   "overlayPainted": [{"class": "GlassChoiceWindow", "paintedFraction": 0.94}]}
        panel = {"id": "S10", "slug": "export-panel", "appearance": "light", "windows": [{"class": "NSSavePanel"}], "inkFraction": 0.07,
                 "panelContentWait": {"reachedContent": True, "inkFraction": 0.07}}
        for label, records, expected in [
            ("popover capture with the popover painted", [popover], 0),
            ("popover claimed but only the editor window listed", [dict(popover, windows=[{"class": "NSWindow"}], overlayPainted=None)], 1),
            ("popover listed but not painted into the pixels", [dict(popover, overlayPainted=[{"class": "GlassChoiceWindow", "paintedFraction": 0.0}])], 1),
            ("popover over its window without the paint measurement", [{k: v for k, v in popover.items() if k != "overlayPainted"}], 1),
            ("popover window shot alone", [dict(popover, slug="color-popover-only-w980", windows=[{"class": "GlassChoiceWindow"}], overlayPainted=None)], 0),
            ("export panel with content", [panel], 0),
            ("export panel that never reached content", [dict(panel, panelContentWait={"reachedContent": False, "inkFraction": 0.002}, inkFraction=0.002)], 1),
            ("export panel record without the wait", [{k: v for k, v in panel.items() if k != "panelContentWait"}], 1),
        ]:
            folder = Path(workdir) / re.sub(r"\W+", "-", "overlay " + label)
            (folder / "raw-sf" / "meta").mkdir(parents=True)
            (folder / "case.png").write_bytes(good)
            for index, record in enumerate(records):
                (folder / "raw-sf" / "meta" / f"{index}.json").write_text(json.dumps(record))
            got = subprocess.run([sys.executable, script, str(folder), "--jobs", "1"], capture_output=True).returncode
            print(f"  self-test {label}: exit {got} (expected {expected})")
            failed |= got != expected
        for label, same, expected in [("S24 states all different", False, 0), ("S24 light and dark pixel-identical", True, 1)]:
            folder = Path(workdir) / re.sub(r"\W+", "-", "s24 " + label)
            (folder / "raw-sf").mkdir(parents=True)
            (folder / "case.png").write_bytes(good)
            for state in ("normal", "highlighted"):
                for appearance in ("light", "dark"):
                    other = png_bytes(8, 8, lambda x, y, seed=(state, appearance): (10 if seed[0] == "normal" else 200, 10 if (seed[1] == "light" or same) else 120, 30 + 40 * ((x + y) % 2)))
                    (folder / "raw-sf" / f"S24-statusitem-{state}-{appearance}.png").write_bytes(other)
            got = subprocess.run([sys.executable, script, str(folder), "--jobs", "1"], capture_output=True).returncode
            print(f"  self-test {label}: exit {got} (expected {expected})")
            failed |= got != expected
        # glass choices (S50-S60): a run missing a required capture, or showing nested glass, small text or a panel that did not dismiss, fails
        def glass_record(surface, slug, appearance="light"):
            variant = promised_variant(slug)
            panel = {"kind": "panel", "variant": variant, "rowTitles": ["Alpha", "Beta", "Gamma"], "glassContainerCount": 1, "plateCount": 2,
                     "nestedGlassCount": 0, "minFontSize": 20.0, "faceTitles": [], "unmeasuredText": ["SegmentedToggle segments"],
                     # A contained panel under its opener: inside an 800 x 600 window whose title bar is the top 30 pt.
                     "panelFrame": [100, 100, 200, 300], "parentFrame": [0, 0, 800, 600], "parentContentFrame": [0, 0, 800, 570], "openerFrame": [90, 420, 60, 30],
                     "parentVisibleFrame": [0, 0, 800, 600], "screenVisibleFrame": [0, 0, 1440, 900], "containmentReported": "parent", "containmentDerived": "parent"}
            if variant == "hover":
                panel["hoveredRow"] = 1
            if variant == "focus":
                panel["focusedRow"] = 0
            if variant == "chosen":
                panel["chosenIndexes"] = [1]
            if variant == "disabled":
                panel.update(disabledRows=[2], disabledTookFocus=False)
            if variant == "busy":
                panel["rowTitles"] = ["Cancel Upload", "Alpha"]
            if variant == "pressed":
                panel["trackPressed"] = True
            if slug.endswith(("-acl-off", "-acl-on")):
                panel.update(rowTitles=["Make uploads public-read"], protocol="S3", chosenIndexes=[0] if slug.endswith("-acl-on") else [])
            if slug.endswith(("-enable-on", "-enable-off")):
                panel.update(rowTitles=["Enable global capture shortcuts"], chosenIndexes=[0] if slug.endswith("-on") else [])
            if slug.endswith("-modifiers-chosen"):
                panel.update(rowTitles=["\u2318", "\u2325", "\u2303", "\u21e7"], chosenIndexes=[1, 2])
            if slug.endswith("-modifiers-disabled"):
                panel.update(rowTitles=["\u2318", "\u2325", "\u2303", "\u21e7"], disabledRows=[0, 1, 2, 3], disabledTookFocus=False)
            if slug.endswith("-clear-all"):
                panel.update(rowTitles=["Clear All"])
            if slug.startswith("capture-key-") and variant != "dismissed":
                panel.update(totalRows=40, visibleRows=12, hostScrolls=True)
            if variant == "scroll":
                panel.update(totalRowsAtScroll=40, visibleRowsAtScroll=12, hostScrollsAtScroll=True, scrolledToEnd=True)
            if slug == "capture-key-dismissed":
                panel.update(firstResponderIsOpener=True, firstResponderIdentifier="GlobalHotkeyKey.screen")
            if slug.endswith("zoom-actual-size"):
                panel.update(actualSizeOn=True, faceShowsPercentage=False, faceTitleNow="Actual", zoomEnabledByApp=False, openedDirectly=True,
                             rowTitles=["100%", "Actual Size"], chosenIndexes=[1])
            if slug.endswith(("-width-640", "-width-560")):
                panel.update(protocol="S3", sheetWidth=560 if slug.endswith("-560") else 640, formWidth=560 if slug.endswith("-560") else 640, sourceTitle="Access key stored in Keychain", faceTitles=["S3-compatible", "Keychain"])
            if slug.endswith(("-original-off", "-original-on")):
                panel.update(rowTitles=["Original size"], chosenIndexes=[0] if slug.endswith("-original-on") else [], originalSizeVisible=True, largeShot=True)
            if variant == "hidden":
                panel.update(rowTitles=[], originalSizeVisible=False, uploadActive=True, windowWidth=980)
            if variant == "dismissed":
                panel.update(panelGone=True, focusReturned=True, openerHadFocus=True, rowTitles=[], plateCount=0, glassContainerCount=0)
            # One measured title per glass choice row, and one measured face per face title: what the harness records when it measured everything.
            panel["rowClasses"] = ["GlassChoiceButton"] * len(panel["rowTitles"])
            panel["labelMetrics"] = ([{"title": t, "kind": "choice title", "fittingSize": [60, 24], "frameSize": [80, 24], "textWidth": 60, "fits": True} for t in panel["rowTitles"]]
                                     + [{"title": t, "kind": "pop-up face", "fittingSize": [100, 24], "frameSize": [200, 24], "textWidth": 100, "fits": True} for t in panel["faceTitles"]])
            return {"id": surface, "slug": slug, "appearance": appearance, "iconMode": "sf", "state": "x", "glassPanel": panel}

        def glass_folder(label, edit=lambda records, gaps: None, surfaces=("S50",), appearances=("light",), requested=None):
            folder = Path(workdir) / re.sub(r"\W+", "-", "glass " + label)
            (folder / "raw-sf" / "meta").mkdir(parents=True)
            (folder / "raw-sf" / "gapsraw").mkdir()
            (folder / "case.png").write_bytes(good)
            records = {(a, sid, slug): glass_record(sid, slug, a) for a in appearances for sid in surfaces for slug in GLASS_SURFACES[sid]}
            gaps = []
            edit(records, gaps)
            for (a, sid, slug), record in records.items():
                (folder / "raw-sf" / "meta" / f"{sid}-{slug}-{a}.json").write_text(json.dumps(record))
            (folder / "raw-sf" / "gapsraw" / "gaps.json").write_text(json.dumps(gaps))
            if requested is not False:
                asked = requested or [{"mode": "sf", "appearance": a, "surfaces": ",".join(surfaces)} for a in appearances]
                (folder / "requested-surfaces.jsonl").write_text("\n".join(json.dumps(r) for r in asked) + "\n")
            return folder

        def drop(sid, slug, a="light"):
            return lambda records, gaps: records.pop((a, sid, slug))

        def tweak(sid, slug, **fields):
            return lambda records, gaps: records[("light", sid, slug)]["glassPanel"].update(fields)

        def drop_field(sid, slug, field):
            return lambda records, gaps: records[("light", sid, slug)]["glassPanel"].pop(field)

        def tweak_metric(sid, slug, index=0, **fields):
            return lambda records, gaps: records[("light", sid, slug)]["glassPanel"]["labelMetrics"][index].update(fields)

        for label, edit, kwargs, expected in [
            ("sound glass run", lambda r, g: None, {}, 0),
            ("sound glass run, light and dark", lambda r, g: None, {"appearances": ("light", "dark")}, 0),
            ("required capture missing", drop("S50", "toolbox-hover"), {}, 1),
            ("dismissal capture missing", drop("S50", "toolbox-dismissed"), {}, 1),
            ("dark twin missing", drop("S50", "toolbox-rest", "dark"), {"appearances": ("light", "dark")}, 1),
            ("requested surface captured nothing", lambda r, g: r.clear(), {}, 1),
            ("nested glass found", tweak("S50", "toolbox-rest", nestedGlassCount=1), {}, 1),
            ("nested glass count absent", drop_field("S50", "toolbox-rest", "nestedGlassCount"), {}, 1),
            ("text at 17 pt", tweak("S50", "toolbox-rest", minFontSize=17.0), {}, 1),
            ("text at exactly 18 pt", tweak("S50", "toolbox-rest", minFontSize=18.0), {}, 0),
            ("text size unrecorded", drop_field("S50", "toolbox-rest", "minFontSize"), {}, 1),
            ("two glass containers", tweak("S50", "toolbox-rest", glassContainerCount=2), {}, 1),
            ("a panel hanging off the right edge of its parent", tweak("S50", "toolbox-rest", panelFrame=[700, 100, 240, 300]), {}, 1),
            ("a panel hanging off the left edge of its parent", tweak("S50", "toolbox-rest", panelFrame=[-60, 100, 240, 300]), {}, 1),
            ("a panel contained in its parent", tweak("S50", "toolbox-rest", panelFrame=[560, 100, 240, 300]), {}, 0),
            ("a panel 1 pt past the parent edge (within tolerance)", tweak("S50", "toolbox-rest", panelFrame=[561, 100, 240, 300]), {}, 0),
            ("a panel 1.5 pt past the parent edge", tweak("S50", "toolbox-rest", panelFrame=[561.5, 100, 240, 300]), {}, 1),
            ("a genuinely oversized panel falls back and is fully on screen", tweak("S50", "toolbox-rest", panelFrame=[10, 100, 900, 300], containmentReported="screenFallback", containmentDerived="screenFallback"), {}, 0),
            ("a false fallback: it fits its parent, reports screenFallback and overhangs", tweak("S50", "toolbox-rest", panelFrame=[700, 100, 240, 300], containmentReported="screenFallback"), {}, 1),
            ("a false fallback: it fits and sits inside its parent yet reports screenFallback", tweak("S50", "toolbox-rest", panelFrame=[100, 100, 240, 300], containmentReported="screenFallback"), {}, 1),
            ("an oversized fallback panel clipped off the right of the screen", tweak("S50", "toolbox-rest", panelFrame=[700, 100, 900, 300], containmentReported="screenFallback"), {}, 1),
            ("an oversized fallback panel clipped off the top of the screen", tweak("S50", "toolbox-rest", panelFrame=[10, 700, 900, 300], containmentReported="screenFallback"), {}, 1),
            ("an oversized panel reported as contained", tweak("S50", "toolbox-rest", panelFrame=[10, 100, 900, 300]), {}, 1),
            ("a fallback panel without the screen frame", tweak("S50", "toolbox-rest", containmentReported="screenFallback", screenVisibleFrame=None, panelFrame=[10, 100, 900, 300]), {}, 1),
            ("a panel beside its opener, hanging off the parent but on screen", tweak("S50", "toolbox-rest", panelFrame=[790, 400, 240, 300], openerFrame=[700, 420, 60, 30], containmentReported="screenFallback"), {}, 0),
            ("a panel beside its opener, clipped off the screen", tweak("S50", "toolbox-rest", panelFrame=[1300, 400, 240, 300], openerFrame=[1210, 420, 60, 30], containmentReported="screenFallback"), {}, 1),
            ("a genuine fallback: the screen shows too little of the parent", tweak("S50", "toolbox-rest", parentFrame=[-600, 0, 800, 600], parentVisibleFrame=[0, 0, 200, 600], panelFrame=[0, 100, 240, 300], containmentReported="screenFallback"), {}, 0),
            ("the same narrow visible parent reported as contained", tweak("S50", "toolbox-rest", parentFrame=[-600, 0, 800, 600], parentVisibleFrame=[0, 0, 200, 600], panelFrame=[0, 100, 240, 300]), {}, 1),
            ("a containable panel in the visible part of a partly off-screen parent", tweak("S50", "toolbox-rest", parentFrame=[-300, 0, 800, 600], parentVisibleFrame=[0, 0, 500, 600], panelFrame=[260, 100, 240, 300]), {}, 0),
            ("a containable panel in the off-screen part of its parent", tweak("S50", "toolbox-rest", parentFrame=[-300, 0, 800, 600], parentVisibleFrame=[0, 0, 500, 600], panelFrame=[400, 100, 240, 300]), {}, 1),
            ("reported containment not recorded", drop_field("S50", "toolbox-rest", "containmentReported"), {}, 1),
            ("containment of an unknown kind", tweak("S50", "toolbox-rest", containmentReported="somewhere"), {}, 1),
            ("a panel above its opener reaching the title bar", tweak("S50", "toolbox-rest", panelFrame=[100, 340, 200, 260], openerFrame=[90, 300, 60, 30]), {}, 1),
            ("a panel above its opener staying below the title bar", tweak("S50", "toolbox-rest", panelFrame=[100, 340, 200, 200], openerFrame=[90, 300, 60, 30]), {}, 0),
            ("a panel taller than its parent is exempt from the title bar rule", tweak("S50", "toolbox-rest", panelFrame=[100, 0, 200, 620], openerFrame=[90, 300, 60, 30]), {}, 0),
            ("panel and parent frames not recorded", drop_field("S50", "toolbox-rest", "parentFrame"), {}, 1),
            ("a title needs more width than its label has", tweak_metric("S50", "toolbox-rest", fittingSize=[200, 24], frameSize=[120, 24], textWidth=200, fits=False), {}, 1),
            ("a title needs more height than its label has", tweak_metric("S50", "toolbox-rest", fittingSize=[60, 48], frameSize=[80, 24]), {}, 1),
            ("a title that fits exactly", tweak_metric("S50", "toolbox-rest", fittingSize=[80, 24], frameSize=[80, 24], textWidth=80), {}, 0),
            ("the harness says a title is cut though the sizes agree", tweak_metric("S50", "toolbox-rest", fits=False), {}, 1),
            ("labelMetrics not recorded", drop_field("S50", "toolbox-rest", "labelMetrics"), {}, 1),
            ("labelMetrics empty where glass choices were recorded", tweak("S50", "toolbox-rest", labelMetrics=[]), {}, 1),
            ("one title measurement short", lambda r, g: r[("light", "S50", "toolbox-rest")]["glassPanel"]["labelMetrics"].pop(), {}, 1),
            ("a custom pop-up face that clips", tweak_metric("S58", "destination-width-560", 4, fittingSize=[260, 24], frameSize=[220, 24], textWidth=260, fits=False), {"surfaces": ("S58",)}, 1),
            ("a custom pop-up face measured and fitting", tweak_metric("S58", "destination-width-560", 4, fittingSize=[220, 24], frameSize=[220, 24], textWidth=220), {"surfaces": ("S58",)}, 0),
            ("pop-up faces shown but not measured", lambda r, g: r[("light", "S58", "destination-width-560")]["glassPanel"].update(labelMetrics=[m for m in r[("light", "S58", "destination-width-560")]["glassPanel"]["labelMetrics"] if m["kind"] != "pop-up face"]), {"surfaces": ("S58",)}, 1),
            ("unmeasured text not listed", drop_field("S50", "toolbox-rest", "unmeasuredText"), {}, 1),
            ("unmeasured text list empty", tweak("S50", "toolbox-rest", unmeasuredText=[]), {}, 1),
            ("a choice title truncated", tweak("S50", "toolbox-rest", truncatedRows=["Export…"]), {}, 1),
            ("no truncated titles recorded", tweak("S50", "toolbox-rest", truncatedRows=[]), {}, 0),
            ("no choice rows", tweak("S50", "toolbox-rest", rowTitles=[]), {}, 1),
            ("hover names no row", tweak("S50", "toolbox-hover", hoveredRow=None), {}, 1),
            ("focus names no row", tweak("S50", "toolbox-focus", focusedRow=None), {}, 1),
            ("chosen has no chosen row", tweak("S50", "toolbox-chosen", chosenIndexes=[]), {}, 1),
            ("disabled capture with no disabled row", tweak("S50", "toolbox-disabled", disabledRows=[]), {}, 1),
            ("disabled row took focus", tweak("S50", "toolbox-disabled", disabledTookFocus=True), {}, 1),
            ("panel still on screen after Escape", tweak("S50", "toolbox-dismissed", panelGone=False), {}, 1),
            ("focus did not return to the opener", tweak("S50", "toolbox-dismissed", focusReturned=False), {}, 1),
            ("opener never had focus", tweak("S50", "toolbox-dismissed", openerHadFocus=False), {}, 1),
            ("slug and variant disagree", tweak("S50", "toolbox-hover", variant="rest"), {}, 1),
            ("busy capture without Cancel Upload", tweak("S52", "upload-busy", rowTitles=["Alpha"]), {"surfaces": ("S52",)}, 1),
            ("sound upload surface", lambda r, g: None, {"surfaces": ("S52",)}, 0),
            ("public-read on capture with the toggle off", tweak("S58", "destination-acl-on", chosenIndexes=[]), {"surfaces": ("S58",)}, 1),
            ("public-read off capture with the toggle on", tweak("S58", "destination-acl-off", chosenIndexes=[0]), {"surfaces": ("S58",)}, 1),
            ("public-read toggle missing", tweak("S58", "destination-acl-on", rowTitles=["Something else"]), {"surfaces": ("S58",)}, 1),
            ("public-read capture on another protocol", tweak("S58", "destination-acl-on", protocol="SFTP"), {"surfaces": ("S58",)}, 1),
            ("Original size on capture with the toggle off", tweak("S59", "footer-original-on", chosenIndexes=[]), {"surfaces": ("S59",)}, 1),
            ("Original size off capture with the toggle on", tweak("S59", "footer-original-off", chosenIndexes=[0]), {"surfaces": ("S59",)}, 1),
            ("Original size toggle not visible on a large shot", tweak("S59", "footer-original-on", originalSizeVisible=False), {"surfaces": ("S59",)}, 1),
            ("Original size capture not on a large shot", tweak("S59", "footer-original-off", largeShot=False), {"surfaces": ("S59",)}, 1),
            ("Original size reflow capture still shows the toggle", tweak("S59", "footer-original-hidden", originalSizeVisible=True), {"surfaces": ("S59",)}, 1),
            ("Original size reflow capture with no upload active", tweak("S59", "footer-original-hidden", uploadActive=False), {"surfaces": ("S59",)}, 1),
            ("Original size reflow capture in a wide window", tweak("S59", "footer-original-hidden", windowWidth=1280), {"surfaces": ("S59",)}, 1),
            ("sound footer Original size surface", lambda r, g: None, {"surfaces": ("S59",)}, 0),
            ("Enable toggle on capture with the toggle off", tweak("S60", "capture-enable-on", chosenIndexes=[]), {"surfaces": ("S60",)}, 1),
            ("Enable toggle off capture with the toggle on", tweak("S60", "capture-enable-off", chosenIndexes=[0]), {"surfaces": ("S60",)}, 1),
            ("modifier plate with none chosen", tweak("S60", "capture-modifiers-chosen", chosenIndexes=[]), {"surfaces": ("S60",)}, 1),
            ("modifier plate with all chosen", tweak("S60", "capture-modifiers-chosen", chosenIndexes=[0, 1, 2, 3]), {"surfaces": ("S60",)}, 1),
            ("modifiers disabled capture with one still enabled", tweak("S60", "capture-modifiers-disabled", disabledRows=[0, 1, 2]), {"surfaces": ("S60",)}, 1),
            ("Clear All plate without Clear All", tweak("S60", "capture-clear-all", rowTitles=["Remove"]), {"surfaces": ("S60",)}, 1),
            ("key panel without row counts", drop_field("S60", "capture-key-rest", "totalRows"), {"surfaces": ("S60",)}, 1),
            ("key panel without host scroll flag", drop_field("S60", "capture-key-focus", "hostScrolls"), {"surfaces": ("S60",)}, 1),
            ("scroll capture where every row is in view", tweak("S60", "capture-key-scroll", visibleRowsAtScroll=40), {"surfaces": ("S60",)}, 1),
            ("scroll capture where the host does not scroll", tweak("S60", "capture-key-scroll", hostScrollsAtScroll=False), {"surfaces": ("S60",)}, 1),
            ("scroll capture that never reached the last key", tweak("S60", "capture-key-scroll", scrolledToEnd=False), {"surfaces": ("S60",)}, 1),
            ("focus not back on the key face", tweak("S60", "capture-key-dismissed", firstResponderIsOpener=False), {"surfaces": ("S60",)}, 1),
            ("sound Capture tab surface", lambda r, g: None, {"surfaces": ("S60",)}, 0),
            ("Actual Size capture with the face not reading Actual", tweak("S51", "zoom-actual-size", faceTitleNow="100%"), {"surfaces": ("S51",)}, 1),
            ("Actual Size capture with Actual Size off", tweak("S51", "zoom-actual-size", actualSizeOn=False), {"surfaces": ("S51",)}, 1),
            ("Actual Size capture without saying whether the zoom was enabled", drop_field("S51", "zoom-actual-size", "zoomEnabledByApp"), {"surfaces": ("S51",)}, 1),
            ("Actual Size capture opened without saying it was presented directly", tweak("S51", "zoom-actual-size", openedDirectly=False), {"surfaces": ("S51",)}, 1),
            ("Actual Size capture with the Actual Size row not chosen", tweak("S51", "zoom-actual-size", chosenIndexes=[0]), {"surfaces": ("S51",)}, 1),
            ("sound Zoom surface", lambda r, g: None, {"surfaces": ("S51",)}, 0),
            ("sound destination surface", lambda r, g: None, {"surfaces": ("S58",)}, 0),
            ("pressed capture, track not pressed", tweak("S54", "size-pressed", trackPressed=False), {"surfaces": ("S54",)}, 1),
            ("glass record missing", lambda r, g: r[("light", "S50", "toolbox-rest")].pop("glassPanel"), {}, 1),
            ("glass gap (the panel never appeared)", lambda r, g: g.append({"id": "S50", "appearance": "light", "surface": "Toolbox", "reason": "panel did not appear"}), {}, 1),
            ("glass gap with an explained note", lambda r, g: g.append({"id": "S50", "appearance": "light", "surface": "Toolbox", "reason": "x", "explained": "n/a"}), {}, 0),
            ("a non-glass gap is not this check's business", lambda r, g: g.append({"id": "S09", "appearance": "light", "surface": "footer", "reason": "x"}), {}, 0),
        ]:
            folder = glass_folder(label, edit, **kwargs)
            outcome = subprocess.run([sys.executable, script, str(folder), "--jobs", "1"], capture_output=True, text=True)
            got = outcome.returncode
            # A seeded fault must fail for the glass reason, not because some other check tripped over the fixture.
            named = expected == 0 or "FAIL glass" in outcome.stdout or "FAIL case.png: glass" in outcome.stdout
            print(f"  self-test glass: {label}: exit {got} (expected {expected}){'' if named else ' -- but not for a glass reason'}")
            failed |= got != expected or not named
        # Without a requested-surfaces.jsonl the surfaces seen decide: S50 alone needs only S50, but an S50 with a hole in it still fails.
        folder = glass_folder("no request file, complete", requested=False)
        got = subprocess.run([sys.executable, script, str(folder), "--jobs", "1"], capture_output=True).returncode
        print(f"  self-test glass: no request file, complete: exit {got} (expected 0)")
        failed |= got != 0
        folder = glass_folder("no request file, hole", drop("S50", "toolbox-focus"), requested=False)
        got = subprocess.run([sys.executable, script, str(folder), "--jobs", "1"], capture_output=True).returncode
        print(f"  self-test glass: no request file, hole: exit {got} (expected 1)")
        failed |= got != 1
        # sheet order: a sheet painted below its parent, or a plain window over an overlay, fails; the right order and an unrelated slug pass
        def entry(number, kind, **more):
            return {"window": number, "class": kind, "title": "", "isOverlay": kind == "GlassChoiceWindow", "isSheet": "parent" in more and kind == "Sheet",
                    **({"sheetParent": more["parent"]} if "parent" in more else {})}
        sheet_cases = [
            ("sheet above its parent", "destination-protocol-rest", [entry(1, "Window"), entry(2, "Sheet", parent=1)], 0),
            ("sheet below its parent", "destination-protocol-rest", [entry(2, "Sheet", parent=1), entry(1, "Window")], 1),
            ("destination sheet below Settings, panel on top", "destination-source-focus", [entry(2, "Sheet", parent=1), entry(1, "Window"), entry(3, "GlassChoiceWindow")], 1),
            ("sheet, parent, then panel", "destination-source-focus", [entry(1, "Window"), entry(2, "Sheet", parent=1), entry(3, "GlassChoiceWindow")], 0),
            ("plain window over the panel", "destination-source-focus", [entry(3, "GlassChoiceWindow"), entry(1, "Window"), entry(2, "Sheet", parent=1)], 1),
            ("sheet slug with no composite order", "destination-width-640", None, 1),
            ("below-parent order on a non-sheet slug is out of scope", "toolbox-rest", [entry(2, "Sheet", parent=1), entry(1, "Window")], 0),
        ]
        for label, slug, order, expected in sheet_cases:
            folder = Path(workdir) / re.sub(r"\W+", "-", "sheet-" + label)
            (folder / "raw-sf" / "meta").mkdir(parents=True)
            (folder / "case.png").write_bytes(good)
            record = {"id": "S99", "slug": slug, "appearance": "light", "windows": [{"class": "Window"}, {"class": "Sheet"}]}
            if order is not None:
                record["compositeOrder"] = order
            (folder / "raw-sf" / "meta" / "case.json").write_text(json.dumps(record))
            run = subprocess.run([sys.executable, script, str(folder), "--jobs", "1"], capture_output=True, text=True)
            named = expected == 0 or "sheet" in run.stdout.lower() or "overlay" in run.stdout.lower()
            print(f"  self-test sheet order: {label}: exit {run.returncode} (expected {expected}){'' if named else ' -- but not for a sheet-order reason'}")
            failed |= run.returncode != expected or not named
        # contrast: advisory by default, fatal under --strict
        low = png_bytes(64, 48, lambda x, y: (128, 128, 128) if (x + y) % 7 else (140, 140, 140))
        weak = sample_layout(windowSize=[64, 48])
        weak["bottomBar"] = {"row": {"frame": [0, 0, 64, 48]}, "status": {"frame": [2, 2, 60, 44]}, "groups": {}}
        weak["viewport"] = {"rect": [0, 0, 52, 48], "trailingMargin": 12}
        weak.pop("topBar")
        folder = Path(workdir) / "contrast"
        (folder / "layout").mkdir(parents=True)
        (folder / "case.png").write_bytes(low)
        (folder / "layout" / "case.json").write_text(json.dumps(weak))
        high = png_bytes(64, 48, lambda x, y: (250, 250, 250) if (x + y) % 7 else (15, 15, 15))
        (folder / "high.png").write_bytes(high)
        (folder / "layout" / "high.json").write_text(json.dumps(weak))
        (folder / "case.png").rename(folder / "case-low.png")
        (folder / "layout" / "case.json").rename(folder / "layout" / "case-low.json")
        for label, flags, expected in [("low and high contrast together are advisory", [], 0), ("low contrast fails under --strict", ["--strict"], 1)]:
            got = subprocess.run([sys.executable, script, str(folder), "--jobs", "1", *flags], capture_output=True).returncode
            print(f"  self-test {label}: exit {got} (expected {expected})")
            failed |= got != expected
        (folder / "case-low.png").unlink()
        (folder / "layout" / "case-low.json").unlink()
        got = subprocess.run([sys.executable, script, str(folder), "--jobs", "1", "--strict"], capture_output=True).returncode
        print(f"  self-test high contrast passes --strict: exit {got} (expected 0)")
        failed |= got != 0
    ink = ratio((0, 0, 0), (255, 255, 255))
    print(f"  self-test black on white ratio {ink:.1f}:1 (expected 21.0)")
    failed |= abs(ink - 21) > 0.01
    if failed:
        raise SystemExit("FAIL check-eye-dump self-test")
    print("PASS check-eye-dump self-test")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folder", nargs="?", type=Path)
    parser.add_argument("--strict", action="store_true", help="also exit 1 on contrast advisories")
    parser.add_argument("--strict-contrast", action="store_true", help="same as --strict for contrast (kept explicit for wiring)")
    parser.add_argument("--self-test", action="store_true", help="prove the checks can fail")
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("-v", "--verbose", action="store_true", help="print notes (skipped contrast samples, near-blank images)")
    options = parser.parse_args()
    if options.self_test:
        self_test()
        return 0
    if not options.folder:
        parser.error("a harness output folder is required")
    return run(options.folder, options.jobs, options.strict, options.strict_contrast)


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    raise SystemExit(main())
