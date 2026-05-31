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
        db = api.get_db()
        try:
            api._setting_set(db, "registration_email_required", False)
            api._setting_set(db, "default_registration_coins", 0)
            db.execute(
                "UPDATE admin_groups SET default_time_coins=0 WHERE id='group_default'"
            )
            db.commit()
        finally:
            db.close()
        res = api.register(
            api.RegisterRequest(username=username, password="pass123456")
        )
        return res["user_id"]

    def _email_code(self, email: str, purpose: str = "bind", user_id=None) -> str:
        db = api.get_db()
        try:
            result = api._create_email_code(
                db,
                email=email,
                purpose=purpose,
                user_id=user_id,
            )
            db.commit()
            return result["code"]
        finally:
            db.close()

    def _register_with_email(
        self,
        username: str,
        email: str,
        *,
        password: str = "pass123456",
        display_name: str = "",
        invitation_code: str = "",
    ) -> dict:
        db = api.get_db()
        try:
            api._setting_set(db, "default_registration_coins", 0)
            db.execute(
                "UPDATE admin_groups SET default_time_coins=0 WHERE id='group_default'"
            )
            db.commit()
        finally:
            db.close()
        return api.register(
            api.RegisterRequest(
                username=username,
                password=password,
                email=email,
                email_code=self._email_code(email),
                display_name=display_name,
                invitation_code=invitation_code,
            )
        )

    def _make_admin(self, username: str, permissions: list[str]) -> str:
        user_id = self._register(username)
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET is_admin=1, admin_permissions=? WHERE id=?",
                (json.dumps(permissions), user_id),
            )
            db.commit()
        finally:
            db.close()
        return user_id

    def test_api_title_uses_duoyi_brand(self):
        self.assertEqual(api.app.title, "多仪 Sync API")

    def test_registration_default_user_group_grants_100_time_coins(self):
        db = api.get_db()
        try:
            api._setting_set(db, "registration_email_required", False)
            api._setting_set(db, "default_registration_coins", 100)
            db.commit()
        finally:
            db.close()

        registered = api.register(
            api.RegisterRequest(username="default-coins-user", password="pass123456")
        )

        self.assertEqual(registered["coin_balance"], 100)
        self.assertEqual(registered["lifetime_coins"], 100)
        self.assertEqual(registered["user"]["coin_balance"], 100)

    def test_init_db_preserves_zero_default_group_time_coins(self):
        db = api.get_db()
        try:
            api._setting_set(db, "registration_email_required", False)
            api._setting_set(db, "default_registration_coins", 0)
            db.execute(
                "UPDATE admin_groups SET default_time_coins=0 WHERE id='group_default'"
            )
            db.commit()
        finally:
            db.close()

        api.init_db()

        db = api.get_db()
        try:
            row = db.execute(
                "SELECT default_time_coins FROM admin_groups WHERE id='group_default'"
            ).fetchone()
            setting_value = api._setting_get(db, "default_registration_coins", 100)
            self.assertEqual(row["default_time_coins"], 0)
            self.assertEqual(setting_value, 0)
            self.assertEqual(api._group_default_time_coins(db, "group_default"), 0)
        finally:
            db.close()

        registered = api.register(
            api.RegisterRequest(username="zero-default-group-user", password="pass123456")
        )

        self.assertEqual(registered["coin_balance"], 0)
        self.assertEqual(registered["lifetime_coins"], 0)
        self.assertEqual(registered["user"]["coin_balance"], 0)

    def test_init_db_seeds_default_group_from_existing_registration_coins(self):
        db = api.get_db()
        try:
            api._setting_set(db, "registration_email_required", False)
            api._setting_set(db, "default_registration_coins", 72)
            db.execute("DELETE FROM admin_groups WHERE id='group_default'")
            db.commit()
        finally:
            db.close()

        api.init_db()

        db = api.get_db()
        try:
            row = db.execute(
                "SELECT default_time_coins FROM admin_groups WHERE id='group_default'"
            ).fetchone()
            self.assertEqual(row["default_time_coins"], 72)
        finally:
            db.close()

        registered = api.register(
            api.RegisterRequest(username="migrated-default-group-user", password="pass123456")
        )

        self.assertEqual(registered["coin_balance"], 72)
        self.assertEqual(registered["lifetime_coins"], 72)
        self.assertEqual(registered["user"]["coin_balance"], 72)

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
        registered = self._register_with_email(
            "profile-user",
            "profile@example.com",
            display_name="资料同学",
        )

        self.assertEqual(registered["email"], "profile@example.com")
        self.assertEqual(registered["display_name"], "资料同学")
        self.assertEqual(registered["identifier"], "profile-user")
        self.assertFalse(registered["can_edit_username"])

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
        self.assertEqual(updated["username"], "profile-user")
        self.assertEqual(updated["email"], "profile-new@example.com")
        self.assertFalse(updated["email_verified"])
        self.assertEqual(updated["avatar"], registered.get("avatar") or "")
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
        self.assertEqual(me["username"], "profile-user")
        self.assertEqual(me["identifier"], "profile-user")
        self.assertFalse(me["can_edit_username"])
        self.assertEqual(me["display_name"], "新昵称")
        self.assertEqual(me["email"], "profile-new@example.com")
        self.assertTrue(me["email_verified"])
        self.assertEqual(me["avatar"], registered.get("avatar") or "")
        self.assertEqual(me["bio"], "用邮箱登录的多仪用户")
        self.assertFalse(me["is_disabled"])

        other_id = self._register("profile-other")
        with self.assertRaises(HTTPException) as conflict:
            api.update_profile(
                api.ProfileUpdate(email="profile-new@example.com"),
                user_id=other_id,
            )
        self.assertEqual(conflict.exception.status_code, 409)

    def test_auth_email_code_profile_and_email_alias_routes_are_live(self):
        user_id = self._register("profile-route-user")
        token = api.TOKENS[user_id]

        with TestClient(api.app) as client:
            profile_response = client.patch(
                "/api/me/profile",
                json={
                    "display_name": "路径用户",
                    "bio": "通过 API 路径保存",
                },
                headers={"Authorization": f"Bearer {token}"},
            )
            code_response = client.post(
                "/api/auth/email/send",
                json={"email": "profile-route@example.com", "purpose": "register"},
                headers={"Authorization": f"Bearer {token}"},
            )
            self.assertEqual(code_response.status_code, 200)
            code_payload = code_response.json()
            self.assertEqual(code_payload["email"], "profile-route@example.com")
            self.assertEqual(code_payload["purpose"], "bind")
            self.assertIn("dev_code", code_payload)

            bind_response = client.post(
                "/api/auth/email/bind",
                json={
                    "email": "profile-route@example.com",
                    "email_code": code_payload["dev_code"],
                },
                headers={"Authorization": f"Bearer {token}"},
            )
            login_code_response = client.post(
                "/api/auth/send-email_code",
                json={"email": "profile-route@example.com", "purpose": "login"},
            )
            self.assertEqual(login_code_response.status_code, 200)
            login_response = client.post(
                "/api/auth/login/email",
                json={
                    "email": "profile-route@example.com",
                    "email_code": login_code_response.json()["dev_code"],
                },
            )

        self.assertEqual(profile_response.status_code, 200)
        profile = profile_response.json()
        self.assertEqual(profile["user_id"], user_id)
        self.assertEqual(profile["display_name"], "路径用户")
        self.assertEqual(profile["bio"], "通过 API 路径保存")
        self.assertEqual(profile["avatar_url"], profile["avatar"])

        self.assertEqual(bind_response.status_code, 200)
        bound = bind_response.json()
        self.assertEqual(bound["user_id"], user_id)
        self.assertEqual(bound["email"], "profile-route@example.com")
        self.assertTrue(bound["email_verified"])

        self.assertEqual(login_response.status_code, 200)
        self.assertEqual(login_response.json()["user_id"], user_id)

    def test_account_mail_defaults_and_registration_email_code_required(self):
        db = api.get_db()
        try:
            runtime = api._account_mail_runtime(db)
            self.assertEqual(runtime["email_code_primary_provider"], "claw163")
            self.assertEqual(runtime["email_code_backup_provider"], "resend")
            self.assertTrue(api._setting_get(db, "registration_email_required", None))
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

    def test_public_health_and_config_include_api_contract(self):
        health = api.health()
        config = api.public_config()

        with TestClient(api.app) as client:
            health_response = client.get("/api/health")
            config_response = client.get("/api/config")
        self.assertEqual(health_response.status_code, 200)
        self.assertEqual(config_response.status_code, 200)
        http_health = health_response.json()
        http_config = config_response.json()

        for payload in (health, config, http_health, http_config):
            self.assertEqual(payload["api_contract_version"], api.API_CONTRACT_VERSION)
            self.assertIn("build_git_sha", payload)
            self.assertIn("build_time", payload)
            self.assertEqual(
                payload["required_routes_hash"],
                api.API_CONTRACT_ROUTES_HASH,
            )
            self.assertIn("POST /api/auth/email-code", payload["required_routes"])
            self.assertIn("PATCH /api/me/profile", payload["required_routes"])
            self.assertIn(
                "PATCH /api/admin/users/{user_id}/coins",
                payload["required_routes"],
            )
            self.assertIn(
                "POST /api/admin/users/{user_id}/coins",
                payload["required_routes"],
            )
            self.assertTrue(payload["features"]["email_code"])
            self.assertTrue(payload["features"]["avatar_upload"])
            self.assertTrue(payload["features"]["admin_coins"])
            self.assertTrue(payload["features"]["mobile_update"])

    def test_api_contract_required_routes_are_registered(self):
        def route_matches(contract_route, registered_route):
            contract_method, contract_path = contract_route.split(" ", 1)
            registered_method, registered_path = registered_route.split(" ", 1)
            if contract_method != registered_method:
                return False
            contract_parts = contract_path.strip("/").split("/")
            registered_parts = registered_path.strip("/").split("/")
            if len(contract_parts) != len(registered_parts):
                return False
            for contract_part, registered_part in zip(contract_parts, registered_parts):
                if registered_part.startswith("{") and registered_part.endswith("}"):
                    continue
                if contract_part != registered_part:
                    return False
            return True

        registered = set()
        for route in api.app.routes:
            path = getattr(route, "path", None)
            methods = getattr(route, "methods", None)
            if not path or not methods:
                continue
            for method in methods:
                if method == "HEAD":
                    continue
                registered.add(f"{method} {path}")

        for route in api.API_CONTRACT_REQUIRED_ROUTES:
            self.assertTrue(
                any(route_matches(route, registered_route) for registered_route in registered),
                route,
            )

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

        registered = self._register_with_email(
            "re0-invite-user",
            "re0-invite-user@example.com",
            invitation_code="RE0INVITE",
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
        registered = self._register_with_email(
            "re0-profile",
            "re0-profile@example.com",
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
        self.assertEqual(updated["username"], "re0-profile")
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

    def test_profile_email_login_and_avatar_compat_routes_do_not_404(self):
        registered = self._register_with_email(
            "compat-profile",
            "compat-profile@example.com",
        )
        user_id = registered["user_id"]
        headers = {"Authorization": f"Bearer {registered['token']}"}

        with TestClient(api.app) as client:
            auth_profile = client.post(
                "/api/auth/profile",
                json={"display_name": "Auth Profile"},
                headers=headers,
            )
            me_profile = client.put(
                "/api/me/profile",
                json={"bio": "Me Profile"},
                headers=headers,
            )
            code_response = client.post(
                "/api/me/email-code",
                json={"email": "compat-bound@example.com", "purpose": "bind"},
                headers=headers,
            )
            bind_response = client.patch(
                "/api/auth/bind-email",
                json={
                    "email": "compat-bound@example.com",
                    "email_code": code_response.json()["dev_code"],
                },
                headers=headers,
            )
            avatar_response = client.put(
                "/api/me/profile/avatar",
                headers=headers,
                files={
                    "avatar": (
                        "avatar.png",
                        b"\x89PNG\r\n\x1a\ncompat-avatar",
                        "image/png",
                    )
                },
            )

        self.assertEqual(auth_profile.status_code, 200)
        self.assertEqual(auth_profile.json()["display_name"], "Auth Profile")
        self.assertEqual(me_profile.status_code, 200)
        self.assertEqual(me_profile.json()["bio"], "Me Profile")
        self.assertEqual(code_response.status_code, 200)
        self.assertEqual(bind_response.status_code, 200)
        self.assertEqual(bind_response.json()["email"], "compat-bound@example.com")
        self.assertTrue(bind_response.json()["email_verified"])
        self.assertEqual(avatar_response.status_code, 200)
        self.assertIn("/api/uploads/avatars/", avatar_response.json()["avatar"])

        db = api.get_db()
        try:
            login_code = api._create_email_code(
                db,
                email="compat-bound@example.com",
                purpose="login",
                user_id=user_id,
            )
            db.commit()
        finally:
            db.close()

        with TestClient(api.app) as client:
            email_login = client.post(
                "/api/auth/login/email-code",
                json={
                    "email": "compat-bound@example.com",
                    "email_code": login_code["code"],
                },
            )

        self.assertEqual(email_login.status_code, 200)
        self.assertEqual(email_login.json()["user_id"], user_id)

    def test_email_login_alias_routes_match_client_contracts(self):
        registered = self._register_with_email(
            "email-login-alias",
            "email-login-alias@example.com",
        )
        user_id = registered["user_id"]
        routes = [
            "/api/auth/email-login",
            "/api/auth/email/login",
            "/api/auth/login/email",
            "/api/auth/email-code-login",
            "/api/auth/login/email-code",
            "/api/auth/email_code_login",
            "/api/auth/login/email_code",
            "/api/user/email-login",
            "/api/user/login/email-code",
            "/api/user/email_code_login",
            "/api/user/login/email_code",
            "/api/account/email-login",
            "/api/account/email_code_login",
        ]

        with TestClient(api.app) as client:
            for index, route in enumerate(routes):
                db = api.get_db()
                try:
                    login_code = api._create_email_code(
                        db,
                        email="email-login-alias@example.com",
                        purpose="login",
                        user_id=user_id,
                    )
                    db.commit()
                finally:
                    db.close()
                body = {
                    "email": "email-login-alias@example.com",
                    ("code" if index % 2 == 0 else "email_code"): login_code["code"],
                }
                response = client.post(route, json=body)
                self.assertEqual(
                    response.status_code,
                    200,
                    f"POST {route}: {response.text}",
                )
                self.assertEqual(response.json()["user_id"], user_id)

    def test_admin_re0_named_routes_for_users_coins_invites_and_settings(self):
        admin_id = self._make_admin(
            "re0-admin-routes",
            ["users", "coins", "settings", "invites"],
        )
        target_id = self._register("re0-admin-target")
        headers = {"Authorization": f"Bearer {api.TOKENS[admin_id]}"}

        with TestClient(api.app) as client:
            put_user = client.put(
                f"/api/admin/users/{target_id}",
                json={"is_disabled": True},
                headers=headers,
            )
            post_user = client.post(
                f"/api/admin/users/{target_id}",
                json={"is_disabled": False},
                headers=headers,
            )
            post_quota = client.post(
                f"/api/admin/users/{target_id}/quota",
                json={"quota": 25, "reason": "RE0 额度兼容"},
                headers=headers,
            )
            put_time_coins = client.put(
                f"/api/admin/users/{target_id}/time-coins",
                json={"time_coins": 40, "reason": "RE0 时光币兼容"},
                headers=headers,
            )
            patch_time_coins = client.patch(
                f"/api/admin/users/{target_id}/time_coins",
                json={"target_balance": 45, "reason": "RE0 下划线时光币兼容"},
                headers=headers,
            )
            patch_coin_balance = client.patch(
                f"/api/admin/users/{target_id}/coin-balance",
                json={"coin_balance": 46, "reason": "金币余额兼容"},
                headers=headers,
            )
            patch_coin_balance_underscore = client.patch(
                f"/api/admin/users/{target_id}/coin_balance",
                json={"target_balance": 47, "reason": "金币余额下划线兼容"},
                headers=headers,
            )
            patch_credit_balance_underscore = client.patch(
                f"/api/admin/users/{target_id}/credit_balance",
                json={"credit_balance": 48, "reason": "积分余额下划线兼容"},
                headers=headers,
            )
            patch_coin_adjustment_underscore = client.patch(
                f"/api/admin/users/{target_id}/coin_adjustment",
                json={"target_balance": 49, "reason": "调整下划线兼容"},
                headers=headers,
            )
            quota_adjust = client.put(
                f"/api/admin/users/{target_id}/quota/adjust",
                json={"quota": 50, "reason": "RE0 额度调整兼容"},
                headers=headers,
            )
            create_invites = client.post(
                "/api/admin/invitation-codes",
                json={"count": 2, "note": "RE0 命名兼容"},
                headers=headers,
            )
            list_invites = client.get(
                "/api/admin/invitation-codes",
                headers=headers,
            )
            patch_settings = client.patch(
                "/api/admin/system-settings",
                json={"force_app_update_enabled": True},
                headers=headers,
            )
            put_settings = client.put(
                "/api/admin/system-settings",
                json={"force_relogin_enabled": True},
                headers=headers,
            )

        self.assertEqual(put_user.status_code, 200)
        self.assertEqual(post_user.status_code, 200)
        self.assertEqual(post_quota.status_code, 200)
        self.assertEqual(post_quota.json()["balance"], 25)
        self.assertEqual(put_time_coins.status_code, 200)
        self.assertEqual(put_time_coins.json()["balance"], 40)
        self.assertEqual(patch_time_coins.status_code, 200)
        self.assertEqual(patch_time_coins.json()["balance"], 45)
        self.assertEqual(patch_coin_balance.status_code, 200)
        self.assertEqual(patch_coin_balance.json()["balance"], 46)
        self.assertEqual(patch_coin_balance_underscore.status_code, 200)
        self.assertEqual(patch_coin_balance_underscore.json()["balance"], 47)
        self.assertEqual(patch_credit_balance_underscore.status_code, 200)
        self.assertEqual(patch_credit_balance_underscore.json()["balance"], 48)
        self.assertEqual(patch_coin_adjustment_underscore.status_code, 200)
        self.assertEqual(patch_coin_adjustment_underscore.json()["balance"], 49)
        self.assertEqual(quota_adjust.status_code, 200)
        self.assertEqual(quota_adjust.json()["balance"], 50)
        self.assertEqual(create_invites.status_code, 200)
        self.assertEqual(len(create_invites.json()["codes"]), 2)
        self.assertEqual(list_invites.status_code, 200)
        self.assertGreaterEqual(list_invites.json()["total"], 2)
        self.assertEqual(patch_settings.status_code, 200)
        self.assertTrue(
            patch_settings.json()["runtime_status"]["force_app_update_enabled"]
        )
        self.assertEqual(put_settings.status_code, 200)
        self.assertTrue(
            put_settings.json()["runtime_status"]["force_relogin_enabled"]
        )

    def test_admin_current_management_routes_do_not_404(self):
        admin_id = self._make_admin(
            "current-admin-routes",
            ["announcements", "invites", "audit", "feedback"],
        )
        user_id = self._register("current-admin-feedback-user")
        admin_headers = {"Authorization": f"Bearer {api.TOKENS[admin_id]}"}
        user_headers = {"Authorization": f"Bearer {api.TOKENS[user_id]}"}

        with TestClient(api.app) as client:
            announcement_list = client.get(
                "/api/admin/announcements?limit=1&offset=0&sort=created_desc",
                headers=admin_headers,
            )
            announcement_create = client.post(
                "/api/admin/announcements",
                json={
                    "title": "当前后台公告",
                    "body": "当前 AdminApi 公告路径不应 404",
                    "level": "warning",
                    "published": True,
                },
                headers=admin_headers,
            )
            ann_id = announcement_create.json()["id"]
            announcement_update = client.patch(
                f"/api/admin/announcements/{ann_id}",
                json={"level": "critical", "published": False},
                headers=admin_headers,
            )
            announcement_delete = client.delete(
                f"/api/admin/announcements/{ann_id}",
                headers=admin_headers,
            )

            invite_create = client.post(
                "/api/admin/invite-codes",
                json={"count": 1, "note": "当前 AdminApi 邀请码路径"},
                headers=admin_headers,
            )
            invite_code = invite_create.json()["codes"][0]
            invite_list = client.get(
                "/api/admin/invite-codes?limit=1&offset=0&sort=created_desc",
                headers=admin_headers,
            )
            invite_delete = client.delete(
                f"/api/admin/invite-codes/{invite_code}",
                headers=admin_headers,
            )

            feedback_create = client.post(
                "/api/me/feedback",
                json={
                    "category": "bug",
                    "content": "后台反馈详情当前路径不应 404",
                },
                headers=user_headers,
            )
            fb_id = feedback_create.json()["id"]
            feedback_list = client.get(
                "/api/admin/feedback?limit=1&offset=0&sort=created_desc",
                headers=admin_headers,
            )
            feedback_detail = client.get(
                f"/api/admin/feedback/{fb_id}",
                headers=admin_headers,
            )
            feedback_delete = client.delete(
                f"/api/admin/feedback/{fb_id}",
                headers=admin_headers,
            )

            audit_log = client.get(
                "/api/admin/audit-log?limit=1&offset=0&sort=created_desc",
                headers=admin_headers,
            )

        for response in [
            announcement_list,
            announcement_create,
            announcement_update,
            announcement_delete,
            invite_create,
            invite_list,
            invite_delete,
            feedback_create,
            feedback_list,
            feedback_detail,
            feedback_delete,
            audit_log,
        ]:
            self.assertNotEqual(response.status_code, 404)
            self.assertLess(response.status_code, 400)

        self.assertIn("items", announcement_list.json())
        self.assertEqual(announcement_create.json()["id"], ann_id)
        self.assertEqual(announcement_update.json()["status"], "ok")
        self.assertEqual(announcement_delete.json()["status"], "ok")
        self.assertEqual(len(invite_create.json()["codes"]), 1)
        self.assertIn("items", invite_list.json())
        self.assertEqual(invite_delete.json()["status"], "ok")
        self.assertEqual(feedback_detail.json()["id"], fb_id)
        self.assertEqual(feedback_delete.json()["deleted"], 1)
        self.assertIn("items", audit_log.json())

    def test_admin_groups_roles_permissions_routes_match_re0_contracts(self):
        admin_id = self._make_admin(
            "group-role-admin",
            ["users", "groups", "roles", "permissions"],
        )
        db = api.get_db()
        try:
            api._setting_set(db, "default_registration_coins", 100)
            db.commit()
        finally:
            db.close()
        headers = {"Authorization": f"Bearer {api.TOKENS[admin_id]}"}

        with TestClient(api.app) as client:
            permissions = client.get("/api/admin/permissions", headers=headers)
            groups = client.get("/api/admin/groups", headers=headers)
            paged_groups = client.get(
                "/api/admin/groups?limit=1&offset=0",
                headers=headers,
            )
            roles = client.get("/api/admin/roles", headers=headers)
            create_group = client.post(
                "/api/admin/groups",
                json={
                    "name": "测试用户组",
                    "description": "RE0 用户组兼容",
                    "default_time_coins": 100,
                    "default_generate_quota": 12,
                    "default_edit_quota": 6,
                    "default_generate_history_retention": 30,
                    "default_edit_history_retention": 15,
                    "image_mode": "general",
                    "is_active": True,
                },
                headers=headers,
            )
            group_id = create_group.json()["id"]
            update_group = client.put(
                f"/api/admin/groups/{group_id}",
                json={
                    "name": "测试用户组改",
                    "description": "可更新",
                    "default_time_coins": 120,
                    "default_generate_quota": 14,
                    "default_edit_quota": 7,
                    "default_generate_history_retention": 32,
                    "default_edit_history_retention": 16,
                    "image_mode": "vip",
                    "is_active": False,
                },
                headers=headers,
            )
            partial_group = client.patch(
                f"/api/admin/groups/{group_id}",
                json={
                    "name": "测试用户组局部改",
                    "description": "隐藏额度保留",
                    "default_time_coins": 130,
                    "image_mode": "general",
                    "is_active": True,
                },
                headers=headers,
            )
            default_group_update = client.patch(
                "/api/admin/groups/group_default",
                json={
                    "name": "默认用户组",
                    "description": "默认注册额度",
                    "default_time_coins": 150,
                    "image_mode": "vip",
                    "is_active": True,
                },
                headers=headers,
            )
            create_role = client.post(
                "/api/admin/roles",
                json={
                    "name": "客服角色",
                    "description": "只处理反馈",
                    "permission_codes": ["feedback"],
                    "is_active": True,
                },
                headers=headers,
            )
            role_id = create_role.json()["id"]
            update_role = client.patch(
                f"/api/admin/roles/{role_id}",
                json={
                    "name": "客服角色改",
                    "description": "反馈和公告",
                    "permissions": ["feedback", "announcements"],
                    "is_active": True,
                },
                headers=headers,
            )
            created_user = client.post(
                "/api/admin/users",
                json={
                    "username": "grouped-user",
                    "password": "pass123456",
                    "group_id": group_id,
                    "role_id": role_id,
                    "is_admin": True,
                    "admin_permissions": ["feedback"],
                },
                headers=headers,
            )

        self.assertEqual(permissions.status_code, 200)
        permission_codes = {item["code"] for item in permissions.json()}
        self.assertIn("users", permission_codes)
        self.assertIn("coins", permission_codes)
        self.assertEqual(groups.status_code, 200)
        self.assertTrue(any(item["id"] == "group_default" for item in groups.json()))
        self.assertEqual(paged_groups.status_code, 200)
        self.assertIn("items", paged_groups.json())
        self.assertEqual(paged_groups.json()["limit"], 1)
        self.assertGreaterEqual(paged_groups.json()["total"], 1)
        self.assertTrue(paged_groups.json()["items"][0]["id"])
        self.assertEqual(roles.status_code, 200)
        self.assertTrue(any(item["id"] == "role_admin" for item in roles.json()))
        self.assertEqual(create_group.status_code, 200)
        self.assertEqual(create_group.json()["default_time_coins"], 100)
        self.assertEqual(update_group.status_code, 200)
        self.assertEqual(update_group.json()["default_time_coins"], 120)
        self.assertFalse(update_group.json()["is_active"])
        self.assertEqual(partial_group.status_code, 200)
        self.assertEqual(partial_group.json()["default_time_coins"], 130)
        self.assertEqual(partial_group.json()["default_generate_quota"], 14)
        self.assertEqual(partial_group.json()["default_edit_quota"], 7)
        self.assertEqual(
            partial_group.json()["default_generate_history_retention"], 32
        )
        self.assertEqual(
            partial_group.json()["default_edit_history_retention"], 16
        )
        self.assertTrue(partial_group.json()["is_active"])
        self.assertEqual(default_group_update.status_code, 200)
        self.assertEqual(default_group_update.json()["default_time_coins"], 150)
        db = api.get_db()
        try:
            self.assertEqual(api._setting_get(db, "default_registration_coins", 0), 150)
        finally:
            db.close()
        self.assertEqual(create_role.status_code, 200)
        self.assertEqual(create_role.json()["permissions"], ["feedback"])
        self.assertEqual(update_role.status_code, 200)
        self.assertEqual(
            update_role.json()["permissions"],
            ["feedback", "announcements"],
        )
        self.assertEqual(created_user.status_code, 200)
        created_payload = created_user.json()
        self.assertEqual(created_payload["group_id"], group_id)
        self.assertEqual(created_payload["role_id"], role_id)
        self.assertIn("feedback", created_payload["permissions"])
        self.assertEqual(created_payload["coin_balance"], 130)

    def test_user_admin_can_read_groups_and_roles_for_assignment(self):
        admin_id = self._make_admin("user-group-reader-admin", ["users"])
        target_id = self._register("user-group-reader-target")
        headers = {"Authorization": f"Bearer {api.TOKENS[admin_id]}"}

        with TestClient(api.app) as client:
            groups = client.get("/api/admin/groups", headers=headers)
            paged_groups = client.get(
                "/api/admin/groups?limit=1&offset=0",
                headers=headers,
            )
            roles = client.get("/api/admin/roles", headers=headers)
            update_user = client.patch(
                f"/api/admin/users/{target_id}",
                json={"group_id": "group_default", "role_id": "role_user"},
                headers=headers,
            )
            create_group = client.post(
                "/api/admin/groups",
                json={"name": "只读管理员不可创建", "default_time_coins": 1},
                headers=headers,
            )

        self.assertEqual(groups.status_code, 200)
        self.assertTrue(any(item["id"] == "group_default" for item in groups.json()))
        self.assertEqual(paged_groups.status_code, 200)
        self.assertIn("items", paged_groups.json())
        self.assertEqual(roles.status_code, 200)
        self.assertTrue(any(item["id"] == "role_user" for item in roles.json()))
        self.assertEqual(update_user.status_code, 200)
        self.assertEqual(update_user.json()["group_id"], "group_default")
        self.assertEqual(update_user.json()["role_id"], "role_user")
        self.assertEqual(create_group.status_code, 403)

    def test_user_admin_cannot_escalate_admin_permissions(self):
        admin_id = self._make_admin("user-only-admin", ["users"])
        target_id = self._register("user-only-target")

        for payload in (
            api.UserUpdate(admin_permissions=[api.ADMIN_ALL_PERMISSION]),
            api.UserUpdate(admin_permissions=[]),
        ):
            with self.assertRaises(HTTPException) as denied:
                api.admin_update_user(admin_id, payload, actor=admin_id)
            self.assertEqual(denied.exception.status_code, 403)

        with self.assertRaises(HTTPException) as denied:
            api.admin_update_user(
                target_id,
                api.UserUpdate(is_admin=True),
                actor=admin_id,
            )
        self.assertEqual(denied.exception.status_code, 403)

        with self.assertRaises(HTTPException) as denied:
            api.admin_create_user(
                api.UserCreate(username="user-only-created-admin", is_admin=True),
                actor=admin_id,
            )
        self.assertEqual(denied.exception.status_code, 403)

        db = api.get_db()
        try:
            actor_row = db.execute(
                "SELECT admin_permissions FROM users WHERE id=?", (admin_id,)
            ).fetchone()
            target_row = db.execute(
                "SELECT is_admin FROM users WHERE id=?", (target_id,)
            ).fetchone()
        finally:
            db.close()
        self.assertEqual(json.loads(actor_row["admin_permissions"]), ["users"])
        self.assertEqual(target_row["is_admin"], 0)

    def test_roles_admin_can_manage_admin_permissions(self):
        actor_id = self._make_admin("roles-admin-can-promote", ["users", "roles"])
        target_id = self._register("roles-admin-target")

        updated = api.admin_update_user(
            target_id,
            api.UserUpdate(
                is_admin=True,
                admin_permissions=["feedback"],
                role_id="role_user",
            ),
            actor=actor_id,
        )

        self.assertTrue(updated["is_admin"])
        self.assertIn("feedback", updated["permissions"])

    def test_roles_admin_cannot_grant_super_admin_permission_or_role(self):
        actor_id = self._make_admin("limited-roles-admin", ["users", "roles"])
        target_id = self._register("limited-roles-target")

        for payload in (
            api.UserUpdate(is_admin=True),
            api.UserUpdate(is_admin=True, admin_permissions=[api.ADMIN_ALL_PERMISSION]),
            api.UserUpdate(role_id="role_admin"),
        ):
            with self.assertRaises(HTTPException) as denied:
                api.admin_update_user(target_id, payload, actor=actor_id)
            self.assertEqual(denied.exception.status_code, 403)

        with self.assertRaises(HTTPException) as denied_create_user:
            api.admin_create_user(
                api.UserCreate(username="limited-roles-created", is_admin=True),
                actor=actor_id,
            )
        self.assertEqual(denied_create_user.exception.status_code, 403)

        with self.assertRaises(HTTPException) as denied_create_role:
            api.admin_create_role(
                api.AdminRoleUpsert(
                    name="越权角色",
                    permissions=[api.ADMIN_ALL_PERMISSION],
                ),
                actor=actor_id,
            )
        self.assertEqual(denied_create_role.exception.status_code, 403)

        db = api.get_db()
        try:
            target_row = db.execute(
                "SELECT is_admin, role_id, admin_permissions FROM users WHERE id=?",
                (target_id,),
            ).fetchone()
        finally:
            db.close()
        self.assertEqual(target_row["is_admin"], 0)
        self.assertNotEqual(target_row["role_id"], "role_admin")
        self.assertNotIn(api.ADMIN_ALL_PERMISSION, target_row["admin_permissions"])

    def test_admin_group_assignment_grants_target_group_default_coins_once(self):
        admin_id = self._make_admin("group-assignment-admin", ["users", "groups"])
        target_id = self._register("group-assignment-target")
        headers = {"Authorization": f"Bearer {api.TOKENS[admin_id]}"}

        with TestClient(api.app) as client:
            created_group = client.post(
                "/api/admin/groups",
                json={"name": "分配额度组", "default_time_coins": 80},
                headers=headers,
            )
            self.assertEqual(created_group.status_code, 200)
            group_id = created_group.json()["id"]

            assigned = client.patch(
                f"/api/admin/users/{target_id}",
                json={"group_id": group_id},
                headers=headers,
            )
            repeated = client.patch(
                f"/api/admin/users/{target_id}",
                json={"group_id": group_id},
                headers=headers,
            )

        self.assertEqual(assigned.status_code, 200)
        self.assertEqual(assigned.json()["group_id"], group_id)
        self.assertEqual(assigned.json()["coin_balance"], 80)
        self.assertEqual(assigned.json()["lifetime_coins"], 80)
        self.assertEqual(repeated.status_code, 200)
        self.assertEqual(repeated.json()["coin_balance"], 80)

    def test_admin_cannot_create_or_assign_disabled_group(self):
        admin_id = self._make_admin("disabled-group-admin", ["users", "groups"])
        target_id = self._register("disabled-group-target")
        headers = {"Authorization": f"Bearer {api.TOKENS[admin_id]}"}

        with TestClient(api.app) as client:
            created_group = client.post(
                "/api/admin/groups",
                json={
                    "name": "停用额度组",
                    "default_time_coins": 999,
                    "is_active": False,
                },
                headers=headers,
            )
            self.assertEqual(created_group.status_code, 200)
            group_id = created_group.json()["id"]

            created_user = client.post(
                "/api/admin/users",
                json={
                    "username": "disabled-group-created-user",
                    "password": "pass123456",
                    "group_id": group_id,
                },
                headers=headers,
            )
            assigned = client.patch(
                f"/api/admin/users/{target_id}",
                json={"group_id": group_id},
                headers=headers,
            )

        self.assertEqual(created_user.status_code, 400)
        self.assertIn("用户组已停用", created_user.text)
        self.assertEqual(assigned.status_code, 400)
        self.assertIn("用户组已停用", assigned.text)

        db = api.get_db()
        try:
            row = db.execute(
                "SELECT group_id FROM users WHERE id=?",
                (target_id,),
            ).fetchone()
            rewards = json.loads(
                db.execute(
                    "SELECT virtual_rewards FROM sync_data WHERE user_id=?",
                    (target_id,),
                ).fetchone()["virtual_rewards"]
            )
        finally:
            db.close()

        self.assertEqual(row["group_id"], "group_default")
        self.assertEqual(rewards.get("balance", 0), 0)

    def test_default_admin_role_migrates_to_all_permissions_for_groups_and_coins(self):
        db = api.get_db()
        try:
            db.execute(
                "UPDATE admin_roles SET permissions=? WHERE id='role_admin'",
                (json.dumps(["users"]),),
            )
            db.commit()
        finally:
            db.close()

        api.init_db()

        db = api.get_db()
        try:
            role_permissions = db.execute(
                "SELECT permissions FROM admin_roles WHERE id='role_admin'"
            ).fetchone()["permissions"]
        finally:
            db.close()
        self.assertEqual(json.loads(role_permissions), [api.ADMIN_ALL_PERMISSION])

        admin_id = self._register("default-role-admin")
        target_id = self._register("default-role-coin-target")
        db = api.get_db()
        try:
            db.execute(
                """
                UPDATE users
                SET is_admin=1, role_id='role_admin', admin_permissions='[]'
                WHERE id=?
                """,
                (admin_id,),
            )
            db.commit()
        finally:
            db.close()
        headers = {"Authorization": f"Bearer {api.TOKENS[admin_id]}"}

        with TestClient(api.app) as client:
            groups = client.get("/api/admin/groups", headers=headers)
            coins = client.post(
                f"/api/admin/users/{target_id}/coins",
                json={"delta": 9, "reason": "默认管理员角色额度调整"},
                headers=headers,
            )

        self.assertEqual(groups.status_code, 200)
        self.assertEqual(coins.status_code, 200)
        self.assertEqual(coins.json()["balance"], 9)

    def test_account_api_fallback_routes_match_client_contracts(self):
        registered = self._register_with_email(
            "fallback-account",
            "fallback-account@example.com",
        )
        token = registered["token"]
        user_id = registered["user_id"]
        headers = {"Authorization": f"Bearer {token}"}
        old_avatar_dir = api.AVATAR_UPLOAD_DIR
        api.AVATAR_UPLOAD_DIR = os.path.join(self._tmp.name, "fallback-avatars")
        try:
            with TestClient(api.app) as client:
                for method, path in [
                    ("patch", "/api/me/profile"),
                    ("post", "/api/me/profile"),
                    ("put", "/api/me/profile"),
                    ("patch", "/api/auth/profile"),
                    ("post", "/api/auth/profile"),
                    ("put", "/api/auth/profile"),
                ]:
                    response = getattr(client, method)(
                        path,
                        json={"display_name": f"{method}:{path}"},
                        headers=headers,
                    )
                    self.assertEqual(
                        response.status_code,
                        200,
                        f"{method.upper()} {path}: {response.text}",
                    )
                    self.assertEqual(response.json()["user_id"], user_id)

                for path in [
                    "/api/auth/email-code",
                    "/api/auth/email-code/send",
                    "/api/auth/email/send-code",
                    "/api/auth/send-email-code",
                    "/api/me/email-code",
                    "/api/me/email-code/send",
                    "/api/me/email/send-code",
                    "/api/me/email/send",
                ]:
                    db = api.get_db()
                    try:
                        db.execute(
                            """
                            UPDATE email_verification_codes
                            SET created_at=?
                            WHERE email=?
                            """,
                            (
                                api._format_utc(api._utc_now() - timedelta(seconds=61)),
                                "fallback-code@example.com",
                            ),
                        )
                        db.commit()
                    finally:
                        db.close()
                    response = client.post(
                        path,
                        json={"email": "fallback-code@example.com", "purpose": "bind"},
                        headers=headers,
                    )
                    self.assertEqual(
                        response.status_code,
                        200,
                        f"POST {path}: {response.text}",
                    )
                    self.assertEqual(response.json()["purpose"], "bind")

                bind_aliases = [
                    "/api/me/email",
                    "/api/me/email/bind",
                    "/api/me/bind-email",
                    "/api/auth/email",
                    "/api/auth/email/bind",
                    "/api/auth/bind-email",
                ]
                for method in ["patch", "post", "put"]:
                    for path in bind_aliases:
                        db = api.get_db()
                        try:
                            bind_code = api._create_email_code(
                                db,
                                email="fallback-bind@example.com",
                                purpose="bind",
                                user_id=user_id,
                            )
                            db.commit()
                        finally:
                            db.close()
                        response = getattr(client, method)(
                            path,
                            json={
                                "email": "fallback-bind@example.com",
                                "code": bind_code["code"],
                                "email_code": bind_code["code"],
                            },
                            headers=headers,
                        )
                        self.assertEqual(
                            response.status_code,
                            200,
                            f"{method.upper()} {path}: {response.text}",
                        )
                        self.assertEqual(
                            response.json()["email"],
                            "fallback-bind@example.com",
                        )
                        self.assertTrue(response.json()["email_verified"])

                db = api.get_db()
                try:
                    profile_code = api._create_email_code(
                        db,
                        email="fallback-profile-code@example.com",
                        purpose="bind",
                        user_id=user_id,
                    )
                    db.commit()
                finally:
                    db.close()
                profile_response = client.patch(
                    "/api/auth/profile",
                    json={
                        "email": "fallback-profile-code@example.com",
                        "code": profile_code["code"],
                    },
                    headers=headers,
                )
                self.assertEqual(profile_response.status_code, 200)
                self.assertEqual(
                    profile_response.json()["email"],
                    "fallback-profile-code@example.com",
                )
                self.assertTrue(profile_response.json()["email_verified"])

                for method, path, field_name in [
                    ("post", "/api/me/avatar", "avatar"),
                    ("patch", "/api/me/profile/avatar", "file"),
                    ("put", "/api/auth/avatar", "image"),
                    ("post", "/api/auth/profile/avatar", "avatar"),
                ]:
                    response = getattr(client, method)(
                        path,
                        headers=headers,
                        files={
                            field_name: (
                                "avatar.png",
                                b"\x89PNG\r\n\x1a\nfallback-avatar",
                                "image/png",
                            )
                        },
                    )
                    self.assertEqual(
                        response.status_code,
                        200,
                        f"{method.upper()} {path}: {response.text}",
                    )
                    self.assertIn("/api/uploads/avatars/", response.json()["avatar"])
        finally:
            api.AVATAR_UPLOAD_DIR = old_avatar_dir

    def test_admin_coin_fallback_routes_match_client_contracts(self):
        admin_id = self._make_admin("coin-contract-admin", ["coins"])
        user_id = self._register("coin-contract-user")
        headers = {"Authorization": f"Bearer {api.TOKENS[admin_id]}"}

        route_methods = [
            ("post", "/api/admin/users/{user_id}/coins"),
            ("patch", "/api/admin/users/{user_id}/coins"),
            ("put", "/api/admin/users/{user_id}/coins"),
            ("post", "/api/admin/users/{user_id}/coin"),
            ("patch", "/api/admin/users/{user_id}/coin"),
            ("put", "/api/admin/users/{user_id}/coin"),
            ("post", "/api/admin/users/{user_id}/time-coins"),
            ("patch", "/api/admin/users/{user_id}/time-coins"),
            ("put", "/api/admin/users/{user_id}/time-coins"),
            ("post", "/api/admin/users/{user_id}/time-coin-balance"),
            ("patch", "/api/admin/users/{user_id}/time-coin-balance"),
            ("put", "/api/admin/users/{user_id}/time-coin-balance"),
            ("post", "/api/admin/users/{user_id}/time_coins"),
            ("patch", "/api/admin/users/{user_id}/time_coins"),
            ("put", "/api/admin/users/{user_id}/time_coins"),
            ("post", "/api/admin/users/{user_id}/time_coin_balance"),
            ("patch", "/api/admin/users/{user_id}/time_coin_balance"),
            ("put", "/api/admin/users/{user_id}/time_coin_balance"),
            ("post", "/api/admin/users/{user_id}/credits"),
            ("patch", "/api/admin/users/{user_id}/credits"),
            ("put", "/api/admin/users/{user_id}/credits"),
            ("post", "/api/admin/users/{user_id}/credit-balance"),
            ("patch", "/api/admin/users/{user_id}/credit-balance"),
            ("put", "/api/admin/users/{user_id}/credit-balance"),
            ("post", "/api/admin/users/{user_id}/coins/adjust"),
            ("patch", "/api/admin/users/{user_id}/coins/adjust"),
            ("put", "/api/admin/users/{user_id}/coins/adjust"),
            ("post", "/api/admin/users/{user_id}/coin-adjustment"),
            ("patch", "/api/admin/users/{user_id}/coin-adjustment"),
            ("put", "/api/admin/users/{user_id}/coin-adjustment"),
            ("post", "/api/admin/users/{user_id}/quota"),
            ("patch", "/api/admin/users/{user_id}/quota"),
            ("put", "/api/admin/users/{user_id}/quota"),
            ("post", "/api/admin/users/{user_id}/quota/adjust"),
            ("patch", "/api/admin/users/{user_id}/quota/adjust"),
            ("put", "/api/admin/users/{user_id}/quota/adjust"),
        ]

        with TestClient(api.app) as client:
            for index, (method, route_template) in enumerate(route_methods, start=1):
                path = route_template.format(user_id=user_id)
                response = getattr(client, method)(
                    path,
                    json={"delta": 1, "reason": f"route contract {index}"},
                    headers=headers,
                )
                self.assertEqual(
                    response.status_code,
                    200,
                    f"{method.upper()} {path}: {response.text}",
                )
                self.assertEqual(response.json()["balance"], index)
                self.assertEqual(response.json()["ledger_entry"]["coins"], 1)

    def test_user_reported_empty_endpoint_contracts_do_not_404(self):
        registered = self._register_with_email(
            "empty-endpoint-user",
            "empty-endpoint-user@example.com",
        )
        user_id = registered["user_id"]
        user_headers = {"Authorization": f"Bearer {registered['token']}"}
        admin_id = self._make_admin(
            "empty-endpoint-admin",
            ["ai", "coins", "feedback", "groups", "settings"],
        )
        admin_headers = {"Authorization": f"Bearer {api.TOKENS[admin_id]}"}
        old_avatar_dir = api.AVATAR_UPLOAD_DIR
        api.AVATAR_UPLOAD_DIR = os.path.join(self._tmp.name, "empty-avatars")

        try:
            with TestClient(api.app) as client:
                profile_routes = [
                    "/api/me/profile",
                    "/api/profile",
                    "/api/auth/profile",
                    "/api/user/profile",
                    "/api/account/profile",
                ]
                for method in ("post", "patch", "put"):
                    for route in profile_routes:
                        response = getattr(client, method)(
                            route,
                            json={
                                "display_name": f"{method}:{route}",
                                "bio": "404 contract profile save",
                            },
                            headers=user_headers,
                        )
                        self.assertNotEqual(
                            response.status_code,
                            404,
                            f"{method.upper()} {route}: {response.text}",
                        )
                        self.assertEqual(response.status_code, 200)
                        self.assertEqual(response.json()["user_id"], user_id)

                email_code_routes = [
                    "/api/auth/email-code",
                    "/api/auth/email-code/send",
                    "/api/auth/email_code",
                    "/api/auth/email_code/send",
                    "/api/auth/email/send",
                    "/api/auth/email/send-code",
                    "/api/auth/send-email-code",
                    "/api/auth/send-email_code",
                    "/api/me/email-code",
                    "/api/me/email-code/send",
                    "/api/me/email_code",
                    "/api/me/email_code/send",
                    "/api/me/email/send",
                    "/api/me/email/send-code",
                    "/api/email-code",
                    "/api/email-code/send",
                    "/api/email_code",
                    "/api/email_code/send",
                    "/api/email/send",
                    "/api/email/send-code",
                    "/api/send-email-code",
                    "/api/send-email_code",
                    "/api/user/email-code",
                    "/api/user/email-code/send",
                    "/api/user/email_code",
                    "/api/user/email_code/send",
                    "/api/user/email/send",
                    "/api/user/email/send-code",
                    "/api/account/email-code",
                    "/api/account/email-code/send",
                    "/api/account/email_code",
                    "/api/account/email_code/send",
                    "/api/account/email/send",
                    "/api/account/email/send-code",
                ]
                for index, route in enumerate(email_code_routes):
                    response = client.post(
                        route,
                        json={
                            "email": f"empty-code-{index}@example.com",
                            "purpose": "bind",
                        },
                        headers=user_headers,
                    )
                    self.assertNotEqual(
                        response.status_code,
                        404,
                        f"POST {route}: {response.text}",
                    )
                    self.assertEqual(response.status_code, 200)
                    self.assertIn("dev_code", response.json())

                bind_routes = [
                    "/api/me/email",
                    "/api/me/email/bind",
                    "/api/me/bind-email",
                    "/api/email",
                    "/api/email/bind",
                    "/api/bind-email",
                    "/api/auth/email",
                    "/api/auth/email/bind",
                    "/api/auth/bind-email",
                    "/api/user/email",
                    "/api/user/email/bind",
                    "/api/user/bind-email",
                    "/api/account/email",
                    "/api/account/email/bind",
                ]
                for index, route in enumerate(bind_routes):
                    email = f"empty-bind-{index}@example.com"
                    db = api.get_db()
                    try:
                        bind_code = api._create_email_code(
                            db,
                            email=email,
                            purpose="bind",
                            user_id=user_id,
                        )
                        db.commit()
                    finally:
                        db.close()
                    response = client.patch(
                        route,
                        json={"email": email, "email_code": bind_code["code"]},
                        headers=user_headers,
                    )
                    self.assertNotEqual(
                        response.status_code,
                        404,
                        f"PATCH {route}: {response.text}",
                    )
                    self.assertEqual(response.status_code, 200)
                    self.assertEqual(response.json()["email"], email)

                login_routes = [
                    "/api/auth/email-login",
                    "/api/auth/email/login",
                    "/api/auth/login/email",
                    "/api/auth/email-code-login",
                    "/api/auth/login/email-code",
                    "/api/auth/email_code_login",
                    "/api/auth/login/email_code",
                    "/api/user/email-login",
                    "/api/user/login/email-code",
                    "/api/user/email_code_login",
                    "/api/user/login/email_code",
                    "/api/account/email-login",
                    "/api/account/email_code_login",
                    "/api/email-login",
                    "/api/email/login",
                    "/api/login/email",
                    "/api/email-code-login",
                    "/api/login/email-code",
                    "/api/email_code_login",
                    "/api/login/email_code",
                ]
                login_email = f"empty-bind-{len(bind_routes) - 1}@example.com"
                latest_login_token = registered["token"]
                for route in login_routes:
                    db = api.get_db()
                    try:
                        login_code = api._create_email_code(
                            db,
                            email=login_email,
                            purpose="login",
                            user_id=user_id,
                        )
                        db.commit()
                    finally:
                        db.close()
                    response = client.post(
                        route,
                        json={
                            "email": login_email,
                            "email_code": login_code["code"],
                        },
                    )
                    self.assertNotEqual(
                        response.status_code,
                        404,
                        f"POST {route}: {response.text}",
                    )
                    self.assertEqual(response.status_code, 200)
                    self.assertEqual(response.json()["user_id"], user_id)
                    latest_login_token = response.json()["token"]

                user_headers = {"Authorization": f"Bearer {latest_login_token}"}

                avatar_routes = [
                    ("post", "/api/me/avatar", "avatar"),
                    ("patch", "/api/me/profile/avatar", "file"),
                    ("put", "/api/avatar", "image"),
                    ("post", "/api/profile/avatar", "avatar"),
                    ("put", "/api/auth/avatar", "image"),
                    ("post", "/api/auth/profile/avatar", "avatar"),
                    ("patch", "/api/user/avatar", "file"),
                    ("put", "/api/user/profile/avatar", "image"),
                    ("post", "/api/account/avatar", "avatar"),
                    ("patch", "/api/account/profile/avatar", "file"),
                ]
                for method, route, field_name in avatar_routes:
                    response = getattr(client, method)(
                        route,
                        headers=user_headers,
                        files={
                            field_name: (
                                "avatar.png",
                                b"\x89PNG\r\n\x1a\nempty-endpoint-avatar",
                                "image/png",
                            )
                        },
                    )
                    self.assertNotEqual(
                        response.status_code,
                        404,
                        f"{method.upper()} {route}: {response.text}",
                    )
                    self.assertEqual(response.status_code, 200)
                    self.assertIn("/api/uploads/avatars/", response.json()["avatar"])

                coin_routes = [
                    "/api/admin/users/{user_id}/coins",
                    "/api/admin/users/{user_id}/coin",
                    "/api/admin/users/{user_id}/coin-balance",
                    "/api/admin/users/{user_id}/coin_balance",
                    "/api/admin/users/{user_id}/time-coins",
                    "/api/admin/users/{user_id}/time_coins",
                    "/api/admin/users/{user_id}/time-coin-balance",
                    "/api/admin/users/{user_id}/time_coin_balance",
                    "/api/admin/users/{user_id}/credits",
                    "/api/admin/users/{user_id}/credit-balance",
                    "/api/admin/users/{user_id}/credit_balance",
                    "/api/admin/users/{user_id}/coins/adjust",
                    "/api/admin/users/{user_id}/time-coins/adjust",
                    "/api/admin/users/{user_id}/time_coins/adjust",
                    "/api/admin/users/{user_id}/time-coin-balance/adjust",
                    "/api/admin/users/{user_id}/time_coin_balance/adjust",
                    "/api/admin/users/{user_id}/coin-adjustment",
                    "/api/admin/users/{user_id}/coin_adjustment",
                    "/api/admin/users/{user_id}/quota",
                    "/api/admin/users/{user_id}/quota/adjust",
                ]
                for index, route_template in enumerate(coin_routes, start=1):
                    route = route_template.format(user_id=user_id)
                    method = ("post", "patch", "put")[index % 3]
                    response = getattr(client, method)(
                        route,
                        json={"delta": 1, "reason": "404 contract coin route"},
                        headers=admin_headers,
                    )
                    self.assertNotEqual(
                        response.status_code,
                        404,
                        f"{method.upper()} {route}: {response.text}",
                    )
                    self.assertEqual(response.status_code, 200)
                    self.assertEqual(response.json()["ledger_entry"]["coins"], 1)

                settings_response = client.post(
                    "/api/admin/system-settings",
                    json={
                        "force_app_update_enabled": True,
                        "latest_version": "8.8.8",
                        "update_notes": "404 contract update settings",
                    },
                    headers=admin_headers,
                )
                self.assertNotEqual(settings_response.status_code, 404)
                self.assertEqual(settings_response.status_code, 200)
                self.assertTrue(
                    settings_response.json()["runtime_status"][
                        "force_app_update_enabled"
                    ]
                )
                settings_patch = client.patch(
                    "/api/admin/settings",
                    json={
                        "force_update_required": True,
                        "latest_version": "8.8.9",
                        "minimum_supported_version": "8.8.8",
                        "update_notes": "404 contract force update settings",
                        "update_download_url": "",
                    },
                    headers=admin_headers,
                )
                self.assertNotEqual(
                    settings_patch.status_code,
                    404,
                    f"PATCH /api/admin/settings: {settings_patch.text}",
                )
                self.assertEqual(settings_patch.status_code, 200)
                self.assertTrue(
                    settings_patch.json()["changed"]["force_update_required"]
                )

                mobile_update = client.get(
                    "/api/mobile/apps/duoyi/update",
                    params={
                        "current_version": "8.8.7",
                        "current_version_code": 80807,
                    },
                )
                self.assertNotEqual(
                    mobile_update.status_code,
                    404,
                    f"GET /api/mobile/apps/duoyi/update: {mobile_update.text}",
                )
                self.assertEqual(mobile_update.status_code, 200)
                mobile_payload = mobile_update.json()
                self.assertTrue(mobile_payload["force_update"])
                self.assertTrue(mobile_payload["force_update_required"])
                self.assertEqual(
                    mobile_payload["minimum_supported_version"], "8.8.8"
                )
                self.assertGreater(
                    mobile_payload["minimum_supported_version_code"], 0
                )

                group_create = client.post(
                    "/api/admin/groups",
                    json={
                        "name": "404 contract group",
                        "description": "group route no-404 check",
                        "default_time_coins": 77,
                        "image_mode": "vip",
                        "is_active": True,
                    },
                    headers=admin_headers,
                )
                self.assertNotEqual(
                    group_create.status_code,
                    404,
                    f"POST /api/admin/groups: {group_create.text}",
                )
                self.assertEqual(group_create.status_code, 200)
                group_id = group_create.json()["id"]
                for route in [
                    "/api/admin/groups",
                    "/api/admin/user-groups",
                    "/api/admin/user_groups",
                ]:
                    response = client.get(route, headers=admin_headers)
                    self.assertNotEqual(
                        response.status_code,
                        404,
                        f"GET {route}: {response.text}",
                    )
                    self.assertEqual(response.status_code, 200)

                for method, route in [
                    ("patch", f"/api/admin/groups/{group_id}"),
                    ("put", f"/api/admin/user-groups/{group_id}"),
                    ("patch", f"/api/admin/user_groups/{group_id}"),
                ]:
                    response = getattr(client, method)(
                        route,
                        json={
                            "name": "404 contract group",
                            "description": "group route no-404 check",
                            "default_time_coins": 78,
                            "image_mode": "general",
                            "is_active": True,
                        },
                        headers=admin_headers,
                    )
                    self.assertNotEqual(
                        response.status_code,
                        404,
                        f"{method.upper()} {route}: {response.text}",
                    )
                    self.assertEqual(response.status_code, 200)

                for index in range(3):
                    created_feedback = client.post(
                        "/api/feedback",
                        json={
                            "category": "bug",
                            "content": f"404 contract feedback page {index}",
                        },
                        headers=user_headers,
                    )
                    self.assertNotEqual(
                        created_feedback.status_code,
                        404,
                        f"POST /api/feedback: {created_feedback.text}",
                    )
                    self.assertEqual(created_feedback.status_code, 200)
                my_feedback_page = client.get(
                    "/api/feedback/me?page=1&page_size=2",
                    headers=user_headers,
                )
                admin_feedback_page = client.get(
                    "/api/admin/feedback?page=1&page_size=2",
                    headers=admin_headers,
                )
                for route, response in [
                    ("/api/feedback/me?page=1&page_size=2", my_feedback_page),
                    ("/api/admin/feedback?page=1&page_size=2", admin_feedback_page),
                ]:
                    self.assertNotEqual(
                        response.status_code,
                        404,
                        f"GET {route}: {response.text}",
                    )
                    self.assertEqual(response.status_code, 200)
                    self.assertIn("items", response.json())
                    self.assertGreaterEqual(response.json()["total"], 3)

                ai_test = client.post(
                    "/api/admin/ai/test",
                    json={"ai_enabled": False},
                    headers=admin_headers,
                )
                ai_healthcheck = client.post(
                    "/api/admin/provider-healthcheck",
                    json={"ai_enabled": False},
                    headers=admin_headers,
                )
                ai_schedule_chat = client.post(
                    "/api/ai/chat",
                    json={
                        "system": "schedule draft test",
                        "user": "tomorrow 9am standup",
                        "temperature": 0,
                        "max_tokens": 16,
                    },
                    headers=user_headers,
                )
                for route, response in [
                    ("/api/admin/ai/test", ai_test),
                    ("/api/admin/provider-healthcheck", ai_healthcheck),
                    ("/api/ai/chat", ai_schedule_chat),
                ]:
                    self.assertNotEqual(
                        response.status_code,
                        404,
                        f"POST {route}: {response.text}",
                    )
                self.assertEqual(ai_test.status_code, 200)
                self.assertEqual(ai_healthcheck.status_code, 200)
                self.assertEqual(ai_schedule_chat.status_code, 503)
        finally:
            api.AVATAR_UPLOAD_DIR = old_avatar_dir

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

    def test_admin_settings_scope_uses_feature_permissions(self):
        ai_admin = self._make_admin("ai-settings-admin", ["ai"])
        backup_admin = self._make_admin("backup-settings-admin", ["backup"])

        ai_settings = api.admin_get_settings(ai_admin, scope="ai")
        self.assertIn("ai_model", ai_settings)
        self.assertIn("ai_api_key_set", ai_settings)
        self.assertNotIn("backup_enabled", ai_settings)
        self.assertNotIn("email_service_enabled", ai_settings)

        backup_settings = api.admin_get_settings(backup_admin, scope="backup")
        self.assertIn("backup_enabled", backup_settings)
        self.assertIn("reminder_email_enabled", backup_settings)
        self.assertIn("email_service_enabled", backup_settings)
        self.assertNotIn("ai_model", backup_settings)
        backup_updated = api.admin_update_settings(
            api.SettingsUpdate(
                backup_enabled=False,
                reminder_email_enabled=True,
                email_service_enabled=False,
            ),
            actor=backup_admin,
        )
        self.assertEqual(backup_updated["changed"]["backup_enabled"], False)
        self.assertEqual(
            backup_updated["changed"]["reminder_email_enabled"], True
        )
        self.assertEqual(backup_updated["changed"]["email_service_enabled"], False)

        with self.assertRaises(HTTPException) as denied:
            api.admin_get_settings(ai_admin)
        self.assertEqual(denied.exception.status_code, 403)

    def test_admin_force_update_settings_persist_to_public_config(self):
        admin_id = self._make_admin("force-update-admin", ["settings"])

        updated = api.admin_update_settings(
            api.SettingsUpdate(
                force_update_required=True,
                latest_version="2.4.0",
                minimum_supported_version="2.1.0",
                update_notes="必须升级以继续同步",
                update_download_url="https://example.test/duoyi-2.4.0.apk",
            ),
            actor=admin_id,
        )

        self.assertEqual(
            updated["changed"],
            {
                "force_update_required": True,
                "force_app_update_enabled": True,
                "latest_version": "2.4.0",
                "latest_version_name": "2.4.0",
                "minimum_supported_version": "2.1.0",
                "update_notes": "必须升级以继续同步",
                "release_notes": "必须升级以继续同步",
                "update_download_url": "https://example.test/duoyi-2.4.0.apk",
                "download_url": "https://example.test/duoyi-2.4.0.apk",
            },
        )
        settings = api.admin_get_settings(admin_id)
        self.assertTrue(settings["force_update_required"])
        self.assertTrue(settings["force_app_update_enabled"])
        self.assertEqual(settings["latest_version"], "2.4.0")
        self.assertEqual(settings["latest_version_name"], "2.4.0")
        self.assertEqual(settings["minimum_supported_version"], "2.1.0")
        self.assertEqual(settings["update_notes"], "必须升级以继续同步")
        self.assertEqual(settings["release_notes"], "必须升级以继续同步")
        self.assertEqual(
            settings["update_download_url"],
            "https://example.test/duoyi-2.4.0.apk",
        )
        self.assertEqual(
            settings["download_url"],
            "https://example.test/duoyi-2.4.0.apk",
        )

        config = api.public_config()
        self.assertEqual(config["latest_version"], "2.4.0")
        self.assertEqual(config["latest_version_name"], "2.4.0")
        self.assertEqual(config["app_update"]["latest_version"], "2.4.0")
        self.assertTrue(config["app_update"]["force_update_required"])
        self.assertTrue(config["app_update"]["force_app_update_enabled"])
        self.assertEqual(
            config["app_update"]["minimum_supported_version"],
            "2.1.0",
        )
        self.assertEqual(config["app_update"]["update_notes"], "必须升级以继续同步")
        self.assertEqual(config["app_update"]["release_notes"], "必须升级以继续同步")
        self.assertEqual(
            config["app_update"]["update_download_url"],
            "https://example.test/duoyi-2.4.0.apk",
        )
        self.assertEqual(
            config["app_update"]["download_url"],
            "https://example.test/duoyi-2.4.0.apk",
        )

        disabled = api.admin_update_settings(
            api.SettingsUpdate(force_update_required=False),
            actor=admin_id,
        )
        self.assertEqual(disabled["changed"]["force_update_required"], False)
        self.assertFalse(api.public_config()["app_update"]["force_update_required"])

        retained_url = api.admin_update_settings(
            api.SettingsUpdate(
                force_update_required=True,
                latest_version="2.5.0",
                minimum_supported_version="2.1.0",
                update_notes="继续使用已有安装包地址",
            ),
            actor=admin_id,
        )
        self.assertNotIn("update_download_url", retained_url["changed"])
        retained_settings = api.admin_get_settings(admin_id)
        self.assertEqual(
            retained_settings["update_download_url"],
            "https://example.test/duoyi-2.4.0.apk",
        )
        self.assertEqual(
            retained_settings["download_url"],
            "https://example.test/duoyi-2.4.0.apk",
        )

    def test_admin_settings_post_alias_updates_force_update_contract(self):
        admin_id = self._make_admin("force-update-post-alias", ["settings"])
        headers = {"Authorization": f"Bearer {api.TOKENS[admin_id]}"}

        with TestClient(api.app) as client:
            response = client.post(
                "/api/admin/settings",
                json={
                    "force_update_required": True,
                    "latest_version": "2.6.0",
                    "minimum_supported_version": "2.5.0",
                    "update_notes": "POST 别名写入更新策略",
                    "update_download_url": "https://example.test/duoyi-2.6.0.apk",
                },
                headers=headers,
            )

        self.assertEqual(response.status_code, 200)
        changed = response.json()["changed"]
        self.assertTrue(changed["force_update_required"])
        self.assertEqual(changed["latest_version"], "2.6.0")
        self.assertEqual(changed["minimum_supported_version"], "2.5.0")
        self.assertEqual(changed["update_notes"], "POST 别名写入更新策略")
        self.assertEqual(
            changed["update_download_url"],
            "https://example.test/duoyi-2.6.0.apk",
        )
        self.assertTrue(api.public_config()["app_update"]["force_update_required"])
        self.assertEqual(
            api.public_config()["app_update"]["latest_version"],
            "2.6.0",
        )

    def test_force_update_settings_require_settings_permission(self):
        admin_id = self._make_admin("force-update-denied", ["users"])

        with self.assertRaises(HTTPException) as denied:
            api.admin_update_settings(
                api.SettingsUpdate(
                    force_update_required=True,
                    latest_version="9.9.9",
                ),
                actor=admin_id,
            )

        self.assertEqual(denied.exception.status_code, 403)

    def test_update_policy_fills_default_notes_and_mobile_update(self):
        admin_id = self._make_admin("force-update-notes", ["settings"])

        def reset_policy_settings():
            db = api.get_db()
            try:
                for key in (
                    "latest_version",
                    "latest_version_name",
                    "minimum_supported_version",
                    "update_notes",
                    "release_notes",
                    "update_download_url",
                    "download_url",
                ):
                    api._setting_set(db, key, "")
                api._setting_set(db, "force_update_required", False)
                api._setting_set(db, "force_app_update_enabled", False)
                db.commit()
            finally:
                db.close()

        for payload in (
            api.SettingsUpdate(latest_version="9.9.9"),
            api.SettingsUpdate(update_download_url="https://example.test/duoyi.apk"),
            api.SettingsUpdate(force_update_required=True),
            api.SettingsUpdate(minimum_supported_version="9.9.9"),
        ):
            reset_policy_settings()
            result = api.admin_update_settings(payload, actor=admin_id)
            self.assertEqual(result["changed"]["update_notes"], api.APP_UPDATE_DEFAULT_NOTES)
            self.assertEqual(result["changed"]["release_notes"], api.APP_UPDATE_DEFAULT_NOTES)
            config = api.public_config()["app_update"]
            self.assertEqual(config["update_notes"], api.APP_UPDATE_DEFAULT_NOTES)
            self.assertEqual(config["release_notes"], api.APP_UPDATE_DEFAULT_NOTES)

        reset_policy_settings()
        old_repository = api.APP_UPDATE_REPOSITORY
        api.APP_UPDATE_REPOSITORY = ""
        try:
            with TestClient(api.app) as client:
                system_settings = client.post(
                    "/api/admin/system-settings",
                    json={"force_app_update_enabled": True},
                    headers={"Authorization": f"Bearer {api.TOKENS[admin_id]}"},
                )
                self.assertEqual(system_settings.status_code, 200)
                runtime = system_settings.json()["runtime_status"]
                self.assertTrue(runtime["force_app_update_enabled"])
                self.assertEqual(runtime["latest_version_name"], api.APP_CURRENT_VERSION)
                self.assertEqual(
                    runtime["release_notes"], api.APP_UPDATE_DEFAULT_NOTES
                )

                response = client.get(
                    "/api/mobile/apps/duoyi/update",
                    params={
                        "current_version_code": api.APP_CURRENT_VERSION_CODE
                    },
                )
            self.assertEqual(response.status_code, 200)
            mobile = response.json()
            self.assertFalse(mobile["available"])
            self.assertFalse(mobile["force_update"])
            self.assertEqual(mobile["force_update_blocked_reason"], "")
            self.assertEqual(mobile["latest_version_name"], api.APP_CURRENT_VERSION)
            self.assertEqual(
                mobile["minimum_supported_version"], api.APP_CURRENT_VERSION
            )
            self.assertGreater(mobile["minimum_supported_version_code"], 0)
            self.assertTrue("force_update_required" in mobile)
            self.assertGreater(mobile["latest_version_code"], 0)
            self.assertEqual(mobile["release_notes"], api.APP_UPDATE_DEFAULT_NOTES)
            self.assertEqual(
                mobile["api_contract_version"], api.API_CONTRACT_VERSION
            )
            self.assertEqual(
                mobile["required_routes_hash"], api.API_CONTRACT_ROUTES_HASH
            )
            self.assertIn(
                "GET /api/mobile/apps/duoyi/update", mobile["required_routes"]
            )
        finally:
            api.APP_UPDATE_REPOSITORY = old_repository

        reset_policy_settings()
        old_repository = api.APP_UPDATE_REPOSITORY
        api.APP_UPDATE_REPOSITORY = ""
        try:
            api.admin_update_settings(
                api.SettingsUpdate(
                    latest_version=api.APP_CURRENT_VERSION,
                    minimum_supported_version="9.9.9",
                    force_update_required=True,
                ),
                actor=admin_id,
            )
            with TestClient(api.app) as client:
                response = client.get(
                    "/api/mobile/apps/duoyi/update",
                    params={
                        "current_version": api.APP_CURRENT_VERSION,
                        "current_version_code": api.APP_CURRENT_VERSION_CODE,
                    },
                )
            self.assertEqual(response.status_code, 200)
            mobile = response.json()
            self.assertTrue(mobile["force_update"])
            self.assertTrue(mobile["force_update_required"])
            self.assertEqual(mobile["minimum_supported_version"], "9.9.9")
            self.assertEqual(mobile["latest_version_name"], "9.9.9")
            self.assertEqual(
                mobile["force_update_blocked_reason"],
                "missing_download_url",
            )
        finally:
            api.APP_UPDATE_REPOSITORY = old_repository

        reset_policy_settings()
        old_repository = api.APP_UPDATE_REPOSITORY
        api.APP_UPDATE_REPOSITORY = ""
        try:
            api.admin_update_settings(
                api.SettingsUpdate(
                    latest_version="9.9.9",
                    update_download_url="",
                    force_update_required=True,
                    update_notes="必须升级但还没有安装包",
                ),
                actor=admin_id,
            )
            with TestClient(api.app) as client:
                response = client.get(
                    "/api/mobile/apps/duoyi/update",
                    params={
                        "current_version_code": api.APP_CURRENT_VERSION_CODE
                    },
                )
            self.assertEqual(response.status_code, 200)
            mobile = response.json()
            self.assertTrue(mobile["available"])
            self.assertTrue(mobile["force_update"])
            self.assertEqual(
                mobile["force_update_blocked_reason"],
                "missing_download_url",
            )
            self.assertEqual(mobile["latest_version_name"], "9.9.9")
            self.assertEqual(mobile["download_url"], "")
        finally:
            api.APP_UPDATE_REPOSITORY = old_repository

        reset_policy_settings()
        old_repository = api.APP_UPDATE_REPOSITORY
        old_mobile_apk_dir = api.MOBILE_APK_DIR
        api.APP_UPDATE_REPOSITORY = ""
        api.MOBILE_APK_DIR = os.path.join(self._tmp.name, "missing_mobile_apps")
        try:
            api.admin_update_settings(
                api.SettingsUpdate(
                    latest_version="9.9.9",
                    update_download_url="/api/mobile/apps/duoyi/download",
                    force_update_required=True,
                    update_notes="配置了本地下载但安装包不存在",
                ),
                actor=admin_id,
            )
            with TestClient(api.app) as client:
                response = client.get(
                    "/api/mobile/apps/duoyi/update",
                    params={
                        "current_version_code": api.APP_CURRENT_VERSION_CODE
                    },
                )
            self.assertEqual(response.status_code, 200)
            mobile = response.json()
            self.assertTrue(mobile["available"])
            self.assertTrue(mobile["force_update"])
            self.assertEqual(
                mobile["force_update_blocked_reason"],
                "missing_download_url",
            )
            self.assertEqual(mobile["download_url"], "")
        finally:
            api.APP_UPDATE_REPOSITORY = old_repository
            api.MOBILE_APK_DIR = old_mobile_apk_dir

        result = api.admin_update_settings(
            api.SettingsUpdate(
                latest_version="9.9.9",
                update_notes="修复关键问题并优化更新提示",
            ),
            actor=admin_id,
        )
        self.assertEqual(result["changed"]["latest_version"], "9.9.9")
        self.assertEqual(result["changed"]["update_notes"], "修复关键问题并优化更新提示")

    def test_force_update_current_preset_uses_release_channel_version(self):
        admin_id = self._make_admin("force-update-channel", ["settings"])
        old_repository = api.APP_UPDATE_REPOSITORY
        old_mobile_apk_dir = api.MOBILE_APK_DIR
        api.APP_UPDATE_REPOSITORY = ""
        api.MOBILE_APK_DIR = os.path.join(self._tmp.name, "mobile_apps")
        next_version = api._next_patch_version(api.APP_CURRENT_VERSION)
        app_dir = os.path.join(api.MOBILE_APK_DIR, "duoyi")
        os.makedirs(app_dir, exist_ok=True)
        with open(os.path.join(app_dir, "duoyi.apk"), "wb") as handle:
            handle.write(b"fake apk")
        with open(os.path.join(app_dir, "manifest.json"), "w", encoding="utf-8") as handle:
            json.dump(
                {
                    "apk_name": "duoyi.apk",
                    "version_name": next_version,
                    "version_code": api._app_version_code(next_version),
                    "release_notes": "发布通道修复通知和小组件问题",
                },
                handle,
            )
        try:
            with TestClient(api.app) as client:
                system_settings = client.post(
                    "/api/admin/system-settings",
                    json={"force_app_update_enabled": True},
                    headers={"Authorization": f"Bearer {api.TOKENS[admin_id]}"},
                )
                self.assertEqual(system_settings.status_code, 200)
                runtime = system_settings.json()["runtime_status"]
                self.assertEqual(runtime["latest_version_name"], api.APP_CURRENT_VERSION)
                self.assertTrue(runtime["force_app_update_enabled"])

                response = client.get(
                    "/api/mobile/apps/duoyi/update",
                    params={
                        "current_version_code": api.APP_CURRENT_VERSION_CODE
                    },
                )
            self.assertEqual(response.status_code, 200)
            mobile = response.json()
            self.assertTrue(mobile["available"])
            self.assertTrue(mobile["force_update"])
            self.assertEqual(mobile["latest_version_name"], next_version)
            self.assertEqual(
                mobile["release_notes"], "发布通道修复通知和小组件问题"
            )
            self.assertIn("/api/mobile/apps/duoyi/download", mobile["download_url"])
        finally:
            api.APP_UPDATE_REPOSITORY = old_repository
            api.MOBILE_APK_DIR = old_mobile_apk_dir

    def test_stale_release_channel_does_not_downgrade_mobile_update(self):
        old_github_latest = api._github_latest_mobile_release
        old_mobile_apk_dir = api.MOBILE_APK_DIR
        api.MOBILE_APK_DIR = os.path.join(self._tmp.name, "empty_mobile_apps")

        def stale_release():
            return {
                "latest_version_name": "1.1.12",
                "latest_version_code": 110012,
                "download_url": "https://example.test/duoyi-1.1.12.apk",
                "release_notes": "旧发布不应覆盖当前版本",
            }

        api._github_latest_mobile_release = stale_release
        try:
            db = api.get_db()
            try:
                api._setting_set(db, "latest_version", "1.1.12")
                api._setting_set(db, "latest_version_name", "1.1.12")
                api._setting_set(
                    db,
                    "download_url",
                    "https://example.test/duoyi-1.1.12.apk",
                )
                api._setting_set(
                    db,
                    "update_download_url",
                    "https://example.test/duoyi-1.1.12.apk",
                )
                db.commit()
            finally:
                db.close()
            with TestClient(api.app) as client:
                response = client.get(
                    "/api/mobile/apps/duoyi/update",
                    params={
                        "current_version": "1.1.12",
                        "current_version_code": "110012",
                    },
                )
            self.assertEqual(response.status_code, 200)
            mobile = response.json()
            self.assertTrue(mobile["available"])
            self.assertEqual(mobile["latest_version_name"], api.APP_CURRENT_VERSION)
            self.assertEqual(mobile["latest_version_code"], api.APP_CURRENT_VERSION_CODE)
            self.assertEqual(mobile["download_url"], "")
            self.assertNotIn("1.1.12", mobile["release_url"])

            current_response = client.get(
                "/api/mobile/apps/duoyi/update",
                params={"current_version": api.APP_CURRENT_VERSION},
            )
            self.assertEqual(current_response.status_code, 200)
            current_mobile = current_response.json()
            self.assertFalse(current_mobile["available"])
            self.assertEqual(
                current_mobile["current_version_code"],
                api.APP_CURRENT_VERSION_CODE,
            )
            self.assertEqual(current_mobile["download_url"], "")
        finally:
            api._github_latest_mobile_release = old_github_latest
            api.MOBILE_APK_DIR = old_mobile_apk_dir

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
        registered = self._register_with_email(
            "reset-code-user",
            "reset-code@example.com",
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
        registered = self._register_with_email(
            "reset-code-by-user",
            "reset-code-by-user@example.com",
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
        registered = self._register_with_email(
            "change-password-user",
            "change-password-user@example.com",
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
        registered = self._register_with_email(
            "avatar-user",
            "avatar-user@example.com",
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
                self.assertTrue(payload["avatar"].startswith("/api/uploads/avatars/"))
                self.assertEqual(payload["coin_balance"], 0)
                self.assertEqual(payload["lifetime_coins"], 0)
                avatar_path = api._avatar_file_path_from_url(payload["avatar"])
                self.assertIsNotNone(avatar_path)
                self.assertTrue(avatar_path.exists())

                filename = os.path.basename(str(avatar_path))
                fetched = client.get(f"/api/uploads/avatars/{filename}")
                self.assertEqual(fetched.status_code, 200)
                self.assertEqual(fetched.content, b"\x89PNG\r\n\x1a\navatar-bytes")

                profile_avatar = client.patch(
                    "/api/me/profile",
                    headers={"Authorization": f"Bearer {registered['token']}"},
                    json={"avatar": "https://example.com/should-not-save.png"},
                )
                self.assertEqual(profile_avatar.status_code, 200)
                self.assertEqual(profile_avatar.json()["avatar"], payload["avatar"])

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

                alias_response = client.post(
                    "/api/me/profile/avatar",
                    headers={"Authorization": f"Bearer {registered['token']}"},
                    files={
                        "file": (
                            "avatar.png",
                            b"\x89PNG\r\n\x1a\navatar-file-alias",
                            "image/png",
                        )
                    },
                )
                self.assertEqual(alias_response.status_code, 200)
                self.assertIn("/api/uploads/avatars/", alias_response.json()["avatar"])
        finally:
            api.AVATAR_UPLOAD_DIR = old_avatar_dir

    def test_password_reset_request_returns_dev_code_without_mail_provider(self):
        registered = self._register_with_email(
            "reset-dev-user",
            "reset-dev@example.com",
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
            latest_dev_code = response.json()["dev_code"]
            for path in (
                "/api/auth/reset-password",
                "/api/auth/reset-password/request",
                "/api/auth/forgot-password",
                "/api/auth/forgot-password/request",
                "/api/password-reset",
                "/api/password-reset/request",
            ):
                alias_response = client.post(
                    path,
                    json={"account": "reset-dev-user"},
                )
                self.assertEqual(alias_response.status_code, 200, path)
                self.assertTrue(alias_response.json()["ok"], path)
                self.assertTrue(alias_response.json()["dev_code"], path)
                latest_dev_code = alias_response.json()["dev_code"]
            confirm_alias = client.post(
                "/api/auth/reset-password/confirm",
                json={
                    "account": "reset-dev-user",
                    "code": latest_dev_code,
                    "new_password": "newpass456",
                },
            )
            self.assertEqual(confirm_alias.status_code, 200)
            self.assertTrue(confirm_alias.json()["ok"])
        self.assertNotIn(registered["user_id"], api.TOKENS)
        logged_in = api.login(
            api.LoginRequest(username="reset-dev-user", password="newpass456")
        )
        self.assertEqual(logged_in["user_id"], registered["user_id"])

    def test_password_reset_sends_email_and_changes_password(self):
        registered = self._register_with_email(
            "reset-user",
            "reset@example.com",
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
                "UPDATE users SET is_admin=1, admin_permissions=? WHERE id=?",
                (json.dumps(["audit"]), owner_id),
            )
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

    def test_sync_preferences_changed_keys_merge_independent_device_edits(self):
        user_id = self._register("sync-pref-keys")

        api.sync(
            api.SyncRequest(
                preferences={
                    "values": {
                        "dailyReminderEnabled": False,
                        "reminderVolumePercent": 40,
                    },
                    "updatedAt": "2026-05-20T00:00:00Z",
                },
            ),
            user_id=user_id,
        )

        api.sync(
            api.SyncRequest(
                preferences={
                    "values": {
                        "dailyReminderEnabled": True,
                        "reminderVolumePercent": 40,
                    },
                    "changedKeys": ["dailyReminderEnabled"],
                    "updatedAt": "2026-05-20T00:01:00Z",
                },
            ),
            user_id=user_id,
        )

        merged = api.sync(
            api.SyncRequest(
                preferences={
                    "values": {
                        "dailyReminderEnabled": False,
                        "reminderVolumePercent": 80,
                    },
                    "changedKeys": ["reminderVolumePercent"],
                    "updatedAt": "2026-05-20T00:02:00Z",
                },
            ),
            user_id=user_id,
        )

        values = merged["preferences"]["values"]
        self.assertTrue(values["dailyReminderEnabled"])
        self.assertEqual(values["reminderVolumePercent"], 80)

        round_trip = api.sync(api.SyncRequest(), user_id=user_id)
        values = round_trip["preferences"]["values"]
        self.assertTrue(values["dailyReminderEnabled"])
        self.assertEqual(values["reminderVolumePercent"], 80)

    def test_sync_quick_capture_templates_merge_by_id_and_tombstone(self):
        user_id = self._register("sync-quick-templates")

        api.sync(
            api.SyncRequest(
                quick_capture_templates={
                    "items": [
                        {
                            "id": "template-a",
                            "title": "模板 A",
                            "content": "A",
                            "createdAt": "2026-05-20T00:00:00Z",
                            "updatedAt": "2026-05-20T00:00:00Z",
                        },
                        {
                            "id": "template-shared",
                            "title": "旧共享模板",
                            "content": "old",
                            "createdAt": "2026-05-20T00:00:00Z",
                            "updatedAt": "2026-05-20T00:00:00Z",
                        },
                    ],
                    "updatedAt": "2026-05-20T00:00:00Z",
                },
            ),
            user_id=user_id,
        )

        merged = api.sync(
            api.SyncRequest(
                quick_capture_templates={
                    "items": [
                        {
                            "id": "template-b",
                            "title": "模板 B",
                            "content": "B",
                            "createdAt": "2026-05-20T00:01:00Z",
                            "updatedAt": "2026-05-20T00:01:00Z",
                        },
                        {
                            "id": "template-shared",
                            "title": "新共享模板",
                            "content": "new",
                            "createdAt": "2026-05-20T00:00:00Z",
                            "updatedAt": "2026-05-20T00:02:00Z",
                        },
                    ],
                    "updatedAt": "2026-05-20T00:02:00Z",
                },
            ),
            user_id=user_id,
        )

        templates = {item["id"]: item for item in merged["quick_capture_templates"]["items"]}
        self.assertIn("template-a", templates)
        self.assertIn("template-b", templates)
        self.assertEqual(templates["template-shared"]["title"], "新共享模板")

        stale = api.sync(
            api.SyncRequest(
                quick_capture_templates={
                    "items": [
                        {
                            "id": "template-shared",
                            "title": "过期共享模板",
                            "content": "stale",
                            "createdAt": "2026-05-20T00:00:00Z",
                            "updatedAt": "2026-05-20T00:01:00Z",
                        }
                    ],
                    "updatedAt": "2026-05-20T00:03:00Z",
                },
            ),
            user_id=user_id,
        )
        templates = {item["id"]: item for item in stale["quick_capture_templates"]["items"]}
        self.assertEqual(templates["template-shared"]["title"], "新共享模板")

        deleted = api.sync(
            api.SyncRequest(
                deleted_items={
                    "quick_capture_templates": {
                        "template-a": "2026-05-20T00:04:00Z",
                    },
                },
            ),
            user_id=user_id,
        )
        templates = {
            item["id"]: item for item in deleted["quick_capture_templates"]["items"]
        }
        self.assertNotIn("template-a", templates)
        self.assertIn("template-b", templates)
        self.assertEqual(
            deleted["deleted_items"]["quick_capture_templates"]["template-a"],
            "2026-05-20T00:04:00Z",
        )

        round_trip = api.sync(api.SyncRequest(), user_id=user_id)
        templates = {
            item["id"]: item for item in round_trip["quick_capture_templates"]["items"]
        }
        self.assertNotIn("template-a", templates)
        self.assertIn("template-b", templates)
        self.assertEqual(templates["template-shared"]["title"], "新共享模板")

    def test_sync_round_trips_location_preferences_quick_capture_courses_time_entries(
        self,
    ):
        user_id = self._register("sync-new-collections")

        synced = api.sync(
            api.SyncRequest(
                location_reminders=[
                    {
                        "id": "location-1",
                        "title": "到公司提醒",
                        "latitude": 31.2304,
                        "longitude": 121.4737,
                        "radiusMeters": 200,
                        "isEnabled": True,
                        "triggerOnce": False,
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
                preferences={
                    "values": {
                        "firstDayOfWeek": 1,
                        "reminderSound": "morning",
                    },
                    "updatedAt": "2026-05-20T00:01:00Z",
                },
                quick_capture_templates={
                    "items": [
                        {
                            "id": "template-round-trip",
                            "title": "灵感",
                            "content": "记录一个想法",
                            "createdAt": "2026-05-20T00:00:00Z",
                            "updatedAt": "2026-05-20T00:02:00Z",
                        }
                    ],
                    "updatedAt": "2026-05-20T00:02:00Z",
                },
                courses=[
                    {
                        "id": "course-1",
                        "name": "高等数学",
                        "teacher": "王老师",
                        "location": "A101",
                        "weekday": 1,
                        "startTime": "08:00",
                        "endTime": "09:40",
                        "updatedAt": "2026-05-20T00:03:00Z",
                    }
                ],
                time_entries=[
                    {
                        "id": "time-1",
                        "title": "深度工作",
                        "categoryId": "focus",
                        "startedAt": "2026-05-20T09:00:00Z",
                        "endedAt": "2026-05-20T10:00:00Z",
                        "updatedAt": "2026-05-20T00:04:00Z",
                    }
                ],
            ),
            user_id=user_id,
        )

        self.assertEqual(synced["location_reminders"][0]["id"], "location-1")
        self.assertEqual(synced["preferences"]["values"]["reminderSound"], "morning")
        self.assertEqual(
            synced["quick_capture_templates"]["items"][0]["id"],
            "template-round-trip",
        )
        self.assertEqual(synced["courses"][0]["name"], "高等数学")
        self.assertEqual(synced["time_entries"][0]["title"], "深度工作")

        round_trip = api.sync(api.SyncRequest(), user_id=user_id)
        self.assertEqual(round_trip["location_reminders"][0]["title"], "到公司提醒")
        self.assertEqual(round_trip["preferences"]["values"]["firstDayOfWeek"], 1)
        self.assertEqual(
            round_trip["quick_capture_templates"]["items"][0]["title"],
            "灵感",
        )
        self.assertEqual(round_trip["courses"][0]["teacher"], "王老师")
        self.assertEqual(round_trip["time_entries"][0]["categoryId"], "focus")

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

    def test_sync_habit_undo_uses_completion_updated_at(self):
        user_id = self._register("sync-habit-undo")

        api.sync(
            api.SyncRequest(
                habits=[
                    {
                        "id": "habit-undo",
                        "name": "撤回测试",
                        "completions": {"2026-05-21": 2},
                        "completionUpdatedAt": {
                            "2026-05-21": "2026-05-20T00:01:00Z",
                        },
                        "updatedAt": "2026-05-20T00:01:00Z",
                    }
                ],
            ),
            user_id=user_id,
        )

        undone = api.sync(
            api.SyncRequest(
                habits=[
                    {
                        "id": "habit-undo",
                        "name": "撤回测试",
                        "completions": {},
                        "completionUpdatedAt": {
                            "2026-05-21": "2026-05-20T00:02:00Z",
                        },
                        "updatedAt": "2026-05-20T00:02:00Z",
                    }
                ],
            ),
            user_id=user_id,
        )

        self.assertNotIn("2026-05-21", undone["habits"][0]["completions"])
        self.assertEqual(
            undone["habits"][0]["completionUpdatedAt"]["2026-05-21"],
            "2026-05-20T00:02:00Z",
        )

        stale = api.sync(
            api.SyncRequest(
                habits=[
                    {
                        "id": "habit-undo",
                        "name": "撤回测试",
                        "completions": {"2026-05-21": 2},
                        "completionUpdatedAt": {
                            "2026-05-21": "2026-05-20T00:01:00Z",
                        },
                        "updatedAt": "2026-05-20T00:03:00Z",
                    }
                ],
            ),
            user_id=user_id,
        )

        self.assertNotIn("2026-05-21", stale["habits"][0]["completions"])
        self.assertEqual(
            stale["habits"][0]["completionUpdatedAt"]["2026-05-21"],
            "2026-05-20T00:02:00Z",
        )

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

    def test_sync_preserves_countdown_collection_and_migrates_legacy_normal(self):
        user_id = self._register("sync-countdowns-preserve")

        synced = api.sync(
            api.SyncRequest(
                countdowns=[
                    {
                        "id": "countdown-keep",
                        "title": "倒数日保留",
                        "targetDate": "2026-06-01T00:00:00Z",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
                anniversaries=[
                    {
                        "id": "legacy-countdown",
                        "title": "旧普通倒数日",
                        "originDate": "2026-05-22T00:00:00Z",
                        "type": 0,
                        "updatedAt": "2026-05-20T00:00:00Z",
                    },
                    {
                        "id": "birthday-keep",
                        "title": "生日保留",
                        "originDate": "2026-05-21T00:00:00Z",
                        "type": 1,
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
            ),
            user_id=user_id,
        )

        countdown_ids = {item["id"] for item in synced["countdowns"]}
        self.assertEqual(countdown_ids, {"countdown-keep", "legacy-countdown"})
        self.assertEqual(synced["anniversaries"][0]["id"], "birthday-keep")
        self.assertIn("countdowns", synced["collection_hashes"])

        db = api.get_db()
        try:
            row = db.execute(
                "SELECT countdowns, anniversaries FROM sync_data WHERE user_id=?",
                (user_id,),
            ).fetchone()
        finally:
            db.close()
        self.assertEqual(
            {item["id"] for item in json.loads(row["countdowns"])},
            {"countdown-keep", "legacy-countdown"},
        )
        self.assertEqual(
            {item["id"] for item in json.loads(row["anniversaries"])},
            {"birthday-keep"},
        )

        deleted = api.sync_item_delta(
            api.SyncItemDeltaRequest(
                deleted_items={
                    "countdowns": {
                        "countdown-keep": "2026-05-21T00:00:00Z",
                    }
                },
                collection_hashes=synced["collection_hashes"],
            ),
            user_id=user_id,
        )
        self.assertEqual(
            [item["id"] for item in deleted["countdowns"]],
            ["legacy-countdown"],
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

    def test_sync_item_delta_tombstone_only_deletes_existing_item(self):
        user_id = self._register("sync-item-delta-tombstone-only")

        first = api.sync(
            api.SyncRequest(
                todos=[
                    {
                        "id": "todo-tombstone-only-remove",
                        "title": "仅墓碑删除",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    },
                    {
                        "id": "todo-tombstone-only-keep",
                        "title": "保留待办",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    },
                ],
                notes=[
                    {
                        "id": "note-tombstone-only-keep",
                        "title": "保留笔记",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
            ),
            user_id=user_id,
        )

        changed = api.sync_item_delta(
            api.SyncItemDeltaRequest(
                items={},
                deleted_items={
                    "todos": {
                        "todo-tombstone-only-remove": "2026-05-20T00:01:00Z"
                    }
                },
                collection_hashes=first["collection_hashes"],
            ),
            user_id=user_id,
        )

        todos = {item["id"]: item for item in changed["todos"]}
        self.assertNotIn("todo-tombstone-only-remove", todos)
        self.assertEqual(todos["todo-tombstone-only-keep"]["title"], "保留待办")
        self.assertEqual(changed["notes"][0]["id"], "note-tombstone-only-keep")
        self.assertNotEqual(
            changed["collection_hashes"]["todos"],
            first["collection_hashes"]["todos"],
        )
        self.assertEqual(
            changed["collection_hashes"]["notes"],
            first["collection_hashes"]["notes"],
        )

        round_trip = api.sync(api.SyncRequest(), user_id=user_id)
        round_trip_todos = {item["id"]: item for item in round_trip["todos"]}
        self.assertNotIn("todo-tombstone-only-remove", round_trip_todos)
        self.assertIn("todo-tombstone-only-keep", round_trip_todos)

    def test_sync_diaries_merge_same_date_by_newest_updated_at(self):
        user_id = self._register("sync-diaries-same-date")

        api.sync(
            api.SyncRequest(
                diaries=[
                    {
                        "id": "diary-old-id",
                        "date": "2026-05-20",
                        "content": "旧日记",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ]
            ),
            user_id=user_id,
        )

        merged = api.sync(
            api.SyncRequest(
                diaries=[
                    {
                        "id": "diary-new-id",
                        "date": "2026-05-20T23:30:00+08:00",
                        "content": "同一天的新日记",
                        "updatedAt": "2026-05-20T00:01:00Z",
                    }
                ]
            ),
            user_id=user_id,
        )

        self.assertEqual(len(merged["diaries"]), 1)
        self.assertEqual(merged["diaries"][0]["id"], "diary-new-id")
        self.assertEqual(merged["diaries"][0]["content"], "同一天的新日记")

        stale = api.sync(
            api.SyncRequest(
                diaries=[
                    {
                        "id": "diary-stale-id",
                        "date": "2026-05-20",
                        "content": "过期日记",
                        "updatedAt": "2026-05-19T23:59:00Z",
                    }
                ]
            ),
            user_id=user_id,
        )
        self.assertEqual(len(stale["diaries"]), 1)
        self.assertEqual(stale["diaries"][0]["id"], "diary-new-id")

        round_trip = api.sync(api.SyncRequest(), user_id=user_id)
        self.assertEqual(len(round_trip["diaries"]), 1)
        self.assertEqual(round_trip["diaries"][0]["id"], "diary-new-id")

    def test_sync_timestamped_schedule_collections_reject_stale_payloads(self):
        user_id = self._register("sync-timestamped-schedule")

        first = api.sync(
            api.SyncRequest(
                courses=[
                    {
                        "id": "course-shared",
                        "name": "旧课程",
                        "teacher": "旧老师",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
                anniversaries=[
                    {
                        "id": "anniversary-shared",
                        "title": "旧纪念日",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
                location_reminders=[
                    {
                        "id": "location-shared",
                        "title": "旧位置提醒",
                        "updatedAt": "2026-05-20T00:00:00Z",
                    }
                ],
            ),
            user_id=user_id,
        )
        self.assertEqual(first["courses"][0]["name"], "旧课程")
        self.assertEqual(first["anniversaries"][0]["title"], "旧纪念日")
        self.assertEqual(first["location_reminders"][0]["title"], "旧位置提醒")

        stale = api.sync(
            api.SyncRequest(
                courses=[
                    {
                        "id": "course-shared",
                        "name": "过期课程",
                        "teacher": "过期老师",
                        "updatedAt": "2026-05-19T23:59:00Z",
                    }
                ],
                anniversaries=[
                    {
                        "id": "anniversary-shared",
                        "title": "过期纪念日",
                        "updatedAt": "2026-05-19T23:59:00Z",
                    }
                ],
                location_reminders=[
                    {
                        "id": "location-shared",
                        "title": "过期位置提醒",
                        "updatedAt": "2026-05-19T23:59:00Z",
                    }
                ],
            ),
            user_id=user_id,
        )
        self.assertEqual(stale["courses"][0]["name"], "旧课程")
        self.assertEqual(stale["anniversaries"][0]["title"], "旧纪念日")
        self.assertEqual(stale["location_reminders"][0]["title"], "旧位置提醒")

        newer = api.sync(
            api.SyncRequest(
                courses=[
                    {
                        "id": "course-shared",
                        "name": "新课程",
                        "teacher": "新老师",
                        "updatedAt": "2026-05-20T00:01:00Z",
                    }
                ],
                anniversaries=[
                    {
                        "id": "anniversary-shared",
                        "title": "新纪念日",
                        "updatedAt": "2026-05-20T00:01:00Z",
                    }
                ],
                location_reminders=[
                    {
                        "id": "location-shared",
                        "title": "新位置提醒",
                        "updatedAt": "2026-05-20T00:01:00Z",
                    }
                ],
            ),
            user_id=user_id,
        )
        self.assertEqual(newer["courses"][0]["name"], "新课程")
        self.assertEqual(newer["anniversaries"][0]["title"], "新纪念日")
        self.assertEqual(newer["location_reminders"][0]["title"], "新位置提醒")

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

    def test_sync_object_merge_accepts_snake_case_and_modified_at(self):
        user_id = self._register("sync-object-timestamps")

        first = api.sync(
            api.SyncRequest(
                user_profile={
                    "displayName": "旧资料",
                    "updated_at": "2026-05-20T00:00:00Z",
                },
                pomodoro_config={
                    "focusDuration": 1500,
                    "modifiedAt": "2026-05-20T00:00:00Z",
                },
                focus_rooms={
                    "activeRoomId": "old-room",
                    "updated_at": "2026-05-20T00:00:00Z",
                },
            ),
            user_id=user_id,
        )
        self.assertEqual(first["user_profile"]["displayName"], "旧资料")
        self.assertEqual(first["pomodoro_config"]["focusDuration"], 1500)
        self.assertEqual(first["focus_rooms"]["activeRoomId"], "old-room")

        stale = api.sync(
            api.SyncRequest(
                user_profile={
                    "displayName": "过期资料",
                    "updated_at": "2026-05-19T23:59:00Z",
                },
                pomodoro_config={
                    "focusDuration": 1200,
                    "modifiedAt": "2026-05-19T23:59:00Z",
                },
                focus_rooms={
                    "activeRoomId": "stale-room",
                    "updated_at": "2026-05-19T23:59:00Z",
                },
            ),
            user_id=user_id,
        )
        self.assertEqual(stale["user_profile"]["displayName"], "旧资料")
        self.assertEqual(stale["pomodoro_config"]["focusDuration"], 1500)
        self.assertEqual(stale["focus_rooms"]["activeRoomId"], "old-room")

        newer = api.sync(
            api.SyncRequest(
                user_profile={
                    "displayName": "snake 新资料",
                    "updated_at": "2026-05-20T00:01:00Z",
                },
                pomodoro_config={
                    "focusDuration": 1800,
                    "modifiedAt": "2026-05-20T00:01:00Z",
                },
                focus_rooms={
                    "activeRoomId": "new-room",
                    "updated_at": "2026-05-20T00:01:00Z",
                },
            ),
            user_id=user_id,
        )
        self.assertEqual(newer["user_profile"]["displayName"], "snake 新资料")
        self.assertEqual(newer["pomodoro_config"]["focusDuration"], 1800)
        self.assertEqual(newer["focus_rooms"]["activeRoomId"], "new-room")

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
                "UPDATE users SET is_admin=1, admin_permissions=?, last_login_at=?, last_active_at=? WHERE id=?",
                (
                    json.dumps(["users"]),
                    api._format_utc(stale_at),
                    api._format_utc(stale_at),
                    admin_id,
                ),
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
        unverified_user = self._register("segment-unverified")
        verified_user = self._register_with_email(
            "segment-verified",
            "segment-verified@example.com",
        )["user_id"]
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_admin=1 WHERE id=?", (admin_id,))
            db.execute(
                "UPDATE users SET email=?, email_verified=0 WHERE id=?",
                ("segment-unverified@example.com", unverified_user),
            )
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

    def test_admin_coin_adjustment_updates_sync_revision_and_survives_client_sync(self):
        admin_id = self._register("coin-admin")
        user_id = self._register("coin-user")
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET is_admin=1, admin_permissions=? WHERE id=?",
                (json.dumps(["coins"]), admin_id),
            )
            db.commit()
        finally:
            db.close()

        adjusted = api.admin_adjust_user_coins(
            user_id,
            api.UserCoinAdjustment(delta=30, reason="补发奖励"),
            actor=admin_id,
        )

        self.assertEqual(adjusted["balance"], 30)
        self.assertEqual(adjusted["lifetime"], 30)
        self.assertEqual(adjusted["server_version"], 1)

        stale_client = api.sync(
            api.SyncRequest(
                virtual_rewards={
                    "balance": 0,
                    "lifetime": 0,
                    "grantIds": [],
                    "ledger": [],
                    "updatedAt": "2026-05-19T00:00:00Z",
                }
            ),
            user_id=user_id,
        )

        self.assertEqual(stale_client["virtual_rewards"]["balance"], 30)
        self.assertEqual(stale_client["virtual_rewards"]["lifetime"], 30)
        self.assertEqual(
            stale_client["virtual_rewards"]["ledger"][0]["id"],
            adjusted["ledger_entry"]["id"],
        )

    def test_admin_coin_adjustment_route_accepts_compatible_payloads(self):
        admin_id = self._register("coin-route-admin")
        user_id = self._register("coin-route-user")
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET is_admin=1, admin_permissions=? WHERE id=?",
                (json.dumps(["coins"]), admin_id),
            )
            db.commit()
        finally:
            db.close()

        with TestClient(api.app) as client:
            response = client.post(
                f"/api/admin/users/{user_id}/quota",
                json={"amount": 25, "reason": "路径补发"},
                headers={"Authorization": f"Bearer {api.TOKENS[admin_id]}"},
            )
            balance_response = client.post(
                f"/api/admin/users/{user_id}/quota",
                json={"quota": 40, "reason": "设为目标余额"},
                headers={"Authorization": f"Bearer {api.TOKENS[admin_id]}"},
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["balance"], 25)
        self.assertEqual(response.json()["ledger_entry"]["coins"], 25)
        self.assertEqual(balance_response.status_code, 200)
        self.assertEqual(balance_response.json()["balance"], 40)
        self.assertEqual(balance_response.json()["ledger_entry"]["coins"], 15)
        synced = api.sync(api.SyncRequest(), user_id=user_id)
        self.assertEqual(synced["virtual_rewards"]["balance"], 40)

    def test_admin_coin_adjustment_compat_routes_and_fields_do_not_404(self):
        admin_id = self._register("coin-compat-admin")
        user_id = self._register("coin-compat-user")
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET is_admin=1, admin_permissions=? WHERE id=?",
                (json.dumps(["coins"]), admin_id),
            )
            db.commit()
        finally:
            db.close()

        headers = {"Authorization": f"Bearer {api.TOKENS[admin_id]}"}
        with TestClient(api.app) as client:
            delta_response = client.patch(
                f"/api/admin/users/{user_id}/time-coins",
                json={"coin_delta": 12, "reason": "兼容增发"},
                headers=headers,
            )
            balance_response = client.put(
                f"/api/admin/users/{user_id}/coins/adjust",
                json={"target_balance": 20, "reason": "兼容设定余额"},
                headers=headers,
            )
            quota_response = client.post(
                f"/api/admin/users/{user_id}/coin-adjustment",
                json={"time_coins": 5, "reason": "兼容目标时光币"},
                headers=headers,
            )
            re0_user_update_response = client.put(
                f"/api/admin/users/{user_id}",
                json={"coin_balance": 18, "reason": "RE0 用户编辑兼容"},
                headers=headers,
            )
            time_coin_balance_response = client.patch(
                f"/api/admin/users/{user_id}/time-coin-balance",
                json={"time_coin_balance": 24, "reason": "RE0 时光币余额兼容"},
                headers=headers,
            )
            time_coin_camel_response = client.put(
                f"/api/admin/users/{user_id}/time_coin_balance",
                json={"timeCoinBalance": 30, "reason": "RE0 驼峰时光币余额兼容"},
                headers=headers,
            )
            credits_response = client.post(
                f"/api/admin/users/{user_id}/credits",
                json={"credits": 33, "reason": "RE0 credits 兼容"},
                headers=headers,
            )
            credit_balance_response = client.put(
                f"/api/admin/users/{user_id}/credit-balance",
                json={"credit_balance": 36, "reason": "RE0 credit balance 兼容"},
                headers=headers,
            )

        self.assertEqual(delta_response.status_code, 200)
        self.assertEqual(delta_response.json()["balance"], 12)
        self.assertEqual(delta_response.json()["ledger_entry"]["coins"], 12)
        self.assertEqual(balance_response.status_code, 200)
        self.assertEqual(balance_response.json()["balance"], 20)
        self.assertEqual(balance_response.json()["ledger_entry"]["coins"], 8)
        self.assertEqual(quota_response.status_code, 200)
        self.assertEqual(quota_response.json()["balance"], 5)
        self.assertEqual(quota_response.json()["ledger_entry"]["coins"], -15)
        self.assertEqual(re0_user_update_response.status_code, 200)
        self.assertEqual(re0_user_update_response.json()["balance"], 18)
        self.assertEqual(
            re0_user_update_response.json()["ledger_entry"]["coins"], 13
        )
        self.assertEqual(time_coin_balance_response.status_code, 200)
        self.assertEqual(time_coin_balance_response.json()["balance"], 24)
        self.assertEqual(time_coin_balance_response.json()["ledger_entry"]["coins"], 6)
        self.assertEqual(time_coin_camel_response.status_code, 200)
        self.assertEqual(time_coin_camel_response.json()["balance"], 30)
        self.assertEqual(time_coin_camel_response.json()["ledger_entry"]["coins"], 6)
        self.assertEqual(credits_response.status_code, 200)
        self.assertEqual(credits_response.json()["balance"], 33)
        self.assertEqual(credits_response.json()["ledger_entry"]["coins"], 3)
        self.assertEqual(credit_balance_response.status_code, 200)
        self.assertEqual(credit_balance_response.json()["balance"], 36)
        self.assertEqual(credit_balance_response.json()["ledger_entry"]["coins"], 3)

    def test_admin_without_coin_permission_cannot_mutate_sync_rewards(self):
        admin_id = self._register("no-coin-admin")
        user_id = self._register("no-coin-user")
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET is_admin=1, admin_permissions=? WHERE id=?",
                (json.dumps(["users"]), admin_id),
            )
            before = db.execute(
                "SELECT virtual_rewards, sync_version, updated_at "
                "FROM sync_data WHERE user_id=?",
                (user_id,),
            ).fetchone()
            db.commit()
        finally:
            db.close()

        with self.assertRaises(HTTPException) as denied:
            api.admin_adjust_user_coins(
                user_id,
                api.UserCoinAdjustment(delta=10, reason="should fail"),
                actor=admin_id,
            )

        self.assertEqual(denied.exception.status_code, 403)
        db = api.get_db()
        try:
            after = db.execute(
                "SELECT virtual_rewards, sync_version, updated_at "
                "FROM sync_data WHERE user_id=?",
                (user_id,),
            ).fetchone()
        finally:
            db.close()
        self.assertEqual(after["virtual_rewards"], before["virtual_rewards"])
        self.assertEqual(after["sync_version"], before["sync_version"])
        self.assertEqual(after["updated_at"], before["updated_at"])

    def test_admin_welfare_grants_route_awards_time_coins(self):
        admin_id = self._make_admin("welfare-admin", ["coins"])
        user_id = self._register("welfare-user")
        disabled_id = self._register("welfare-disabled")
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_disabled=1 WHERE id=?", (disabled_id,))
            db.commit()
        finally:
            db.close()

        with TestClient(api.app) as client:
            response = client.post(
                "/api/admin/welfare-grants",
                json={
                    "title": "补丁福利",
                    "body": "修复后补发",
                    "generate_bonus": 3,
                    "edit_bonus": 2,
                    "notify": False,
                },
                headers={"Authorization": f"Bearer {api.TOKENS[admin_id]}"},
            )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["coins"], 5)
        self.assertGreaterEqual(payload["users"], 2)
        self.assertEqual(payload["generate_bonus"], 3)
        self.assertEqual(payload["edit_bonus"], 2)

        user_rewards = api.sync(api.SyncRequest(), user_id=user_id)[
            "virtual_rewards"
        ]
        self.assertEqual(user_rewards["balance"], 5)
        self.assertEqual(user_rewards["lifetime"], 5)
        self.assertEqual(user_rewards["ledger"][0]["title"], "补丁福利")
        self.assertEqual(user_rewards["ledger"][0]["generate_bonus"], 3)
        disabled_rewards = api.sync(api.SyncRequest(), user_id=disabled_id)[
            "virtual_rewards"
        ]
        self.assertEqual(disabled_rewards.get("balance", 0), 0)

    def test_admin_granular_permissions_gate_feature_families(self):
        denied_admin = self._make_admin("granular-denied", ["users"])
        checks = [
            (
                "settings",
                lambda actor: api.admin_get_settings(_=actor),
            ),
            (
                "feedback",
                lambda actor: api.list_all_feedback(_=actor, limit=10, offset=0),
            ),
            (
                "announcements",
                lambda actor: api.admin_list_announcements(
                    _=actor, limit=10, offset=0
                ),
            ),
            (
                "invites",
                lambda actor: api.list_invite_codes(_=actor, limit=10, offset=0),
            ),
            (
                "audit",
                lambda actor: api.admin_audit_log(_=actor, limit=10, offset=0),
            ),
            (
                "backup",
                lambda actor: api.admin_backups(_=actor, limit=10, offset=0),
            ),
        ]

        for permission, call in checks:
            with self.subTest(permission=permission, allowed=False):
                with self.assertRaises(HTTPException) as denied:
                    call(denied_admin)
                self.assertEqual(denied.exception.status_code, 403)

            allowed_admin = self._make_admin(
                f"granular-{permission}", [permission]
            )
            with self.subTest(permission=permission, allowed=True):
                result = call(allowed_admin)
                self.assertIsInstance(result, dict)

    def test_my_feedback_supports_pagination_without_breaking_legacy_list(self):
        user_id = self._register("feedback-pagination")
        for index in range(3):
            api.create_feedback(
                api.FeedbackCreate(category="bug", content=f"反馈 {index}"),
                user_id=user_id,
            )

        legacy = api.my_feedback(user_id=user_id, page=None, page_size=None)
        self.assertIsInstance(legacy, list)
        self.assertEqual(len(legacy), 3)

        page = api.my_feedback(user_id=user_id, page=2, page_size=2)
        self.assertEqual(page["total"], 3)
        self.assertEqual(page["page"], 2)
        self.assertEqual(page["page_size"], 2)
        self.assertEqual(page["total_pages"], 2)
        self.assertEqual(len(page["items"]), 1)
        self.assertEqual(page["items"][0]["content"], "反馈 0")

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
        empty_user = self._register_with_email(
            "backup-empty",
            "backup-empty@example.com",
            display_name="空备份",
        )["user_id"]
        synced_user = self._register_with_email(
            "backup-synced",
            "backup-synced@example.com",
            display_name="有备份",
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
        user_id = self._register_with_email(
            "=backup-export-user",
            "backup-export@example.com",
            display_name="+导出用户",
        )["user_id"]
        self._register("backup-export-empty")
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
        self.assertIn(
            "id,username,email,email_verified,display_name,category,status,content,admin_reply",
            text,
        )
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
                "idx_feedback_user_created_status",
                "idx_feedback_created_at",
                "idx_announcements_published_level_id",
                "idx_announcements_created_at",
                "idx_invite_codes_used_created",
                "idx_invite_codes_created_at",
                "idx_invite_codes_used_at",
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

    def test_admin_test_buttons_http_routes_do_not_404(self):
        admin_id = self._make_admin(
            "admin-test-buttons@example.com",
            ["ai", "settings"],
        )
        db = api.get_db()
        try:
            for key, value in {
                "ai_enabled": False,
                "ai_model": "test-model",
                "reminder_email_enabled": True,
                "reminder_email_smtp_host": "smtp.example.com",
                "reminder_email_smtp_port": 465,
                "reminder_email_smtp_username": "mailer@example.com",
                "reminder_email_smtp_password": "secret",
                "reminder_email_from": "noreply@example.com",
                "email_service_enabled": True,
                "email_code_primary_provider": "smtp",
                "email_code_backup_provider": "none",
                "email_code_active_slot": "primary",
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

        sent = []
        old_send = api._smtp_send
        try:
            api._smtp_send = lambda **kwargs: sent.append(kwargs)
            with TestClient(api.app) as client:
                headers = {"Authorization": f"Bearer {api.TOKENS[admin_id]}"}
                ai_test = client.post("/api/admin/ai/test", headers=headers)
                ai_test_form = client.post(
                    "/api/admin/ai/test",
                    headers=headers,
                    json={
                        "ai_enabled": False,
                        "ai_api_key": "temporary-key",
                        "ai_base_url": "https://temporary.example.com/v1",
                        "ai_model": "temporary-model",
                    },
                )
                provider_healthcheck = client.post(
                    "/api/admin/provider-healthcheck",
                    headers=headers,
                    json={"apply_switch": False},
                )
                reminder_test = client.post(
                    "/api/admin/reminders/email/test",
                    headers=headers,
                )
                account_test = client.post(
                    "/api/admin/account-email/test",
                    headers=headers,
                )
        finally:
            api._smtp_send = old_send

        self.assertEqual(ai_test.status_code, 200)
        self.assertFalse(ai_test.json()["ok"])
        self.assertEqual(ai_test.json()["model"], "test-model")
        self.assertFalse(ai_test.json()["enabled"])
        self.assertTrue(ai_test.json()["skipped"])
        self.assertNotIn("尚未配置 API Key", ai_test.text)
        self.assertEqual(ai_test_form.status_code, 200)
        self.assertFalse(ai_test_form.json()["ok"])
        self.assertEqual(ai_test_form.json()["model"], "temporary-model")
        self.assertFalse(ai_test_form.json()["enabled"])
        self.assertTrue(ai_test_form.json()["skipped"])
        self.assertNotIn("尚未配置 API Key", ai_test_form.text)
        self.assertEqual(provider_healthcheck.status_code, 200)
        self.assertFalse(provider_healthcheck.json()["ok"])
        self.assertEqual(provider_healthcheck.json()["model"], "test-model")
        self.assertFalse(provider_healthcheck.json()["enabled"])
        self.assertTrue(provider_healthcheck.json()["skipped"])
        self.assertNotIn("尚未配置 API Key", provider_healthcheck.text)
        self.assertEqual(reminder_test.status_code, 200)
        self.assertEqual(
            reminder_test.json()["recipient"],
            "admin-test-buttons@example.com",
        )
        self.assertEqual(account_test.status_code, 200)
        self.assertEqual(
            account_test.json()["recipient"],
            "admin-test-buttons@example.com",
        )
        self.assertEqual([mail["subject"] for mail in sent], [
            "多仪邮件提醒测试",
            "多仪账号邮件测试",
        ])

    def test_ai_response_parser_supports_chat_and_output_text_shapes(self):
        self.assertEqual(
            api._ai_chat_content_from_response(
                {"choices": [{"message": {"content": "ok"}}]}
            ),
            "ok",
        )
        self.assertEqual(
            api._ai_chat_content_from_response({"output_text": "ok"}),
            "ok",
        )
        self.assertEqual(api._ai_chat_content_from_response({}), "")

    def test_feedback_create_validates_content_and_normalizes_category(self):
        user_id = self._register("feedback-user")

        with self.assertRaises(HTTPException) as empty:
            api.create_feedback(
                api.FeedbackCreate(category="bug", content="   "),
                user_id=user_id,
            )
        self.assertEqual(empty.exception.status_code, 400)

        fallback_category = api.create_feedback(
            api.FeedbackCreate(category="invalid", content="按钮没有反应"),
            user_id=user_id,
        )
        self.assertEqual(fallback_category["status"], "open")

        created = api.create_feedback(
            api.FeedbackCreate(category="bug", content="  通知没有声音  "),
            user_id=user_id,
        )
        self.assertEqual(created["status"], "open")

        items = api.my_feedback(user_id=user_id)
        self.assertEqual(items[0]["category"], "bug")
        self.assertEqual(items[0]["content"], "通知没有声音")
        self.assertEqual(items[1]["category"], "other")

    def test_re0_feedback_password_overview_and_backup_alias_routes_do_not_404(self):
        user_id = self._register("re0-alias-user")
        admin_id = self._make_admin("re0-alias-admin", ["feedback", "backup"])
        user_headers = {"Authorization": f"Bearer {api.TOKENS[user_id]}"}
        admin_headers = {"Authorization": f"Bearer {api.TOKENS[admin_id]}"}

        with TestClient(api.app) as client:
            created = client.post(
                "/api/me/feedback",
                json={
                    "type": "bug",
                    "category": "bug",
                    "title": "反馈标题",
                    "content": "RE0 风格反馈入口不应 404",
                },
                headers=user_headers,
            )
            self.assertEqual(created.status_code, 200)
            fb_id = created.json()["id"]

            my_list = client.get(
                "/api/me/feedback?page=1&page_size=10&keyword=RE0&type=feedback",
                headers=user_headers,
            )
            my_detail = client.get(f"/api/me/feedback/{fb_id}", headers=user_headers)
            my_detail_alias = client.get(
                f"/api/feedback/me/{fb_id}",
                headers=user_headers,
            )
            admin_list = client.get(
                "/api/admin/feedback",
                params={
                    "page": 1,
                    "page_size": 10,
                    "keyword": "RE0",
                    "type": "feedback",
                    "start_at": "2000-01-01T00:00:00Z",
                },
                headers=admin_headers,
            )
            admin_detail = client.get(
                f"/api/admin/feedback/{fb_id}",
                headers=admin_headers,
            )
            summary = client.post(
                f"/api/admin/feedback/{fb_id}/ai-summary",
                headers=admin_headers,
            )
            automation = client.get(
                "/api/admin/feedback/automation",
                headers=admin_headers,
            )
            save_automation = client.post(
                "/api/admin/feedback/automation",
                json={
                    "auto_enabled": True,
                    "automation_limit": "10",
                    "interval_minutes": 30,
                    "auto_reply_enabled": True,
                    "auto_export_enabled": True,
                },
                headers=admin_headers,
            )
            auto_run = client.post(
                "/api/admin/feedback/auto-run",
                headers=admin_headers,
            )
            auto_reply = client.post(
                "/api/admin/feedback/auto-reply",
                headers=admin_headers,
            )
            auto_reply_detail = client.get(
                f"/api/admin/feedback/{fb_id}",
                headers=admin_headers,
            )
            insights = client.get(
                "/api/admin/feedback/insights?period=month",
                headers=admin_headers,
            )
            insights_export = client.post(
                "/api/admin/feedback/export?period=month",
                headers=admin_headers,
            )
            status_update = client.post(
                f"/api/admin/feedback/{fb_id}/status",
                json={"status": "accepted", "note": "已进入处理"},
                headers=admin_headers,
            )
            reply_update = client.post(
                f"/api/admin/feedback/{fb_id}/reply",
                json={"reply": "已修复", "status": "resolved"},
                headers=admin_headers,
            )
            password = client.post(
                "/api/me/password",
                json={
                    "current_password": "pass123456",
                    "new_password": "newpass123456",
                },
                headers=user_headers,
            )
            overview = client.get("/api/admin/overview", headers=admin_headers)
            local_backups = client.get(
                "/api/admin/local-backups",
                headers=admin_headers,
            )
            run_local_backup = client.post(
                "/api/admin/local-backups/run",
                headers=admin_headers,
            )

        self.assertEqual(my_list.status_code, 200)
        self.assertEqual(my_list.json()["items"][0]["id"], fb_id)
        self.assertEqual(my_detail.status_code, 200)
        self.assertEqual(my_detail_alias.status_code, 200)
        self.assertEqual(my_detail.json()["content"], "RE0 风格反馈入口不应 404")
        self.assertEqual(admin_list.status_code, 200)
        self.assertEqual(admin_list.json()["items"][0]["id"], fb_id)
        self.assertEqual(admin_detail.status_code, 200)
        self.assertEqual(summary.status_code, 200)
        self.assertIn("summary", summary.json())
        self.assertEqual(automation.status_code, 200)
        self.assertEqual(save_automation.status_code, 200)
        self.assertTrue(save_automation.json()["auto_enabled"])
        self.assertEqual(auto_run.status_code, 200)
        self.assertGreaterEqual(auto_run.json()["processed"], 1)
        self.assertEqual(auto_reply.status_code, 200)
        self.assertGreaterEqual(auto_reply.json()["processed"], 1)
        self.assertEqual(auto_reply_detail.status_code, 200)
        self.assertIn("已收到你的", auto_reply_detail.json()["admin_reply"])
        self.assertEqual(auto_reply_detail.json()["status"], "in_progress")
        self.assertEqual(insights.status_code, 200)
        self.assertEqual(insights.json()["period"], "month")
        self.assertEqual(insights_export.status_code, 200)
        self.assertTrue(insights_export.json()["ok"])
        self.assertEqual(status_update.status_code, 200)
        self.assertEqual(reply_update.status_code, 200)
        self.assertEqual(password.status_code, 200)
        self.assertEqual(overview.status_code, 200)
        self.assertIn("users", overview.json())
        self.assertEqual(local_backups.status_code, 200)
        self.assertIn("items", local_backups.json())
        self.assertEqual(run_local_backup.status_code, 200)

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

        status_only = api.reply_feedback(
            api.FeedbackReply(
                feedback_id=fb_id,
                reply="",
                status="resolved",
            ),
            actor=admin_id,
        )
        self.assertEqual(status_only["status"], "ok")
        after_status_only = api.my_feedback(user_id=user_id)[0]
        self.assertEqual(after_status_only["status"], "resolved")
        self.assertEqual(after_status_only["admin_reply"], "已加入排查")

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
        empty_bulk = api.bulk_update_feedback_status(
            api.FeedbackBulkStatus(
                feedback_ids=[fb_id, second["id"]],
                reply="",
                status="closed",
            ),
            actor=admin_id,
        )
        self.assertEqual(empty_bulk["updated"], 2)
        feedback = api.my_feedback(user_id=user_id)
        self.assertTrue(all(item["status"] == "closed" for item in feedback[:2]))
        self.assertTrue(
            all(item["admin_reply"] == "已收到，进入处理中。" for item in feedback[:2])
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
        registered = self._register_with_email(
            "focus-room-websocket",
            "focus-room-websocket@example.com",
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
        registered = self._register_with_email(
            "focus-global-websocket",
            "focus-global-websocket@example.com",
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
