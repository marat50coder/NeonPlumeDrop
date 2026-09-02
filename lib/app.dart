import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/profile_service.dart';
import 'core/theme.dart';
import 'flarepath/flare_router.dart';
import 'flarepath/pages/ignite_screen.dart';
import 'flarepath/pages/orbit_boot_gate.dart';

class NeonPlumeDropApp extends StatelessWidget {
  const NeonPlumeDropApp({super.key, this.router});

  final FlareRouter? router;

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
          scaffoldBackgroundColor: Colors.black,
          colorScheme: ColorScheme.fromSeed(
            seedColor: NeonColors.cyan,
            brightness: Brightness.dark,
          ).copyWith(surface: Colors.black),
          appBarTheme: const AppBarTheme(
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.black,
              statusBarBrightness: Brightness.dark,
              statusBarIconBrightness: Brightness.light,
              systemNavigationBarColor: Colors.black,
              systemNavigationBarIconBrightness: Brightness.light,
              systemNavigationBarContrastEnforced: false,
            ),
          ),
        ),
        builder: (context, child) => ClampedTextScale(child: child!),
        home: router == null
            ? const IgniteScreen()
            : OrbitBootGate(router: router!),
      ),
    );
  }
}
