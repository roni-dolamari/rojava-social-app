import 'package:rojava/data/model/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import 'device_service.dart';
import 'ban_check_service.dart';

class AuthService {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final BanCheckService _banCheckService = BanCheckService();

  // Sign up with ban checks
  Future<UserModel?> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      // Get device ID
      final deviceId = await DeviceService.getDeviceId();
      print('🔐 Device ID: $deviceId');

      // Perform pre-auth checks
      final preAuthCheck = await _banCheckService.performPreAuthCheck(deviceId);

      if (preAuthCheck['allowed'] != true) {
        // Log blocked attempt
        await _banCheckService.logSignupAttempt(
          deviceId: deviceId,
          success: false,
          blockedReason: preAuthCheck['reason'],
        );

        throw Exception(preAuthCheck['reason']);
      }

      // Proceed with signup
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );

      if (response.user != null) {
        // Register device
        await _banCheckService.registerDevice(response.user!.id);

        // Log successful attempt
        await _banCheckService.logSignupAttempt(
          deviceId: deviceId,
          success: true,
        );

        // Get user profile
        return await getUserProfile(response.user!.id);
      }

      return null;
    } catch (e) {
      print('Sign up error: $e');
      rethrow;
    }
  }

  // Sign in with ban checks
  Future<UserModel?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      // Get device ID
      final deviceId = await DeviceService.getDeviceId();
      print('🔐 Device ID: $deviceId');

      // Check if device is banned
      final deviceBanned = await _banCheckService.isDeviceBanned(deviceId);
      if (deviceBanned) {
        await _banCheckService.logLoginAttempt(
          email: email,
          deviceId: deviceId,
          success: false,
          blockedReason: 'Device banned',
        );
        throw Exception('This device has been banned from accessing the app.');
      }

      // Check login rate limit
      final canLogin = await _banCheckService.canAttemptLogin(email, deviceId);
      if (!canLogin) {
        await _banCheckService.logLoginAttempt(
          email: email,
          deviceId: deviceId,
          success: false,
          blockedReason: 'Rate limit exceeded',
        );
        throw Exception(
          'Too many failed login attempts. Please try again in 15 minutes.',
        );
      }

      // Attempt login
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        // Check if user is banned
        final userBanned = await _banCheckService.isUserBanned(
          response.user!.id,
        );
        if (userBanned) {
          // Sign out immediately
          await _supabase.auth.signOut();

          await _banCheckService.logLoginAttempt(
            email: email,
            deviceId: deviceId,
            success: false,
            blockedReason: 'User banned',
          );

          throw Exception(
            'Your account has been banned. Contact support for more information.',
          );
        }

        // Register/update device
        await _banCheckService.registerDevice(response.user!.id);

        // Log successful login
        await _banCheckService.logLoginAttempt(
          email: email,
          deviceId: deviceId,
          success: true,
        );

        return await getUserProfile(response.user!.id);
      }

      return null;
    } catch (e) {
      // Log failed attempt for rate limiting
      try {
        final deviceId = await DeviceService.getDeviceId();
        await _banCheckService.logLoginAttempt(
          email: email,
          deviceId: deviceId,
          success: false,
          blockedReason: e.toString(),
        );
      } catch (logError) {
        print('Failed to log login attempt: $logError');
      }

      print('Sign in error: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      print('Sign out error: $e');
      rethrow;
    }
  }

  // Get user profile
  Future<UserModel?> getUserProfile(String userId) async {
    try {
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
      print('Get user profile error: $e');
      return null;
    }
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      print('Reset password error: $e');
      rethrow;
    }
  }

  // Update profile
  Future<void> updateProfile({
    required String userId,
    String? fullName,
    String? avatarUrl,
  }) async {
    try {
      await _supabase
          .from('profiles')
          .update({
            if (fullName != null) 'full_name': fullName,
            if (avatarUrl != null) 'avatar_url': avatarUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
    } catch (e) {
      print('Update profile error: $e');
      rethrow;
    }
  }
}
