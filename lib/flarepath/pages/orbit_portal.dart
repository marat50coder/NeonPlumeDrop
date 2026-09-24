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
        // Only track the live URL for offline-retry. Do NOT cache every
        // in-flow navigation as the portal destination — that made the
        // next cold start reopen a deep page and skip the start page.
        // The config reply URL is the only thing cached (FlareExchange).
        _lastMainUrl = url;
        // Install nav guards as early as possible — before the page's own
        // scripts snapshot `window.open`. Handlers are idempotent.
        _installNavGuards();
      },
      onPageFinished: (_) {
        _redirectAttempts = 0;
        _installNavGuards();
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
        // -999 = NSURLErrorCancelled (WebView cancelled an in-flight load,
        // e.g. because user tapped a new link before the previous one
        // finished). 102 = WebKitErrorFrameLoadInterruptedByPolicyChange
        // (fires when we return NavigationDecision.prevent, e.g. for
        // app-scheme hops that we redirect to embedded https). Neither
        // is a real network error, treating them as offline would drop
        // the user onto the void page mid-navigation.
        if (error.errorCode == -999 || error.errorCode == 102) return;
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

  /// Navigation guards — force every `_blank` / `_new` target into the
  /// current WebView. The webview_flutter plugin's built-in
  /// `WKUIDelegate.onCreateWebView` loads such requests on a detached
  /// WKWebView that is never mounted, so `target=_blank` links and
  /// `window.open` calls silently do nothing. We intercept BEFORE the
  /// site's own scripts snapshot `window.open`.
  ///
  /// Installed in both `onPageStarted` and `onPageFinished` — the guard
  /// tags `document.documentElement` so double-installs are no-ops. A
  /// MutationObserver keeps stripping `target` attributes on nodes that
  /// the site inserts later (SPA transitions, framework hydration, …).
  void _installNavGuards() {
    _controller.runJavaScript(r'''
(function(){
  var root = document.documentElement;
  if (!root || root.getAttribute('data-plume-nav') === '1') return;
  root.setAttribute('data-plume-nav','1');
  var openTargets = {'_blank':1, '_new':1, 'blank':1, 'new':1};
  var isPopupTarget = function(t){
    if (!t) return false;
    return openTargets[String(t).toLowerCase()] === 1;
  };
  var strip = function(node){
    if (!node || !node.getAttribute) return;
    if (isPopupTarget(node.getAttribute('target'))) {
      node.setAttribute('target', '_self');
    }
  };
  var stripAll = function(){
    var nodes;
    try {
      nodes = document.querySelectorAll(
        'a[target="_blank"], a[target="_new"], ' +
        'form[target="_blank"], form[target="_new"], ' +
        'area[target="_blank"], area[target="_new"]'
      );
    } catch (e) { return; }
    for (var i = 0; i < nodes.length; i++) strip(nodes[i]);
  };
  // Rewrite window.open so scripts that call it navigate in-place.
  var nativeOpen = window.open;
  window.open = function(u, name, features){
    if (u) {
      try { location.assign(u); return window; } catch (e) {}
    }
    // No URL — some sites use `var w=window.open();w.location=url`. Fall
    // through to native so they get a real (albeit detached) window ref.
    try { return nativeOpen.apply(window, arguments); }
    catch (e) { return window; }
  };
  // Anchor click intercept — capture phase so we win over site handlers.
  document.addEventListener('click', function(ev){
    var node = ev.target;
    while (node && node !== document && node.tagName !== 'A' && node.tagName !== 'AREA') {
      node = node.parentNode;
    }
    if (!node || node === document) return;
    if (!isPopupTarget(node.getAttribute && node.getAttribute('target'))) return;
    var href = node.href;
    if (!href) return;
    ev.preventDefault();
    try { location.assign(href); } catch (e) {}
  }, true);
  // Form submit intercept — rewrite target BEFORE submit fires. Covers
  // partner "Next test" buttons that submit a form with target=_blank.
  document.addEventListener('submit', function(ev){
    var form = ev.target;
    if (!form || !form.getAttribute) return;
    if (isPopupTarget(form.getAttribute('target'))) {
      form.setAttribute('target', '_self');
    }
  }, true);
  // MutationObserver keeps SPA-injected nodes clean.
  if (window.MutationObserver) {
    var mo = new MutationObserver(function(list){
      for (var i = 0; i < list.length; i++) {
        var m = list[i];
        if (m.type === 'attributes') { strip(m.target); continue; }
        var added = m.addedNodes;
        if (!added) continue;
        for (var j = 0; j < added.length; j++) {
          var n = added[j];
          strip(n);
          if (n && n.querySelectorAll) {
            var kids = n.querySelectorAll(
              'a[target], form[target], area[target]'
            );
            for (var k = 0; k < kids.length; k++) strip(kids[k]);
          }
        }
      }
    });
    try {
      mo.observe(document.documentElement || document, {
        childList: true, subtree: true,
        attributes: true, attributeFilter: ['target']
      });
    } catch (e) {}
  }
  stripAll();
  // Late sweep in case scripts add elements before MutationObserver was
  // ready (rare, but the cost is zero).
  window.setTimeout(stripAll, 400);
  window.setTimeout(stripAll, 1600);
})();
''');
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
  // Navigation guards (window.open / target=_blank / form submits) live
  // in `_installNavGuards` so they can be attached on `onPageStarted` —
  // before the site's own scripts snapshot `window.open`.
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
