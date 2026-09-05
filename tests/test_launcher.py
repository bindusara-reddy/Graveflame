"""Focused launcher contracts; standard-library only."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLAY = ROOT / "play.sh"


class LauncherTests(unittest.TestCase):
    def launch(self, *, driver_ok=True, gpu="auto", vsync="auto", extra=()):
        self.assertTrue(PLAY.is_file(), "play.sh must launch the game with the appropriate GPU")
        with tempfile.TemporaryDirectory(prefix="graveflame-launch-test-") as directory:
            root = Path(directory)
            gpu_probe = root / "nvidia-smi"
            gpu_probe.write_text("#!/bin/sh\nexit " + ("0" if driver_ok else "1") + "\n")
            gpu_probe.chmod(0o755)
            engine = root / "fake godot"
            engine.write_text(
                "#!/usr/bin/python3\nimport json,os,sys\n"
                "print(json.dumps({'cwd':os.getcwd(),'args':sys.argv[1:],"
                "'prime':os.getenv('__NV_PRIME_RENDER_OFFLOAD'),"
                "'vendor':os.getenv('__GLX_VENDOR_LIBRARY_NAME')}))\n"
            )
            engine.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"],
                       GODOT_BIN=str(engine), GRAVEFLAME_GPU=gpu, GRAVEFLAME_VSYNC=vsync)
            env.pop("__NV_PRIME_RENDER_OFFLOAD", None)
            env.pop("__GLX_VENDOR_LIBRARY_NAME", None)
            result = subprocess.run(["bash", str(PLAY), *extra], cwd=root, env=env,
                                    text=True, capture_output=True, check=True)
            return json.loads(result.stdout)

    def test_selects_working_nvidia_driver(self):
        result = self.launch()
        self.assertEqual(result["prime"], "1")
        self.assertEqual(result["vendor"], "nvidia")

    def test_nvidia_avoids_vsync_stalls_with_bounded_frame_rate(self):
        result = self.launch()
        self.assertEqual(result["args"], ["--path", ".", "--disable-vsync", "--max-fps", "120"])

    def test_can_keep_project_vsync_on_nvidia(self):
        result = self.launch(vsync="default")
        self.assertEqual(result["prime"], "1")
        self.assertEqual(result["vendor"], "nvidia")
        self.assertEqual(result["args"], ["--path", "."])

    def test_keeps_default_renderer_without_working_nvidia(self):
        result = self.launch(driver_ok=False)
        self.assertIsNone(result["prime"])
        self.assertIsNone(result["vendor"])
        self.assertEqual(result["args"], ["--path", "."])

    def test_allows_explicit_default_gpu(self):
        result = self.launch(gpu="default")
        self.assertIsNone(result["prime"])
        self.assertIsNone(result["vendor"])
        self.assertEqual(result["args"], ["--path", "."])

    def test_resolves_project_and_preserves_arguments(self):
        result = self.launch(extra=("--resolution", "1280x720", "--", "path with spaces"))
        self.assertEqual(result["cwd"], str(ROOT))
        self.assertEqual(result["args"], ["--path", ".", "--disable-vsync", "--max-fps", "120", "--resolution", "1280x720", "--", "path with spaces"])


if __name__ == "__main__":
    unittest.main()
