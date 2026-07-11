import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Thin wrapper over Dio. The single HTTP entry point for every module's remote
/// datasource. Modules never construct Dio directly — they receive an
/// [ApiClient] so base URL, auth, logging and error mapping stay centralized.
class ApiClient {
  ApiClient(AppConfig config, {Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: config.apiBaseUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  final Dio _dio;

  Dio get raw => _dio;

  /// Attach a bearer token (call after auth).
  void setAuthToken(String? token) {
    if (token == null) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? query}) =>
      _dio.get<T>(path, queryParameters: query);

  Future<Response<T>> post<T>(String path, {Object? data}) =>
      _dio.post<T>(path, data: data);
}
