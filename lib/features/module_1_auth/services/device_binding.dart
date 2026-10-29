import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Reads a build identifier for display in the offline demo.
/// Android's build id is shown for diagnostics; it is not a hardware UUID.
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
