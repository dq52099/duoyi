import 'api_client.dart';

/// Backward-compatible name for code that still imports api_service.dart.
class ApiService extends ApiClient {
  ApiService({super.baseUrl = '', super.token, super.httpClient});
}
