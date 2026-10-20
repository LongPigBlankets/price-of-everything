"""Retired commands must never rewrite data, even with the former force argument."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RetiredGeneratorTests(unittest.TestCase):
    def check_refusal(self, name: str, arguments: list[str]) -> None:
        # Exercise a disposable project, so a regression cannot damage live tables.
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            (project / "scripts").mkdir()
            (project / "data").mkdir()
            script = project / "scripts" / name
            shutil.copy2(ROOT / "price-of-everything-0.1/scripts" / name, script)
            (project / "data/recipes_all.csv").write_bytes(b"recipe_id,display_name\r\nr_001,Keep me\r\n")
            (project / "data/recipes_master_source.csv").write_bytes(b"recipe_id,display_name\r\nr_001,Old recipe\r\n")
            before = {str(p.relative_to(project)): p.read_bytes() for p in project.rglob("*") if p.is_file()}
            result = subprocess.run([sys.executable, str(script), *arguments], cwd=project,
                                    capture_output=True, text=True, timeout=5)
            after = {str(p.relative_to(project)): p.read_bytes() for p in project.rglob("*") if p.is_file()}
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("RETIRED", result.stderr)
            self.assertIn("content-authoring.md", result.stderr)
            self.assertEqual(before, after, "A retired command modified its disposable project")

    def test_normal_invocation_refuses(self) -> None:
        for name in ("build_recipes_all.py", "rebalance_recipes.py"):
            with self.subTest(script=name):
                self.check_refusal(name, [])

    def test_former_override_also_refuses(self) -> None:
        for name in ("build_recipes_all.py", "rebalance_recipes.py"):
            with self.subTest(script=name):
                self.check_refusal(name, ["--i-know-this-renumbers-and-deletes"])


if __name__ == "__main__":
    unittest.main()
