import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/token_manager.dart';

const _railwayHost = 'mylo-production-5516.up.railway.app';

const baseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://$_railwayHost',
);

// Separate HTTP client for DoH queries — connects directly to Cloudflare IP 1.1.1.1
// (no DNS lookup needed, bypasses broken system DNS)
final _dohRawClient = HttpClient()
  ..badCertificateCallback = (_, __, ___) => true
  ..connectionTimeout = const Duration(seconds: 10);

final Map<String, String> _ipCache = {};

/// Resolve a hostname via Cloudflare DNS-over-HTTPS (1.1.1.1).
/// Connects to 1.1.1.1 by IP — no system DNS needed.
Future<String?> _resolveViaDoh(String hostname) async {
  if (_ipCache.containsKey(hostname)) return _ipCache[hostname];
  try {
    final req = await _dohRawClient.getUrl(
      Uri.parse('https://1.1.1.1/dns-query?name=$hostname&type=A'),
    );
    req.headers.set('accept', 'application/dns-json');
    final resp = await req.close();
    final body = await resp.transform(const Utf8Decoder()).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final answers = (data['Answer'] as List?)
        ?.where((a) => (a as Map)['type'] == 1)
        .toList();
    if (answers == null || answers.isEmpty) return null;
    final ip = (answers.first as Map)['data'] as String;
    _ipCache[hostname] = ip;
    return ip;
  } catch (_) {
    return null;
  }
}

/// Wraps an already-connected Socket as a ConnectionTask<Socket>.
class _CompletedSocketTask implements ConnectionTask<Socket> {
  final Socket _socket;
  _CompletedSocketTask(this._socket);
  @override
  Future<Socket> get socket => Future.value(_socket);
  @override
  void cancel([Object? message]) {}
}

final dioProvider = Provider<Dio>((ref) {
  final secCtx = SecurityContext(withTrustedRoots: true);

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

  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final client = HttpClient(context: secCtx);
    client.badCertificateCallback = (_, __, ___) => true;

    // Override connection factory: resolve hostname via DoH, then connect
    // directly by IP while keeping the original hostname as SNI.
    client.connectionFactory =
        (Uri uri, String? proxyHost, int? proxyPort) async {
      final host = uri.host;
      final port = (uri.port == 0 || uri.port == -1) ? 443 : uri.port;

      // Resolve via DoH (fallback to hostname if DoH fails)
      final ip = await _resolveViaDoh(host);
      final target = ip ?? host;

      // SecureSocket.connect supports serverName (SNI) — required for Railway
      final socket = await SecureSocket.connect(
        target,
        port,
        context: secCtx,
        onBadCertificate: (cert) => true,
        supportedProtocols: ['http/1.1'],
        serverName: host,
      );
      return _CompletedSocketTask(socket);
    };

    return client;
  };

  // Auth token interceptor
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await TokenManager.getToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    },
  ));

  // Retry interceptor — retry up to 2x on connection errors
  dio.interceptors.add(InterceptorsWrapper(
    onError: (error, handler) async {
      final isRetriable = error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout;
      final retryCount = error.requestOptions.extra['retryCount'] ?? 0;
      if (isRetriable && retryCount < 2) {
        // Clear IP cache on retry so DoH re-resolves
        _ipCache.clear();
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
