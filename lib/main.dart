import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/audio_service.dart';
import 'core/orientation_controller.dart';
import 'core/profile_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  await OrientationController.allowAll();
  try {
    await ProfileService.instance.load();
  } catch (_) {}
  try {
    await AudioService.instance.init();
  } catch (_) {}
  runApp(const NeonPlumeDropApp());
}
