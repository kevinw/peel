import os
import pathlib
import sys

import bpy

# Thin Python entrypoint for the native Blender-side exporter. The actual .peelscene
# binary is written by Blender C++ in source/blender/io/peel.

def fail(message: str) -> None:
    print(f"PEEL EXPORT FAILED: {message}", flush=True)
    os._exit(1)


def main() -> None:
    output_path = os.environ.get("PEEL_EXPORT_OUTPUT")
    if not output_path:
        fail("PEEL_EXPORT_OUTPUT is not set")

    output = pathlib.Path(output_path)
    if output.exists():
        output.unlink()

    result = bpy.ops.wm.peel_export_headless(filepath=str(output))
    if "FINISHED" not in result:
        fail(f"operator returned {result}")

    print(f"PEEL EXPORT: wrote {output}", flush=True)


main()
