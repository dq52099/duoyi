"""Unit tests for _app_version_code legacy (+1) and +10 stride fallback calculation."""

import unittest
from unittest.mock import patch

import main as api


class AppVersionCodeStrideTest(unittest.TestCase):
    def test_legacy_base_code_uses_unit_stride(self):
        with (
            patch.object(api, "APP_CURRENT_VERSION", "1.1.43"),
            patch.object(api, "APP_CURRENT_VERSION_CODE", 140009),
        ):
            self.assertEqual(api._app_version_code("1.1.43"), 140009)
            self.assertEqual(api._app_version_code("v1.1.43"), 140009)
            self.assertEqual(api._app_version_code("1.1.44"), 140010)
            self.assertEqual(api._app_version_code("1.1.46"), 140012)
            self.assertEqual(api._app_version_code("1.2.0"), 140009 + (120000 - 110043))
            self.assertEqual(api._app_version_code("1.1.42"), 110042)
            self.assertEqual(api._app_version_code("9.9.9"), 990009)

    def test_threshold_below_1500000_keeps_unit_stride(self):
        with (
            patch.object(api, "APP_CURRENT_VERSION", "1.1.46"),
            patch.object(api, "APP_CURRENT_VERSION_CODE", 1499999),
        ):
            self.assertEqual(api._app_version_code("1.1.47"), 1500000)

    def test_stride_ten_at_or_above_1500000(self):
        with (
            patch.object(api, "APP_CURRENT_VERSION", "1.1.47"),
            patch.object(api, "APP_CURRENT_VERSION_CODE", 1500000),
        ):
            self.assertEqual(api._app_version_code("1.1.47"), 1500000)
            self.assertEqual(api._app_version_code("v1.1.47"), 1500000)
            self.assertEqual(api._app_version_code("1.1.48"), 1500010)
            self.assertEqual(api._app_version_code("v1.1.48"), 1500010)
            self.assertEqual(api._app_version_code("1.1.49"), 1500020)
            self.assertEqual(api._app_version_code("1.1.50"), 1500030)
            self.assertEqual(
                api._app_version_code("1.2.0"),
                1500000 + (120000 - 110047) * 10,
            )
            self.assertEqual(
                api._app_version_code("9.9.9"),
                1500000 + (990009 - 110047) * 10,
            )
            self.assertEqual(api._app_version_code("1.1.46"), 110046)

    def test_stride_ten_clamps_non_positive_code_diff_to_one_step(self):
        with (
            patch.object(api, "APP_CURRENT_VERSION", "1.1.10001"),
            patch.object(api, "APP_CURRENT_VERSION_CODE", 1500010),
        ):
            self.assertEqual(api._app_version_code("1.2.0"), 1500020)


if __name__ == "__main__":
    unittest.main()
