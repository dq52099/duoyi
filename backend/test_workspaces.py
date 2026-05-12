import os
import tempfile
import unittest

from fastapi import HTTPException

import main as api


class WorkspaceApiTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._old_db_path = api.DB_PATH
        api.DB_PATH = os.path.join(self._tmp.name, "duoyi-test.db")
        api.TOKENS.clear()
        api.init_db()

    def tearDown(self):
        api.DB_PATH = self._old_db_path
        api.TOKENS.clear()
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


if __name__ == "__main__":
    unittest.main()
