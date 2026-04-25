import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'token_manager.dart';
import '../api/api_client.dart';
import '../notifications/fcm_service.dart';

class AuthUser {
  final String id;
  final String username;
  final String email;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final String? phone;
  final int postsCount;
  final int followersCount;
  final int followingCount;
  AuthUser({
    required this.id, required this.username, required this.email,
    this.displayName, this.avatarUrl, this.bio, this.phone,
    this.postsCount = 0, this.followersCount = 0, this.followingCount = 0,
  });
  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
    id: j['id'], username: j['username'], email: j['email'],
    displayName: j['displayName'], avatarUrl: j['avatarUrl'],
    bio: j['bio'], phone: j['phone'],
    postsCount: (j['postsCount'] as num?)?.toInt() ?? 0,
    followersCount: (j['followersCount'] as num?)?.toInt() ?? 0,
    followingCount: (j['followingCount'] as num?)?.toInt() ?? 0,
  );
}

String _parseError(DioException e, String fallback) {
  // Show full underlying error for debugging
  final underlying = e.error != null ? '\n[${e.error.runtimeType}: ${e.error}]' : '';
  if (e.response != null) {
    final data = e.response!.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    if (data is String && data.isNotEmpty) return 'Server: $data';
    return 'Server error ${e.response!.statusCode}$underlying';
  }
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'Timeout$underlying';
    case DioExceptionType.connectionError:
      return 'Connection error$underlying';
    case DioExceptionType.badCertificate:
      return 'SSL error$underlying';
    default:
      return '$fallback: ${e.type.name}$underlying';
  }
}

class AuthNotifier extends AsyncNotifier<AuthUser?> {
  @override
  Future<AuthUser?> build() async {
    final token = await TokenManager.getToken();
    if (token == null) return null;

    // Build a minimal AuthUser from cached id so the user is logged in
    // immediately on cold start, even if /auth/me is briefly unreachable
    // (network blip, backend cold-boot, transient 5xx, ...). We only force
    // a logout when the server explicitly rejects the token (401/403).
    final cachedId = await TokenManager.getUserId();
    final cached = cachedId != null
        ? AuthUser(id: cachedId, username: '', email: '')
        : null;

    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/auth/me');
      final data = res.data;
      final status = res.statusCode ?? 0;
      if (status == 401 || status == 403) {
        await TokenManager.clear();
        return null;
      }
      if (data is Map<String, dynamic>) {
        return AuthUser.fromJson(data);
      }
      // Anything else (5xx, HTML, ...) → keep the cached session.
      return cached;
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      if (code == 401 || code == 403) {
        await TokenManager.clear();
        return null;
      }
      // Network error / 5xx: keep the user signed in with cached data.
      return cached;
    } catch (_) {
      return cached;
    }
  }

  String _serverErrorMessage(Response res, String fallback) {
    final data = res.data;
    if (data is Map) {
      final msg = data['error'] ?? data['message'];
      if (msg != null && msg.toString().isNotEmpty) return msg.toString();
    }
    if (data is String && data.isNotEmpty) return data;
    return '$fallback (kode ${res.statusCode})';
  }

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post('/auth/login', data: {'email': email, 'password': password});
      final status = res.statusCode ?? 0;
      if (status >= 400 || res.data is! Map) {
        state = AsyncValue.error(_serverErrorMessage(res, 'Login gagal'), StackTrace.current);
        return;
      }
      final data = res.data as Map<String, dynamic>;
      final token = data['token'];
      final userJson = data['user'];
      if (token is! String || userJson is! Map) {
        state = AsyncValue.error('Respons login tidak valid dari server', StackTrace.current);
        return;
      }
      await TokenManager.saveToken(token);
      final user = AuthUser.fromJson(Map<String, dynamic>.from(userJson));
      await TokenManager.saveUserId(user.id);
      state = AsyncValue.data(user);
      // Daftarkan device FCM token ke backend (silent, tidak blokir login).
      // ignore: unawaited_futures
      FcmService.registerWithBackend(dio);
    } on DioException catch (e, s) {
      state = AsyncValue.error(_parseError(e, 'Login gagal'), s);
    } catch (e, s) {
      state = AsyncValue.error('Login error: $e', s);
    }
  }

  Future<void> register(String username, String email, String password, String displayName) async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post('/auth/register', data: {
        'username': username, 'email': email, 'password': password, 'displayName': displayName,
      });
      final status = res.statusCode ?? 0;
      if (status >= 400 || res.data is! Map) {
        state = AsyncValue.error(_serverErrorMessage(res, 'Registrasi gagal'), StackTrace.current);
        return;
      }
      final data = res.data as Map<String, dynamic>;
      final token = data['token'];
      final userJson = data['user'];
      if (token is! String || userJson is! Map) {
        state = AsyncValue.error('Respons registrasi tidak valid dari server', StackTrace.current);
        return;
      }
      await TokenManager.saveToken(token);
      final user = AuthUser.fromJson(Map<String, dynamic>.from(userJson));
      await TokenManager.saveUserId(user.id);
      state = AsyncValue.data(user);
      // ignore: unawaited_futures
      FcmService.registerWithBackend(dio);
    } on DioException catch (e, s) {
      state = AsyncValue.error(_parseError(e, 'Registrasi gagal'), s);
    } catch (e, s) {
      state = AsyncValue.error('Register error: $e', s);
    }
  }

  Future<void> logout() async {
    try {
      await FcmService.unregisterFromBackend(ref.read(dioProvider));
    } catch (_) {}
    await TokenManager.clear();
    state = const AsyncValue.data(null);
  }

  Future<void> refreshProfile() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/auth/me');
      if (res.data is Map<String, dynamic>) {
        state = AsyncValue.data(AuthUser.fromJson(res.data as Map<String, dynamic>));
      }
    } catch (_) {
      // keep current state
    }
  }
}

final authStateProvider = AsyncNotifierProvider<AuthNotifier, AuthUser?>(() => AuthNotifier());
