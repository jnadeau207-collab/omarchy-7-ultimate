#!/usr/bin/env python3
"""Prove Files LIVE Open, Rename, and Copy on the metal Hyprland session.

Cloud EXIT 0 is not this leftover. Cut / Trash / Empty Bin stay unauthorized.
Hyprland 0.56 parks occluders through hl.dsp.window.move (follow=false).
The 0.51 silent workspace dispatcher is invalid on this compositor.
"""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HELPER = Path(os.environ.get("OMARCHY_PATH") or "") / "test/acceptance.d/hyprbars-pointer-proof.py"
if not HELPER.is_file():
  HELPER = Path(__file__).resolve().parent / "hyprbars-pointer-proof.py"
spec = importlib.util.spec_from_file_location("hyprbars_pointer_proof", HELPER)
mod = importlib.util.module_from_spec(spec)
sys.modules["hyprbars_pointer_proof"] = mod
spec.loader.exec_module(mod)

AbsPointer = mod.AbsPointer
ProofError = mod.ProofError
as_user = mod.as_user
client_by_addr = mod.client_by_addr
clients = mod.clients
grim = mod.grim
hypr = mod.hypr
hypr_env = mod.hypr_env
monitor_size = mod.monitor_size
wait_until = mod.wait_until
OMARCHY_PATH = mod.OMARCHY_PATH
USER_HOME = mod.USER_HOME

FILES_CLASS = "org.omarchy.Files"
NAV_NARROW = 150
NAV_WIDE = 190
ADDRESS_H = 40
COMMAND_H = 30
HEADER_H = 22
ROW_H = 18
NOTICE_H = 26
OCCLUDE_CLASSES = {"cursor", "org.omarchy.Settings"}


def git_sha() -> str:
  proc = subprocess.run(
    ["git", "-C", OMARCHY_PATH, "rev-parse", "HEAD"],
    check=True,
    capture_output=True,
    text=True,
  )
  return proc.stdout.strip()


def hypr_try(*args: str) -> subprocess.CompletedProcess[str]:
  return subprocess.run(["hyprctl", *args], env=hypr_env(), text=True, capture_output=True)


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


def files_windows() -> list[dict]:
  return [c for c in clients() if c.get("class") == FILES_CLASS]


def active_window() -> dict:
  return json.loads(hypr("-j", "activewindow") or "{}")


def active_class() -> str:
  return str(active_window().get("class") or "")


def workspace_of(addr: str) -> str:
  win = client_by_addr(addr)
  if not win:
    return ""
  ws = win.get("workspace") or {}
  return str(ws.get("name") or ws.get("id") or "")


def move_window_workspace(addr: str, dest: str) -> None:
  # omarchy-shell window moveToDesktop returns {"changed":true} on this metal
  # without moving the client (Hyprland 0.56). Park through the live Lua
  # dispatcher and require the workspace to change.
  lua = (
    'hl.dsp.window.move({ workspace = "'
    + dest
    + '", follow = false, window = "address:'
    + str(addr)
    + '" })'
  )
  proc = hypr_try("dispatch", lua)
  if proc.returncode != 0:
    raise ProofError(
      "hl.dsp.window.move "
      + addr
      + " -> "
      + dest
      + " failed: "
      + ((proc.stdout or "") + " " + (proc.stderr or "")).strip()
    )


def park_window(addr: str) -> None:
  move_window_workspace(addr, "2")


def unpark_window(addr: str) -> None:
  move_window_workspace(addr, "1")


def park_occluders() -> list[str]:
  saved = []
  for c in clients():
    cls = str(c.get("class") or "")
    if cls == FILES_CLASS:
      continue
    ws = str((c.get("workspace") or {}).get("name") or "")
    if ws != "1":
      continue
    if not c.get("mapped", True):
      continue
    addr = c.get("address")
    if not addr:
      continue
    if cls not in OCCLUDE_CLASSES and cls.lower() not in OCCLUDE_CLASSES:
      # Park every other mapped client on desktop 1 so Files is the only
      # product window the compositor can raise over HDMI-A-1.
      if cls.startswith("org.omarchy."):
        continue
    saved.append(addr)
    park_window(addr)
  if saved:
    wait_until(
      "occluders off workspace 1",
      8,
      lambda: all(workspace_of(addr) != "1" for addr in saved),
    )
  hypr_try("dispatch", 'hl.dsp.focus({ workspace = "1" })')
  time.sleep(0.25)
  return saved


