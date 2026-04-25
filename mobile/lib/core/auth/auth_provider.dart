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
  AuthUser({required this.id, required this.username, required this.email, this.displayName, this.avatarUrl});
  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
    id: j['id'], username: j['username'], email: j['email'],
    displayName: j['displayName'], avatarUrl: j['avatarUrl'],
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
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/auth/me');
      return AuthUser.fromJson(res.data as Map<String, dynamic>);
    } catch (_) {
      await TokenManager.clear();
      return null;
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
      state = AsyncValue.data(AuthUser.fromJson(res.data as Map<String, dynamic>));
    } catch (_) {
      // keep current state
    }
  }
}

final authStateProvider = AsyncNotifierProvider<AuthNotifier, AuthUser?>(() => AuthNotifier());
