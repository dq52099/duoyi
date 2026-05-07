import 'api_client.dart';

/// 薄封装的管理员 API。所有方法需使用已登录为管理员的 ApiClient。
class AdminApi {
  final ApiClient client;

  const AdminApi(this.client);

  // ---- Stats ----
  Future<Map<String, dynamic>> stats() => client.get('/api/admin/stats');

  // ---- Settings ----
  Future<Map<String, dynamic>> getSettings() =>
      client.get('/api/admin/settings');

  Future<Map<String, dynamic>> updateSettings({
    bool? inviteCodeRequired,
    bool? registrationEnabled,
    bool? maintenanceMode,
    String? maintenanceMessage,
  }) {
    final body = <String, dynamic>{};
    if (inviteCodeRequired != null) {
      body['invite_code_required'] = inviteCodeRequired;
    }
    if (registrationEnabled != null) {
      body['registration_enabled'] = registrationEnabled;
    }
    if (maintenanceMode != null) body['maintenance_mode'] = maintenanceMode;
    if (maintenanceMessage != null) {
      body['maintenance_message'] = maintenanceMessage;
    }
    return client.patch('/api/admin/settings', body);
  }

  // ---- Users ----
  Future<List<Map<String, dynamic>>> listUsers({String? query}) async {
    final path = query == null || query.isEmpty
        ? '/api/admin/users'
        : '/api/admin/users?q=${Uri.encodeComponent(query)}';
    final list = await client.getList(path);
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> updateUser(
    String userId, {
    bool? isAdmin,
    bool? isDisabled,
    String? newPassword,
  }) async {
    final body = <String, dynamic>{};
    if (isAdmin != null) body['is_admin'] = isAdmin;
    if (isDisabled != null) body['is_disabled'] = isDisabled;
    if (newPassword != null && newPassword.isNotEmpty) {
      body['new_password'] = newPassword;
    }
    await client.patch('/api/admin/users/$userId', body);
  }

  Future<void> deleteUser(String userId) =>
      client.delete('/api/admin/users/$userId');

  // ---- Announcements ----
  Future<List<Map<String, dynamic>>> listAnnouncements() async {
    final list = await client.getList('/api/admin/announcements');
    return list.cast<Map<String, dynamic>>();
  }

  Future<int> createAnnouncement({
    required String title,
    required String body,
    String level = 'info',
    bool published = true,
  }) async {
    final res = await client.post('/api/admin/announcements', {
      'title': title,
      'body': body,
      'level': level,
      'published': published,
    });
    return (res['id'] as num?)?.toInt() ?? 0;
  }

  Future<void> updateAnnouncement(
    int id, {
    String? title,
    String? body,
    String? level,
    bool? published,
  }) async {
    final payload = <String, dynamic>{};
    if (title != null) payload['title'] = title;
    if (body != null) payload['body'] = body;
    if (level != null) payload['level'] = level;
    if (published != null) payload['published'] = published;
    await client.patch('/api/admin/announcements/$id', payload);
  }

  Future<void> deleteAnnouncement(int id) =>
      client.delete('/api/admin/announcements/$id');

  // ---- Feedback ----
  Future<List<Map<String, dynamic>>> listFeedback({String? status}) async {
    final path = status == null || status.isEmpty
        ? '/api/admin/feedback'
        : '/api/admin/feedback?status=${Uri.encodeComponent(status)}';
    final list = await client.getList(path);
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> replyFeedback({
    required int feedbackId,
    required String reply,
    String status = 'resolved',
  }) =>
      client.post('/api/admin/feedback/reply', {
        'feedback_id': feedbackId,
        'reply': reply,
        'status': status,
      });

  Future<void> deleteFeedback(int id) =>
      client.delete('/api/admin/feedback/$id');

  // ---- Invite codes ----
  Future<List<Map<String, dynamic>>> listInviteCodes() async {
    final list = await client.getList('/api/admin/invite-codes');
    return list.cast<Map<String, dynamic>>();
  }

  Future<List<String>> createInviteCodes({
    int count = 1,
    String note = '',
  }) async {
    final res = await client.post('/api/admin/invite-codes', {
      'count': count,
      'note': note,
    });
    return (res['codes'] as List<dynamic>? ?? const []).cast<String>();
  }

  Future<void> deleteInviteCode(String code) =>
      client.delete('/api/admin/invite-codes/$code');

  // ---- Audit log ----
  Future<List<Map<String, dynamic>>> auditLog({String? action}) async {
    final path = action == null || action.isEmpty
        ? '/api/admin/audit-log'
        : '/api/admin/audit-log?action=${Uri.encodeComponent(action)}';
    final list = await client.getList(path);
    return list.cast<Map<String, dynamic>>();
  }
}
