import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('同步冲突记录有独立展示入口且不暴露手动同步', () {
    final screen = File(
      'lib/screens/sync_conflict_log_screen.dart',
    ).readAsStringSync();
    final provider = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();

    expect(provider, contains('final List<String> changedFields'));
    expect(provider, contains("'changedFields': changedFields"));
    expect(provider, contains('_changedWorkspaceFields(prior, item)'));
    expect(provider, contains("'id', 'workspaceId', 'createdAt', 'updatedAt'"));
    expect(screen, contains('sync_merge_decisions'));
    expect(screen, contains('SyncMergeDecision.fromJson'));
    expect(screen, contains('items.sort((a, b) => b.decidedAt.compareTo(a.decidedAt));'));
    expect(screen, contains("I18n.tr('sync_conflict.keep_remote')"));
    expect(screen, contains("I18n.tr('sync_conflict.keep_local')"));
    expect(screen, contains('item.changedFields.isNotEmpty'));
    expect(screen, contains('_FieldChip'));
    expect(screen, contains(r'字段: $field'));
    expect(screen, isNot(contains('syncNow')));
    expect(screen, isNot(contains('CloudSyncProvider')));
    expect(mine, contains('同步冲突记录'));
    expect(mine, contains('SyncConflictLogScreen'));
  });
}
