import os
import tempfile
import unittest
from datetime import timedelta

from fastapi import HTTPException

import main as api


class WorkspaceApiTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._old_db_path = api.DB_PATH
        api.DB_PATH = os.path.join(self._tmp.name, "duoyi-test.db")
        api.TOKENS.clear()
        api.TOKEN_LAST_ACTIVE.clear()
        api.init_db()

    def tearDown(self):
        api.DB_PATH = self._old_db_path
        api.TOKENS.clear()
        api.TOKEN_LAST_ACTIVE.clear()
        self._tmp.cleanup()

    def _register(self, username: str) -> str:
        res = api.register(
            api.RegisterRequest(username=username, password="pass123456")
        )
        return res["user_id"]

    def test_invite_acceptance_adds_member_and_workspace_visible(self):
        owner_id = self._register("owner")
        member_id = self._register("member")

        workspace = api.create_workspace(
            api.WorkspaceCreate(name="家庭共享"), user_id=owner_id
        )
        invite = api.create_workspace_invite(
            workspace["id"],
            api.WorkspaceInviteCreate(role="viewer"),
            user_id=owner_id,
        )

        accepted = api.accept_workspace_invite(invite["code"], user_id=member_id)
        member_workspaces = api.list_workspaces(user_id=member_id)

        self.assertEqual(accepted["workspace_id"], workspace["id"])
        self.assertTrue(
            any(item["id"] == workspace["id"] for item in member_workspaces)
        )

    def test_viewer_cannot_invite_or_overwrite_workspace_sync_data(self):
        owner_id = self._register("owner")
        viewer_id = self._register("viewer")

        workspace = api.create_workspace(
            api.WorkspaceCreate(name="项目共享"), user_id=owner_id
        )
        invite = api.create_workspace_invite(
            workspace["id"],
            api.WorkspaceInviteCreate(role="viewer"),
            user_id=owner_id,
        )
        api.accept_workspace_invite(invite["code"], user_id=viewer_id)

        with self.assertRaises(HTTPException) as denied:
            api.create_workspace_invite(
                workspace["id"],
                api.WorkspaceInviteCreate(role="viewer"),
                user_id=viewer_id,
            )
        self.assertEqual(denied.exception.status_code, 403)

        owner_sync = api.sync(
            api.SyncRequest(
                workspace_payloads={
                    workspace["id"]: {
                        "todos": [
                            {
                                "id": "todo-1",
                                "title": "owner value",
                                "updatedAt": "2026-01-01T00:00:00Z",
                            }
                        ]
                    }
                }
            ),
            user_id=owner_id,
        )
        self.assertEqual(
            owner_sync["workspace_payloads"][workspace["id"]]["todos"][0][
                "title"
            ],
            "owner value",
        )

        viewer_sync = api.sync(
            api.SyncRequest(
                workspace_payloads={
                    workspace["id"]: {
                        "todos": [
                            {
                                "id": "todo-1",
                                "title": "viewer overwrite",
                                "updatedAt": "2026-01-02T00:00:00Z",
                            }
                        ]
                    }
                }
            ),
            user_id=viewer_id,
        )
        self.assertEqual(
            viewer_sync["workspace_payloads"][workspace["id"]]["todos"][0][
                "title"
            ],
            "owner value",
        )

    def test_verify_token_rejects_disabled_user_and_clears_token(self):
        user_id = self._register("disabled-user")
        token = api.TOKENS[user_id]

        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_disabled=1 WHERE id=?", (user_id,))
            db.commit()
        finally:
            db.close()

        with self.assertRaises(HTTPException) as denied:
            api._verify_token(f"Bearer {token}")

        self.assertEqual(denied.exception.status_code, 403)
        self.assertNotIn(user_id, api.TOKENS)

    def test_verify_token_rejects_deleted_user_and_clears_token(self):
        user_id = self._register("deleted-user")
        token = api.TOKENS[user_id]

        db = api.get_db()
        try:
            db.execute("DELETE FROM users WHERE id=?", (user_id,))
            db.commit()
        finally:
            db.close()

        with self.assertRaises(HTTPException) as denied:
            api._verify_token(f"Bearer {token}")

        self.assertEqual(denied.exception.status_code, 401)
        self.assertNotIn(user_id, api.TOKENS)

    def test_admin_online_status_uses_recent_activity_window(self):
        admin_id = self._register("admin-online")
        user_id = self._register("normal-online")
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_admin=1 WHERE id=?", (admin_id,))
            db.commit()
        finally:
            db.close()

        active_users = api.admin_list_users(_=admin_id, limit=100, offset=0)
        target = next(u for u in active_users if u["user_id"] == user_id)
        self.assertTrue(target["online"])
        self.assertIsNotNone(target["last_active_at"])

        api.TOKEN_LAST_ACTIVE[user_id] = api._utc_now() - timedelta(
            seconds=api.SESSION_ONLINE_SECONDS + 1
        )

        stale_users = api.admin_list_users(_=admin_id, limit=100, offset=0)
        target = next(u for u in stale_users if u["user_id"] == user_id)
        self.assertFalse(target["online"])
        self.assertIsNotNone(target["last_active_at"])

    def test_feedback_create_validates_content_and_category(self):
        user_id = self._register("feedback-user")

        with self.assertRaises(HTTPException) as empty:
            api.create_feedback(
                api.FeedbackCreate(category="bug", content="   "),
                user_id=user_id,
            )
        self.assertEqual(empty.exception.status_code, 400)

        with self.assertRaises(HTTPException) as bad_category:
            api.create_feedback(
                api.FeedbackCreate(category="invalid", content="按钮没有反应"),
                user_id=user_id,
            )
        self.assertEqual(bad_category.exception.status_code, 400)

        created = api.create_feedback(
            api.FeedbackCreate(category="bug", content="  通知没有声音  "),
            user_id=user_id,
        )
        self.assertEqual(created["status"], "open")

        items = api.my_feedback(user_id=user_id)
        self.assertEqual(items[0]["category"], "bug")
        self.assertEqual(items[0]["content"], "通知没有声音")

    def test_admin_feedback_reply_and_delete_validate_targets(self):
        admin_id = self._register("feedback-admin")
        user_id = self._register("feedback-owner")
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_admin=1 WHERE id=?", (admin_id,))
            db.commit()
        finally:
            db.close()

        created = api.create_feedback(
            api.FeedbackCreate(category="feature", content="希望有小组件预览"),
            user_id=user_id,
        )
        fb_id = created["id"]

        replied = api.reply_feedback(
            api.FeedbackReply(
                feedback_id=fb_id,
                reply=" 已加入排查 ",
                status="in_progress",
            ),
            actor=admin_id,
        )
        self.assertEqual(replied["status"], "ok")
        self.assertEqual(api.my_feedback(user_id=user_id)[0]["admin_reply"], "已加入排查")

        with self.assertRaises(HTTPException) as bad_status:
            api.reply_feedback(
                api.FeedbackReply(
                    feedback_id=fb_id,
                    reply="done",
                    status="invalid",
                ),
                actor=admin_id,
            )
        self.assertEqual(bad_status.exception.status_code, 400)

        api.delete_feedback(fb_id, actor=admin_id)
        with self.assertRaises(HTTPException) as missing:
            api.delete_feedback(fb_id, actor=admin_id)
        self.assertEqual(missing.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
