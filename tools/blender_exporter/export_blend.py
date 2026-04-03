import os
import pathlib
import traceback

import bpy


def fail(message: str) -> None:
    print(f"PEEL EXPORT FAILED: {message}", flush=True)
    os._exit(1)


def verify_output(output: pathlib.Path) -> None:
    if not output.exists():
        fail(f"output file was not created: {output}")

    text = output.read_text()
    if "object_count=" not in text:
        fail("output file missing object_count")

    expected_name = os.environ.get("PEEL_EXPORT_EXPECT_NAME")
    if expected_name:
        needle = f"name={expected_name}"
        if needle not in text:
            fail(f"output file missing expected object '{expected_name}'")


def run() -> None:
    output_path = os.environ.get("PEEL_EXPORT_OUTPUT")
    if not output_path:
        fail("PEEL_EXPORT_OUTPUT is not set")

    exporter_lib = os.environ.get("PEEL_BLENDER_EXPORTER_LIB")
    if not exporter_lib:
        fail("PEEL_BLENDER_EXPORTER_LIB is not set")

    output = pathlib.Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()

    try:
        result = bpy.ops.wm.peel_export_headless(filepath=str(output))
        print(f"PEEL EXPORT: operator result {result}", flush=True)

        if "FINISHED" not in result:
            fail(f"unexpected operator result: {result}")

        verify_output(output)
        print(f"PEEL EXPORT: wrote {output}", flush=True)
        bpy.ops.wm.quit_blender()
    except Exception:
        traceback.print_exc()
        os._exit(1)

run()
