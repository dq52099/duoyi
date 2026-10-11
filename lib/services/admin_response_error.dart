import '../core/i18n.dart';
import 'api_client.dart';

enum AdminResponseFailure {
  itemsNotList,
  itemNotObject,
  missingItems,
  invalidPage,
  missingCoinBalance,
  groupsNotList,
  groupNotObject,
  rolesNotList,
  roleNotObject,
  routeMissing,
}

/// Carries app-owned response diagnostics without interpreting server text.
class AdminResponseException extends ApiException
    implements UserVisibleApiException {
  const AdminResponseException(this.failure, {this.endpoint = ''}) : super('');

  final AdminResponseFailure failure;
  final String endpoint;

  @override
  String get message => diagnostic();

  String diagnostic({AppLocale? locale}) {
    final isEn = (locale ?? I18n.current) == AppLocale.en;
    return switch (failure) {
      AdminResponseFailure.itemsNotList =>
        isEn
            ? 'Invalid server response: paginated items must be a list'
            : '接口返回结构错误：分页 items 需要列表',
      AdminResponseFailure.itemNotObject =>
        isEn
            ? 'Invalid server response: paginated items must contain objects'
            : '接口返回结构错误：分页 items 只能包含对象',
      AdminResponseFailure.missingItems =>
        isEn
            ? 'Invalid server response: $endpoint is missing paginated items'
            : '接口返回结构错误：$endpoint 缺少 items 分页字段',
      AdminResponseFailure.invalidPage =>
        isEn
            ? 'Invalid server response: $endpoint requires a page or list'
            : '接口返回结构错误：$endpoint 需要分页对象或列表',
      AdminResponseFailure.missingCoinBalance =>
        isEn
            ? 'Invalid server response: coin adjustment is missing balance fields'
            : '接口返回结构错误：时光币调整缺少余额字段',
      AdminResponseFailure.groupsNotList =>
        isEn
            ? 'Invalid server response: user groups must be a list'
            : '接口返回结构错误：用户组需要列表',
      AdminResponseFailure.groupNotObject =>
        isEn
            ? 'Invalid server response: user groups must contain objects'
            : '接口返回结构错误：用户组列表只能包含对象',
      AdminResponseFailure.rolesNotList =>
        isEn
            ? 'Invalid server response: roles must be a list'
            : '接口返回结构错误：角色需要列表',
      AdminResponseFailure.roleNotObject =>
        isEn
            ? 'Invalid server response: roles must contain objects'
            : '接口返回结构错误：角色列表只能包含对象',
      AdminResponseFailure.routeMissing =>
        isEn ? '404: Endpoint not found' : '404: 接口不存在',
    };
  }

  @override
  String get userVisibleMessage {
    final isEn = I18n.current == AppLocale.en;
    return switch (failure) {
      AdminResponseFailure.missingCoinBalance =>
        isEn
            ? 'The server did not confirm the coin balance. Refresh to check it before adjusting again.'
            : '服务器未确认时光币余额，请刷新后核对，再决定是否继续调整。',
      AdminResponseFailure.routeMissing =>
        isEn
            ? 'This feature is unavailable on the current server. Update the server and try again.'
            : '当前服务器不支持此功能，请更新服务器后重试。',
      _ =>
        isEn
            ? 'The server returned invalid data. Refresh and try again.'
            : '服务器返回的数据无效，请刷新后重试。',
    };
  }
}
