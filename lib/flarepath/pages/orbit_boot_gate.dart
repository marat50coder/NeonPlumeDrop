import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../flare_router.dart';
import 'ignite_screen.dart';
import 'void_signal_page.dart';

/// Always paints nowifi on the first Flutter frame.
///
/// After that frame is on screen we probe the WAN. LOADING is pushed only
/// if packets actually flow. A previous online install leaves a stale Wi-Fi
/// path in iOS — that must not open the loading art.
class OrbitBootGate extends StatefulWidget {
  const OrbitBootGate({super.key, required this.router});

  final FlareRouter router;

  @override
  State<OrbitBootGate> createState() => _OrbitBootGateState();
}

class _OrbitBootGateState extends State<OrbitBootGate> {
  var _probed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openLoadingOnlyIfOnline());
    });
  }

  Future<void> _openLoadingOnlyIfOnline() async {
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || _probed) return;
    _probed = true;

    final online = await widget.router.probe.quickReach();
    if (!online || !mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => IgniteScreen(router: widget.router),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return VoidSignalPage(
      probe: widget.router.probe,
      retryBuilder: (_) => IgniteScreen(router: widget.router),
    );
  }
}
