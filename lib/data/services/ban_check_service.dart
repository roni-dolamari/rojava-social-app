import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import 'device_service.dart';

class BanCheckService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  // Check if device is banned
  Future<bool> isDeviceBanned(String deviceId) async {
    try {
      final response = await _supabase
          .from('banned_devices')
          .select('id')
          .eq('device_id', deviceId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      print('Error checking device ban: $e');
      return false;
    }
  }

  // Check if user is banned
  Future<bool> isUserBanned(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('is_banned')
          .eq('id', userId)
          .maybeSingle();

      return response?['is_banned'] == true;
    } catch (e) {
      print('Error checking user ban: $e');
      return false;
    }
  }

  // Register device for a user
  Future<void> registerDevice(String userId) async {
    try {
      final deviceId = await DeviceService.getDeviceId();
      final deviceInfo = await DeviceService.getDeviceInfo();

      await _supabase.from('device_registry').upsert({
        'user_id': userId,
        'device_id': deviceId,
        'device_info': deviceInfo,
        'last_seen': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error registering device: $e');
    }
  }

  // Check rate limiting for signup
  Future<bool> canAttemptSignup(String deviceId) async {
    try {
      // Check attempts in last hour
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));

      final response = await _supabase
          .from('signup_attempts')
          .select('id')
          .eq('device_id', deviceId)
          .gte('attempted_at', oneHourAgo.toIso8601String());

      final attemptCount = (response as List).length;

      // Allow max 3 signup attempts per hour per device
      return attemptCount < 3;
    } catch (e) {
      print('Error checking signup rate limit: $e');
      return true; // Allow on error to not block legitimate users
    }
  }

  // Log signup attempt
  Future<void> logSignupAttempt({
    required String deviceId,
    required bool success,
    String? blockedReason,
  }) async {
    try {
      await _supabase.from('signup_attempts').insert({
        'device_id': deviceId,
        'success': success,
        'blocked_reason': blockedReason,
        'attempted_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error logging signup attempt: $e');
    }
  }

  // Check rate limiting for login
  Future<bool> canAttemptLogin(String email, String deviceId) async {
    try {
      // Check failed login attempts in last 15 minutes
      final fifteenMinAgo = DateTime.now().subtract(
        const Duration(minutes: 15),
      );

      final response = await _supabase
          .from('login_attempts')
          .select('id')
          .eq('email', email)
          .eq('device_id', deviceId)
          .eq('success', false)
          .gte('attempted_at', fifteenMinAgo.toIso8601String());

      final failedAttempts = (response as List).length;

      // Allow max 5 failed login attempts per 15 minutes
      return failedAttempts < 5;
    } catch (e) {
      print('Error checking login rate limit: $e');
      return true;
    }
  }

  // Log login attempt
  Future<void> logLoginAttempt({
    required String email,
    required String deviceId,
    required bool success,
    String? blockedReason,
  }) async {
    try {
      await _supabase.from('login_attempts').insert({
        'email': email,
        'device_id': deviceId,
        'success': success,
        'blocked_reason': blockedReason,
        'attempted_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error logging login attempt: $e');
    }
  }

  // Comprehensive pre-auth check
  Future<Map<String, dynamic>> performPreAuthCheck(String deviceId) async {
    try {
      // Check if device is banned
      final deviceBanned = await isDeviceBanned(deviceId);
      if (deviceBanned) {
        return {
          'allowed': false,
          'reason': 'This device has been banned from accessing the app.',
        };
      }

      // Check signup rate limit
      final canSignup = await canAttemptSignup(deviceId);
      if (!canSignup) {
        return {
          'allowed': false,
          'reason': 'Too many signup attempts. Please try again later.',
        };
      }

      return {'allowed': true};
    } catch (e) {
      print('Error in pre-auth check: $e');
      return {'allowed': true}; // Allow on error to not block legitimate users
    }
  }
}
