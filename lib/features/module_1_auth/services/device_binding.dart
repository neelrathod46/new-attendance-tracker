import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Reads a build identifier for display in the offline demo.
/// Android's build id is not a unique hardware UUID; Supabase device binding
/// will need a persistent installation UUID when the online path is added.
Future<String> readDeviceId() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      print('[AUTH] Android device id=${info.id}');
      return info.id;
    }
  } catch (error) {
    print('[AUTH] Device id unavailable: $error');
  }
  return 'offline-device';
}
