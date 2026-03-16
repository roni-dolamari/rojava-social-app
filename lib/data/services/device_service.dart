import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const String _deviceIdKey = 'unique_device_id';

  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();

    String? storedId = prefs.getString(_deviceIdKey);
    if (storedId != null && storedId.isNotEmpty) {
      return storedId;
    }

    String deviceId;

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        final rawId =
            '${androidInfo.id}-${androidInfo.device}-${androidInfo.model}-${androidInfo.brand}';
        deviceId = _hashString(rawId);
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceId = _hashString(iosInfo.identifierForVendor ?? 'unknown-ios');
      } else {
        deviceId = _hashString(
          'unknown-platform-${DateTime.now().millisecondsSinceEpoch}',
        );
      }
    } catch (e) {
      print('Error getting device ID: $e');
      deviceId = _hashString(
        'fallback-${DateTime.now().millisecondsSinceEpoch}',
      );
    }

    await prefs.setString(_deviceIdKey, deviceId);
    return deviceId;
  }

  static Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return {
          'platform': 'android',
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'androidVersion': androidInfo.version.release,
          'sdkInt': androidInfo.version.sdkInt,
          'brand': androidInfo.brand,
          'device': androidInfo.device,
          'isPhysicalDevice': androidInfo.isPhysicalDevice,
          'id': androidInfo.id,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return {
          'platform': 'ios',
          'model': iosInfo.model,
          'systemName': iosInfo.systemName,
          'systemVersion': iosInfo.systemVersion,
          'name': iosInfo.name,
          'isPhysicalDevice': iosInfo.isPhysicalDevice,
          'identifierForVendor': iosInfo.identifierForVendor,
        };
      }
    } catch (e) {
      print('Error getting device info: $e');
    }

    return {'platform': 'unknown'};
  }

  static String _hashString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static Future<void> clearDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceIdKey);
  }
}
