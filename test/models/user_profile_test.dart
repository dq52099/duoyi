import 'package:duoyi/models/user_profile.dart';
import 'package:test/test.dart';

void main() {
  test(
    'UserProfile persists account profile fields with old data fallback',
    () {
      final profile = UserProfile.fromJson({
        'username': 'local-name',
        'avatarInitials': 'L',
        'displayName': 'Display Name',
        'email': 'user@example.com',
        'emailVerified': true,
        'avatarUrl': 'https://example.com/avatar.png',
        'bio': 'profile bio',
        'updatedAt': '2026-05-22T08:00:00.000Z',
      });

      expect(profile.username, 'local-name');
      expect(profile.avatarInitials, 'L');
      expect(profile.displayName, 'Display Name');
      expect(profile.email, 'user@example.com');
      expect(profile.emailVerified, isTrue);
      expect(profile.avatarUrl, 'https://example.com/avatar.png');
      expect(profile.bio, 'profile bio');
      expect(profile.updatedAt?.toIso8601String(), '2026-05-22T08:00:00.000Z');

      expect(profile.toJson(), containsPair('displayName', 'Display Name'));
      expect(profile.toJson(), containsPair('email', 'user@example.com'));
      expect(profile.toJson(), containsPair('emailVerified', true));
      expect(
        profile.toJson(),
        containsPair('avatarUrl', 'https://example.com/avatar.png'),
      );
      expect(profile.toJson(), containsPair('bio', 'profile bio'));
      expect(
        profile.toJson(),
        containsPair('updatedAt', '2026-05-22T08:00:00.000Z'),
      );

      final legacy = UserProfile.fromJson({'username': 'legacy'});
      expect(legacy.displayName, isEmpty);
      expect(legacy.email, isEmpty);
      expect(legacy.emailVerified, isFalse);
      expect(legacy.avatarUrl, isEmpty);
      expect(legacy.bio, isEmpty);
      expect(legacy.updatedAt, isNull);
    },
  );
}