def unpark_occluders(addrs: list[str]) -> None:
  seen = set(addrs)
  for addr in addrs:
    try:
      unpark_window(addr)
    except Exception:
      pass
  for c in clients():
    cls = str(c.get("class") or "")
    if cls not in OCCLUDE_CLASSES and cls.lower() not in OCCLUDE_CLASSES:
      continue
    addr = c.get("address")
    if not addr or addr in seen:
      continue
    try:
      unpark_window(addr)
    except Exception:
      pass


def close_files() -> None:
  # omarchy-shell window close returns changed:true without unmapping Files
  # on this metal. Reuse the live Files window; launch navigates it.
  return


def launch_files(relative: str) -> None:
  args = json.dumps({"relativePath": relative})
  proc = as_user(
    [
      f"{OMARCHY_PATH}/bin/omarchy-launch-files",
      "--route",
      "files.documents",
      "--args-json",
      args,
      "--source",
      "automation",
    ],
    wait=True,
    timeout=12,
  )
  if proc.returncode != 0 and len(files_windows()) == 0:
    raise ProofError(f"omarchy-launch-files failed: {proc.stdout} {proc.stderr}")


def focus_files(pointer: AbsPointer | None = None, attempts: list | None = None) -> dict:
  wait_until("Files window", 10, lambda: len(files_windows()) >= 1)
  win = files_windows()[0]
  addr = win["address"]
  as_user(["omarchy-shell", "window", "activate", addr], wait=True, timeout=5)
  if attempts is not None:
    attempts.append({"step": "omarchy-shell-activate", "active": active_class()})
  hypr_try("dispatch", f'hl.dsp.focus({{ window = "address:{addr}" }})')
  if attempts is not None:
    attempts.append({"step": "lua-focus-address", "active": active_class()})
  hypr_try("dispatch", 'hl.dsp.focus({ window = "class:org.omarchy.Files" })')
  if attempts is not None:
    attempts.append({"step": "lua-focus-class", "active": active_class()})
  hypr_try("dispatch", f'hl.dsp.window.bring_to_top({{ window = "address:{addr}" }})')
  if attempts is not None:
    attempts.append({"step": "lua-bring-to-top", "active": active_class()})
  hypr_try("dispatch", 'hl.dsp.focus({ workspace = "1" })')
  if attempts is not None:
    attempts.append({"step": "lua-focus-workspace-1", "active": active_class()})
  time.sleep(0.2)
  if pointer is not None:
    x, y = win["at"]
    w, h = win["size"]
    pointer.click(x + max(w // 2, 40), y + ADDRESS_H + COMMAND_H + HEADER_H + ROW_H)
    time.sleep(0.35)
    if attempts is not None:
      attempts.append({"step": "abs-pointer-click-files", "active": active_class()})
    win = client_by_addr(addr) or files_windows()[0]
  if active_class() != FILES_CLASS:
    raise ProofError(
      "compositor did not focus Files; active="
      + repr(active_class())
      + " files="
      + addr
      + " (Lua dispatch and AbsPointer click returned ok; Cursor kept activewindow)"
    )
  return client_by_addr(addr) or win


def click_first_row(pointer: AbsPointer, win: dict, notice: bool = False) -> None:
  x, y = win["at"]
  w, _h = win["size"]
  nav = NAV_WIDE if w >= 900 else NAV_NARROW
  row_x = x + nav + 80
  row_y = y + ADDRESS_H + COMMAND_H + (NOTICE_H if notice else 0) + HEADER_H + (ROW_H // 2)
  pointer.click(row_x, row_y)
  time.sleep(0.2)


def wtype(*keys: str) -> None:
  proc = as_user(["wtype", *keys], wait=True, timeout=8)
  if proc.returncode != 0:
    raise ProofError(f"wtype failed {keys!r}: {proc.stderr}")


def grim_hdmi(path: Path) -> None:
  proc = as_user(["grim", "-o", "HDMI-A-1", str(path)], wait=True, timeout=8)
  if proc.returncode != 0:
    grim(str(path))


def grim_win(path: Path, win: dict) -> None:
  x, y = win["at"]
  w, h = win["size"]
  geom = f"{x},{y} {w}x{h}"
  proc = as_user(["grim", "-g", geom, str(path)], wait=True, timeout=8)
  if proc.returncode != 0:
    grim(str(path))


def close_non_files() -> None:
  for c in clients():
    cls = str(c.get("class") or "")
    if cls in {FILES_CLASS, "cursor", "org.omarchy.Settings"}:
      continue
    if str(c.get("workspace", {}).get("name") or "") != "1":
      continue
    addr = c.get("address")
    if addr:
      as_user(["omarchy-shell", "window", "close", addr], wait=True, timeout=5)


def handler_windows() -> list[dict]:
  skip = {FILES_CLASS, "cursor", "org.omarchy.Settings"}
  skip_l = {s.lower() for s in skip}
  out = []
  for c in clients():
    cls = str(c.get("class") or "")
    if cls in skip or cls.lower() in skip_l:
      continue
    if str((c.get("workspace") or {}).get("name") or "") != "1":
      continue
    if not c.get("mapped", True):
      continue
    out.append(c)
  return out


def mime_default(mime: str) -> str:
  proc = as_user(["xdg-mime", "query", "default", mime], wait=True, timeout=5)
  return (proc.stdout or "").strip()


def write_leftover(path: Path, payload: dict) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def snapshot_clients() -> list[dict]:
  out = []
  for c in clients():
    out.append(
      {
        "class": c.get("class"),
        "title": c.get("title"),
        "workspace": (c.get("workspace") or {}).get("name"),
        "mapped": c.get("mapped"),
        "hidden": c.get("hidden"),
        "at": c.get("at"),
        "size": c.get("size"),
        "address": c.get("address"),
      }
    )
  return out


def main() -> int:
  out = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/files-live-metal")
  out.mkdir(parents=True, exist_ok=True)
  leftover_path = out / "leftover.json"
  sha = git_sha()
  monitor = monitor_report()
  payload = {
    "sha": sha,
    "monitor": monitor,
    "hyprlandSignature": hypr_env().get("HYPRLAND_INSTANCE_SIGNATURE"),
    "filesLiveMetal": "OPEN",
    "focus": "fail",
    "verbs": {"open": "unrun", "rename": "unrun", "copy": "unrun"},
    "cutAuthorized": False,
    "emptyBinAuthorized": False,
    "trashAuthorized": False,
    "cloudExit0IsNotMetalLeftover": True,
    "exit": 2,
    "error": "",
    "grims": {},
    "focusAttempts": [],
  }
  parked = []
  pointer = None
  proof_dir = Path(USER_HOME) / "Documents" / f"omarchy-files-live-{sha[:12]}"
  source_name = "alpha-live.txt"
  renamed_name = "beta-live.txt"
  copied_name = "beta-live (2).txt"
  try:
    if monitor.get("name") != "HDMI-A-1":
      raise ProofError(f"focused monitor is {monitor.get('name')!r}, not HDMI-A-1")
    payload["xdgMimeTextPlain"] = mime_default("text/plain")
    if proof_dir.exists():
      shutil.rmtree(proof_dir)
    proof_dir.mkdir(parents=True)
    (proof_dir / source_name).write_text("files-live-open\n", encoding="utf-8")
    payload["proofDir"] = str(proof_dir)
    payload["names"] = {"source": source_name, "renamed": renamed_name, "copied": copied_name}
    parked = park_occluders()
    launch_files(proof_dir.name)
    pointer = AbsPointer()
    win = focus_files(pointer, attempts=payload["focusAttempts"])
    payload["focus"] = "pass"
    time.sleep(2.4)
    win = client_by_addr(win["address"]) or files_windows()[0]
    click_first_row(pointer, win, notice=False)
    wtype("-k", "Home")
    time.sleep(0.25)
    grim_hdmi(out / "01-listing-hdmi.png")
    grim_win(out / "01-listing-window.png", files_windows()[0])
    payload["grims"]["listing"] = "01-listing-hdmi.png"
    wtype("-k", "Return")
    time.sleep(1.6)
    wait_until("Open mapped a handler window", 8, lambda: len(handler_windows()) >= 1)
    grim_hdmi(out / "02-open-hdmi.png")
    grim_win(out / "02-open-window.png", files_windows()[0] if files_windows() else {"at": [0, 0], "size": [1, 1]})
    opened = handler_windows()
    if not opened:
      raise ProofError("Open did not map a handler window on workspace 1")
    payload["verbs"]["open"] = "pass"
    payload["openHandler"] = {"class": opened[0].get("class"), "title": opened[0].get("title")}
    payload["grims"]["open"] = "02-open-hdmi.png"
    close_non_files()
    time.sleep(0.5)
    win = focus_files(pointer)
    click_first_row(pointer, win, notice=True)
    wtype("-k", "Home")
    wtype("-k", "F2")
    time.sleep(0.45)
    grim_hdmi(out / "03-rename-dialog-hdmi.png")
    grim_win(out / "03-rename-dialog-window.png", files_windows()[0])
    payload["grims"]["renameDialog"] = "03-rename-dialog-hdmi.png"
    wtype("-M", "ctrl", "-k", "a", "-m", "ctrl")
    time.sleep(0.1)
    wtype("--", renamed_name)
    wtype("-k", "Return")
    wait_until("renamed file on disk", 8, lambda: (proof_dir / renamed_name).is_file())
    if (proof_dir / source_name).exists():
      raise ProofError("rename left the original name on disk")
    payload["verbs"]["rename"] = "pass"
    time.sleep(0.7)
    grim_hdmi(out / "04-renamed-hdmi.png")
    grim_win(out / "04-renamed-window.png", files_windows()[0])
    payload["grims"]["renamed"] = "04-renamed-hdmi.png"
    win = focus_files(pointer)
    click_first_row(pointer, win, notice=True)
    wtype("-k", "Home")
    wtype("-M", "ctrl", "-k", "c", "-m", "ctrl")
    time.sleep(0.25)
    wtype("-M", "ctrl", "-k", "v", "-m", "ctrl")
    wait_until("copied file on disk", 10, lambda: (proof_dir / copied_name).is_file())
    payload["verbs"]["copy"] = "pass"
    time.sleep(0.9)
    grim_hdmi(out / "05-copied-hdmi.png")
    grim_win(out / "05-copied-window.png", files_windows()[0])
    payload["grims"]["copied"] = "05-copied-hdmi.png"
    payload["filesLiveMetal"] = "CLOSED"
    payload["exit"] = 0
    write_leftover(leftover_path, payload)
    print(json.dumps(payload, indent=2))
    return 0
  except Exception as error:
    payload["error"] = str(error)
    payload["filesLiveMetal"] = "OPEN"
    payload["exit"] = 2
    payload["activeClass"] = active_class()
    payload["activeWindow"] = {
      "class": active_window().get("class"),
      "title": active_window().get("title"),
      "address": active_window().get("address"),
    }
    payload["clients"] = snapshot_clients()
    try:
      grim_hdmi(out / "fail-hdmi.png")
      payload["grims"]["fail"] = "fail-hdmi.png"
      wins = files_windows()
      if wins:
        grim_win(out / "fail-files.png", wins[0])
    except Exception:
      pass
    write_leftover(leftover_path, payload)
    print(json.dumps(payload, indent=2), file=sys.stderr)
    return 2
  finally:
    if pointer is not None:
      pointer.close()
    unpark_occluders(parked)


if __name__ == "__main__":
  sys.exit(main())
