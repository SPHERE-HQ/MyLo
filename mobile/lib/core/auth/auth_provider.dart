import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'token_manager.dart';
import '../api/api_client.dart';

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
  if (e.response != null) {
    final data = e.response!.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    if (data is String && data.isNotEmpty) return data;
    return 'Server error ${e.response!.statusCode}';
  }
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'Koneksi timeout — periksa jaringan kamu';
    case DioExceptionType.connectionError:
      return 'Tidak bisa terhubung ke server — pastikan internet aktif';
    case DioExceptionType.badCertificate:
      return 'Masalah sertifikat SSL';
    default:
      return '$fallback: ${e.message ?? 'unknown error'}';
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

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post('/auth/login', data: {'email': email, 'password': password});
      final data = res.data as Map<String, dynamic>;
      await TokenManager.saveToken(data['token'] as String);
      final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
      await TokenManager.saveUserId(user.id);
      state = AsyncValue.data(user);
    } on DioException catch (e, s) {
      state = AsyncValue.error(_parseError(e, 'Login gagal'), s);
    } catch (e, s) {
      state = AsyncValue.error('Login gagal: $e', s);
    }
  }

  Future<void> register(String username, String email, String password, String displayName) async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post('/auth/register', data: {
        'username': username, 'email': email, 'password': password, 'displayName': displayName,
      });
      final data = res.data as Map<String, dynamic>;
      await TokenManager.saveToken(data['token'] as String);
      final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
      state = AsyncValue.data(user);
    } on DioException catch (e, s) {
      state = AsyncValue.error(_parseError(e, 'Registrasi gagal'), s);
    } catch (e, s) {
      state = AsyncValue.error('Registrasi gagal: $e', s);
    }
  }

  Future<void> logout() async {
    await TokenManager.clear();
    state = const AsyncValue.data(null);
  }
}

final authStateProvider = AsyncNotifierProvider<AuthNotifier, AuthUser?>(() => AuthNotifier());
