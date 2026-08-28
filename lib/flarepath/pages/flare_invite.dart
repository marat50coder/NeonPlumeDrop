import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/game_assets.dart';
import '../../core/theme.dart';
import '../config/flare_config.dart';
import '../infra/flare_pulse.dart';
import '../infra/plume_vault.dart';

class FlareInvite extends StatefulWidget {
  const FlareInvite({
    super.key,
    required this.vault,
    required this.pulse,
    required this.nextBuilder,
    this.onTokenReady,
  });

  final PlumeVault vault;
  final FlarePulse pulse;
  final WidgetBuilder nextBuilder;
  final Future<void> Function(String token)? onTokenReady;

  @override
  State<FlareInvite> createState() => _FlareInviteState();
}

class _FlareInviteState extends State<FlareInvite> {
  bool _working = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _accept() async {
    if (_working) return;
    setState(() => _working = true);
    final granted = await widget.pulse.askPermission();
    final token = widget.pulse.token;
    if (granted && token != null && token.isNotEmpty) {
      await widget.onTokenReady?.call(token);
    }
    if (!granted) await _snooze();
    _continue();
  }

  Future<void> _skip() async {
    if (_working) return;
    setState(() => _working = true);
    await _snooze();
    _continue();
  }

  Future<void> _snooze() {
    final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        FlareConfig.pushSnoozeSeconds;
    return widget.vault.snoozePushInvite(until);
  }

  void _continue() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute<void>(builder: widget.nextBuilder));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final landscape = media.orientation == Orientation.landscape;
    final background = landscape
        ? GameAssets.notifyHorizontal
        : GameAssets.notifyVertical;
    final width = landscape
        ? (media.size.width * 0.352).clamp(240.0, 432.0)
        : (media.size.width * 0.78).clamp(270.0, 430.0);
    final acceptH = landscape ? 51.0 : 72.0;
    final skipH = landscape ? 45.0 : 62.0;

    return Scaffold(
      backgroundColor: NeonColors.voidBlack,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            background,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
          Align(
            alignment: Alignment(0, landscape ? 0.78 : 0.88),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _GlowButton(
                  width: width,
                  height: acceptH,
                  label: 'Allow',
                  emphasized: true,
                  busy: _working,
                  fontSize: landscape ? 18 : 23,
                  onTap: _accept,
                ),
                SizedBox(height: landscape ? 8 : 14),
                _GlowButton(
                  width: width * 0.88,
                  height: skipH,
                  label: 'Not now',
                  emphasized: false,
                  busy: false,
                  fontSize: landscape ? 16 : 20,
                  onTap: _skip,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowButton extends StatelessWidget {
  const _GlowButton({
    required this.width,
    required this.height,
    required this.label,
    required this.emphasized,
    required this.busy,
    required this.fontSize,
    required this.onTap,
  });

  final double width;
  final double height;
  final String label;
  final bool emphasized;
  final bool busy;
  final double fontSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = height / 2;
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            colors: emphasized
                ? const <Color>[NeonColors.cyan, NeonColors.magenta]
                : const <Color>[Color(0xFF2A2158), Color(0xFF16102E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: emphasized ? NeonColors.cyan : Colors.white24,
            width: 2.2,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: (emphasized ? NeonColors.cyan : Colors.black)
                  .withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: busy ? null : onTap,
            child: Center(
              child: busy
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                        height: 1.0,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
