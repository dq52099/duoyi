import 'api_client.dart';

class AdminPage {
  final List<Map<String, dynamic>> items;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;

  const AdminPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  factory AdminPage.fromJson(
    Map<String, dynamic> json, {
    required int fallbackLimit,
    required int fallbackOffset,
  }) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final total = ((json['total'] as num?) ?? items.length).toInt();
    final limit = ((json['limit'] as num?) ?? fallbackLimit).toInt();
    final offset = ((json['offset'] as num?) ?? fallbackOffset).toInt();
    final hasMore = json['has_more'] == true || offset + items.length < total;
    return AdminPage(
      items: items,
      total: total,
      limit: limit,
      offset: offset,
      hasMore: hasMore,
    );
  }

  factory AdminPage.fromItems(
    List<Map<String, dynamic>> items, {
    required int limit,
    required int offset,
  }) {
    return AdminPage(
      items: items,
      total: items.length,
      limit: limit,
      offset: offset,
      hasMore: false,
    );
  }
}

/// 薄封装的管理员 API。所有方法需使用已登录为管理员的 ApiClient。
class AdminApi {
  final ApiClient client;

  const AdminApi(this.client);

  String _path(String base, Map<String, Object?> params) {
    final query = <String, String>{};
    for (final entry in params.entries) {
      final value = entry.value;
      if (value == null) continue;
      final text = value.toString();
      if (text.isEmpty) continue;
      query[entry.key] = text;
    }
    if (query.isEmpty) return base;
    return Uri(path: base, queryParameters: query).toString();
  }

  Future<AdminPage> _getPage(
    String base, {
    Map<String, Object?> params = const {},
    int limit = 20,
    int offset = 0,
  }) async {
    final pageParams = <String, Object?>{
      ...params,
      'limit': limit,
      'offset': offset,
    };
    final path = _path(base, pageParams);
    final json = await client.get(path);
    if (json.containsKey('items')) {
      return AdminPage.fromJson(
        json,
        fallbackLimit: limit,
        fallbackOffset: offset,
      );
    }
    final legacy = await client.getList(path);
    return AdminPage.fromItems(
      legacy.cast<Map<String, dynamic>>(),
      limit: limit,
      offset: offset,
    );
  }

  // ---- Stats ----
  Future<Map<String, dynamic>> stats() => client.get('/api/admin/stats');

  // ---- Settings ----
  Future<Map<String, dynamic>> getSettings() =>
      client.get('/api/admin/settings');

  Future<Map<String, dynamic>> updateSettings({
    bool? inviteCodeRequired,
    bool? registrationEnabled,
    bool? registrationEmailRequired,
    bool? maintenanceMode,
    String? maintenanceMessage,
    bool? forceUpdateRequired,
    String? latestVersion,
    String? minimumSupportedVersion,
    String? updateNotes,
    String? updateDownloadUrl,
  }) {
    final body = <String, dynamic>{};
    if (inviteCodeRequired != null) {
      body['invite_code_required'] = inviteCodeRequired;
    }
    if (registrationEnabled != null) {
      body['registration_enabled'] = registrationEnabled;
    }
    if (registrationEmailRequired != null) {
      body['registration_email_required'] = registrationEmailRequired;
    }
    if (maintenanceMode != null) body['maintenance_mode'] = maintenanceMode;
    if (maintenanceMessage != null) {
      body['maintenance_message'] = maintenanceMessage;
    }
    if (forceUpdateRequired != null) {
      body['force_update_required'] = forceUpdateRequired;
    }
    if (latestVersion != null) body['latest_version'] = latestVersion;
    if (minimumSupportedVersion != null) {
      body['minimum_supported_version'] = minimumSupportedVersion;
    }
    if (updateNotes != null) body['update_notes'] = updateNotes;
    if (updateDownloadUrl != null) {
      body['update_download_url'] = updateDownloadUrl;
    }
    return client.patch('/api/admin/settings', body);
  }

