import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../infra/skyline_probe.dart';

class VoidSignalPage extends StatefulWidget {
  const VoidSignalPage({
    super.key,
    required this.probe,
    required this.retryBuilder,
  });

  final SkylineProbe probe;
  final WidgetBuilder retryBuilder;

  @override
  State<VoidSignalPage> createState() => _VoidSignalPageState();
}

class _VoidSignalPageState extends State<VoidSignalPage> {
  bool _checking = false;
  bool _stillOffline = false;

  static const SystemUiOverlayStyle _blackChrome = SystemUiOverlayStyle(
    statusBarColor: Color(0xFF1A0A2E),
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF16082A),
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_blackChrome);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _retry() async {
    if (_checking) return;
    HapticFeedback.lightImpact();
    setState(() {
      _checking = true;
      _stillOffline = false;
    });
    bool online = false;
    try {
      online = await widget.probe.canReachNetwork();
    } catch (_) {
      online = false;
    }
    if (!mounted) return;
    if (online) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: widget.retryBuilder),
      );
      return;
    }
    setState(() {
      _checking = false;
      _stillOffline = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final shortest = size.shortestSide;
    final titleSize = landscape ? 20.0 : (shortest < 380 ? 20.0 : 22.0);
    final subtitleSize = landscape ? 15.0 : 16.0;
    final buttonWidth = landscape
        ? (size.width * 0.42).clamp(240.0, 420.0)
        : (size.width * 0.68).clamp(250.0, 400.0);
    final buttonHeight = landscape ? 54.0 : 64.0;

    const gradient = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFF2B1250),
          Color(0xFF5B2C8A),
          Color(0xFF9B5CFF),
          Color(0xFF3A1860),
        ],
        stops: <double>[0.0, 0.38, 0.72, 1.0],
      ),
    );

    final copy = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'NO INTERNET CONNECTION',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            height: 1.2,
          ),
        ),
        SizedBox(height: landscape ? 10 : 14),
        Text(
          'Check your connection and try again',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFFC8C8D4),
            fontSize: subtitleSize,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
      ],
    );

    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _RetryChip(
          width: buttonWidth,
          height: buttonHeight,
          busy: _checking,
          onTap: _retry,
        ),
        if (_stillOffline)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Still offline',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _blackChrome,
      child: Scaffold(
        backgroundColor: const Color(0xFF16082A),
        body: SizedBox.expand(
          child: DecoratedBox(
            decoration: gradient,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: landscape ? 56 : 28,
                  vertical: landscape ? 16 : 36,
                ),
                child: Center(
                  child: landscape
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Expanded(child: copy),
                            const SizedBox(width: 32),
                            actions,
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            copy,
                            const SizedBox(height: 36),
                            actions,
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RetryChip extends StatelessWidget {
  const _RetryChip({
    required this.width,
    required this.height,
    required this.busy,
    required this.onTap,
  });

  final double width;
  final double height;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          gradient: const LinearGradient(
            colors: <Color>[NeonColors.cyan, NeonColors.magenta],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white24, width: 2.2),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: busy ? null : onTap,
            child: Center(
              child: busy
                  ? const SizedBox.square(
                      dimension: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Retry',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
