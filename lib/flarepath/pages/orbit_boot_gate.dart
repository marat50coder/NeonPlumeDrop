import 'package:flutter/material.dart';

import '../flare_router.dart';
import 'ignite_screen.dart';

/// First frame is LOADING. IgniteScreen itself jumps to nowifi only when
/// the DNS probe fails — same contract as Bolt-of-Aether `NovaWarmup`.
class OrbitBootGate extends StatelessWidget {
  const OrbitBootGate({super.key, required this.router});

  final FlareRouter router;

  @override
  Widget build(BuildContext context) => IgniteScreen(router: router);
}
