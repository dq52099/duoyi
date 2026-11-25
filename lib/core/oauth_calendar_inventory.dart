import 'package:shared_preferences/shared_preferences.dart';

import 'oauth_calendar_storage.dart';
import 'oauth_calendar_workspace_codec.dart';
import 'oauth_pending_authorization.dart';
import 'oauth_refresh_journal.dart';

/// Classifies the complete private inventory after reload, without writing or
/// issuing a capability. Unknown, orphaned and legacy records stay quarantined.
final class OAuthCalendarInventory {
  static List<OAuthOwnedSourceRecord> validate(
    SharedPreferences preferences,
    OAuthScopedOwnerRecord scope,
  ) {
    final rawAccounts = preferences.get(OAuthCalendarStorage.accountsKey);
    final rows = !preferences.containsKey(OAuthCalendarStorage.accountsKey)
        ? const <OAuthOwnedSourceRecord>[]
        : rawAccounts is String
        ? OAuthOwnedSourceRecord.parseList(rawAccounts, scope: scope)
        : null;
    if (rows == null) throw const OAuthWorkspaceCodecException();
    OAuthOwnedRefreshJournal? refresh;
    if (preferences.containsKey(OAuthCalendarStorage.refreshJournalKey)) {
      final raw = preferences.get(OAuthCalendarStorage.refreshJournalKey);
      refresh = raw is String
          ? OAuthOwnedRefreshJournal.parse(raw, scope: scope)
          : null;
      final actual = rows
          .where((row) => row.account['id'] == refresh?.sourceAccountId)
          .firstOrNull;
      if (refresh == null ||
          actual == null ||
          (!refresh.matchesOriginalSource(actual) &&
              !refresh.matchesReturnedSource(actual))) {
        throw const OAuthWorkspaceCodecException();
      }
    }
    final caches = {
      for (final row in rows)
        '${OAuthCalendarStorage.eventsKeyPrefix}${row.account['id']}': row,
    };
    for (final key in preferences.getKeys().where(
      OAuthCalendarStorage.isOAuthScopeKey,
    )) {
      if (key == OAuthCalendarStorage.scopeOwnerKey ||
          key == OAuthCalendarStorage.accountsKey ||
          key == OAuthCalendarStorage.refreshJournalKey) {
        continue;
      }
      final raw = preferences.get(key);
      if (key == OAuthCalendarStorage.pendingAuthorizationKey) {
        final pending = raw is String
            ? OAuthOwnedPendingAuthorization.parse(raw, scope: scope)
            : null;
        if (pending == null ||
            (refresh != null &&
                pending.sourceAccountId == refresh.sourceAccountId)) {
          throw const OAuthWorkspaceCodecException();
        }
        continue;
      }
      final source = caches[key];
      if (source == null ||
          raw is! String ||
          OAuthOwnedEventsRecord.parse(raw, source: source) == null) {
        throw const OAuthWorkspaceCodecException();
      }
    }
    return rows;
  }
}
