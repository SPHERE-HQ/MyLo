import 'dart:io';
  import 'package:mime/mime.dart';
  import 'package:supabase_flutter/supabase_flutter.dart';
  import 'package:uuid/uuid.dart';

  class SupabaseService {
    static final _client = Supabase.instance.client;
    static const _uuid = Uuid();

    static Future<String> uploadAvatar(File file, String userId) async {
      final ext = file.path.split('.').last;
      final path = 'users/$userId/avatar_${_uuid.v4()}.$ext';
      await _client.storage.from('avatars').upload(
        path,
        file,
        fileOptions: FileOptions(
          contentType: lookupMimeType(file.path) ?? 'image/jpeg',
          upsert: true,
        ),
      );
      return _client.storage.from('avatars').getPublicUrl(path);
    }

    static Future<String> uploadMedia(File file, String userId, String source) async {
      final ext = file.path.split('.').last;
      final path = '$source/$userId/${_uuid.v4()}.$ext';
      await _client.storage.from('media').upload(
        path,
        file,
        fileOptions: FileOptions(
          contentType: lookupMimeType(file.path) ?? 'application/octet-stream',
          upsert: false,
        ),
      );
      return _client.storage.from('media').getPublicUrl(path);
    }

    static Future<List<String>> uploadMultipleMedia(
      List<File> files,
      String userId,
      String source,
    ) async {
      final futures = files.map((f) => uploadMedia(f, userId, source));
      return Future.wait(futures);
    }
  }
  