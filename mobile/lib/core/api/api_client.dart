import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
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
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    validateStatus: (status) => status != null && status < 500,
  ));

  // Allow self-signed dev certs in debug builds
  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final client = HttpClient();
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    client.connectionTimeout = const Duration(seconds: 30);
    return client;
  };

  // Attach JWT to outgoing requests
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await TokenManager.getToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    },
  ));

  // Retry on transient connection errors (max 2 attempts)
  dio.interceptors.add(InterceptorsWrapper(
    onError: (error, handler) async {
      final isRetriable = error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout;
      final retryCount = (error.requestOptions.extra['retryCount'] as int?) ?? 0;
      if (isRetriable && retryCount < 2) {
        await Future.delayed(const Duration(seconds: 2));
        final opts = error.requestOptions;
        opts.extra['retryCount'] = retryCount + 1;
        try {
          final response = await dio.fetch(opts);
          handler.resolve(response);
          return;
        } catch (_) {}
      }
      handler.next(error);
    },
  ));

  return dio;
});
