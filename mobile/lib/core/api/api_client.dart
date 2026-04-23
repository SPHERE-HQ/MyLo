import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/token_manager.dart';

const baseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://mylo-production-5516.up.railway.app',
);

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
    validateStatus: (status) => status != null && status < 500,
  ));

  // Auth token interceptor
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await TokenManager.getToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    },
    onError: (error, handler) {
      handler.next(error);
    },
  ));

  // Retry interceptor — retry up to 2x on connection errors
  dio.interceptors.add(InterceptorsWrapper(
    onError: (error, handler) async {
      final isConnectionError = error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout;
      final retryCount = error.requestOptions.extra['retryCount'] ?? 0;
      if (isConnectionError && retryCount < 2) {
        await Future.delayed(const Duration(seconds: 2));
        final opts = error.requestOptions;
        opts.extra['retryCount'] = retryCount + 1;
        try {
          final response = await dio.fetch(opts);
          handler.resolve(response);
        } catch (e) {
          handler.next(error);
        }
        return;
      }
      handler.next(error);
    },
  ));

  return dio;
});
