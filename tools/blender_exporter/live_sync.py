import os
import pathlib
import time
import traceback

import bpy
from bpy.app.handlers import persistent

# Live reload wrapper around the native Blender-side exporter. This only schedules
# exports; the file format itself is emitted by Blender C++.
DEBOUNCE_SECONDS = float(os.environ.get("PEEL_LIVE_DEBOUNCE", "0.175"))
STATE = {
    "dirty": True,
    "last_change": time.monotonic(),
    "output_path": None,
}


def default_output_path(blend_path: str) -> str:
    return blend_path + ".peelscene"


def resolve_output_path() -> str:
    env_path = os.environ.get("PEEL_LIVE_OUTPUT")
    if env_path:
        return env_path

    blend_path = bpy.data.filepath
    if not blend_path:
        raise RuntimeError("Current .blend has not been saved and PEEL_LIVE_OUTPUT is not set")
    return default_output_path(blend_path)


def mark_dirty(*_args) -> None:
    STATE["dirty"] = True
    STATE["last_change"] = time.monotonic()


@persistent
def on_depsgraph_update(_scene, _depsgraph) -> None:
    mark_dirty()


@persistent
def on_save_post(_dummy) -> None:
    mark_dirty()


def timer_callback():
    if STATE["output_path"] is None:
        try:
            STATE["output_path"] = resolve_output_path()
            print(f"PEEL LIVE SYNC: output {STATE['output_path']}", flush=True)
        except Exception as exc:
            print(f"PEEL LIVE SYNC: {exc}", flush=True)
            return 1.0

    if STATE["dirty"] and (time.monotonic() - STATE["last_change"]) >= DEBOUNCE_SECONDS:
        try:
            result = bpy.ops.wm.peel_export_headless(filepath=STATE["output_path"])
            if "FINISHED" not in result:
                raise RuntimeError(f"peel_export_headless returned {result}")
            print(f"PEEL LIVE SYNC: exported {STATE['output_path']}", flush=True)
            STATE["dirty"] = False
        except Exception:
            traceback.print_exc()
    return 0.1


def ensure_handler(handler_list, callback):
    for existing in list(handler_list):
        if getattr(existing, "__name__", "") == callback.__name__:
            handler_list.remove(existing)
    handler_list.append(callback)


ensure_handler(bpy.app.handlers.depsgraph_update_post, on_depsgraph_update)
ensure_handler(bpy.app.handlers.save_post, on_save_post)
bpy.app.timers.register(timer_callback, first_interval=0.1, persistent=True)
print("PEEL LIVE SYNC: registered", flush=True)
