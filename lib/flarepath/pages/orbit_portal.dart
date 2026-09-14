import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../config/flare_config.dart';
import '../infra/flare_pulse.dart';
import '../infra/orbit_agent.dart';
import '../infra/plume_vault.dart';
import '../infra/skyline_probe.dart';
import 'void_signal_page.dart';

class OrbitPortal extends StatefulWidget {
  const OrbitPortal({
    super.key,
    required this.url,
    required this.vault,
    required this.probe,
    required this.pulse,
    required this.agent,
    this.coldLaunch = false,
  });

  final String url;
  final PlumeVault vault;
  final SkylineProbe probe;
  final FlarePulse pulse;
  final OrbitAgent agent;
  final bool coldLaunch;

  @override
  State<OrbitPortal> createState() => _OrbitPortalState();
}

class _OrbitPortalState extends State<OrbitPortal> with WidgetsBindingObserver {
  late final WebViewController _controller;
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  bool _viewportReady = false;
  bool _coldReloadIssued = false;
  bool _offlineShown = false;
  int _redirectAttempts = 0;
  String? _lastMainUrl;
  Timer? _metricsDebounce;
  Size? _lastMetricsSize;

  static const Set<String> _inAppSchemes = <String>{
    'http',
    'https',
    'about',
    'data',
    'blob',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterImmersive();
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    final params = Platform.isIOS
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
            javaScriptCanOpenWindowsAutomatically: true,
          )
        : const PlatformWebViewControllerCreationParams();
    _controller =
        WebViewController.fromPlatformCreationParams(
            params,
            onPermissionRequest: (request) => request.grant(),
          )
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black)
          ..setUserAgent(widget.agent.userAgent)
          ..enableZoom(false)
          ..setNavigationDelegate(_navigation());
    if (_controller.platform is WebKitWebViewController) {
      (_controller.platform as WebKitWebViewController)
          .setAllowsBackForwardNavigationGestures(true);
    }

    widget.pulse.onDestination = _onPushLink;
    _networkSubscription = widget.probe.changes.listen((states) {
      if (states.every((state) => state == ConnectivityResult.none)) {
        _goOffline();
      }
    });

    if (widget.coldLaunch) {
      _settleColdViewport();
    } else {
      _viewportReady = true;
      _controller.loadRequest(Uri.parse(widget.url));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
  }

  void _onPushLink(String url) {
    if (!mounted) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
    unawaited(widget.vault.consumePushUrl());
    _controller.loadRequest(uri);
  }

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _settleColdViewport() async {
    _enterImmersive();
    await Future<void>.delayed(
      const Duration(milliseconds: FlareConfig.coldViewportMs),
    );
    if (!mounted) return;
    setState(() => _viewportReady = true);
    await _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    setState(() {});
    final view = View.of(context);
    final size = view.physicalSize;
    final rotated = _lastMetricsSize != null &&
        ((_lastMetricsSize!.width < _lastMetricsSize!.height) !=
            (size.width < size.height));
    _lastMetricsSize = size;
    if (!rotated) return;
    _enterImmersive();
    _metricsDebounce?.cancel();
    _pokeReflow(FlareConfig.reflowPokesMs);
  }

  void _pokeReflow(List<int> delaysMs) {
    for (final ms in delaysMs) {
      Timer(Duration(milliseconds: ms), () {
        if (!mounted) return;
        _controller
            .runJavaScript(
              'window.dispatchEvent(new Event("orientationchange"));'
              'window.dispatchEvent(new Event("resize"));'
              'if(window.visualViewport)'
              '  window.visualViewport.dispatchEvent(new Event("resize"));',
            )
            .catchError((_) {});
      });
    }
    _metricsDebounce = Timer(const Duration(milliseconds: 410), () {
      if (!mounted) return;
      _installOrbitShell();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enterImmersive();
      _consumePending();
    }
  }

  Future<void> _consumePending() async {
    final value = await widget.vault.consumePushUrl();
    final uri = value == null ? null : Uri.tryParse(value);
    if (mounted && uri != null && uri.hasScheme) {
      await _controller.loadRequest(uri);
    }
  }

  NavigationDelegate _navigation() {
    return NavigationDelegate(
      onPageStarted: (url) {
        _lastMainUrl = url;
        unawaited(widget.vault.cacheUrl(url, null));
      },
      onPageFinished: (_) {
        _redirectAttempts = 0;
        _installOrbitShell();
        Future<void>.delayed(
          const Duration(milliseconds: FlareConfig.pageSettleMs),
          () async {
            if (!mounted) return;
            setState(() {});
            await _controller.runJavaScript(
              'window.dispatchEvent(new Event("resize"));'
              'window.visualViewport?.dispatchEvent(new Event("resize"));',
            );
            _installOrbitShell();
            if (widget.coldLaunch && !_coldReloadIssued) {
              _coldReloadIssued = true;
              String? current;
              try {
                current = await _controller.currentUrl();
              } catch (_) {
                current = null;
              }
              if (!mounted) return;
              if (current == widget.url) {
                await _controller.reload();
              }
            }
          },
        );
      },
      onWebResourceError: (error) {
        if (error.errorCode == -999) return;
        final mainFrame = error.isForMainFrame ?? true;
        final lower = error.description.toLowerCase();
        final redirectLoop = error.errorCode == -1007 ||
            lower.contains('too_many_redirects') ||
            lower.contains('too many redirects');
        final retryUrl = error.url ?? _lastMainUrl;
        if (redirectLoop &&
            retryUrl != null &&
            retryUrl.isNotEmpty &&
            _redirectAttempts < FlareConfig.redirectLoopBudget) {
          _redirectAttempts++;
          _controller.loadRequest(Uri.parse(retryUrl));
          return;
        }
        if (!mainFrame) return;
        _showOfflineAfterProbe();
      },
      onNavigationRequest: (request) {
        final uri = Uri.tryParse(request.url);
        if (uri == null) return NavigationDecision.prevent;
        final scheme = uri.scheme.toLowerCase();
        if (_inAppSchemes.contains(scheme)) {
          if (request.isMainFrame) _lastMainUrl = request.url;
          return NavigationDecision.navigate;
        }
        if (scheme == 'javascript') {
          return NavigationDecision.prevent;
        }
        // App-scheme hops (OneLink / af_dp / intent) often carry the next
        // https URL in a query field. Load that in this WebView so partner
        // "next test" redirects are not dropped.
        final embedded = _httpInside(uri);
        if (embedded != null) {
          _controller.loadRequest(embedded);
          return NavigationDecision.prevent;
        }
        launchUrl(uri, mode: LaunchMode.externalApplication)
            .catchError((_) => false);
        return NavigationDecision.prevent;
      },
    );
  }

  /// Pulls an http(s) destination out of an app-scheme URL without a host
  /// allowlist — only scheme gating.
  static Uri? _httpInside(Uri uri) {
    const keys = <String>[
      'af_web_dp',
      'browser_fallback_url',
      'click_url',
      'url',
      'link',
      'redirect',
      'deep_link_value',
    ];
    for (final key in keys) {
      final raw = uri.queryParameters[key];
      if (raw == null || raw.isEmpty) continue;
      final inner = Uri.tryParse(raw);
      if (inner != null &&
          (inner.scheme == 'http' || inner.scheme == 'https') &&
          inner.host.isNotEmpty) {
        return inner;
      }
    }
    final blob = uri.toString();
    final httpsAt = blob.indexOf('https://');
    final httpAt = blob.indexOf('http://');
    final at = httpsAt >= 0
        ? httpsAt
        : httpAt >= 0
        ? httpAt
        : -1;
    if (at < 0) return null;
    final inner = Uri.tryParse(blob.substring(at));
    if (inner != null &&
        (inner.scheme == 'http' || inner.scheme == 'https') &&
        inner.host.isNotEmpty) {
      return inner;
    }
    return null;
  }

  Future<void> _showOfflineAfterProbe() async {
    if (_offlineShown) return;
    bool online = true;
    try {
      online = await widget.probe.canReachNetwork();
    } catch (_) {
      online = false;
    }
    if (online) return;
    _goOffline();
  }

  Future<void> _goOffline() async {
    if (_offlineShown || !mounted) return;
    _offlineShown = true;
    String current;
    try {
      current = await _controller.currentUrl() ?? widget.url;
    } catch (_) {
      current = widget.url;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => VoidSignalPage(
          probe: widget.probe,
          retryBuilder: (_) => OrbitPortal(
            url: current,
            vault: widget.vault,
            probe: widget.probe,
            pulse: widget.pulse,
            agent: widget.agent,
          ),
        ),
      ),
    );
  }

  void _installOrbitShell() {
    _controller.runJavaScript(r'''
(function(){
  var root = document.documentElement;
  if (!root || root.getAttribute('data-plume-ready') === '1') return;
  root.setAttribute('data-plume-ready','1');
  var glue = function(){ return Array.prototype.join.call(arguments, ''); };
  var pinInset = function(){
    var sides = ['top','right','bottom','left'];
    var i;
    for (i = 0; i < sides.length; i++) {
      var side = sides[i];
      root.style.setProperty(glue(String.fromCharCode(45,45),'safe','-area-','inset-',side), '0px');
      root.style.setProperty(glue(String.fromCharCode(45,45),'safe','-',side), '0px');
    }
    var short = ['sat','sar','sab','sal'];
    for (i = 0; i < short.length; i++) {
      root.style.setProperty(glue(String.fromCharCode(45,45), short[i]), '0px');
    }
  };
  var pinChrome = function(){
    root.style.overscrollBehavior = 'none';
    if (document.body) document.body.style.overscrollBehavior = 'none';
    root.style.webkitTapHighlightColor = 'rgba(0,0,0,0)';
    root.style.colorScheme = 'dark';
  };
  var pinFields = function(){
    var nodes = document.querySelectorAll('input,textarea,select,[contenteditable="true"]');
    var i;
    for (i = 0; i < nodes.length; i++) {
      nodes[i].style.fontSize = '16px';
    }
  };
  var wanted =
    'width=device-width, initial-scale=1, maximum-scale=1, ' +
    'minimum-scale=1, user-scalable' + '=no, viewport-fit=contain';
  var pinViewport = function(){
    var head = document.head || root;
    if (!head) return;
    var meta = document.querySelector('meta[name="viewport"]');
    if (meta) return;
    meta = document.createElement('meta');
    meta.setAttribute('name', 'viewport');
    meta.setAttribute('content', wanted);
    head.appendChild(meta);
  };
  var railId = 'plume-orbit-rail';
  var pinRail = function(){
    var head = document.head || root;
    if (!head) return;
    var rail = document.getElementById(railId);
    if (!rail) {
      rail = document.createElement('style');
      rail.id = railId;
      head.appendChild(rail);
    }
    rail.textContent =
      '::-webkit-scrollbar{width:6px;height:6px}' +
      '::-webkit-scrollbar-thumb{background:rgba(61,239,255,.38);border-radius:4px}';
  };
  var kbUp = function(){
    var vv = window.visualViewport;
    return !!vv && vv.height < window.innerHeight * 0.73;
  };
  var refresh = function(){
    if (kbUp()) return;
    pinInset();
    pinChrome();
    pinViewport();
    pinFields();
    pinRail();
  };
  var follow = function(u){
    if (!u) return;
    try { location.assign(u); } catch (e) {}
  };
  window.open = function(u){
    follow(u);
    return window;
  };
  document.addEventListener('click', function(ev){
    var node = ev.target;
    while (node && node.tagName !== 'A') node = node.parentNode;
    if (!node) return;
    var t = (node.getAttribute('target') || '').toLowerCase();
    if (t !== '_blank' && t !== '_new') return;
    var href = node.href;
    if (!href) return;
    ev.preventDefault();
    follow(href);
  }, true);
  var wrapHist = function(name){
    var orig = history[name];
    if (typeof orig !== 'function') return;
    history[name] = function(){
      var out = orig.apply(this, arguments);
      window.setTimeout(refresh, 80);
      return out;
    };
  };
  wrapHist('pushState');
  wrapHist('replaceState');
  window.addEventListener('popstate', function(){
    window.setTimeout(refresh, 80);
  });
  var isField = function(node){
    return !!node && node.matches &&
      node.matches('input, textarea, select, [contenteditable="true"]');
  };
  document.addEventListener('focusin', function(ev){
    if (!isField(ev.target)) return;
    window.setTimeout(function(){
      var active = document.activeElement;
      if (isField(active)) active.scrollIntoView({block:'nearest'});
    }, 310);
  }, true);
  refresh();
  window.setTimeout(refresh, 240);
  window.setTimeout(refresh, 880);
  window.setInterval(refresh, 4100);
})();
''');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _metricsDebounce?.cancel();
    _networkSubscription?.cancel();
    widget.pulse.onDestination = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).viewPadding;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _controller.canGoBack()) {
          await _controller.goBack();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: ColoredBox(
          color: Colors.black,
          child: _viewportReady
              ? Padding(
                  padding: EdgeInsets.only(
                    top: safe.top,
                    bottom: safe.bottom,
                    left: safe.left,
                    right: safe.right,
                  ),
                  child: WebViewWidget(controller: _controller),
                )
              : const ColoredBox(color: Colors.black),
        ),
      ),
    );
  }
}
