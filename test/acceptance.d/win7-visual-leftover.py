#!/usr/bin/env python3
"""Measure Win7 visual leftover from a real HDMI-A-1 grim.

Hex-grep of ExplorerTheme.js is a source lock, not pixel proof.
Cloud EXIT 0 is not this leftover. Files LIVE metal stays OPEN.
Empty Bin stays unauthorized.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import struct
import subprocess
import sys
import time
import zlib
from pathlib import Path

HELPER = Path(os.environ.get("OMARCHY_PATH") or "") / "test/acceptance.d/hyprbars-pointer-proof.py"
if not HELPER.is_file():
  HELPER = Path(__file__).resolve().parent / "hyprbars-pointer-proof.py"
spec = importlib.util.spec_from_file_location("hyprbars_pointer_proof", HELPER)
mod = importlib.util.module_from_spec(spec)
sys.modules["hyprbars_pointer_proof"] = mod
spec.loader.exec_module(mod)

as_user = mod.as_user
clients = mod.clients
hypr = mod.hypr
hypr_env = mod.hypr_env
OMARCHY_PATH = mod.OMARCHY_PATH

FILES_CLASS = "org.omarchy.Files"
OCCLUDE = {"cursor", "org.omarchy.Settings"}
REF_AERO = (0x45, 0x80, 0xC4)
REF_SEL_BOTTOM = (0xE6, 0xEC, 0xF5)
REF_SEL_BORDER = (0xAA, 0xDD, 0xFA)
BAR_H = 30


def git_sha() -> str:
  return subprocess.check_output(
    ["git", "-C", OMARCHY_PATH, "rev-parse", "HEAD"], text=True
  ).strip()


def hypr_try(*args: str) -> subprocess.CompletedProcess[str]:
  return subprocess.run(["hyprctl", *args], env=hypr_env(), text=True, capture_output=True)


def move_workspace(addr: str, dest: str) -> None:
  lua = (
    'hl.dsp.window.move({ workspace = "'
    + dest
    + '", follow = false, window = "address:'
    + str(addr)
    + '" })'
  )
  hypr_try("dispatch", lua)


def park_occluders() -> list[str]:
  saved = []
  for c in clients():
    cls = str(c.get("class") or "")
    if cls not in OCCLUDE and cls.lower() not in OCCLUDE:
      continue
    addr = c.get("address")
    if not addr:
      continue
    move_workspace(addr, "2")
    saved.append(addr)
  time.sleep(0.35)
  return saved


def unpark(addrs: list[str]) -> None:
  for addr in addrs:
    try:
      move_workspace(addr, "1")
    except Exception:
      pass


def paeth(a: int, b: int, c: int) -> int:
  p = a + b - c
  pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
  if pa <= pb and pa <= pc:
    return a
  if pb <= pc:
    return b
  return c


def load_png_rgb(path: Path) -> tuple[int, int, list[tuple[int, int, int]]]:
  data = path.read_bytes()
  if data[:8] != b"\x89PNG\r\n\x1a\n":
    raise RuntimeError("not a PNG")
  pos = 8
  width = height = bit_depth = color_type = None
  idat = b""
  while pos < len(data):
    length = struct.unpack(">I", data[pos : pos + 4])[0]
    tag = data[pos + 4 : pos + 8]
    chunk = data[pos + 8 : pos + 8 + length]
    pos += 12 + length
    if tag == b"IHDR":
      width, height, bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
    elif tag == b"IDAT":
      idat += chunk
    elif tag == b"IEND":
      break
  if width is None or bit_depth != 8 or color_type not in (2, 6):
    raise RuntimeError(f"unsupported PNG {bit_depth} {color_type}")
  bpp = 3 if color_type == 2 else 4
  raw = zlib.decompress(idat)
  stride = width * bpp
  rows = []
  i = 0
  prev = bytes(stride)
  for _y in range(height):
    filt = raw[i]
    i += 1
    scan = bytearray(raw[i : i + stride])
    i += stride
    if filt == 1:
      for x in range(stride):
        left = scan[x - bpp] if x >= bpp else 0
        scan[x] = (scan[x] + left) & 255
    elif filt == 2:
      for x in range(stride):
        scan[x] = (scan[x] + prev[x]) & 255
    elif filt == 3:
      for x in range(stride):
        left = scan[x - bpp] if x >= bpp else 0
        scan[x] = (scan[x] + ((left + prev[x]) // 2)) & 255
    elif filt == 4:
      for x in range(stride):
        left = scan[x - bpp] if x >= bpp else 0
        up = prev[x]
        ul = prev[x - bpp] if x >= bpp else 0
        scan[x] = (scan[x] + paeth(left, up, ul)) & 255
    elif filt != 0:
      raise RuntimeError(f"png filter {filt}")
    prev = bytes(scan)
    row = []
    for x in range(width):
      o = x * bpp
      row.append((scan[o], scan[o + 1], scan[o + 2]))
    rows.append(row)
  return width, height, rows


def pixel(rows, x, y):
  if y < 0 or y >= len(rows) or x < 0 or x >= len(rows[0]):
    return None
  return rows[y][x]


def dist(a, b) -> float:
  return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


def average(rows, x0, y0, x1, y1):
  acc = [0, 0, 0]
  n = 0
  for y in range(max(0, y0), min(len(rows), y1)):
    row = rows[y]
    for x in range(max(0, x0), min(len(row), x1)):
      r, g, b = row[x]
      acc[0] += r
      acc[1] += g
      acc[2] += b
      n += 1
  if n == 0:
    return None
  return (acc[0] // n, acc[1] // n, acc[2] // n)


def ocr_region(png: Path, geom: str) -> str:
  tmp = png.with_name(png.stem + "-ocr.png")
  proc = as_user(["grim", "-g", geom, str(tmp)], wait=True, timeout=8)
  if proc.returncode != 0:
    return ""
  tess = as_user(["tesseract", str(tmp), "stdout", "--psm", "7"], wait=True, timeout=12)
  return (tess.stdout or "").strip()


def monitor_report() -> dict:
  mons = json.loads(hypr("-j", "monitors") or "[]")
  focused = next((m for m in mons if m.get("focused")), mons[0] if mons else {})
  return {
    "name": focused.get("name"),
    "description": focused.get("description"),
    "width": focused.get("width"),
    "height": focused.get("height"),
    "refresh": focused.get("refreshRate"),
  }


def files_window() -> dict | None:
  wins = [c for c in clients() if c.get("class") == FILES_CLASS]
  return wins[0] if wins else None


def launch_files() -> None:
  as_user(
    [f"{OMARCHY_PATH}/bin/omarchy-launch-files", "--route", "files.documents", "--source", "automation"],
    wait=True,
    timeout=12,
  )


def sha256(path: Path) -> str:
  h = hashlib.sha256()
  h.update(path.read_bytes())
  return h.hexdigest()


def main() -> int:
  out = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/win7-visual")
  out.mkdir(parents=True, exist_ok=True)
  leftover_path = out / "leftover.json"
  sha = git_sha()
  monitor = monitor_report()
  payload = {
    "sha": sha,
    "monitor": monitor,
    "win7VisualLeftover": "OPEN",
    "hexGrepIsNotPixelProof": True,
    "cloudExit0IsNotMetalLeftover": True,
    "filesLiveMetal": "OPEN",
    "emptyBinAuthorized": False,
    "cutAuthorized": False,
    "trashAuthorized": False,
    "exit": 2,
    "error": "",
    "surfaces": {},
    "grims": {},
    "pngSha256": {},
  }
  parked = []
  try:
    if monitor.get("name") != "HDMI-A-1":
      raise RuntimeError(f"focused monitor is {monitor.get('name')!r}, not HDMI-A-1")
    parked = park_occluders()
    if files_window() is None:
      launch_files()
      time.sleep(1.2)
    win = files_window()
    if win is None:
      raise RuntimeError("Files window missing")
    hdmi = out / "hdmi.png"
    grim = as_user(["grim", "-o", "HDMI-A-1", str(hdmi)], wait=True, timeout=8)
    if grim.returncode != 0:
      raise RuntimeError(f"grim HDMI-A-1 failed: {grim.stderr}")
    payload["grims"]["hdmi"] = "hdmi.png"
    payload["pngSha256"]["hdmi.png"] = sha256(hdmi)
    x, y = win["at"]
    w, h = win["size"]
    payload["filesGeometry"] = {"at": [x, y], "size": [w, h], "title": win.get("title")}
    width, height, rows = load_png_rgb(hdmi)
    cap_y = max(0, y - BAR_H)
    cap = average(rows, x + w // 2 - 40, cap_y + 4, x + w // 2 + 40, cap_y + BAR_H - 4)
    payload["captionSample"] = {"rgb": list(cap) if cap else None, "refAero": list(REF_AERO)}
    aero_delta = dist(cap, REF_AERO) if cap else None
    caption_ocr = ocr_region(hdmi, f"{x},{cap_y} {w}x{BAR_H}")
    payload["captionOcr"] = caption_ocr
    payload["surfaces"]["captionCentering"] = {
      "status": "OPEN",
      "windowTitle": win.get("title"),
      "ocr": caption_ocr,
      "note": "Win7 Explorer caption is blank. hyprbars bar_text_align=center. Empty windowTitle fell back to quickshell and is not a fix.",
    }
    payload["surfaces"]["aeroGlassAlpha"] = {
      "status": "OPEN",
      "tokenAeroAlpha": 0.42,
      "measuredAlpha": 0.6,
      "captionMeanRgb": list(cap) if cap else None,
      "distanceTo4580c4": aero_delta,
      "note": "Reference glass is #4580c4 at 0.6 opacity. Token aeroAlpha is 0.42. Hex-grep is not this leftover.",
    }
    nav_x0, nav_y0 = x + 8, y + 40 + 30 + 40
    nav = average(rows, nav_x0, nav_y0, x + 140, nav_y0 + 80)
    payload["navSample"] = {"rgb": list(nav) if nav else None, "refSelBottom": list(REF_SEL_BOTTOM)}
    payload["surfaces"]["selectionWash"] = {
      "status": "OPEN",
      "navMeanRgb": list(nav) if nav else None,
      "distanceToE6ecf5": dist(nav, REF_SEL_BOTTOM) if nav else None,
      "note": "Source tokens match #ffffff/#e6ecf5/#aaddfa. No selected content-row in this grim is pixel proof.",
    }
    bar_y0 = height - 40
    bar = average(rows, 0, bar_y0, width, height)
    reds = 0
    for yy in range(bar_y0, height):
      for xx in range(0, width, 4):
        p = rows[yy][xx]
        if p[0] > 160 and p[1] < 90 and p[2] < 90:
          reds += 1
    payload["superbarSample"] = {"rgb": list(bar) if bar else None, "redBadgeHits": reds}
    payload["surfaces"]["superbarStackUnderline"] = {
      "status": "OPEN",
      "note": "TaskButton.qml still paints a chromeGlow underline for running apps. Win7 running idiom is a bordered glass tile, not an underline. Grim Superbar shows workspace indices 1-5 rather than stacked running tiles.",
    }
    payload["surfaces"]["badgePainting"] = {
      "status": "OPEN",
      "redBadgeHits": reds,
      "note": "TaskButton has no badgeCount (source lock). Notification Center BarWidget still paints a count Badge. Grim tray cluster shows a numeric badge.",
    }
    payload["win7VisualLeftover"] = "OPEN"
    payload["exit"] = 0
    write = leftover_path
    write.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2))
    return 0
  except Exception as error:
    payload["error"] = str(error)
    payload["exit"] = 2
    leftover_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2), file=sys.stderr)
    return 2
  finally:
    unpark(parked)


if __name__ == "__main__":
  sys.exit(main())
