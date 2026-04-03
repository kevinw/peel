import os
import pathlib
import sys
import traceback

THIS_DIR = pathlib.Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from peel_blend_export import export_scene_or_raise


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

    try:
        export_scene_or_raise(str(output))
        print(f"PEEL EXPORT: wrote {output}", flush=True)
    except Exception:
        traceback.print_exc()
        os._exit(1)


main()
