import 'dart:io';
import 'package:rojava/data/model/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';

class ProfileService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  // Get current user profile
  Future<UserModel?> getCurrentProfile() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      return UserModel.fromJson({
        ...response,
        'email': _supabase.auth.currentUser?.email ?? '',
      });
    } catch (e) {
      print('Get profile error: $e');
      rethrow;
    }
  }

  // Update profile
  Future<void> updateProfile({
    required String userId,
    String? fullName,
    String? bio,
    String? phone,
  }) async {
    try {
      await _supabase
          .from('profiles')
          .update({
            if (fullName != null) 'full_name': fullName,
            if (bio != null) 'bio': bio,
            if (phone != null) 'phone': phone,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
    } catch (e) {
      print('Update profile error: $e');
      rethrow;
    }
  }

  // Upload profile picture
  Future<String> uploadProfilePicture({
    required String userId,
    required File imageFile,
  }) async {
    try {
      print('Starting upload for user: $userId');

      final fileExt = imageFile.path.split('.').last.toLowerCase();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'avatar_$timestamp.$fileExt';
      final filePath = '$userId/$fileName';

      print('File path: $filePath');
      print('File extension: $fileExt');

      // Read file as bytes
      final bytes = await imageFile.readAsBytes();
      print('File size: ${bytes.length} bytes');

      // Upload to Supabase Storage
      final uploadResponse = await _supabase.storage
          .from('avatars')
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$fileExt',
              upsert: true,
            ),
          );

      print('Upload response: $uploadResponse');

      // Get public URL
      final publicUrl = _supabase.storage
          .from('avatars')
          .getPublicUrl(filePath);

      print('Public URL: $publicUrl');

      // Update profile with new avatar URL
      await _supabase
          .from('profiles')
          .update({
            'avatar_url': publicUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      print('Profile updated with avatar URL');

      return publicUrl;
    } catch (e, stackTrace) {
      print('Upload error: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Delete profile picture
  Future<void> deleteProfilePicture(String userId) async {
    try {
      await _supabase
          .from('profiles')
          .update({
            'avatar_url': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
    } catch (e) {
      print('Delete avatar error: $e');
      rethrow;
    }
  }
}