  // ---- Users ----
  Future<AdminPage> listUsersPage({
    String? query,
    String? status,
    bool? online,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/users',
    params: {'q': query, 'status': status, 'online': online, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> listUsers({String? query}) async {
    return (await listUsersPage(query: query, limit: 100, offset: 0)).items;
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

  Future<void> setUserAdminPermissions(
    String userId, {
    required List<String> permissions,
  }) async {
    await client.patch('/api/admin/users/$userId', {
      'admin_permissions': permissions,
    });
  }

  Future<Map<String, dynamic>> adjustUserCoins(
    String userId, {
    required int delta,
    String? reason,
  }) async {
    final body = <String, dynamic>{'delta': delta};
    if (reason != null && reason.trim().isNotEmpty) {
      body['reason'] = reason.trim();
    }
    return client.post('/api/admin/users/$userId/coins', body);
  }

  Future<String> exportUsersCsv({
    String? query,
    String? status,
    bool? online,
    String? sort,
    int limit = 5000,
  }) => client.getText(
    _path('/api/admin/users/export.csv', {
      'q': query,
      'status': status,
      'online': online,
      'sort': sort,
      'limit': limit,
    }),
  );

  Future<void> bulkUpdateUserStatus({
    required List<String> userIds,
    required bool isDisabled,
  }) => client.post('/api/admin/users/bulk-status', {
    'user_ids': userIds,
    'is_disabled': isDisabled,
  });

  Future<void> deleteUser(String userId) =>
      client.delete('/api/admin/users/$userId');

  // ---- Announcements ----
  Future<AdminPage> listAnnouncementsPage({
    String? query,
    String? status,
    String? level,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/announcements',
    params: {'q': query, 'status': status, 'level': level, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> listAnnouncements() async {
    return (await listAnnouncementsPage(limit: 100, offset: 0)).items;
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
  Future<AdminPage> listFeedbackPage({
    String? status,
    String? query,
    String? category,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/feedback',
    params: {'status': status, 'q': query, 'category': category, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> listFeedback({String? status}) async {
    return (await listFeedbackPage(
      status: status,
      limit: 100,
      offset: 0,
    )).items;
  }

  Future<void> replyFeedback({
    required int feedbackId,
    required String reply,
    String status = 'resolved',
  }) => client.post('/api/admin/feedback/reply', {
    'feedback_id': feedbackId,
    'reply': reply,
    'status': status,
  });

  Future<void> bulkUpdateFeedbackStatus({
    required List<int> feedbackIds,
    required String reply,
    String status = 'in_progress',
  }) => client.post('/api/admin/feedback/bulk-status', {
    'feedback_ids': feedbackIds,
    'reply': reply,
    'status': status,
  });

  Future<String> exportFeedbackCsv({
    String? status,
    String? query,
    String? category,
    String? sort,
    int limit = 5000,
  }) => client.getText(
    _path('/api/admin/feedback/export.csv', {
      'status': status,
      'q': query,
      'category': category,
      'sort': sort,
      'limit': limit,
    }),
  );

  Future<void> deleteFeedback(int id) =>
      client.delete('/api/admin/feedback/$id');

  // ---- Invite codes ----
  Future<AdminPage> listInviteCodesPage({
    String? query,
    String? status,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/invite-codes',
    params: {'q': query, 'status': status, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> listInviteCodes() async {
    return (await listInviteCodesPage(limit: 100, offset: 0)).items;
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
  Future<AdminPage> auditLogPage({
    String? action,
    String? query,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/audit-log',
    params: {'action': action, 'q': query, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> auditLog({String? action}) async {
    return (await auditLogPage(action: action, limit: 100, offset: 0)).items;
  }

  // ---- AI diagnostic ----
  Future<Map<String, dynamic>> testAi() => client.post('/api/admin/ai/test');

  // ---- Reminder email diagnostic ----
  Future<Map<String, dynamic>> testReminderEmail() =>
      client.post('/api/admin/reminders/email/test');

  // ---- Account email diagnostic ----
  Future<Map<String, dynamic>> testAccountEmail() =>
      client.post('/api/admin/account-email/test');

  // ---- Backups ----
  Future<AdminPage> listBackupsPage({
    String? query,
    String? status,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/backups',
    params: {'q': query, 'status': status, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> listBackups() async {
    return (await listBackupsPage(limit: 100, offset: 0)).items;
  }

  Future<String> exportBackupsCsv({
    String? query,
    String? status,
    String? sort,
    int limit = 5000,
  }) => client.getText(
    _path('/api/admin/backups/export.csv', {
      'q': query,
      'status': status,
      'sort': sort,
      'limit': limit,
    }),
  );

  Future<void> wipeBackup(String userId) =>
      client.delete('/api/admin/backups/$userId');

  Future<AdminPage> listServerBackupsPage({
    String? query,
    String? status,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) => _getPage(
    '/api/admin/server-backups',
    params: {'q': query, 'status': status, 'sort': sort},
    limit: limit,
    offset: offset,
  );

  Future<List<Map<String, dynamic>>> listServerBackups() async {
    return (await listServerBackupsPage(limit: 100, offset: 0)).items;
  }

  Future<String> exportServerBackupsCsv({
    String? query,
    String? status,
    String? sort,
    int limit = 5000,
  }) => client.getText(
    _path('/api/admin/server-backups/export.csv', {
      'q': query,
      'status': status,
      'sort': sort,
      'limit': limit,
    }),
  );

  Future<Map<String, dynamic>> runServerBackup() =>
      client.post('/api/admin/server-backups/run');
}
