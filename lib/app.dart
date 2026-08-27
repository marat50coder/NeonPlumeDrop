import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/profile_service.dart';
import 'core/theme.dart';
import 'screens/splash_screen.dart';

class NeonPlumeDropApp extends StatelessWidget {
  const NeonPlumeDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProfileService>.value(
      value: ProfileService.instance,
      child: MaterialApp(
        title: 'Neon Plume Drop',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: NeonColors.voidBlack,
          colorScheme: ColorScheme.fromSeed(
            seedColor: NeonColors.cyan,
            brightness: Brightness.dark,
          ),
        ),
        builder: (context, child) => ClampedTextScale(child: child!),
        home: const SplashScreen(),
      ),
    );
  }
}
