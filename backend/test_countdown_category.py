"""Default category provenance at legacy conversion and sync boundaries."""

import json
import os
import tempfile
import unittest

import main as api


class CountdownCategoryTest(unittest.TestCase):
    def test_legacy_conversion_marks_only_generated_categories(self):
        base = {"id": "legacy", "originDate": "2032-09-20", "title": "User title"}
        for category in (None, "", "  "):
            with self.subTest(category=category):
                original = dict(base)
                if category is not None:
                    original["category"] = category
                result = api._countdown_from_legacy_anniversary(original)
                self.assertEqual(result["category"], "默认")
                self.assertIs(result["categoryIsDefault"], True)
                self.assertEqual(result["targetDate"], base["originDate"])
                self.assertEqual(result["title"], base["title"])
                self.assertNotIn("categoryIsDefault", original)

        for category in ("默认", "Default", " 用户分类 "):
            with self.subTest(category=category):
                result = api._countdown_from_legacy_anniversary(
                    {**base, "category": category}
                )
                self.assertEqual(result["category"], category)
                self.assertNotIn("categoryIsDefault", result)

        for marker in (True, False):
            result = api._countdown_from_legacy_anniversary(
                {**base, "category": "默认", "categoryIsDefault": marker}
            )
            self.assertIs(result["categoryIsDefault"], marker)

    def test_sync_and_database_keep_explicit_default_and_custom_categories(self):
        old_path = api.DB_PATH
        with tempfile.TemporaryDirectory() as directory:
            api.DB_PATH = os.path.join(directory, "category-test.db")
            try:
                api.init_db()
                db = api.get_db()
                try:
                    api._setting_set(db, "registration_email_required", False)
                    api._setting_set(db, "default_registration_coins", 0)
                    db.commit()
                finally:
                    db.close()
                user_id = api.register(
                    api.RegisterRequest(
                        username="countdown-category-test", password="pass123456"
                    )
                )["user_id"]
                base = {
                    "title": "User title",
                    "targetDate": "2032-09-20T00:00:00Z",
                    "updatedAt": "2026-10-15T00:00:00Z",
                    "category": "默认",
                }
                records = [
                    {**base, "id": "generated", "categoryIsDefault": True},
                    {**base, "id": "custom", "categoryIsDefault": False},
                    {**base, "id": "ambiguous"},
                ]
                synced = api.sync(api.SyncRequest(countdowns=records), user_id=user_id)
                self.assertEqual(
                    {item["id"]: item for item in synced["countdowns"]},
                    {item["id"]: item for item in records},
                )
                db = api.get_db()
                try:
                    stored = json.loads(
                        db.execute(
                            "SELECT countdowns FROM sync_data WHERE user_id=?",
                            (user_id,),
                        ).fetchone()["countdowns"]
                    )
                finally:
                    db.close()
                self.assertEqual(
                    {item["id"]: item for item in stored},
                    {item["id"]: item for item in records},
                )
            finally:
                api.DB_PATH = old_path
                api.TOKENS.clear()
                api.TOKEN_LAST_ACTIVE.clear()


if __name__ == "__main__":
    unittest.main()
