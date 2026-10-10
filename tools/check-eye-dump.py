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
        for key in ("statusRow", "status", "originalSizeCheckbox"):
            node = bar.get(key)
            if visible(node):
                box = rect(node["frame"])
                if not inside(box, bounds):
                    problems.append(f"clip: {bar_name}.{key} {node['frame']} leaves its row")
                placed.append((key, box))
        status_row = bar.get("statusRow")
        if visible(status_row):
            for key in ("status", "originalSizeCheckbox"):
                node = bar.get(key)
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
    cases = [
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
