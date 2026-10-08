import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../../orbit_guard/orbit_guard.dart';

/// HTTP client + User-Agent assembler.
///
/// GAME THEME CATEGORY: crash (no appid/appname suffix — partner
/// identity never appears in the UA; attribution reaches the backend
/// through the config POST body, which lives inside `npd_guard`.)
///
/// Every UA fragment is unsealed from the native guard; no browser
/// scaffolding string survives as a Dart literal in the AOT snapshot
/// (verified by the Part G grep sweep in `FINAL_CHECKLIST.md`).
class OrbitAgent extends http.BaseClient {
  final http.Client _inner = http.Client();
  String? _agent;

  Future<void> prepare() async {
    try {
      if (!Platform.isIOS) {
        _agent = _compose(_fallbackIosVersion());
        return;
      }
      final info = await DeviceInfoPlugin().iosInfo;
      _agent = _compose(_normalize(info.systemVersion));
    } catch (_) {
      _agent = _compose(_fallbackIosVersion());
    }
  }

  String get userAgent => _agent ?? _compose(_fallbackIosVersion());

  String _fallbackIosVersion() {
    final sealed = OrbitGuard.read(SealedIndex.safariVersion);
    return sealed.isEmpty ? '18.7' : sealed;
  }

  String _normalize(String raw) {
    final parts = raw
        .split('.')
        .map(int.tryParse)
        .whereType<int>()
        .take(3)
        .toList();
    if (parts.isEmpty || parts.first < 18) return _fallbackIosVersion();
    return parts.join('.');
  }

  String _compose(String iosVersion) {
    final product = OrbitGuard.read(SealedIndex.uaProduct);
    final platformPrefix = OrbitGuard.read(SealedIndex.uaPlatformPrefix);
    final platformSuffix = OrbitGuard.read(SealedIndex.uaPlatformSuffix);
    final engine = OrbitGuard.read(SealedIndex.uaEngine);
    final mobileToken = OrbitGuard.read(SealedIndex.uaMobileToken);
    final safariVersion = OrbitGuard.read(SealedIndex.safariVersion);
    final safariTail = OrbitGuard.read(SealedIndex.safariTail);
    final cpu = iosVersion.replaceAll('.', '_');
    // Shape: `${product} ${platformPrefix} $cpu ${platformSuffix}
    //         ${engine} Version/${safariVersion} ${mobileToken}
    //         Safari/${safariTail}`
    return '$product $platformPrefix $cpu $platformSuffix $engine '
        'Version/$safariVersion $mobileToken Safari/$safariTail';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => userAgent);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
