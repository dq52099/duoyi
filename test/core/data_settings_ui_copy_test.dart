import 'dart:async';
import 'dart:io';

import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final genericFormatters = <String, String Function(Object?)>{
    'export': DataSettingsUiCopy.formatExportError,
    'import': DataSettingsUiCopy.formatImportError,
    'file import': DataSettingsUiCopy.formatFileImportError,
    'file migration': DataSettingsUiCopy.formatFileMigrationError,
    'data migration': DataSettingsUiCopy.formatDataMigrationError,
    'rollback': DataSettingsUiCopy.formatRollbackError,
    'WebDAV save': DataSettingsUiCopy.formatWebDavSaveError,
  };
  final genericFallbacks = <String, List<String>>{
    'export': [
      '导出失败，请检查存储权限后重试',
      'Export failed. Please check storage permissions and try again.',
    ],
    'import': [
      '导入失败，请检查备份内容后重试',
      'Import failed. Please check the backup content and retry.',
    ],
    'file import': [
      '文件导入失败，请检查文件后重试',
      'File import failed. Please check the file and try again.',
    ],
    'file migration': [
      '文件迁移失败，请检查后重试',
      'File migration failed. Please try again.',
    ],
    'data migration': [
      '数据迁移失败，请检查来源数据后重试',
      'Data migration failed. Please check source data and retry.',
    ],
    'rollback': [
      '撤销导入失败，本地数据未变更',
      'Failed to undo import. Local data remains unchanged.',
    ],
    'WebDAV save': [
      '保存 WebDAV 配置失败，请检查输入项',
      'Failed to save WebDAV configuration. Please check the input.',
    ],
  };
  final webDavActionFormatters = <String, String Function(Object?)>{
    'upload': DataSettingsUiCopy.formatWebDavUploadError,
    'restore': DataSettingsUiCopy.formatWebDavRestoreError,
  };

  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('every built-in reward has English display copy for its real ID', () {
    I18n.setLocale(AppLocale.en);
    final labels = <String>[
      for (final reward in ThemeProvider.focusBackdropRewards) ...[
        DataSettingsUiCopy.focusBackdropName(reward.id, reward.name),
        DataSettingsUiCopy.focusBackdropDescription(
          reward.id,
          reward.description,
        ),
      ],
      for (final reward in ThemeProvider.avatarFrameRewards) ...[
        DataSettingsUiCopy.avatarFrameName(reward.id, reward.name),
        DataSettingsUiCopy.avatarFrameDescription(reward.id, reward.description),
      ],
      for (final reward in ThemeProvider.cardSkinRewards) ...[
        DataSettingsUiCopy.cardSkinName(reward.id, reward.name),
        DataSettingsUiCopy.cardSkinDescription(reward.id, reward.description),
      ],
    ];
    expect(labels, everyElement(isNotEmpty));
    expect(labels.where(RegExp(r'[\u3400-\u9fff]').hasMatch), isEmpty);
  });

  test('custom reward text remains unchanged in either language', () {
    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      expect(
        DataSettingsUiCopy.focusBackdropName('custom-id', '我的背景'),
        '我的背景',
      );
      expect(
        DataSettingsUiCopy.avatarFrameDescription('custom-id', 'My frame'),
        'My frame',
      );
    }
  });

  test('backup, export, migration, rollback, and WebDAV fallbacks localize', () {
    final internalError = StateError(
      'synthetic diagnostic at '
      'https://synthetic-user:synthetic-password@dav.example.invalid/'
      'backup?token=synthetic-token',
    );
    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      final languageIndex = locale == AppLocale.zh ? 0 : 1;
      for (final entry in genericFormatters.entries) {
        final message = entry.value(internalError);
        expect(
          message,
          genericFallbacks[entry.key]![languageIndex],
          reason: '${entry.key} unexpected-error fallback in $locale',
        );
        expect(message, isNot(contains('synthetic')));
      }
    }
  });

  test('null errors use localized generic operation copy', () {
    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      final expectedGeneric = locale == AppLocale.zh
          ? '操作未成功，请重试'
          : 'Operation failed, please try again.';
      for (final formatter in genericFormatters.values) {
        expect(formatter(null), expectedGeneric);
      }
      final expectedWebDavAction = locale == AppLocale.zh
          ? '操作未成功，请稍后重试'
          : 'Operation failed, please try again.';
      for (final formatter in webDavActionFormatters.values) {
        expect(formatter(null), expectedWebDavAction);
      }
    }
  });

  test('FormatException branches are localized and hide raw details', () {
    final specialFormatters = <
      String,
      String Function(Object?)
    >{
      'import': DataSettingsUiCopy.formatImportError,
      'file import': DataSettingsUiCopy.formatFileImportError,
      'file migration': DataSettingsUiCopy.formatFileMigrationError,
      'WebDAV save': DataSettingsUiCopy.formatWebDavSaveError,
      'WebDAV upload': DataSettingsUiCopy.formatWebDavUploadError,
      'WebDAV restore': DataSettingsUiCopy.formatWebDavRestoreError,
    };
    final expectedZh = <String, String>{
      'import': '备份内容不是有效的 JSON 格式，请核对后重试',
      'file import': '所选文件格式无效，请核对备份文件',
      'file migration': '文件解析失败，请检查来源类型与字段映射',
      'WebDAV save': '请输入有效的 WebDAV URL（如 https://dav.example.com/dav）',
      'WebDAV upload': '请输入有效的 WebDAV URL',
      'WebDAV restore': '请输入有效的 WebDAV URL',
    };
    final expectedEn = <String, String>{
      'import': 'Invalid JSON format. Please verify the backup content.',
      'file import':
          'Selected file format is invalid. Please select a valid backup file.',
      'file migration':
          'File format is not recognized. Please check source type and field mapping.',
      'WebDAV save':
          'Please enter a valid WebDAV URL (e.g., https://dav.example.com/dav).',
      'WebDAV upload': 'Please enter a valid WebDAV URL.',
      'WebDAV restore': 'Please enter a valid WebDAV URL.',
    };

    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      final expectedByFormatter =
          locale == AppLocale.zh ? expectedZh : expectedEn;
      for (final entry in specialFormatters.entries) {
        final message = entry.value(
          const FormatException('synthetic parser diagnostic'),
        );
        expect(message, expectedByFormatter[entry.key]);
        expect(message, isNot(contains('synthetic')));
      }

      final genericFormatException = locale == AppLocale.zh
          ? const {
              'export': '导出失败，请检查存储权限后重试',
              'data migration': '数据迁移失败，请检查来源数据后重试',
              'rollback': '撤销导入失败，本地数据未变更',
            }
          : const {
              'export':
                  'Export failed. Please check storage permissions and try again.',
              'data migration':
                  'Data migration failed. Please check source data and retry.',
              'rollback': 'Failed to undo import. Local data remains unchanged.',
            };
      for (final key in genericFormatException.keys) {
        final message = genericFormatters[key]!(
          const FormatException('synthetic parser diagnostic'),
        );
        expect(message, genericFormatException[key]);
        expect(message, isNot(contains('synthetic')));
      }
    }
  });

  test('safe ApiException 4xx details stay literal in every locale', () {
    const error = ApiException('422: 导入数据包含不支持的字段');
    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      for (final entry in genericFormatters.entries) {
        expect(
          entry.value(error),
          '导入数据包含不支持的字段',
          reason: '${entry.key} preserves safe server detail in $locale',
        );
      }
    }
  });

  test('captured typed API errors render using the current locale', () {
    final capturedError = const ApiException(
      '连接服务器超时：synthetic diagnostic at '
      'https://synthetic-user:synthetic-password@api.example.invalid',
    );

    I18n.setLocale(AppLocale.zh);
    final capturedWhileChinese = DataSettingsUiCopy.formatExportError(
      capturedError,
    );
    expect(capturedWhileChinese, '连接超时，请稍后重试');

    I18n.setLocale(AppLocale.en);
    final renderedAfterLocaleChange = DataSettingsUiCopy.formatExportError(
      capturedError,
    );
    expect(renderedAfterLocaleChange, 'Connection timed out. Please try again.');
    expect(renderedAfterLocaleChange, isNot(contains('synthetic')));
    expect(renderedAfterLocaleChange, isNot(contains('api.example.invalid')));
  });

  test('unexpected API 5xx diagnostics use each localized fallback', () {
    const error = ApiException(
      '503: synthetic backend diagnostic token=synthetic-token',
    );
    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      final languageIndex = locale == AppLocale.zh ? 0 : 1;
      for (final entry in genericFormatters.entries) {
        final message = entry.value(error);
        expect(message, genericFallbacks[entry.key]![languageIndex]);
        expect(message, isNot(contains('synthetic')));
      }
    }
  });

  test('typed WebDAV network failures localize for upload and restore', () {
    final failures = <Object>[
      const SocketException('synthetic network diagnostic'),
      TimeoutException('synthetic timeout diagnostic'),
      StateError('socket synthetic generic diagnostic'),
      StateError('handshake failed synthetic generic diagnostic'),
      StateError('connection refused synthetic generic diagnostic'),
      StateError('request timed out synthetic generic diagnostic'),
    ];
    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      final expected = locale == AppLocale.zh
          ? '无法连接到 WebDAV 服务器，请检查网络和服务器地址'
          : 'Cannot connect to WebDAV server. Please check your network and server URL.';
      for (final failure in failures) {
        for (final formatter in webDavActionFormatters.values) {
          final message = formatter(failure);
          expect(message, expected);
          expect(message, isNot(contains('synthetic')));
        }
      }
    }
  });

  test('WebDAV HTTP status branches match service errors in both locales', () {
    final expectedZh = <int, String>{
      401: 'WebDAV 认证失败，请检查用户名和密码/Token',
      403: 'WebDAV 认证失败，请检查用户名和密码/Token',
      404: 'WebDAV 云端未找到指定的备份文件',
      500: 'WebDAV 服务器返回错误，请检查路径与读写权限',
      503: 'WebDAV 服务器返回错误，请检查路径与读写权限',
    };
    final expectedEn = <int, String>{
      401: 'WebDAV authentication failed. Please verify your username and password/token.',
      403: 'WebDAV authentication failed. Please verify your username and password/token.',
      404: 'Remote backup file not found on WebDAV server.',
      500:
          'WebDAV server returned an error. Please verify the URL and folder permissions.',
      503:
          'WebDAV server returned an error. Please verify the URL and folder permissions.',
    };

    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      final expectedByStatus =
          locale == AppLocale.zh ? expectedZh : expectedEn;
      for (final status in expectedByStatus.keys) {
        final uploadError = StateError('WebDAV 上传失败: HTTP $status');
        final restoreError = StateError('WebDAV 下载失败: HTTP $status');
        expect(
          DataSettingsUiCopy.formatWebDavUploadError(uploadError),
          expectedByStatus[status],
          reason: 'upload HTTP $status in $locale',
        );
        expect(
          DataSettingsUiCopy.formatWebDavRestoreError(restoreError),
          expectedByStatus[status],
          reason: 'restore HTTP $status in $locale',
        );
      }
    }
  });

  test('unexpected WebDAV diagnostics and credential URLs stay hidden', () {
    final diagnostic = StateError('synthetic internal stack and token');
    final credentialUrl = StateError(
      'synthetic request to '
      'https://synthetic-user:synthetic-password@dav.example.invalid/'
      'backup?token=synthetic-token',
    );

    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      final expectedActionFallbacks = locale == AppLocale.zh
          ? {
              'upload': 'WebDAV 备份上传失败，请检查配置与网络连接',
              'restore': 'WebDAV 恢复失败，请检查配置与网络连接',
            }
          : {
              'upload':
                  'Failed to upload backup to WebDAV. Please check your settings and network connection.',
              'restore':
                  'Failed to restore from WebDAV. Please check your settings and network connection.',
            };
      for (final entry in webDavActionFormatters.entries) {
        final genericMessage = entry.value(diagnostic);
        expect(genericMessage, expectedActionFallbacks[entry.key]);
        expect(genericMessage, isNot(contains('synthetic')));

        final urlMessage = entry.value(credentialUrl);
        expect(
          urlMessage,
          locale == AppLocale.zh
              ? 'WebDAV 服务器返回错误，请检查路径与读写权限'
              : 'WebDAV server returned an error. Please verify the URL and folder permissions.',
        );
        expect(urlMessage, isNot(contains('synthetic')));
        expect(urlMessage, isNot(contains('dav.example.invalid')));
        expect(urlMessage, isNot(contains('synthetic-password')));
      }
    }
  });
}
