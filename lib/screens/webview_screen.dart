import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme.dart';
import '../widgets/neon_button.dart';

/// Generic in-app browser used for Privacy Policy and Support, per the
/// product requirement that both open through a WebView rather than the
/// system browser.
class SimpleWebViewScreen extends StatefulWidget {
  const SimpleWebViewScreen({super.key, required this.title, required this.url});

  final String title;
  final String url;

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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(NeonColors.voidBlack)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _progress = p / 100);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeonColors.voidBlack,
      appBar: AppBar(
        backgroundColor: NeonColors.deepSpace,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title, style: NeonTextStyles.heading(size: 18)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_progress < 1)
              LinearProgressIndicator(
                value: _progress,
                minHeight: 3,
                backgroundColor: Colors.white12,
                color: NeonColors.cyan,
              ),
            Expanded(
              child: _hasError
                  ? _ErrorState(onRetry: () {
                      setState(() => _hasError = false);
                      _controller.reload();
                    })
                  : WebViewWidget(controller: _controller),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            Text(
              'Couldn\'t load this page. Check your connection and try again.',
              textAlign: TextAlign.center,
              style: NeonTextStyles.body,
            ),
            const SizedBox(height: 20),
            NeonButton(label: 'Retry', icon: Icons.refresh_rounded, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
