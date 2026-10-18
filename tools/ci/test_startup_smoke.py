"""Regression checks: an exit-zero engine error must never pass the smoke gate."""
from pathlib import Path
import sys
import tempfile
import unittest

from run_startup_smoke import check_output, MARKERS, run_game


class StartupGateTests(unittest.TestCase):
    def test_clean_ready_launch(self):
        check_output(MARKERS["fresh"] + "\n", 0, MARKERS["fresh"])

    def test_engine_errors_even_when_exit_is_zero(self):
        for message in ("ERROR: Missing asset", "SCRIPT ERROR: Invalid call",
                        "USER ERROR: Failed resource", "Parse Error: Broken script",
                        "\x1b[31mERROR: Missing resource\x1b[0m"):
            with self.subTest(message=message), self.assertRaisesRegex(RuntimeError, "Engine errors"):
                check_output(MARKERS["fresh"] + "\n" + message, 0, MARKERS["fresh"])

    def test_nonzero_exit(self):
        with self.assertRaisesRegex(RuntimeError, "code 1"):
            check_output(MARKERS["fresh"], 1, MARKERS["fresh"])

    def test_silent_exit_is_not_readiness(self):
        with self.assertRaisesRegex(RuntimeError, "Missing startup"):
            check_output("", 0, MARKERS["fresh"])

    def test_wrong_eula_branch(self):
        with self.assertRaisesRegex(RuntimeError, "Unexpected startup"):
            check_output("\n".join(MARKERS.values()), 0, MARKERS["fresh"])

    def test_hung_process_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "exceeded"):
                run_game([sys.executable, "-c", "import time; time.sleep(10)"],
                         path, path, "fresh", 0.1)

    def test_error_in_engine_log_only_fails(self):
        fake = (
            "import pathlib, sys; "
            "pathlib.Path(sys.argv[sys.argv.index('--log-file') + 1]).write_text('ERROR: Missing asset'); "
            "print('[STARTUP] eula_ready')"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "Engine errors"):
                run_game([sys.executable, "-c", fake], path, path, "fresh", 5)

    def test_missing_engine_log_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "Missing engine log"):
                run_game([sys.executable, "-c", "print('[STARTUP] eula_ready')"],
                         path, path, "fresh", 5)


if __name__ == "__main__":
    unittest.main()
