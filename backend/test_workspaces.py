import asyncio
import inspect
import json
import os
import tempfile
import unittest
from datetime import timedelta

from fastapi import HTTPException
from fastapi.testclient import TestClient

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

    def test_api_title_uses_duoyi_brand(self):
        self.assertEqual(api.app.title, "多仪 Sync API")

    def test_legacy_password_hash_migrates_on_login(self):
        user_id = self._register("legacy-password")
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET password_hash=? WHERE id=?",
                (api._legacy_hash_password("pass123456"), user_id),
            )
            db.commit()
        finally:
            db.close()

        logged_in = api.login(
            api.LoginRequest(username="legacy-password", password="pass123456")
        )

        self.assertEqual(logged_in["user_id"], user_id)
        db = api.get_db()
        try:
            row = db.execute(
                "SELECT password_hash FROM users WHERE id=?", (user_id,)
            ).fetchone()
        finally:
            db.close()
        self.assertEqual(row["password_hash"], api._hash_password("pass123456"))

    def test_account_email_login_profile_update_and_uniqueness(self):
        registered = api.register(
            api.RegisterRequest(
                username="profile-user",
                password="pass123456",
                email="profile@example.com",
                display_name="资料同学",
            )
        )

        self.assertEqual(registered["email"], "profile@example.com")
        self.assertEqual(registered["display_name"], "资料同学")

        logged_in = api.login(
            api.LoginRequest(username="profile@example.com", password="pass123456")
        )
        self.assertEqual(logged_in["user_id"], registered["user_id"])
        account_login = api.login(
            api.LoginRequest(account="profile-user", password="pass123456")
        )
        self.assertEqual(account_login["user_id"], registered["user_id"])
        email_login = api.login(
            api.LoginRequest(email="profile@example.com", password="pass123456")
        )
        self.assertEqual(email_login["user_id"], registered["user_id"])

        updated = api.update_profile(
            api.ProfileUpdate(
                username="profile-new",
                email="profile-new@example.com",
                display_name="新昵称",
                avatar="https://example.com/avatar.png",
                bio="用邮箱登录的多仪用户",
            ),
            user_id=registered["user_id"],
        )
        self.assertEqual(updated["username"], "profile-new")
        self.assertEqual(updated["email"], "profile-new@example.com")
        self.assertFalse(updated["email_verified"])
        self.assertEqual(updated["avatar"], "https://example.com/avatar.png")
        self.assertEqual(updated["bio"], "用邮箱登录的多仪用户")

        db = api.get_db()
        try:
            with self.assertRaises(HTTPException) as unverified_login_code:
                api._create_email_code(
                    db,
                    email="profile-new@example.com",
                    purpose="login",
                )
            self.assertEqual(unverified_login_code.exception.status_code, 404)
            bind_code = api._create_email_code(
                db,
                email="profile-new@example.com",
                purpose="bind",
                user_id=registered["user_id"],
            )
            db.commit()
        finally:
            db.close()

        verified = api.update_profile(
            api.ProfileUpdate(
                email="profile-new@example.com",
                email_code=bind_code["code"],
            ),
            user_id=registered["user_id"],
        )
        self.assertTrue(verified["email_verified"])

        db = api.get_db()
        try:
            login_code = api._create_email_code(
                db,
                email="profile-new@example.com",
                purpose="login",
            )
            db.commit()
        finally:
            db.close()
        code_logged_in = api.email_login(
            api.EmailLoginRequest(
                email="profile-new@example.com",
                code=login_code["code"],
            )
        )
        self.assertEqual(code_logged_in["user_id"], registered["user_id"])

        me = api.me(user_id=registered["user_id"])
        self.assertEqual(me["username"], "profile-new")
        self.assertEqual(me["display_name"], "新昵称")
        self.assertEqual(me["email"], "profile-new@example.com")
        self.assertTrue(me["email_verified"])
        self.assertEqual(me["avatar"], "https://example.com/avatar.png")
        self.assertEqual(me["bio"], "用邮箱登录的多仪用户")
        self.assertFalse(me["is_disabled"])

        other_id = self._register("profile-other")
        with self.assertRaises(HTTPException) as conflict:
            api.update_profile(
                api.ProfileUpdate(email="profile-new@example.com"),
                user_id=other_id,
            )
        self.assertEqual(conflict.exception.status_code, 409)

    def test_account_mail_defaults_and_registration_email_code_required(self):
        db = api.get_db()
        try:
            runtime = api._account_mail_runtime(db)
            self.assertEqual(runtime["email_code_primary_provider"], "claw163")
            self.assertEqual(runtime["email_code_backup_provider"], "resend")
            api._setting_set(db, "registration_email_required", True)
            code_result = api._create_email_code(
                db,
                email="required@example.com",
                purpose="bind",
            )
            db.commit()
        finally:
            db.close()

        with self.assertRaises(HTTPException) as no_email:
            api.register(
                api.RegisterRequest(
                    username="required-no-email",
                    password="pass123456",
                )
            )
        self.assertEqual(no_email.exception.status_code, 400)

        with self.assertRaises(HTTPException) as no_code:
            api.register(
                api.RegisterRequest(
                    username="required-no-code",
                    password="pass123456",
                    email="required-no-code@example.com",
                )
            )
        self.assertEqual(no_code.exception.status_code, 400)

        registered = api.register(
            api.RegisterRequest(
                username="required-with-code",
                password="pass123456",
                email="required@example.com",
                email_code=code_result["code"],
            )
        )
        self.assertTrue(registered["email_verified"])
        self.assertIn("user", registered)
        self.assertEqual(registered["user"]["username"], "required-with-code")

    def test_re0_registration_aliases_and_public_bootstrap(self):
        db = api.get_db()
        try:
            api._setting_set(db, "allow_public_registration", True)
            api._setting_set(db, "registration_invite_required", True)
            db.execute(
                "INSERT INTO invite_codes(code, note) VALUES(?, ?)",
                ("RE0INVITE", "re0 alias"),
            )
            db.commit()
        finally:
            db.close()

        config = api.public_config()
        self.assertTrue(config["allow_public_registration"])
        self.assertTrue(config["registration_enabled"])
        self.assertTrue(config["registration_invite_required"])
        self.assertTrue(config["invite_code_required"])
        bootstrap = api.bootstrap_config()
        self.assertEqual(bootstrap["app_name"], "多仪")
        self.assertTrue(bootstrap["allow_public_registration"])
        self.assertTrue(bootstrap["registration_invite_required"])

        registered = api.register(
            api.RegisterRequest(
                username="re0-invite-user",
                password="pass123456",
                invitation_code="RE0INVITE",
            )
        )

        self.assertEqual(registered["username"], "re0-invite-user")
        self.assertEqual(registered["user"]["username"], "re0-invite-user")
        db = api.get_db()
        try:
            row = db.execute(
                "SELECT used_by FROM invite_codes WHERE code=?",
                ("RE0INVITE",),
            ).fetchone()
        finally:
            db.close()
        self.assertEqual(row["used_by"], registered["user_id"])

    def test_re0_profile_email_and_avatar_alias_routes(self):
        registered = api.register(
            api.RegisterRequest(username="re0-profile", password="pass123456")
        )
        user_id = registered["user_id"]

        updated = api.update_my_profile(
            api.ProfileUpdate(
                username="re0-profile-new",
                display_name="RE0 用户",
                bio="通过 RE0 资料接口更新",
            ),
            user_id=user_id,
        )
        self.assertEqual(updated["username"], "re0-profile-new")
        self.assertEqual(updated["user"]["display_name"], "RE0 用户")

        db = api.get_db()
        try:
            code_result = api._create_email_code(
                db,
                email="re0-profile@example.com",
                purpose="bind",
                user_id=user_id,
            )
            db.commit()
        finally:
            db.close()

        bound = api.bind_my_email(
            api.EmailLoginRequest(
                email="re0-profile@example.com",
                code=code_result["code"],
            ),
            user_id=user_id,
        )
        self.assertEqual(bound["email"], "re0-profile@example.com")
        self.assertTrue(bound["user"]["email_verified"])

        with TestClient(api.app) as client:
            avatar = client.post(
                "/api/me/avatar",
                headers={"Authorization": f"Bearer {registered['token']}"},
                files={
                    "avatar": (
                        "avatar.png",
                        b"\x89PNG\r\n\x1a\nre0-avatar",
                        "image/png",
                    )
                },
            )
        self.assertEqual(avatar.status_code, 200)
        self.assertIn("/api/uploads/avatars/", avatar.json()["avatar"])
        self.assertEqual(avatar.json()["user"]["avatar"], avatar.json()["avatar"])

    def test_re0_mail_settings_aliases_and_hermes_runtime_status(self):
        admin_id = self._register("settings-admin")
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_admin=1 WHERE id=?", (admin_id,))
            api._setting_set(db, "allow_public_registration", False)
            api._setting_set(db, "registration_invite_required", True)
            api._setting_set(db, "hermes_base_url", "https://hermes.example.test")
            api._setting_set(db, "hermes_api_key", "he_secret")
            runtime = api._account_mail_runtime(db)
            status = api._account_email_runtime_status(runtime)
            db.commit()
        finally:
            db.close()

        self.assertFalse(api.public_config()["allow_public_registration"])
        self.assertTrue(api.public_config()["registration_invite_required"])
        self.assertEqual(runtime["hermes_base_url"], "https://hermes.example.test")
        self.assertEqual(runtime["hermes_api_key"], "he_secret")
        self.assertTrue(status["hermes_configured"])

        settings = api.admin_get_settings(admin_id)
        self.assertTrue(settings["hermes_api_key_set"])
        self.assertIn("***", settings["hermes_api_key"])
        self.assertTrue(settings["hermes_configured"])

    def test_email_code_login_uses_verified_bound_email(self):
        db = api.get_db()
        try:
            code_result = api._create_email_code(
                db,
                email="code-login@example.com",
                purpose="bind",
            )
            db.commit()
        finally:
            db.close()
        registered = api.register(
            api.RegisterRequest(
                username="code-login-user",
                password="pass123456",
                email="code-login@example.com",
                email_code=code_result["code"],
            )
        )
        db = api.get_db()
        try:
            login_code = api._create_email_code(
                db,
                email="code-login@example.com",
                purpose="login",
            )
            db.commit()
        finally:
            db.close()

        logged_in = api.email_login(
            api.EmailLoginRequest(
                email="code-login@example.com",
                code=login_code["code"],
            )
        )

        self.assertEqual(logged_in["user_id"], registered["user_id"])
        self.assertEqual(logged_in["email"], "code-login@example.com")

    def test_password_reset_confirm_accepts_bound_email_code(self):
        registered = api.register(
            api.RegisterRequest(
                username="reset-code-user",
                password="pass123456",
                email="reset-code@example.com",
            )
        )

        sent = []
        old_send = api._send_account_email
        try:
            api._send_account_email = (
                lambda db, **kwargs: sent.append(kwargs)
                or {"sent": True, "provider": "test"}
            )
            result = api.request_password_reset(
                api.PasswordResetRequest(email="reset-code@example.com")
            )
        finally:
            api._send_account_email = old_send

        self.assertTrue(result["ok"])
        token_line = next(
            line for line in sent[0]["body"].splitlines() if "重置验证码：" in line
        )
        code = token_line.split("重置验证码：", 1)[1].strip()

        confirmed = api.confirm_password_reset(
            api.PasswordResetConfirm(
                email="reset-code@example.com",
                code=code,
                password="newpass456",
            )
        )
        self.assertTrue(confirmed["ok"])
        self.assertNotIn(registered["user_id"], api.TOKENS)

        with self.assertRaises(HTTPException) as reused:
            api.confirm_password_reset(
                api.PasswordResetConfirm(token=code, password="newpass789")
            )
        self.assertEqual(reused.exception.status_code, 400)
        self.assertIn("已使用", reused.exception.detail)

        logged_in = api.login(
            api.LoginRequest(username="reset-code@example.com", password="newpass456")
        )
        self.assertEqual(logged_in["user_id"], registered["user_id"])
        self.assertTrue(logged_in["email_verified"])

    def test_password_reset_confirm_accepts_username_and_emailed_code(self):
        registered = api.register(
            api.RegisterRequest(
                username="reset-code-by-user",
                password="pass123456",
                email="reset-code-by-user@example.com",
            )
        )

        sent = []
        old_send = api._send_account_email
        try:
            api._send_account_email = (
                lambda db, **kwargs: sent.append(kwargs)
                or {"sent": True, "provider": "test"}
            )
            result = api.request_password_reset(
                api.PasswordResetRequest(account="reset-code-by-user")
            )
        finally:
            api._send_account_email = old_send

        self.assertTrue(result["ok"])
        self.assertEqual(sent[0]["to_addr"], "reset-code-by-user@example.com")
        token_line = next(
            line for line in sent[0]["body"].splitlines() if "重置验证码：" in line
        )
        code = token_line.split("重置验证码：", 1)[1].strip()

        confirmed = api.confirm_password_reset(
            api.PasswordResetConfirm(
                account="reset-code-by-user",
                code=code,
                password="newpass456",
            )
        )
        self.assertTrue(confirmed["ok"])
        self.assertNotIn(registered["user_id"], api.TOKENS)
        logged_in = api.login(
            api.LoginRequest(account="reset-code-by-user", password="newpass456")
        )
        self.assertEqual(logged_in["user_id"], registered["user_id"])

    def test_change_password_requires_current_password_and_rotates_login(self):
        registered = api.register(
            api.RegisterRequest(username="change-password-user", password="pass123456")
        )

        with self.assertRaises(HTTPException) as wrong_current:
            api.change_password(
                api.ChangePasswordRequest(
                    current_password="wrong-password",
                    new_password="newpass456",
                ),
                user_id=registered["user_id"],
            )
        self.assertEqual(wrong_current.exception.status_code, 403)

        changed = api.change_password(
            api.ChangePasswordRequest(
                current_password="pass123456",
                new_password="newpass456",
            ),
            user_id=registered["user_id"],
        )
        self.assertTrue(changed["ok"])

        with self.assertRaises(HTTPException) as old_password:
            api.login(
                api.LoginRequest(
                    username="change-password-user",
                    password="pass123456",
                )
            )
        self.assertEqual(old_password.exception.status_code, 401)

        logged_in = api.login(
            api.LoginRequest(username="change-password-user", password="newpass456")
        )
        self.assertEqual(logged_in["user_id"], registered["user_id"])

    def test_avatar_upload_updates_profile_and_serves_file(self):
        registered = api.register(
            api.RegisterRequest(username="avatar-user", password="pass123456")
        )
        old_avatar_dir = api.AVATAR_UPLOAD_DIR
        api.AVATAR_UPLOAD_DIR = os.path.join(self._tmp.name, "avatars")
        try:
            with TestClient(api.app) as client:
                response = client.post(
                    "/api/auth/avatar",
                    headers={"Authorization": f"Bearer {registered['token']}"},
                    files={
                        "avatar": (
                            "avatar.png",
                            b"\x89PNG\r\n\x1a\navatar-bytes",
                            "image/png",
                        )
                    },
                )
                self.assertEqual(response.status_code, 200)
                payload = response.json()
                self.assertIn("/api/uploads/avatars/", payload["avatar"])
                avatar_path = api._avatar_file_path_from_url(payload["avatar"])
                self.assertIsNotNone(avatar_path)
                self.assertTrue(avatar_path.exists())

                filename = os.path.basename(str(avatar_path))
                fetched = client.get(f"/api/uploads/avatars/{filename}")
                self.assertEqual(fetched.status_code, 200)
                self.assertEqual(fetched.content, b"\x89PNG\r\n\x1a\navatar-bytes")

                invalid = client.post(
                    "/api/auth/avatar",
                    headers={"Authorization": f"Bearer {registered['token']}"},
                    files={
                        "avatar": (
                            "avatar.png",
                            b"not-a-real-png",
                            "image/png",
                        )
                    },
                )
                self.assertEqual(invalid.status_code, 400)
                self.assertIn("内容与格式不匹配", invalid.json()["detail"])
        finally:
            api.AVATAR_UPLOAD_DIR = old_avatar_dir

    def test_password_reset_request_returns_dev_code_without_mail_provider(self):
        registered = api.register(
            api.RegisterRequest(
                username="reset-dev-user",
                password="pass123456",
                email="reset-dev@example.com",
            )
        )

        result = api.request_password_reset(
            api.PasswordResetRequest(account="reset-dev-user")
        )

        self.assertTrue(result["ok"])
        self.assertTrue(result["dev_code"])
        with TestClient(api.app) as client:
            response = client.post(
                "/api/auth/password-reset",
                json={"account": "reset-dev-user"},
            )
            self.assertEqual(response.status_code, 200)
            self.assertTrue(response.json()["ok"])
            self.assertTrue(response.json()["dev_code"])
        confirmed = api.confirm_password_reset(
            api.PasswordResetConfirm(
                token=result["dev_code"],
                password="newpass456",
            )
        )
        self.assertTrue(confirmed["ok"])
        self.assertNotIn(registered["user_id"], api.TOKENS)
        logged_in = api.login(
            api.LoginRequest(username="reset-dev-user", password="newpass456")
        )
        self.assertEqual(logged_in["user_id"], registered["user_id"])

    def test_password_reset_sends_email_and_changes_password(self):
        registered = api.register(
            api.RegisterRequest(
                username="reset-user",
                password="pass123456",
                email="reset@example.com",
            )
        )
        db = api.get_db()
        try:
            for key, value in {
                "reminder_email_smtp_host": "smtp.example.com",
                "reminder_email_smtp_port": 465,
                "reminder_email_smtp_username": "mailer@example.com",
                "reminder_email_smtp_password": "secret",
                "reminder_email_from": "noreply@example.com",
            }.items():
                api._setting_set(db, key, value)
            db.commit()
        finally:
            db.close()

        sent = []
        old_send = api._smtp_send
        try:
            api._smtp_send = lambda **kwargs: sent.append(kwargs)
            result = api.request_password_reset(
                api.PasswordResetRequest(username="reset@example.com")
            )
        finally:
            api._smtp_send = old_send

        self.assertTrue(result["ok"])
        self.assertEqual(sent[0]["to_addr"], "reset@example.com")
        token_line = next(
            line for line in sent[0]["body"].splitlines() if "重置验证码：" in line
        )
        token = token_line.split("重置验证码：", 1)[1].strip()

        confirmed = api.confirm_password_reset(
            api.PasswordResetConfirm(token=token, password="newpass456")
        )
        self.assertTrue(confirmed["ok"])
        self.assertNotIn(registered["user_id"], api.TOKENS)

        with self.assertRaises(HTTPException) as old_denied:
            api.login(api.LoginRequest(username="reset-user", password="pass123456"))
        self.assertEqual(old_denied.exception.status_code, 401)

        logged_in = api.login(
            api.LoginRequest(username="reset@example.com", password="newpass456")
        )
        self.assertEqual(logged_in["user_id"], registered["user_id"])

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

    def test_workspace_payload_round_trips_goals_and_calendar_events(self):
        owner_id = self._register("workspace-goal-owner")
        member_id = self._register("workspace-goal-member")

        workspace = api.create_workspace(
            api.WorkspaceCreate(name="目标日程共享"), user_id=owner_id
        )
        invite = api.create_workspace_invite(
            workspace["id"],
            api.WorkspaceInviteCreate(role="editor"),
            user_id=owner_id,
        )
        api.accept_workspace_invite(invite["code"], user_id=member_id)

        owner_sync = api.sync(
            api.SyncRequest(
                workspace_payloads={
                    workspace["id"]: {
                        "goals": [
                            {
                                "id": "goal-1",
                                "title": "共享目标",
                                "workspaceId": workspace["id"],
                                "updatedAt": "2026-05-20T00:00:00Z",
                            }
                        ],
                        "calendar_events": [
                            {
                                "id": "event-1",
                                "title": "共享日程",
                                "workspaceId": workspace["id"],
                                "updatedAt": "2026-05-20T00:01:00Z",
                            }
                        ],
                    }
                }
            ),
            user_id=owner_id,
        )

        workspace_payload = owner_sync["workspace_payloads"][workspace["id"]]
        self.assertEqual(workspace_payload["goals"][0]["title"], "共享目标")
        self.assertEqual(
            workspace_payload["calendar_events"][0]["title"], "共享日程"
        )

        member_sync = api.sync(api.SyncRequest(), user_id=member_id)
        member_payload = member_sync["workspace_payloads"][workspace["id"]]

        self.assertEqual(member_payload["goals"][0]["id"], "goal-1")
        self.assertEqual(member_payload["calendar_events"][0]["id"], "event-1")

    def test_viewer_cannot_overwrite_workspace_goals_or_calendar_events(self):
        owner_id = self._register("goal-owner")
        viewer_id = self._register("goal-viewer")

        workspace = api.create_workspace(
            api.WorkspaceCreate(name="只读目标日程"), user_id=owner_id
        )
        invite = api.create_workspace_invite(
            workspace["id"],
            api.WorkspaceInviteCreate(role="viewer"),
            user_id=owner_id,
        )
        api.accept_workspace_invite(invite["code"], user_id=viewer_id)

        api.sync(
            api.SyncRequest(
                workspace_payloads={
                    workspace["id"]: {
                        "goals": [
                            {
                                "id": "goal-1",
                                "title": "owner goal",
                                "updatedAt": "2026-05-20T00:00:00Z",
                            }
                        ],
                        "calendar_events": [
                            {
                                "id": "event-1",
                                "title": "owner event",
                                "updatedAt": "2026-05-20T00:00:00Z",
                            }
                        ],
                    }
                }
            ),
            user_id=owner_id,
        )

        viewer_sync = api.sync(
            api.SyncRequest(
                workspace_payloads={
                    workspace["id"]: {
                        "goals": [
                            {
                                "id": "goal-1",
                                "title": "viewer goal overwrite",
                                "updatedAt": "2026-05-21T00:00:00Z",
                            }
                        ],
                        "calendar_events": [
                            {
                                "id": "event-1",
                                "title": "viewer event overwrite",
                                "updatedAt": "2026-05-21T00:00:00Z",
                            }
                        ],
                    }
                }
            ),
            user_id=viewer_id,
        )

        workspace_payload = viewer_sync["workspace_payloads"][workspace["id"]]
        self.assertEqual(workspace_payload["goals"][0]["title"], "owner goal")
        self.assertEqual(
            workspace_payload["calendar_events"][0]["title"], "owner event"
        )

    def test_sync_round_trips_calendar_events(self):
        user_id = self._register("calendar-sync")

        synced = api.sync(
            api.SyncRequest(
                calendar_events=[
                    {
                        "id": "event-1",
                        "title": "本地日程",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ]
            ),
            user_id=user_id,
        )

        self.assertEqual(synced["calendar_events"][0]["title"], "本地日程")

        round_trip = api.sync(api.SyncRequest(), user_id=user_id)

        self.assertEqual(round_trip["calendar_events"][0]["id"], "event-1")

    def test_workspace_comments_and_activity_feed(self):
        owner_id = self._register("owner")
        member_id = self._register("member")

        workspace = api.create_workspace(
            api.WorkspaceCreate(name="协作空间"), user_id=owner_id
        )
        invite = api.create_workspace_invite(
            workspace["id"],
            api.WorkspaceInviteCreate(role="editor"),
            user_id=owner_id,
        )
        api.accept_workspace_invite(invite["code"], user_id=member_id)

        comment = api.create_workspace_comment(
            workspace["id"],
            api.WorkspaceCommentCreate(body="我来跟进提醒问题", target_id="todo-1"),
            user_id=member_id,
        )
        comments = api.list_workspace_comments(
            workspace["id"],
            target_id="todo-1",
            user_id=owner_id,
        )
        activities = api.list_workspace_activities(
            workspace["id"],
            user_id=owner_id,
        )

        self.assertEqual(comment["body"], "我来跟进提醒问题")
        self.assertEqual(comment["target_id"], "todo-1")
        self.assertEqual(comments[0]["author_user_id"], member_id)
        self.assertTrue(
            any(item["action"] == "workspace.comment" for item in activities)
        )
        self.assertTrue(
            any(
                item["action"] == "workspace.invite.accept"
                for item in activities
            )
        )

    def test_workspace_comment_mentions_create_unread_inbox_items(self):
        owner_id = self._register("mention-owner")
        member_id = self._register("mention-member")

        workspace = api.create_workspace(
            api.WorkspaceCreate(name="提及空间"), user_id=owner_id
        )
        invite = api.create_workspace_invite(
            workspace["id"],
            api.WorkspaceInviteCreate(role="editor"),
            user_id=owner_id,
        )
        api.accept_workspace_invite(invite["code"], user_id=member_id)

        api.create_workspace_comment(
            workspace["id"],
            api.WorkspaceCommentCreate(
                body="@mention-member 请看一下这个提醒问题",
                target_id="todo-mention",
            ),
            user_id=owner_id,
        )
        mentions = api.list_workspace_mentions(user_id=member_id)
        unread_mentions = api.list_workspace_mentions(
            unread_only=True,
            user_id=member_id,
        )

        self.assertEqual(len(mentions), 1)
        self.assertEqual(mentions[0]["workspace_id"], workspace["id"])
        self.assertEqual(mentions[0]["target_id"], "todo-mention")
        self.assertEqual(mentions[0]["author_user_id"], owner_id)
        self.assertIsNone(mentions[0]["read_at"])
        self.assertEqual(len(unread_mentions), 1)

        api.mark_workspace_mention_read(mentions[0]["id"], user_id=member_id)
        self.assertEqual(
            api.list_workspace_mentions(unread_only=True, user_id=member_id),
            [],
        )

    def test_workspace_comment_mentions_send_account_email_when_configured(self):
        owner_id = self._register("mention-mail-owner")
        member_id = self._register("mention-mail-member")
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET email=?, email_verified=1 WHERE id=?",
                ("mention-mail-member@example.com", member_id),
            )
            for key, value in {
                "email_service_enabled": True,
                "email_code_primary_provider": "smtp",
                "email_code_backup_provider": "none",
                "email_smtp_host": "smtp.example.com",
                "email_smtp_port": 465,
                "email_smtp_username": "mailer@example.com",
                "email_smtp_password": "secret",
                "email_smtp_from": "noreply@example.com",
            }.items():
                api._setting_set(db, key, value)
            db.commit()
        finally:
            db.close()

        workspace = api.create_workspace(
            api.WorkspaceCreate(name="邮件提及空间"), user_id=owner_id
        )
        invite = api.create_workspace_invite(
            workspace["id"],
            api.WorkspaceInviteCreate(role="editor"),
            user_id=owner_id,
        )
        api.accept_workspace_invite(invite["code"], user_id=member_id)

        sent = []
        old_send = api._smtp_send
        try:
            api._smtp_send = lambda **kwargs: sent.append(kwargs)
            api.create_workspace_comment(
                workspace["id"],
                api.WorkspaceCommentCreate(
                    body="@mention-mail-member 请处理同步冲突",
                    target_id="todo-mail-mention",
                ),
                user_id=owner_id,
            )
        finally:
            api._smtp_send = old_send

        mentions = api.list_workspace_mentions(user_id=member_id)

        self.assertEqual(len(mentions), 1)
        self.assertEqual(sent[0]["to_addr"], "mention-mail-member@example.com")
        self.assertIn("多仪共享空间提及", sent[0]["subject"])
        self.assertIn("todo-mail-mention", sent[0]["body"])

    def test_workspace_mentions_match_email_display_name_and_dedupe(self):
        owner_id = self._register("mention-alias-owner")
        member_id = self._register("mention-alias-member")
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET email=?, email_verified=1, display_name=? WHERE id=?",
                ("alias.member@example.com", "提及昵称", member_id),
            )
            db.commit()
        finally:
            db.close()

        workspace = api.create_workspace(
            api.WorkspaceCreate(name="别名提及空间"), user_id=owner_id
        )
        invite = api.create_workspace_invite(
            workspace["id"],
            api.WorkspaceInviteCreate(role="editor"),
            user_id=owner_id,
        )
        api.accept_workspace_invite(invite["code"], user_id=member_id)

        api.create_workspace_comment(
            workspace["id"],
            api.WorkspaceCommentCreate(
                body=(
                    "@alias.member@example.com @alias.member "
                    f"@{member_id} @提及昵称 同一个成员只生成一条未读提及"
                ),
                target_id="todo-mention-alias",
            ),
            user_id=owner_id,
        )
        mentions = api.list_workspace_mentions(user_id=member_id)

        self.assertEqual(len(mentions), 1)
        self.assertEqual(mentions[0]["target_id"], "todo-mention-alias")
        self.assertEqual(mentions[0]["author_user_id"], owner_id)

    def test_workspace_mention_email_failure_does_not_block_comment(self):
        owner_id = self._register("mention-fail-owner")
        member_id = self._register("mention-fail-member")
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET email=?, email_verified=1 WHERE id=?",
                ("mention-fail-member@example.com", member_id),
            )
            for key, value in {
                "email_service_enabled": True,
                "email_code_primary_provider": "smtp",
                "email_code_backup_provider": "none",
                "email_smtp_host": "smtp.example.com",
                "email_smtp_port": 465,
                "email_smtp_username": "mailer@example.com",
                "email_smtp_password": "secret",
                "email_smtp_from": "noreply@example.com",
            }.items():
                api._setting_set(db, key, value)
            db.commit()
        finally:
            db.close()

        workspace = api.create_workspace(
            api.WorkspaceCreate(name="失败不阻塞"), user_id=owner_id
        )
        invite = api.create_workspace_invite(
            workspace["id"],
            api.WorkspaceInviteCreate(role="editor"),
            user_id=owner_id,
        )
        api.accept_workspace_invite(invite["code"], user_id=member_id)

        old_send = api._smtp_send
        try:
            api._smtp_send = lambda **kwargs: (_ for _ in ()).throw(
                RuntimeError("smtp down")
            )
            comment = api.create_workspace_comment(
                workspace["id"],
                api.WorkspaceCommentCreate(
                    body="@mention-fail-member 邮件失败也要保留提及",
                    target_id="todo-mention-fail",
                ),
                user_id=owner_id,
            )
        finally:
            api._smtp_send = old_send

        mentions = api.list_workspace_mentions(user_id=member_id)
        comments = api.list_workspace_comments(
            workspace["id"],
            target_id="todo-mention-fail",
            user_id=member_id,
        )
        audit = api.admin_audit_log(
            action="workspace.mention_email.failed",
            limit=10,
            offset=0,
            _=owner_id,
        )

        self.assertEqual(comment["target_id"], "todo-mention-fail")
        self.assertEqual(len(mentions), 1)
        self.assertEqual(comments[0]["id"], comment["id"])
        self.assertEqual(audit["items"][0]["target"], member_id)

    def test_workspace_leaderboard_counts_assigned_completed_todos(self):
        owner_id = self._register("leader-owner")
        member_id = self._register("leader-member")

        workspace = api.create_workspace(
            api.WorkspaceCreate(name="排行空间"), user_id=owner_id
        )
        invite = api.create_workspace_invite(
            workspace["id"],
            api.WorkspaceInviteCreate(role="editor"),
            user_id=owner_id,
        )
        api.accept_workspace_invite(invite["code"], user_id=member_id)

        api.sync(
            api.SyncRequest(
                workspace_payloads={
                    workspace["id"]: {
                        "todos": [
                            {
                                "id": "todo-1",
                                "title": "已完成",
                                "assigneeId": member_id,
                                "isCompleted": True,
                                "updatedAt": "2026-01-01T00:00:00Z",
                            },
                            {
                                "id": "todo-2",
                                "title": "未完成",
                                "assigneeId": member_id,
                                "isCompleted": False,
                                "updatedAt": "2026-01-01T00:00:00Z",
                            },
                            {
                                "id": "todo-3",
                                "title": "owner 完成",
                                "assigneeId": owner_id,
                                "isCompleted": True,
                                "updatedAt": "2026-01-01T00:00:00Z",
                            },
                        ]
                    }
                }
            ),
            user_id=owner_id,
        )

        leaderboard = api.workspace_leaderboard(workspace["id"], user_id=owner_id)
        member = next(item for item in leaderboard if item["user_id"] == member_id)
        owner = next(item for item in leaderboard if item["user_id"] == owner_id)

        self.assertEqual(member["assigned"], 2)
        self.assertEqual(member["completed"], 1)
        self.assertEqual(member["completion_rate"], 0.5)
        self.assertEqual(owner["assigned"], 1)
        self.assertEqual(owner["completed"], 1)

    def test_sync_round_trips_focus_rooms_rewards_and_penalties(self):
        user_id = self._register("focus-sync")

        synced = api.sync(
            api.SyncRequest(
                pomodoro_sessions=[
                    {
                        "id": "focus-1",
                        "durationSeconds": 1500,
                        "focusRoomId": "deep_work_room",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
                focus_penalties=[
                    {
                        "id": "penalty-1",
                        "reason": "leaveApp",
                        "affectedSeconds": 600,
                        "updatedAt": "2026-05-20T00:01:00Z",
                    }
                ],
                virtual_rewards={
                    "balance": 12,
                    "updatedAt": "2026-05-20T00:02:00Z",
                },
                focus_rooms={
                    "activeRoomId": "deep_work_room",
                    "updatedAt": "2026-05-20T00:03:00Z",
                },
                theme_shop_state={
                    "activeCardSkinId": "paper_card",
                    "updatedAt": "2026-05-20T00:04:00Z",
                },
            ),
            user_id=user_id,
        )

        self.assertEqual(synced["pomodoro_sessions"][0]["focusRoomId"], "deep_work_room")
        self.assertEqual(synced["focus_penalties"][0]["reason"], "leaveApp")
        self.assertEqual(synced["virtual_rewards"]["balance"], 12)
        self.assertEqual(synced["focus_rooms"]["activeRoomId"], "deep_work_room")
        self.assertEqual(synced["theme_shop_state"]["activeCardSkinId"], "paper_card")

        round_trip = api.sync(api.SyncRequest(), user_id=user_id)

        self.assertEqual(round_trip["focus_penalties"][0]["id"], "penalty-1")
        self.assertEqual(round_trip["virtual_rewards"]["balance"], 12)
        self.assertEqual(round_trip["focus_rooms"]["activeRoomId"], "deep_work_room")
        self.assertEqual(round_trip["theme_shop_state"]["activeCardSkinId"], "paper_card")

    def test_sync_tombstone_deletes_server_pomodoro_and_time_entry(self):
        user_id = self._register("sync-tombstone")

        api.sync(
            api.SyncRequest(
                pomodoro_sessions=[
                    {
                        "id": "focus-delete",
                        "durationSeconds": 1500,
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
                time_entries=[
                    {
                        "id": "time-delete",
                        "title": "旧专注记录",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
            ),
            user_id=user_id,
        )

        deleted = api.sync(
            api.SyncRequest(
                deleted_items={
                    "pomodoro_sessions": {
                        "focus-delete": "2026-05-20T00:01:00Z",
                    },
                    "time_entries": {
                        "time-delete": "2026-05-20T00:01:00Z",
                    },
                }
            ),
            user_id=user_id,
        )

        self.assertEqual(deleted["pomodoro_sessions"], [])
        self.assertEqual(deleted["time_entries"], [])
        self.assertEqual(
            deleted["deleted_items"]["pomodoro_sessions"]["focus-delete"],
            "2026-05-20T00:01:00Z",
        )

        round_trip = api.sync(api.SyncRequest(), user_id=user_id)
        self.assertEqual(round_trip["pomodoro_sessions"], [])
        self.assertEqual(round_trip["time_entries"], [])

    def test_sync_newer_item_wins_over_older_tombstone(self):
        user_id = self._register("sync-newer-over-tombstone")

        synced = api.sync(
            api.SyncRequest(
                habits=[
                    {
                        "id": "habit-restore",
                        "name": "今天打卡",
                        "completions": {"2026-05-21": 1},
                        "updatedAt": "2026-05-20T00:02:00Z",
                    }
                ],
                deleted_items={
                    "habits": {"habit-restore": "2026-05-20T00:01:00Z"},
                },
            ),
            user_id=user_id,
        )

        self.assertEqual(synced["habits"][0]["id"], "habit-restore")
        self.assertNotIn("habits", synced["deleted_items"])

    def test_sync_user_profile_uses_updated_at_conflict_resolution(self):
        user_id = self._register("sync-profile-updated-at")

        initial = api.sync(
            api.SyncRequest(
                user_profile={
                    "username": "old-name",
                    "displayName": "旧昵称",
                    "updatedAt": "2026-05-20T00:00:00Z",
                }
            ),
            user_id=user_id,
        )
        self.assertEqual(initial["user_profile"]["displayName"], "旧昵称")

        stale = api.sync(
            api.SyncRequest(
                user_profile={
                    "username": "stale-name",
                    "displayName": "过期资料",
                    "updatedAt": "2026-05-19T23:59:00Z",
                }
            ),
            user_id=user_id,
        )
        self.assertEqual(stale["user_profile"]["displayName"], "旧昵称")

        newer = api.sync(
            api.SyncRequest(
                user_profile={
                    "username": "new-name",
                    "displayName": "新昵称",
                    "email": "new@example.com",
                    "updatedAt": "2026-05-20T00:01:00Z",
                }
            ),
            user_id=user_id,
        )
        self.assertEqual(newer["user_profile"]["displayName"], "新昵称")
        self.assertEqual(newer["user_profile"]["email"], "new@example.com")

    def test_sync_status_exposes_lightweight_revision(self):
        user_id = self._register("sync-status-revision")

        before = api.sync_status(user_id=user_id)
        self.assertEqual(before["server_version"], 0)
        self.assertTrue(before["server_updated_at"])

        first = api.sync(
            api.SyncRequest(
                todos=[
                    {
                        "id": "todo-revision",
                        "title": "第一次同步",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ]
            ),
            user_id=user_id,
        )
        self.assertEqual(first["server_version"], 1)
        self.assertTrue(first["server_updated_at"])

        after_first = api.sync_status(user_id=user_id)
        self.assertEqual(after_first["server_version"], first["server_version"])
        self.assertEqual(
            after_first["server_updated_at"],
            first["server_updated_at"],
        )

        second = api.sync(api.SyncRequest(), user_id=user_id)
        self.assertEqual(second["server_version"], first["server_version"] + 1)

        after_second = api.sync_status(user_id=user_id)
        self.assertEqual(after_second["server_version"], second["server_version"])

    def test_sync_pull_returns_only_changed_collections(self):
        user_id = self._register("sync-pull-delta")

        first = api.sync(
            api.SyncRequest(
                todos=[
                    {
                        "id": "todo-delta",
                        "title": "第一次同步",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
                habits=[
                    {
                        "id": "habit-delta",
                        "name": "早睡",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
                user_profile={
                    "displayName": "同步用户",
                    "updatedAt": "2026-05-20T00:00:00Z",
                },
            ),
            user_id=user_id,
        )
        self.assertIn("collection_hashes", first)
        hashes = first["collection_hashes"]

        unchanged = api.sync_pull(
            api.SyncPullRequest(collection_hashes=hashes),
            user_id=user_id,
        )
        self.assertEqual(unchanged["server_version"], first["server_version"])
        self.assertIn("collection_hashes", unchanged)
        self.assertNotIn("todos", unchanged)
        self.assertNotIn("habits", unchanged)
        self.assertNotIn("user_profile", unchanged)

        second = api.sync(
            api.SyncRequest(
                todos=[
                    {
                        "id": "todo-delta",
                        "title": "远端改了待办",
                        "updatedAt": "2026-05-20T00:01:00Z",
                    }
                ],
                habits=[
                    {
                        "id": "habit-delta",
                        "name": "早睡",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
                user_profile={
                    "displayName": "同步用户",
                    "updatedAt": "2026-05-20T00:00:00Z",
                },
            ),
            user_id=user_id,
        )
        changed = api.sync_pull(
            api.SyncPullRequest(collection_hashes=hashes),
            user_id=user_id,
        )

        self.assertEqual(changed["server_version"], second["server_version"])
        self.assertIn("todos", changed)
        self.assertEqual(changed["todos"][0]["title"], "远端改了待办")
        self.assertNotIn("habits", changed)
        self.assertNotIn("user_profile", changed)
        self.assertNotEqual(
            changed["collection_hashes"]["todos"],
            hashes["todos"],
        )
        self.assertEqual(
            changed["collection_hashes"]["habits"],
            hashes["habits"],
        )

    def test_sync_delta_upload_updates_only_changed_collections(self):
        user_id = self._register("sync-delta-upload")

        first = api.sync(
            api.SyncRequest(
                todos=[
                    {
                        "id": "todo-delta-upload",
                        "title": "旧待办",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
                habits=[
                    {
                        "id": "habit-keep",
                        "name": "保留习惯",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
            ),
            user_id=user_id,
        )

        changed = api.sync_delta(
            api.SyncDeltaRequest(
                collections={
                    "todos": [
                        {
                            "id": "todo-delta-upload",
                            "title": "只上传待办变更",
                            "updatedAt": "2026-05-20T00:01:00Z",
                        }
                    ]
                },
                collection_hashes=first["collection_hashes"],
            ),
            user_id=user_id,
        )

        self.assertEqual(changed["todos"][0]["title"], "只上传待办变更")
        self.assertEqual(changed["habits"][0]["id"], "habit-keep")
        self.assertIn("collection_hashes", changed)
        self.assertNotEqual(
            changed["collection_hashes"]["todos"],
            first["collection_hashes"]["todos"],
        )
        self.assertEqual(
            changed["collection_hashes"]["habits"],
            first["collection_hashes"]["habits"],
        )

    def test_sync_item_delta_upload_updates_only_changed_items(self):
        user_id = self._register("sync-item-delta-upload")

        first = api.sync(
            api.SyncRequest(
                todos=[
                    {
                        "id": "todo-item-delta-1",
                        "title": "旧待办 1",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    },
                    {
                        "id": "todo-item-delta-2",
                        "title": "保留待办 2",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    },
                    {
                        "id": "todo-item-delta-remove",
                        "title": "将删除",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    },
                ],
                habits=[
                    {
                        "id": "habit-item-delta-keep",
                        "name": "保留习惯",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
                user_profile={
                    "displayName": "旧资料",
                    "updatedAt": "2026-05-20T00:00:00Z",
                },
            ),
            user_id=user_id,
        )

        changed = api.sync_item_delta(
            api.SyncItemDeltaRequest(
                items={
                    "todos": [
                        {
                            "id": "todo-item-delta-1",
                            "title": "只上传这一条",
                            "updatedAt": "2026-05-20T00:01:00Z",
                        }
                    ]
                },
                objects={
                    "user_profile": {
                        "displayName": "新资料",
                        "updatedAt": "2026-05-20T00:02:00Z",
                    }
                },
                deleted_items={
                    "todos": {
                        "todo-item-delta-remove": "2026-05-20T00:03:00Z"
                    }
                },
                collection_hashes=first["collection_hashes"],
            ),
            user_id=user_id,
        )

        todos = {item["id"]: item for item in changed["todos"]}
        self.assertEqual(todos["todo-item-delta-1"]["title"], "只上传这一条")
        self.assertEqual(todos["todo-item-delta-2"]["title"], "保留待办 2")
        self.assertNotIn("todo-item-delta-remove", todos)
        self.assertEqual(changed["habits"][0]["id"], "habit-item-delta-keep")
        self.assertEqual(changed["user_profile"]["displayName"], "新资料")
        self.assertIn("collection_hashes", changed)
        self.assertNotEqual(
            changed["collection_hashes"]["todos"],
            first["collection_hashes"]["todos"],
        )
        self.assertEqual(
            changed["collection_hashes"]["habits"],
            first["collection_hashes"]["habits"],
        )

    def test_sync_timestamp_merge_parses_timezone_offsets(self):
        user_id = self._register("sync-timezone-merge")

        first = api.sync(
            api.SyncRequest(
                user_profile={
                    "displayName": "北京时间旧资料",
                    "updatedAt": "2026-05-20T23:00:00+08:00",
                },
                habits=[
                    {
                        "id": "habit-zone",
                        "name": "旧习惯",
                        "updatedAt": "2026-05-20T23:00:00+08:00",
                    }
                ],
            ),
            user_id=user_id,
        )
        self.assertEqual(first["user_profile"]["displayName"], "北京时间旧资料")
        self.assertEqual(first["habits"][0]["name"], "旧习惯")

        newer = api.sync(
            api.SyncRequest(
                user_profile={
                    "displayName": "UTC 新资料",
                    "updatedAt": "2026-05-20T16:00:00Z",
                },
                habits=[
                    {
                        "id": "habit-zone",
                        "name": "新习惯",
                        "updatedAt": "2026-05-20T16:00:00Z",
                    }
                ],
            ),
            user_id=user_id,
        )

        self.assertEqual(newer["user_profile"]["displayName"], "UTC 新资料")
        self.assertEqual(newer["habits"][0]["name"], "新习惯")

    def test_sync_events_streams_revision_sse(self):
        user_id = self._register("sync-events")
        synced = api.sync(
            api.SyncRequest(
                user_profile={
                    "displayName": "实时同步同学",
                    "updatedAt": "2026-05-22T00:00:00Z",
                },
            ),
            user_id=user_id,
        )

        async def first_event():
            response = await api.sync_events(interval_seconds=2, user_id=user_id)
            stream = response.body_iterator
            try:
                chunk = await stream.__anext__()
            finally:
                await stream.aclose()
            return response, chunk

        response, chunk = asyncio.run(first_event())
        text = chunk.decode("utf-8") if isinstance(chunk, bytes) else chunk
        data_line = next(line for line in text.splitlines() if line.startswith("data: "))
        payload = json.loads(data_line.removeprefix("data: "))

        self.assertEqual(response.media_type, "text/event-stream")
        self.assertEqual(response.headers["cache-control"], "no-cache")
        self.assertEqual(response.headers["x-accel-buffering"], "no")
        self.assertIn("event: sync", text)
        self.assertEqual(payload["server_version"], synced["server_version"])
        self.assertEqual(
            payload["server_updated_at"],
            synced["server_updated_at"],
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

        active_users = api.admin_list_users(_=admin_id, limit=100, offset=0)["items"]
        target = next(u for u in active_users if u["user_id"] == user_id)
        self.assertTrue(target["online"])
        self.assertIsNotNone(target["last_login_at"])
        self.assertIsNotNone(target["last_active_at"])
        self.assertTrue(target["last_login_at"].endswith("Z"))
        self.assertTrue(target["last_active_at"].endswith("Z"))
        self.assertIsNotNone(api._parse_server_time(target["last_login_at"]))
        self.assertIsNotNone(api._parse_server_time(target["last_active_at"]))

        stale_at = api._utc_now() - timedelta(
            seconds=api.SESSION_ONLINE_SECONDS + 1,
        )
        api.TOKEN_LAST_ACTIVE[user_id] = stale_at
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET last_active_at=? WHERE id=?",
                (api._format_utc(stale_at), user_id),
            )
            db.commit()
        finally:
            db.close()

        stale_users = api.admin_list_users(_=admin_id, limit=100, offset=0)["items"]
        target = next(u for u in stale_users if u["user_id"] == user_id)
        self.assertFalse(target["online"])
        self.assertEqual(target["last_active_at"], api._format_utc(stale_at))

    def test_admin_stats_active_7d_uses_login_or_activity_timestamps(self):
        admin_id = self._register("active-admin")
        recent_user_id = self._register("active-recent")
        stale_user_id = self._register("active-stale")
        stale_at = api._utc_now() - timedelta(days=8)
        recent_at = api._utc_now() - timedelta(days=1)
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET is_admin=1, last_login_at=?, last_active_at=? WHERE id=?",
                (api._format_utc(stale_at), api._format_utc(stale_at), admin_id),
            )
            db.execute(
                "UPDATE users SET last_login_at=?, last_active_at=? WHERE id=?",
                (api._format_utc(stale_at), api._format_utc(recent_at), recent_user_id),
            )
            db.execute(
                "UPDATE users SET last_login_at=?, last_active_at=? WHERE id=?",
                (api._format_utc(stale_at), api._format_utc(stale_at), stale_user_id),
            )
            db.commit()
        finally:
            db.close()

        stats = api.admin_stats(_=admin_id)

        self.assertEqual(stats["users"]["active_7d"], 1)

    def test_admin_large_data_lists_return_paged_responses(self):
        admin_id = self._register("paged-admin")
        user_ids = [self._register(f"paged-user-{i}") for i in range(4)]
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_admin=1 WHERE id=?", (admin_id,))
            db.executemany(
                "UPDATE sync_data SET sync_version=?, updated_at=? WHERE user_id=?",
                [
                    (i + 1, api._utc_now_text(), user_id)
                    for i, user_id in enumerate(user_ids)
                ],
            )
            for i in range(4):
                db.execute(
                    "INSERT INTO announcements(title, body, level, published) "
                    "VALUES(?,?,?,?)",
                    (f"公告 {i}", f"内容 {i}", "info", 1),
                )
                db.execute(
                    "INSERT INTO feedback(user_id, category, content, status) "
                    "VALUES(?,?,?,?)",
                    (user_ids[i], "bug", f"反馈 {i}", "open"),
                )
                db.execute(
                    "INSERT INTO invite_codes(code, note) VALUES(?, ?)",
                    (f"INVITE-{i}", f"note {i}"),
                )
                db.execute(
                    "INSERT INTO server_backups(id, filename, size_bytes, status) "
                    "VALUES(?,?,?,?)",
                    (f"backup-{i}", f"duoyi_backup_{i}.zip", 1024 + i, "created"),
                )
                db.execute(
                    "INSERT INTO audit_log(actor_id, actor_name, action, target, detail) "
                    "VALUES(?,?,?,?,?)",
                    (admin_id, "paged-admin", "feedback.reply", f"fb-{i}", f"反馈处理 {i}"),
                )
            db.executemany(
                "UPDATE sync_data SET sync_version=?, updated_at=? WHERE user_id=?",
                [
                    (i + 1, f"2024-01-0{i + 1}T00:00:00Z", user_ids[i])
                    for i in range(4)
                ],
            )
            db.commit()
        finally:
            db.close()

        def assert_page(page, *, total=None):
            self.assertEqual(set(page.keys()), {"items", "total", "limit", "offset", "has_more"})
            self.assertEqual(page["limit"], 2)
            self.assertEqual(page["offset"], 1)
            self.assertEqual(len(page["items"]), 2)
            self.assertTrue(page["has_more"])
            if total is not None:
                self.assertEqual(page["total"], total)

        assert_page(api.admin_list_users(_=admin_id, limit=2, offset=1))
        assert_page(api.admin_backups(_=admin_id, limit=2, offset=1))
        assert_page(
            api.admin_backups(_=admin_id, status="synced", limit=2, offset=1)
        )
        assert_page(api.admin_server_backups(_=admin_id, limit=2, offset=1), total=4)
        assert_page(
            api.admin_server_backups(
                _=admin_id, status="created", limit=2, offset=1
            ),
            total=4,
        )
        assert_page(api.admin_list_announcements(_=admin_id, limit=2, offset=1), total=4)
        assert_page(api.list_all_feedback(_=admin_id, limit=2, offset=1), total=4)
        assert_page(api.list_invite_codes(_=admin_id, limit=2, offset=1), total=4)
        assert_page(api.admin_audit_log(_=admin_id, q="反馈处理", limit=2, offset=1), total=4)

    def test_admin_user_filters_support_operational_segments(self):
        admin_id = self._register("segment-admin")
        online_user = self._register("segment-online")
        offline_user = self._register("segment-offline")
        feedback_user = self._register("segment-feedback")
        no_email_user = self._register("segment-no-email")
        unverified_user = api.register(
            api.RegisterRequest(
                username="segment-unverified",
                password="pass123456",
                email="segment-unverified@example.com",
            )
        )["user_id"]
        verified_user = api.register(
            api.RegisterRequest(
                username="segment-verified",
                password="pass123456",
                email="segment-verified@example.com",
            )
        )["user_id"]
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_admin=1 WHERE id=?", (admin_id,))
            db.execute(
                "UPDATE users SET email_verified=1 WHERE id=?",
                (verified_user,),
            )
            db.execute(
                "INSERT INTO feedback(user_id, category, content, status) VALUES(?,?,?,?)",
                (feedback_user, "bug", "需要帮助", "open"),
            )
            db.commit()
        finally:
            db.close()

        api._drop_session(offline_user)
        api._drop_session(no_email_user)

        online_page = api.admin_list_users(_=admin_id, online=True, limit=100, offset=0)
        online_ids = {row["user_id"] for row in online_page["items"]}
        self.assertIn(online_user, online_ids)
        self.assertNotIn(offline_user, online_ids)

        offline_page = api.admin_list_users(
            _=admin_id, online=False, limit=100, offset=0
        )
        offline_ids = {row["user_id"] for row in offline_page["items"]}
        self.assertIn(offline_user, offline_ids)
        self.assertNotIn(online_user, offline_ids)

        unverified = api.admin_list_users(
            _=admin_id, status="unverified_email", limit=100, offset=0
        )["items"]
        self.assertEqual([row["user_id"] for row in unverified], [unverified_user])

        verified = api.admin_list_users(
            _=admin_id, status="verified_email", limit=100, offset=0
        )["items"]
        self.assertEqual([row["user_id"] for row in verified], [verified_user])

        no_email = api.admin_list_users(
            _=admin_id, status="no_email", q="segment-no-email", limit=100, offset=0
        )["items"]
        self.assertEqual([row["user_id"] for row in no_email], [no_email_user])

        has_feedback = api.admin_list_users(
            _=admin_id, status="has_feedback", limit=100, offset=0
        )["items"]
        self.assertEqual([row["user_id"] for row in has_feedback], [feedback_user])

        sorted_by_email = api.admin_list_users(
            _=admin_id, q="segment-", sort="email_asc", limit=100, offset=0
        )["items"]
        emails = [row["email"] for row in sorted_by_email if row["email"]]
        self.assertEqual(emails, sorted(emails, key=str.lower))

    def test_admin_user_export_online_filter_and_bulk_status(self):
        admin_id = self._register("bulk-admin")
        online_user = self._register("bulk-online")
        offline_user = self._register("bulk-offline")
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_admin=1 WHERE id=?", (admin_id,))
            db.commit()
        finally:
            db.close()
        api._drop_session(offline_user)

        with TestClient(api.app) as client:
            exported = client.get(
                "/api/admin/users/export.csv",
                params={"online": "true", "q": "bulk-", "sort": "username_asc"},
                headers={"Authorization": f"Bearer {api.TOKENS[admin_id]}"},
            )
            bulk = client.post(
                "/api/admin/users/bulk-status",
                json={"user_ids": [online_user, offline_user, online_user], "is_disabled": True},
                headers={"Authorization": f"Bearer {api.TOKENS[admin_id]}"},
            )

        self.assertEqual(exported.status_code, 200)
        text = exported.content.decode("utf-8-sig")
        self.assertIn("bulk-online", text)
        self.assertNotIn("bulk-offline", text)
        self.assertEqual(bulk.status_code, 200)
        self.assertEqual(bulk.json()["updated"], 2)
        self.assertNotIn(online_user, api.TOKENS)
        self.assertNotIn(offline_user, api.TOKENS)

        db = api.get_db()
        try:
            rows = db.execute(
                "SELECT id, is_disabled FROM users WHERE id IN (?, ?)",
                (online_user, offline_user),
            ).fetchall()
            audit = db.execute(
                "SELECT action, detail FROM audit_log WHERE action='user.bulk_status'"
            ).fetchone()
        finally:
            db.close()
        self.assertEqual({row["id"]: row["is_disabled"] for row in rows}, {
            online_user: 1,
            offline_user: 1,
        })
        self.assertIsNotNone(audit)
        self.assertIn('"count": 2', audit["detail"])

        restored = api.admin_bulk_update_user_status(
            api.UserBulkStatus(user_ids=[online_user, offline_user], is_disabled=False),
            actor=admin_id,
        )
        self.assertEqual(restored["updated"], 2)

    def test_admin_large_data_lists_support_sort_contracts(self):
        admin_id = self._register("admin-sort")
        user_a = self._register("sort-user-a")
        user_b = self._register("sort-user-b")
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_admin=1 WHERE id=?", (admin_id,))
            db.execute(
                "UPDATE sync_data SET sync_version=1 WHERE user_id IN (?, ?)",
                (user_a, user_b),
            )
            db.execute(
                "INSERT INTO announcements(title, body, level, published) VALUES(?,?,?,?)",
                ("普通公告", "内容", "info", 1),
            )
            db.execute(
                "INSERT INTO announcements(title, body, level, published) VALUES(?,?,?,?)",
                ("紧急公告", "内容", "critical", 1),
            )
            db.execute(
                "INSERT INTO feedback(user_id, category, content, status, updated_at) VALUES(?,?,?,?,?)",
                (user_a, "bug", "稍后处理", "resolved", "2024-01-01T00:00:00Z"),
            )
            db.execute(
                "INSERT INTO feedback(user_id, category, content, status, updated_at) VALUES(?,?,?,?,?)",
                (user_b, "bug", "先处理", "open", "2024-01-02T00:00:00Z"),
            )
            db.execute(
                "INSERT INTO invite_codes(code, note, used_by, used_at) VALUES(?,?,?,?)",
                ("ZZZ-CODE", "late", user_a, "2024-01-02T00:00:00Z"),
            )
            db.execute(
                "INSERT INTO invite_codes(code, note) VALUES(?,?)",
                ("AAA-CODE", "early"),
            )
            db.execute(
                "INSERT INTO server_backups(id, filename, size_bytes, status) VALUES(?,?,?,?)",
                ("server-z", "z-backup.zip", 2048, "uploaded"),
            )
            db.execute(
                "INSERT INTO server_backups(id, filename, size_bytes, status) VALUES(?,?,?,?)",
                ("server-a", "a-backup.zip", 1024, "local_only"),
            )
            db.execute(
                "INSERT INTO audit_log(actor_id, actor_name, action, target, detail) VALUES(?,?,?,?,?)",
                (admin_id, "z-admin", "user.update", "z-target", ""),
            )
            db.execute(
                "INSERT INTO audit_log(actor_id, actor_name, action, target, detail) VALUES(?,?,?,?,?)",
                (admin_id, "a-admin", "announcement.update", "a-target", ""),
            )
            db.commit()
        finally:
            db.close()

        announcements = api.admin_list_announcements(
            _=admin_id, sort="level_desc", limit=10, offset=0
        )["items"]
        self.assertEqual(announcements[0]["level"], "critical")

        backups = api.admin_backups(
            _=admin_id, q="sort-user", sort="username_asc", limit=10, offset=0
        )["items"]
        self.assertEqual([row["username"] for row in backups], ["sort-user-a", "sort-user-b"])
        self.assertTrue(all(row["has_snapshot"] for row in backups))
        self.assertTrue(all(row["sync_version"] >= 0 for row in backups))

        server_backups = api.admin_server_backups(
            _=admin_id, sort="filename_asc", limit=10, offset=0
        )["items"]
        self.assertEqual(server_backups[0]["filename"], "a-backup.zip")

        feedback = api.list_all_feedback(
            _=admin_id, sort="status_asc", limit=10, offset=0
        )["items"]
        self.assertEqual(feedback[0]["status"], "open")

        invites = api.list_invite_codes(
            _=admin_id, sort="code_asc", limit=10, offset=0
        )["items"]
        self.assertEqual(invites[0]["code"], "AAA-CODE")

        audit = api.admin_audit_log(
            _=admin_id, sort="actor_asc", limit=10, offset=0
        )["items"]
        self.assertEqual(audit[0]["actor_name"], "a-admin")

    def test_admin_backups_searches_identity_and_uses_real_snapshot_status(self):
        admin_id = self._register("backup-search-admin")
        empty_user = api.register(
            api.RegisterRequest(
                username="backup-empty",
                password="pass123456",
                email="backup-empty@example.com",
                display_name="空备份",
            )
        )["user_id"]
        synced_user = api.register(
            api.RegisterRequest(
                username="backup-synced",
                password="pass123456",
                email="backup-synced@example.com",
                display_name="有备份",
            )
        )["user_id"]
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_admin=1 WHERE id=?", (admin_id,))
            db.execute(
                "UPDATE sync_data SET sync_version=0, updated_at=? WHERE user_id=?",
                (api._format_utc(api._utc_now() - timedelta(days=2)), empty_user),
            )
            db.execute(
                "UPDATE sync_data SET sync_version=9, todos=?, updated_at=? WHERE user_id=?",
                ('[{"id":"todo-1","title":"x"}]', api._utc_now_text(), synced_user),
            )
            db.commit()
        finally:
            db.close()

        email_match = api.admin_backups(
            _=admin_id, q="backup-synced@example.com", limit=10, offset=0
        )["items"]
        self.assertEqual([row["user_id"] for row in email_match], [synced_user])
        self.assertEqual(email_match[0]["display_name"], "有备份")

        empty = api.admin_backups(_=admin_id, status="empty", limit=100, offset=0)[
            "items"
        ]
        empty_ids = {row["user_id"] for row in empty}
        self.assertIn(empty_user, empty_ids)
        self.assertNotIn(synced_user, empty_ids)

        synced = api.admin_backups(
            _=admin_id, status="synced", sort="version_desc", limit=100, offset=0
        )["items"]
        synced_ids = {row["user_id"] for row in synced}
        self.assertIn(synced_user, synced_ids)
        self.assertNotIn(empty_user, synced_ids)
        self.assertEqual(synced[0]["sync_version"], 9)
        self.assertTrue(synced[0]["has_snapshot"])

    def test_admin_backup_exports_use_filters_and_escape_formulas(self):
        admin_id = self._register("backup-export-admin")
        user_id = api.register(
            api.RegisterRequest(
                username="=backup-export-user",
                password="pass123456",
                email="backup-export@example.com",
                display_name="+导出用户",
            )
        )["user_id"]
        api.register(
            api.RegisterRequest(username="backup-export-empty", password="pass123456")
        )
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_admin=1 WHERE id=?", (admin_id,))
            db.execute(
                "UPDATE sync_data SET sync_version=11, todos=?, updated_at=? WHERE user_id=?",
                ('[{"id":"todo-1","title":"x"}]', api._utc_now_text(), user_id),
            )
            db.execute(
                "INSERT INTO server_backups(id, filename, size_bytes, status, detail, remote_url, local_path) "
                "VALUES(?,?,?,?,?,?,?)",
                (
                    "server-export-1",
                    "=server-backup.zip",
                    2048,
                    "uploaded",
                    "+uploaded",
                    "https://example.com/backup.zip",
                    "/tmp/backup.zip",
                ),
            )
            db.execute(
                "INSERT INTO server_backups(id, filename, size_bytes, status, detail) "
                "VALUES(?,?,?,?,?)",
                ("server-export-2", "local.zip", 1024, "local_only", "local"),
            )
            db.commit()
        finally:
            db.close()

        with TestClient(api.app) as client:
            backup_response = client.get(
                "/api/admin/backups/export.csv",
                params={
                    "status": "synced",
                    "q": "backup-export@example.com",
                    "sort": "version_desc",
                },
                headers={"Authorization": f"Bearer {api.TOKENS[admin_id]}"},
            )
            self.assertEqual(backup_response.status_code, 200)
            self.assertEqual(backup_response.headers["X-Total-Count"], "1")
            backup_csv = backup_response.text
            self.assertIn("user_id,username,email,display_name", backup_csv)
            self.assertIn("'=backup-export-user", backup_csv)
            self.assertIn("'+导出用户", backup_csv)
            self.assertIn(",11,1,", backup_csv)

            server_response = client.get(
                "/api/admin/server-backups/export.csv",
                params={
                    "status": "uploaded",
                    "q": "server-backup",
                    "sort": "filename_asc",
                },
                headers={"Authorization": f"Bearer {api.TOKENS[admin_id]}"},
            )
            self.assertEqual(server_response.status_code, 200)
            self.assertEqual(server_response.headers["X-Total-Count"], "1")
            server_csv = server_response.text
            self.assertIn("id,filename,size_bytes,status", server_csv)
            self.assertIn("'=server-backup.zip", server_csv)
            self.assertIn("'+uploaded", server_csv)

        db = api.get_db()
        try:
            actions = [
                row["action"]
                for row in db.execute(
                    "SELECT action FROM audit_log WHERE actor_id=? ORDER BY id",
                    (admin_id,),
                ).fetchall()
            ]
            self.assertIn("backup.export", actions)
            self.assertIn("server_backup.export", actions)
        finally:
            db.close()

    def test_admin_feedback_export_csv_uses_filters_and_escapes_formulas(self):
        admin_id = self._register("feedback-export-admin")
        user_a = self._register("feedback-export-a")
        user_b = self._register("feedback-export-b")
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_admin=1 WHERE id=?", (admin_id,))
            db.execute(
                "INSERT INTO feedback(user_id, category, content, status, admin_reply) "
                "VALUES(?,?,?,?,?)",
                (user_a, "bug", "=IMPORTXML(\"http://bad\")", "open", "+handled"),
            )
            db.execute(
                "INSERT INTO feedback(user_id, category, content, status, admin_reply) "
                "VALUES(?,?,?,?,?)",
                (user_b, "wish", "普通愿望", "resolved", "已处理"),
            )
            db.commit()
        finally:
            db.close()

        with TestClient(api.app) as client:
            response = client.get(
                "/api/admin/feedback/export.csv",
                params={
                    "status": "open",
                    "category": "bug",
                    "q": "IMPORTXML",
                    "sort": "status_asc",
                },
                headers={"Authorization": f"Bearer {api.TOKENS[admin_id]}"},
            )

        self.assertEqual(response.status_code, 200)
        self.assertIn("text/csv", response.headers["content-type"])
        self.assertEqual(response.headers["x-total-count"], "1")
        self.assertEqual(response.headers["x-exported-count"], "1")
        text = response.content.decode("utf-8-sig")
        self.assertIn("id,username,category,status,content,admin_reply", text)
        self.assertIn("feedback-export-a", text)
        self.assertIn("'=IMPORTXML", text)
        self.assertIn("'+handled", text)
        self.assertNotIn("普通愿望", text)

        db = api.get_db()
        try:
            audit = db.execute(
                "SELECT action, detail FROM audit_log WHERE action='feedback.export'"
            ).fetchone()
        finally:
            db.close()
        self.assertIsNotNone(audit)
        self.assertIn('"rows": 1', audit["detail"])
        self.assertIn('"total": 1', audit["detail"])

    def test_admin_large_data_indexes_and_stats_are_sql_backed(self):
        db = api.get_db()
        try:
            index_rows = db.execute(
                "SELECT name FROM sqlite_master WHERE type='index'"
            ).fetchall()
        finally:
            db.close()
        index_names = {row["name"] for row in index_rows}

        self.assertTrue(
            {
                "idx_users_created_at",
                "idx_users_admin_disabled_created",
                "idx_users_last_login_at",
                "idx_users_last_active_at",
                "idx_feedback_status_category_id",
                "idx_feedback_user_id",
                "idx_announcements_published_level_id",
                "idx_invite_codes_used_created",
                "idx_audit_log_action_id",
                "idx_server_backups_status_created",
                "idx_sync_data_updated_at",
            }.issubset(index_names)
        )

        stats_source = inspect.getsource(api.admin_stats)
        self.assertIn("SELECT COUNT(*) AS c FROM users", stats_source)
        self.assertIn("SELECT COUNT(*) AS c FROM feedback", stats_source)
        self.assertIn("SELECT COUNT(*) AS c FROM announcements", stats_source)
        self.assertIn("SELECT COUNT(*) AS c FROM invite_codes", stats_source)
        self.assertNotIn("FROM sync_data", stats_source)
        self.assertNotIn("json.loads", stats_source)

    def test_admin_online_status_turns_off_after_logout(self):
        admin_id = self._register("admin-logout")
        user_id = self._register("normal-logout")
        token = api.TOKENS[user_id]
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_admin=1 WHERE id=?", (admin_id,))
            db.commit()
        finally:
            db.close()

        before_logout = api.admin_list_users(_=admin_id, limit=100, offset=0)["items"]
        target = next(u for u in before_logout if u["user_id"] == user_id)
        self.assertTrue(target["online"])

        api.logout(user_id=api._verify_token(f"Bearer {token}"))

        after_logout = api.admin_list_users(_=admin_id, limit=100, offset=0)["items"]
        target = next(u for u in after_logout if u["user_id"] == user_id)
        self.assertFalse(target["online"])
        self.assertNotIn(user_id, api.TOKENS)
        self.assertNotIn(user_id, api.TOKEN_LAST_ACTIVE)

    def test_verify_token_persists_last_active_at(self):
        user_id = self._register("active-persist")
        token = api.TOKENS[user_id]

        db = api.get_db()
        try:
            before = db.execute(
                "SELECT last_active_at FROM users WHERE id=?", (user_id,)
            ).fetchone()["last_active_at"]
        finally:
            db.close()

        verified = api._verify_token(f"Bearer {token}")

        db = api.get_db()
        try:
            after = db.execute(
                "SELECT last_active_at FROM users WHERE id=?", (user_id,)
            ).fetchone()["last_active_at"]
        finally:
            db.close()

        self.assertEqual(verified, user_id)
        self.assertIsNotNone(after)
        if before is not None:
            self.assertIsNotNone(api._parse_server_time(before))

    def test_email_reminder_job_dispatches_through_smtp_config(self):
        user_id = self._register("reminder@example.com")
        db = api.get_db()
        try:
            for key, value in {
                "reminder_email_enabled": True,
                "reminder_email_smtp_host": "smtp.example.com",
                "reminder_email_smtp_port": 465,
                "reminder_email_smtp_username": "mailer@example.com",
                "reminder_email_smtp_password": "secret",
                "reminder_email_from": "noreply@example.com",
            }.items():
                api._setting_set(db, key, value)
            db.commit()
        finally:
            db.close()

        scheduled = api.schedule_email_reminder_once(
            api.ReminderEmailOnceRequest(
                id=8801,
                title="待办提醒",
                body="检查邮件提醒链路",
                when="2026-01-01T00:00:00Z",
                payload="duoyi://todo/1",
            ),
            user_id=user_id,
        )
        self.assertEqual(scheduled["reminder_id"], 8801)

        sent = []
        old_send = api._smtp_send
        try:
            api._smtp_send = lambda **kwargs: sent.append(kwargs)
            count = api.dispatch_due_reminder_emails()
        finally:
            api._smtp_send = old_send

        self.assertEqual(count, 1)
        self.assertEqual(sent[0]["to_addr"], "reminder@example.com")
        self.assertEqual(sent[0]["subject"], "待办提醒")

        db = api.get_db()
        try:
            row = db.execute(
                "SELECT sent_at, next_send_at, cancelled FROM reminder_email_jobs WHERE id=?",
                (scheduled["id"],),
            ).fetchone()
        finally:
            db.close()
        self.assertIsNotNone(row["sent_at"])
        self.assertIsNone(row["next_send_at"])
        self.assertEqual(row["cancelled"], 0)

    def test_email_reminder_repeating_and_cancel_are_user_scoped(self):
        user_id = self._register("plain-user")
        scheduled = api.schedule_email_reminder_repeating(
            api.ReminderEmailRepeatingRequest(
                id=9902,
                title="每周提醒",
                body="周计划",
                hour=9,
                minute=30,
                weekdays=[1, 3, 8],
            ),
            user_id=user_id,
        )
        self.assertEqual(scheduled["schedule_kind"], "repeating")

        cancelled = api.cancel_email_reminder(9902, user_id=user_id)
        self.assertEqual(cancelled["id"], scheduled["id"])

        db = api.get_db()
        try:
            row = db.execute(
                "SELECT cancelled, next_send_at, weekdays_json FROM reminder_email_jobs WHERE id=?",
                (scheduled["id"],),
            ).fetchone()
        finally:
            db.close()
        self.assertEqual(row["cancelled"], 1)
        self.assertIsNone(row["next_send_at"])
        self.assertEqual(row["weekdays_json"], "[1, 3]")

    def test_admin_can_send_reminder_email_test_message(self):
        admin_id = self._register("admin-reminder@example.com")
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_admin=1 WHERE id=?", (admin_id,))
            for key, value in {
                "reminder_email_enabled": True,
                "reminder_email_smtp_host": "smtp.example.com",
                "reminder_email_smtp_port": 465,
                "reminder_email_smtp_username": "mailer@example.com",
                "reminder_email_smtp_password": "secret",
                "reminder_email_from": "noreply@example.com",
            }.items():
                api._setting_set(db, key, value)
            db.commit()
        finally:
            db.close()

        sent = []
        old_send = api._smtp_send
        try:
            api._smtp_send = lambda **kwargs: sent.append(kwargs)
            result = api.admin_reminder_email_test(actor=admin_id)
        finally:
            api._smtp_send = old_send

        self.assertTrue(result["ok"])
        self.assertEqual(result["recipient"], "admin-reminder@example.com")
        self.assertEqual(sent[0]["subject"], "多仪邮件提醒测试")
        self.assertIn("SMTP 投递配置可用", sent[0]["body"])

    def test_admin_can_send_account_email_test_message(self):
        admin_id = self._register("admin-account@example.com")
        fallback_admin_id = self._register("account-mail-admin")
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET is_admin=1 WHERE id IN (?, ?)",
                (admin_id, fallback_admin_id),
            )
            for key, value in {
                "email_service_enabled": True,
                "email_code_primary_provider": "smtp",
                "email_code_backup_provider": "none",
                "email_code_active_slot": "primary",
                "email_smtp_host": "smtp.example.com",
                "email_smtp_port": 465,
                "email_smtp_username": "mailer@example.com",
                "email_smtp_password": "secret",
                "email_smtp_from": "noreply@example.com",
                "system_notice_email_to": "bad-address ops@example.com",
            }.items():
                api._setting_set(db, key, value)
            db.commit()
        finally:
            db.close()

        sent = []
        old_send = api._smtp_send
        try:
            api._smtp_send = lambda **kwargs: sent.append(kwargs)
            result = api.admin_account_email_test(actor=admin_id)
            fallback = api.admin_account_email_test(actor=fallback_admin_id)
        finally:
            api._smtp_send = old_send

        self.assertTrue(result["ok"])
        self.assertEqual(result["recipient"], "admin-account@example.com")
        self.assertEqual(result["provider"], "smtp")
        self.assertEqual(result["slot"], "primary")
        self.assertEqual(sent[0]["subject"], "多仪账号邮件测试")
        self.assertEqual(sent[0]["to_addr"], "admin-account@example.com")
        self.assertIn("noreply@example.com", sent[0]["from_addr"])
        self.assertIn("账号验证码邮件通道可用", sent[0]["body"])

        self.assertTrue(fallback["ok"])
        self.assertEqual(fallback["recipient"], "ops@example.com")
        self.assertEqual(sent[1]["to_addr"], "ops@example.com")

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

        second = api.create_feedback(
            api.FeedbackCreate(category="bug", content="通知没有声音"),
            user_id=user_id,
        )
        bulk = api.bulk_update_feedback_status(
            api.FeedbackBulkStatus(
                feedback_ids=[fb_id, second["id"], second["id"]],
                reply=" 已收到，进入处理中。 ",
                status="in_progress",
            ),
            actor=admin_id,
        )
        self.assertEqual(bulk["updated"], 2)
        feedback = api.my_feedback(user_id=user_id)
        self.assertTrue(
            all(
                item["status"] == "in_progress"
                and item["admin_reply"] == "已收到，进入处理中。"
                for item in feedback[:2]
            )
        )

        with self.assertRaises(HTTPException) as missing_bulk:
            api.bulk_update_feedback_status(
                api.FeedbackBulkStatus(
                    feedback_ids=[fb_id, 999999],
                    reply="处理中",
                    status="in_progress",
                ),
                actor=admin_id,
            )
        self.assertEqual(missing_bulk.exception.status_code, 404)

        api.delete_feedback(fb_id, actor=admin_id)
        with self.assertRaises(HTTPException) as missing:
            api.delete_feedback(fb_id, actor=admin_id)
        self.assertEqual(missing.exception.status_code, 404)

    def test_focus_room_heartbeat_marks_user_online_and_ranks_members(self):
        first_id = self._register("focus-room-first")
        second_id = self._register("focus-room-second")

        first = api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="第一位",
                weekly_seconds=45 * 60,
                session_count=2,
                started_at="2026-05-20T08:00:00Z",
            ),
            user_id=first_id,
        )
        self.assertEqual(first["online_count"], 1)

        ranking = api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="第二位",
                weekly_seconds=90 * 60,
                session_count=3,
                started_at="2026-05-20T09:00:00Z",
            ),
            user_id=second_id,
        )

        self.assertEqual(ranking["room_id"], "deep_work_room")
        self.assertEqual(ranking["online_count"], 2)
        self.assertEqual(
            [entry["display_name"] for entry in ranking["entries"]],
            ["第二位", "第一位"],
        )
        self.assertEqual(ranking["entries"][0]["rank"], 1)
        self.assertTrue(ranking["entries"][0]["is_current_user"])
        self.assertTrue(ranking["entries"][0]["online"])
        self.assertTrue(ranking["entries"][0]["last_seen_at"].endswith("Z"))

    def test_focus_room_ranking_caps_suspicious_weekly_seconds(self):
        user_id = self._register("focus-room-cap")
        reported_seconds = api.FOCUS_ROOM_MAX_WEEKLY_SECONDS * 3

        ranking = api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="超长专注",
                weekly_seconds=reported_seconds,
                session_count=api.FOCUS_ROOM_MAX_SESSION_COUNT + 99,
            ),
            user_id=user_id,
        )
        entry = ranking["entries"][0]

        self.assertEqual(entry["raw_weekly_seconds"], reported_seconds)
        self.assertEqual(entry["weekly_seconds"], api.FOCUS_ROOM_MAX_WEEKLY_SECONDS)
        self.assertEqual(entry["session_count"], api.FOCUS_ROOM_MAX_SESSION_COUNT)
        self.assertIn("weekly_seconds_capped", entry["risk_flags"])
        self.assertIn("session_count_capped", entry["risk_flags"])
        self.assertIn("server cap", entry["risk_summary"])

    def test_focus_room_heartbeat_flags_repeated_and_jumpy_sessions(self):
        user_id = self._register("focus-room-risk")

        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="风控同学",
                weekly_seconds=30 * 60,
                session_count=2,
            ),
            user_id=user_id,
        )
        first_seen = api.focus_room_ranking("deep_work_room", user_id=user_id)[
            "entries"
        ][0]["last_seen_at"]

        ranking = api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="风控同学",
                weekly_seconds=35 * 60,
                session_count=200,
            ),
            user_id=user_id,
        )
        entry = ranking["entries"][0]

        self.assertEqual(
            entry["session_count"],
            2 + api.FOCUS_ROOM_MAX_SESSION_COUNT_JUMP,
        )
        self.assertEqual(entry["last_seen_at"], first_seen)
        self.assertIn("heartbeat_throttled", entry["risk_flags"])
        self.assertIn("session_count_jump_capped", entry["risk_flags"])
        self.assertIn("too soon", entry["risk_summary"])

    def test_focus_room_leave_and_stale_heartbeat_clear_online_status(self):
        active_id = self._register("focus-room-active")
        stale_id = self._register("focus-room-stale")

        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="在线",
                weekly_seconds=30 * 60,
                session_count=1,
            ),
            user_id=active_id,
        )
        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="过期",
                weekly_seconds=60 * 60,
                session_count=2,
            ),
            user_id=stale_id,
        )

        stale_at = api._utc_now() - timedelta(
            seconds=api.FOCUS_ROOM_ONLINE_SECONDS + 1,
        )
        db = api.get_db()
        try:
            db.execute(
                "UPDATE focus_room_presence SET last_seen_at=? WHERE room_id=? AND user_id=?",
                (api._format_utc(stale_at), "deep_work_room", stale_id),
            )
            db.commit()
        finally:
            db.close()

        ranking = api.focus_room_ranking("deep_work_room", user_id=active_id)
        stale = next(
            entry for entry in ranking["entries"] if entry["user_id"] == stale_id
        )
        self.assertEqual(ranking["online_count"], 1)
        self.assertFalse(stale["online"])

        left = api.leave_focus_room("deep_work_room", user_id=active_id)
        active = next(
            entry for entry in left["entries"] if entry["user_id"] == active_id
        )
        self.assertEqual(left["online_count"], 0)
        self.assertFalse(active["online"])
        self.assertFalse(active["active"])

    def test_focus_room_events_streams_ranking_sse(self):
        user_id = self._register("focus-room-events")
        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="实时同学",
                weekly_seconds=2400,
                session_count=2,
                active=True,
            ),
            user_id=user_id,
        )

        async def first_event():
            response = await api.focus_room_events(
                "deep_work_room",
                interval_seconds=2,
                user_id=user_id,
            )
            stream = response.body_iterator
            try:
                chunk = await stream.__anext__()
            finally:
                await stream.aclose()
            return response, chunk

        response, chunk = asyncio.run(first_event())
        text = chunk.decode("utf-8") if isinstance(chunk, bytes) else chunk
        data_line = next(line for line in text.splitlines() if line.startswith("data: "))
        payload = json.loads(data_line.removeprefix("data: "))

        self.assertEqual(response.media_type, "text/event-stream")
        self.assertEqual(response.headers["cache-control"], "no-cache")
        self.assertIn("event: ranking", text)
        self.assertEqual(payload["room_id"], "deep_work_room")
        self.assertEqual(payload["online_count"], 1)
        self.assertEqual(payload["entries"][0]["display_name"], "实时同学")

    def test_focus_room_events_websocket_streams_and_responds_to_ping(self):
        registered = api.register(
            api.RegisterRequest(
                username="focus-room-websocket",
                password="pass123456",
            )
        )
        user_id = registered["user_id"]
        token = registered["token"]
        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="双向同学",
                weekly_seconds=3600,
                session_count=3,
                active=True,
            ),
            user_id=user_id,
        )

        with TestClient(api.app) as client:
            with client.websocket_connect(
                f"/ws/focus-rooms/deep_work_room/events?token={token}&interval_seconds=2"
            ) as websocket:
                first = websocket.receive_json()
                websocket.send_json({"event": "ping"})
                second = websocket.receive_json()

        self.assertEqual(first["event"], "ranking")
        self.assertEqual(first["data"]["room_id"], "deep_work_room")
        self.assertEqual(first["data"]["online_count"], 1)
        self.assertEqual(first["data"]["entries"][0]["display_name"], "双向同学")
        self.assertEqual(second["event"], "ranking")

    def test_focus_global_leaderboard_events_streams_ranking_sse(self):
        user_id = self._register("focus-global-events")
        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="全站实时同学",
                weekly_seconds=4200,
                session_count=4,
                active=True,
            ),
            user_id=user_id,
        )

        async def first_event():
            response = await api.focus_global_leaderboard_events(
                interval_seconds=2,
                user_id=user_id,
            )
            stream = response.body_iterator
            try:
                chunk = await stream.__anext__()
            finally:
                await stream.aclose()
            return response, chunk

        response, chunk = asyncio.run(first_event())
        text = chunk.decode("utf-8") if isinstance(chunk, bytes) else chunk
        data_line = next(line for line in text.splitlines() if line.startswith("data: "))
        payload = json.loads(data_line.removeprefix("data: "))

        self.assertEqual(response.media_type, "text/event-stream")
        self.assertEqual(response.headers["cache-control"], "no-cache")
        self.assertIn("event: ranking", text)
        self.assertEqual(payload["scope"], "global")
        self.assertEqual(payload["online_count"], 1)
        self.assertEqual(payload["entries"][0]["display_name"], "focus-global-events")

    def test_focus_global_leaderboard_events_websocket_streams_and_responds_to_ping(
        self,
    ):
        registered = api.register(
            api.RegisterRequest(
                username="focus-global-websocket",
                password="pass123456",
            )
        )
        user_id = registered["user_id"]
        token = registered["token"]
        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="全站双向同学",
                weekly_seconds=5400,
                session_count=5,
                active=True,
            ),
            user_id=user_id,
        )

        with TestClient(api.app) as client:
            with client.websocket_connect(
                f"/ws/focus-leaderboard/global/events?token={token}&interval_seconds=2"
            ) as websocket:
                first = websocket.receive_json()
                websocket.send_json({"event": "ping"})
                second = websocket.receive_json()

        self.assertEqual(first["event"], "ranking")
        self.assertEqual(first["data"]["scope"], "global")
        self.assertEqual(first["data"]["online_count"], 1)
        self.assertEqual(
            first["data"]["entries"][0]["display_name"],
            "focus-global-websocket",
        )
        self.assertEqual(second["event"], "ranking")
        self.assertEqual(second["data"]["scope"], "global")

    def test_focus_friends_list_and_ranking_use_server_relationships(self):
        current_id = self._register("focus-friend-current")
        friend_id = self._register("focus-friend-target")
        stranger_id = self._register("focus-friend-stranger")

        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="当前用户",
                weekly_seconds=30 * 60,
                session_count=2,
            ),
            user_id=current_id,
        )
        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="好友用户",
                weekly_seconds=90 * 60,
                session_count=4,
            ),
            user_id=friend_id,
        )
        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="陌生人",
                weekly_seconds=180 * 60,
                session_count=8,
            ),
            user_id=stranger_id,
        )

        requested = api.add_focus_friend(
            api.FocusFriendCreate(username="focus-friend-target"),
            user_id=current_id,
        )
        pending_for_current = api.list_focus_friend_requests(user_id=current_id)
        pending_for_friend = api.list_focus_friend_requests(user_id=friend_id)
        ranking_before_accept = api.focus_friend_leaderboard(user_id=current_id)

        self.assertEqual(requested["user_id"], friend_id)
        self.assertEqual(requested["status"], "pending")
        self.assertEqual(pending_for_current["outgoing"][0]["user_id"], friend_id)
        self.assertEqual(pending_for_friend["incoming"][0]["user_id"], current_id)
        self.assertEqual(
            [entry["user_id"] for entry in ranking_before_accept["entries"]],
            [current_id],
        )

        accepted = api.accept_focus_friend_request(current_id, user_id=friend_id)
        friends = api.list_focus_friends(user_id=current_id)
        reciprocal = api.list_focus_friends(user_id=friend_id)
        ranking = api.focus_friend_leaderboard(user_id=current_id)

        self.assertEqual(accepted["user_id"], current_id)
        self.assertEqual(accepted["status"], "accepted")
        self.assertEqual([item["user_id"] for item in friends["items"]], [friend_id])
        self.assertTrue(friends["items"][0]["online"])
        self.assertEqual(
            [item["user_id"] for item in reciprocal["items"]],
            [current_id],
        )
        self.assertEqual(ranking["scope"], "friends")
        self.assertEqual(
            [entry["user_id"] for entry in ranking["entries"]],
            [friend_id, current_id],
        )
        self.assertNotIn(
            stranger_id,
            [entry["user_id"] for entry in ranking["entries"]],
        )
        self.assertEqual(ranking["entries"][0]["rank"], 1)
        self.assertEqual(ranking["entries"][0]["weekly_seconds"], 90 * 60)

        removed = api.remove_focus_friend(friend_id, user_id=current_id)
        after_remove = api.list_focus_friends(user_id=current_id)
        ranking_after_remove = api.focus_friend_leaderboard(user_id=current_id)

        self.assertEqual(removed["status"], "ok")
        self.assertEqual(after_remove["items"], [])
        self.assertEqual(
            [entry["user_id"] for entry in ranking_after_remove["entries"]],
            [current_id],
        )

    def test_focus_global_leaderboard_uses_server_scores_and_caps_suspicious_values(
        self,
    ):
        current_id = self._register("focus-global-current")
        other_id = self._register("focus-global-other")
        suspicious_id = self._register("focus-global-suspicious")
        disabled_id = self._register("focus-global-disabled")

        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="当前用户",
                weekly_seconds=30 * 60,
                session_count=1,
            ),
            user_id=current_id,
        )
        api.focus_room_heartbeat(
            "reading_room",
            api.FocusRoomHeartbeatRequest(
                display_name="当前用户",
                weekly_seconds=45 * 60,
                session_count=2,
            ),
            user_id=current_id,
        )
        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="全站第二",
                weekly_seconds=90 * 60,
                session_count=2,
            ),
            user_id=other_id,
        )
        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="异常记录",
                weekly_seconds=api.FOCUS_ROOM_MAX_WEEKLY_SECONDS * 3,
                session_count=api.FOCUS_ROOM_MAX_SESSION_COUNT + 50,
            ),
            user_id=suspicious_id,
        )
        api.focus_room_heartbeat(
            "deep_work_room",
            api.FocusRoomHeartbeatRequest(
                display_name="停用账号",
                weekly_seconds=120 * 60,
                session_count=3,
            ),
            user_id=disabled_id,
        )
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_disabled=1 WHERE id=?", (disabled_id,))
            db.commit()
        finally:
            db.close()

        ranking = api.focus_global_leaderboard(user_id=current_id)
        ids = [entry["user_id"] for entry in ranking["entries"]]
        current = next(entry for entry in ranking["entries"] if entry["user_id"] == current_id)
        suspicious = next(
            entry for entry in ranking["entries"] if entry["user_id"] == suspicious_id
        )

        self.assertEqual(ranking["scope"], "global")
        self.assertEqual(ranking["online_count"], 3)
        self.assertEqual(ids, [suspicious_id, other_id, current_id])
        self.assertNotIn(disabled_id, ids)
        self.assertEqual(current["weekly_seconds"], 75 * 60)
        self.assertEqual(current["session_count"], 3)
        self.assertTrue(current["is_current_user"])
        self.assertEqual(
            suspicious["raw_weekly_seconds"],
            api.FOCUS_ROOM_MAX_WEEKLY_SECONDS * 3,
        )
        self.assertEqual(
            suspicious["weekly_seconds"],
            api.FOCUS_ROOM_MAX_WEEKLY_SECONDS,
        )
        self.assertEqual(
            suspicious["session_count"],
            api.FOCUS_ROOM_MAX_SESSION_COUNT,
        )
        self.assertIn("weekly_seconds_capped", suspicious["risk_flags"])
        self.assertIn("session_count_capped", suspicious["risk_flags"])
        self.assertEqual(suspicious["rank"], 1)

    def test_focus_friend_request_reject_cancel_and_limit(self):
        requester_id = self._register("focus-requester")
        reject_target_id = self._register("focus-request-reject")
        cancel_target_id = self._register("focus-request-cancel")

        api.add_focus_friend(
            api.FocusFriendCreate(username="focus-request-reject"),
            user_id=requester_id,
        )
        rejected = api.reject_focus_friend_request(
            requester_id,
            user_id=reject_target_id,
        )
        self.assertEqual(rejected["status"], "ok")
        self.assertEqual(
            api.list_focus_friend_requests(user_id=reject_target_id)["incoming"],
            [],
        )
        self.assertEqual(api.list_focus_friends(user_id=requester_id)["items"], [])

        api.add_focus_friend(
            api.FocusFriendCreate(username="focus-request-cancel"),
            user_id=requester_id,
        )
        cancelled = api.cancel_focus_friend_request(
            cancel_target_id,
            user_id=requester_id,
        )
        self.assertEqual(cancelled["status"], "ok")
        self.assertEqual(
            api.list_focus_friend_requests(user_id=cancel_target_id)["incoming"],
            [],
        )

        old_limit = api.FOCUS_FRIEND_REQUEST_LIMIT_PER_DAY
        api.FOCUS_FRIEND_REQUEST_LIMIT_PER_DAY = 1
        try:
            limited_requester_id = self._register("focus-request-limited-owner")
            limited_id = self._register("focus-request-limited")
            api.add_focus_friend(
                api.FocusFriendCreate(username="focus-request-limited"),
                user_id=limited_requester_id,
            )
            api.cancel_focus_friend_request(
                limited_id,
                user_id=limited_requester_id,
            )
            next_target_id = self._register("focus-request-limited-2")
            with self.assertRaises(HTTPException) as denied:
                api.add_focus_friend(
                    api.FocusFriendCreate(user_id=next_target_id),
                    user_id=limited_requester_id,
                )
            self.assertEqual(denied.exception.status_code, 429)
        finally:
            api.FOCUS_FRIEND_REQUEST_LIMIT_PER_DAY = old_limit

    def test_focus_room_invite_accept_returns_room_and_marks_presence(self):
        owner_id = self._register("focus-room-owner")
        member_id = self._register("focus-room-member")

        invite = api.create_focus_room_invite(
            "exam_sprint_room",
            api.FocusRoomInviteCreate(
                room_name="考试冲刺自习室",
                description="一起刷题",
                weekly_target_seconds=12 * 60 * 60,
                accent_color=0xFF7C4DFF,
            ),
            user_id=owner_id,
        )

        accepted = api.accept_focus_room_invite(
            invite["code"],
            api.FocusRoomInviteAccept(display_name="加入者"),
            user_id=member_id,
        )

        self.assertEqual(accepted["room"]["id"], "exam_sprint_room")
        self.assertEqual(accepted["room"]["name"], "考试冲刺自习室")
        self.assertEqual(accepted["room"]["weekly_target_seconds"], 12 * 60 * 60)
        self.assertEqual(accepted["ranking"]["online_count"], 1)
        member = next(
            entry
            for entry in accepted["ranking"]["entries"]
            if entry["user_id"] == member_id
        )
        self.assertTrue(member["online"])
        self.assertEqual(member["display_name"], "加入者")

    def test_focus_room_invite_rejects_expired_code(self):
        owner_id = self._register("focus-room-expired-owner")
        member_id = self._register("focus-room-expired-member")
        expired_at = api._utc_now() - timedelta(minutes=1)

        invite = api.create_focus_room_invite(
            "reading_room",
            api.FocusRoomInviteCreate(
                room_name="阅读自习室",
                expires_at=api._format_utc(expired_at),
            ),
            user_id=owner_id,
        )

        with self.assertRaises(HTTPException) as denied:
            api.accept_focus_room_invite(
                invite["code"],
                api.FocusRoomInviteAccept(display_name="迟到者"),
                user_id=member_id,
            )

        self.assertEqual(denied.exception.status_code, 400)

    def test_focus_room_invite_list_and_revoke_are_owner_scoped(self):
        owner_id = self._register("focus-room-invite-owner")
        other_id = self._register("focus-room-invite-other")
        member_id = self._register("focus-room-invite-member")

        invite = api.create_focus_room_invite(
            "deep_work_room",
            api.FocusRoomInviteCreate(room_name="深度工作自习室"),
            user_id=owner_id,
        )

        owner_list = api.list_focus_room_invites(
            "deep_work_room",
            user_id=owner_id,
        )
        other_list = api.list_focus_room_invites(
            "deep_work_room",
            user_id=other_id,
        )

        self.assertEqual(len(owner_list["items"]), 1)
        self.assertEqual(owner_list["items"][0]["id"], invite["id"])
        self.assertEqual(owner_list["items"][0]["code"], invite["code"])
        self.assertFalse(owner_list["items"][0]["revoked"])
        self.assertEqual(other_list["items"], [])

        with self.assertRaises(HTTPException) as forbidden:
            api.revoke_focus_room_invite(invite["id"], user_id=other_id)
        self.assertEqual(forbidden.exception.status_code, 404)

        revoked = api.revoke_focus_room_invite(invite["id"], user_id=owner_id)
        self.assertEqual(revoked["status"], "ok")
        owner_list = api.list_focus_room_invites(
            "deep_work_room",
            user_id=owner_id,
        )
        self.assertTrue(owner_list["items"][0]["revoked"])

        with self.assertRaises(HTTPException) as denied:
            api.accept_focus_room_invite(
                invite["code"],
                api.FocusRoomInviteAccept(display_name="加入者"),
                user_id=member_id,
            )
        self.assertEqual(denied.exception.status_code, 404)

    def test_focus_room_invite_usage_limit_counts_first_join_only(self):
        owner_id = self._register("focus-room-limit-owner")
        first_member_id = self._register("focus-room-limit-first")
        second_member_id = self._register("focus-room-limit-second")

        invite = api.create_focus_room_invite(
            "limit_room",
            api.FocusRoomInviteCreate(
                room_name="限额自习室",
                max_uses=1,
            ),
            user_id=owner_id,
        )

        self.assertEqual(invite["max_uses"], 1)
        self.assertEqual(invite["used_count"], 0)
        self.assertIsNone(invite["last_used_at"])

        accepted = api.accept_focus_room_invite(
            invite["code"],
            api.FocusRoomInviteAccept(display_name="首次加入者"),
            user_id=first_member_id,
        )
        repeated = api.accept_focus_room_invite(
            invite["code"],
            api.FocusRoomInviteAccept(display_name="首次加入者"),
            user_id=first_member_id,
        )

        self.assertEqual(accepted["room"]["id"], "limit_room")
        self.assertEqual(repeated["room"]["id"], "limit_room")

        owner_list = api.list_focus_room_invites("limit_room", user_id=owner_id)
        self.assertEqual(len(owner_list["items"]), 1)
        self.assertEqual(owner_list["items"][0]["max_uses"], 1)
        self.assertEqual(owner_list["items"][0]["used_count"], 1)
        self.assertIsNotNone(owner_list["items"][0]["last_used_at"])

        with self.assertRaises(HTTPException) as denied:
            api.accept_focus_room_invite(
                invite["code"],
                api.FocusRoomInviteAccept(display_name="第二位加入者"),
                user_id=second_member_id,
            )
        self.assertEqual(denied.exception.status_code, 400)
        self.assertEqual(
            denied.exception.detail,
            "Focus room invite usage limit reached",
        )


if __name__ == "__main__":
    unittest.main()
