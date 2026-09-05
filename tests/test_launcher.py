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
        """Run a copy of play.sh in an isolated fixture project that already has
        a class cache (warm path), so these tests never depend on, or touch, the
        real repository's .godot/ directory. ColdStartTests cover the cold path."""
        self.assertTrue(PLAY.is_file(), "play.sh must launch the game with the appropriate GPU")
        with tempfile.TemporaryDirectory(prefix="graveflame-launch-test-") as directory:
            root = Path(directory)
            project = root / "project dir"
            project.mkdir()
            (project / "play.sh").write_bytes(PLAY.read_bytes())
            (project / "project.godot").write_text("[application]\nconfig/name=\"Graveflame\"\n")
            cache = project / ".godot" / "global_script_class_cache.cfg"
            cache.parent.mkdir()
            cache.write_text("list=[]\n")
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
            result = subprocess.run(["bash", str(project / "play.sh"), *extra], cwd=root, env=env,
                                    text=True, capture_output=True, check=True)
            lines = result.stdout.strip().splitlines()
            self.assertEqual(len(lines), 1, "warm launch must call the engine exactly once")
            launched = json.loads(lines[0])
            launched["project"] = str(project)
            return launched

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
        self.assertEqual(result["cwd"], result["project"], "engine runs in the launcher's own project directory")
        self.assertEqual(result["args"], ["--path", ".", "--disable-vsync", "--max-fps", "120", "--resolution", "1280x720", "--", "path with spaces"])


class ColdStartTests(unittest.TestCase):
    """A clean checkout has no .godot/ class cache, so class_name lookups fail at
    boot; the launcher must import once (headless, no caller arguments), refuse to
    start on a broken import, and skip the step entirely once the cache exists."""

    CACHE = Path(".godot") / "global_script_class_cache.cfg"

    def run_project(self, *, cold, import_fails=False, import_output="", extra=()):
        with tempfile.TemporaryDirectory(prefix="graveflame-cold-test-") as directory:
            project = Path(directory) / "project dir"
            project.mkdir()
            (project / "play.sh").write_bytes(PLAY.read_bytes())
            (project / "project.godot").write_text("[application]\nconfig/name=\"Graveflame\"\n")
            if not cold:
                (project / self.CACHE).parent.mkdir()
                (project / self.CACHE).write_text("list=[]\n")
            calls = Path(directory) / "calls.jsonl"
            engine = Path(directory) / "fake godot"
            engine.write_text(
                "#!/usr/bin/python3\nimport json,os,sys\n"
                "args=sys.argv[1:]\n"
                "open(os.environ['FAKE_CALLS'],'a').write(json.dumps({'cwd':os.getcwd(),'args':args})+'\\n')\n"
                "if '--import' in args:\n"
                "    sys.stdout.write(os.environ.get('FAKE_IMPORT_OUTPUT',''))\n"
                "    if os.environ.get('FAKE_IMPORT_FAIL')=='1':\n"
                "        sys.exit(3)\n"
                "    os.makedirs('.godot',exist_ok=True)\n"
                "    open('.godot/global_script_class_cache.cfg','w').write('list=[]\\n')\n"
                "    sys.exit(0)\n"
                "print('GAME_STARTED')\n"
            )
            engine.chmod(0o755)
            env = dict(os.environ, GODOT_BIN=str(engine), GRAVEFLAME_GPU="default",
                       FAKE_CALLS=str(calls), FAKE_IMPORT_FAIL="1" if import_fails else "0",
                       FAKE_IMPORT_OUTPUT=import_output)
            result = subprocess.run(["bash", str(project / "play.sh"), *extra], cwd=directory,
                                    env=env, text=True, capture_output=True)
            recorded = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
            return result, recorded, project

    def test_cold_start_imports_once_then_launches(self):
        result, calls, project = self.run_project(cold=True, extra=("--quit-after", "240"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c["args"] for c in calls],
                         [["--path", ".", "--headless", "--import"], ["--path", ".", "--quit-after", "240"]])
        self.assertTrue(all(c["cwd"] == str(project) for c in calls))
        self.assertIn("GAME_STARTED", result.stdout)

    def test_warm_start_skips_import(self):
        result, calls, _ = self.run_project(cold=False, extra=("--quit-after", "240"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c["args"] for c in calls], [["--path", ".", "--quit-after", "240"]])

    def test_failed_import_stops_the_launch(self):
        result, calls, _ = self.run_project(cold=True, import_fails=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)
        self.assertNotIn("GAME_STARTED", result.stdout)
        self.assertIn("import", result.stderr.lower())

    def test_script_errors_during_import_stop_the_launch(self):
        result, calls, _ = self.run_project(cold=True, import_output="SCRIPT ERROR: Parse Error: boom\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)
        self.assertIn("SCRIPT ERROR", result.stderr)


if __name__ == "__main__":
    unittest.main()
