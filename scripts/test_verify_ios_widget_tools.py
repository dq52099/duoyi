"""Regression coverage for portable widget verifier executable selection."""

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from verify_ios_widget_timer_core import _resolve_executable


class SwiftExecutableResolutionTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        driver = self.root / "swift-driver"
        driver.write_text("#!/bin/sh\nexit 0\n")
        driver.chmod(0o700)
        self.swift = self.root / "swift"
        self.swift.symlink_to(driver)

    def test_explicit_swift_path_keeps_driver_mode_symlink(self):
        self.assertEqual(str(self.swift), _resolve_executable(str(self.swift)))

    def test_path_lookup_keeps_driver_mode_symlink(self):
        with patch.dict(os.environ, {"PATH": str(self.root)}):
            self.assertEqual(str(self.swift), _resolve_executable("swift"))

    def test_fallback_path_keeps_driver_mode_symlink(self):
        with patch("verify_ios_widget_timer_core.shutil.which", return_value=None):
            self.assertEqual(str(self.swift), _resolve_executable(str(self.swift)))

    def test_missing_and_nonexecutable_files_are_rejected(self):
        no_execute = self.root / "no-execute"
        no_execute.write_text("not executable")
        no_execute.chmod(0o600)
        self.assertIsNone(_resolve_executable(str(no_execute)))
        self.assertIsNone(_resolve_executable(str(self.root / "missing")))


if __name__ == "__main__":
    unittest.main()
