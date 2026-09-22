import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme.dart';
import '../widgets/neon_button.dart';

/// Generic in-app browser used for Privacy Policy and Support, per the
/// product requirement that both open through a WebView rather than the
/// system browser.
class SimpleWebViewScreen extends StatefulWidget {
  const SimpleWebViewScreen({
    super.key,
    required this.title,
    required this.url,
    this.fillPage = false,
  });

  final String title;
  final String url;

  /// Stretch the remote page (the Support card is `max-width: 400px`)
  /// so the form fills the device, not a postage-stamp in the middle.
  final bool fillPage;

  @override
  State<SimpleWebViewScreen> createState() => _SimpleWebViewScreenState();
}

class _SimpleWebViewScreenState extends State<SimpleWebViewScreen> {
  late final WebViewController _controller;
  double _progress = 0;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Legal/support pages must be readable regardless of the device's
      // dark-mode preference — force a white page with black text.
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _progress = p / 100);
          },
          onPageFinished: (_) {
            _forceReadableStyle();
            if (widget.fillPage) _fillRemotePage();
          },
          onWebResourceError: (error) {
            // A failed sub-resource (icon, font, analytics beacon) must not
            // replace a page that otherwise rendered fine.
            if (!mounted || error.isForMainFrame == false) return;
            setState(() => _hasError = true);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  /// Overrides any dark-theme CSS the remote page ships so the text is
  /// always black on white (the page rendered white-on-dark before, which
  /// was unreadable in the white game's Privacy Policy).
  void _fillRemotePage() {
    _controller.runJavaScript(r'''
(function(){
  var id='npd-fill';
  if(document.getElementById(id))return;
  var v=document.querySelector('meta[name="viewport"]');
  if(!v){v=document.createElement('meta');v.name='viewport';(document.head||document.documentElement).appendChild(v);}
  v.content='width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
  var s=document.createElement('style');
  s.id=id;
  s.textContent=
    'html,body{height:100% !important;min-height:100vh !important;min-height:100dvh !important;'
    +'width:100% !important;margin:0 !important;padding:0 !important;'
    +'background:#ffffff !important;overflow-x:hidden !important;}'
    +'.support-container{max-width:none !important;width:100% !important;'
    +'min-height:100vh !important;min-height:100dvh !important;margin:0 !important;'
    +'border-radius:0 !important;box-shadow:none !important;'
    +'padding:88px 22px 36px 22px !important;box-sizing:border-box !important;'
    +'display:flex !important;flex-direction:column !important;justify-content:flex-start !important;}'
    +'form{flex:1 1 auto !important;display:flex !important;flex-direction:column !important;}'
    +'textarea{flex:1 1 auto !important;min-height:180px !important;}';
  (document.head||document.documentElement).appendChild(s);
})();
''').catchError((_) {});
  }

  void _forceReadableStyle() {
    _controller.runJavaScript(r'''
(function(){
  var id='npd-readable';
  if(document.getElementById(id))return;
  var s=document.createElement('style');
  s.id=id;
  s.textContent='html,body{background:#ffffff !important;color:#000000 !important;}'
    +'*{color:#000000 !important;border-color:#cccccc !important;}'
    +'a{color:#0645ad !important;}';
  (document.head||document.documentElement).appendChild(s);
  var m=document.querySelector('meta[name="color-scheme"]');
  if(!m){m=document.createElement('meta');m.name='color-scheme';document.head&&document.head.appendChild(m);}
  m.content='light';
})();
''').catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _hasError
                ? _ErrorState(
                    onRetry: () {
                      setState(() => _hasError = false);
                      _controller.reload();
                    },
                  )
                : WebViewWidget(controller: _controller),
            if (_progress < 1)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 3,
                  backgroundColor: Colors.black12,
                  color: NeonColors.cyan,
                ),
              ),
            Positioned(
              top: top + 8,
              left: 12,
              child: Material(
                color: Colors.white,
                elevation: 2,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, color: Colors.black45, size: 48),
              const SizedBox(height: 16),
              Text(
                'Couldn\'t load this page. Check your connection and try again.',
                textAlign: TextAlign.center,
                style: NeonTextStyles.body.copyWith(color: Colors.black87),
              ),
              const SizedBox(height: 20),
              NeonButton(label: 'Retry', icon: Icons.refresh_rounded, onPressed: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}
