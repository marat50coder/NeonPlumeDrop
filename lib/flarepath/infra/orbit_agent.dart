import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../config/flare_config.dart';

class OrbitAgent extends http.BaseClient {
  final http.Client _inner = http.Client();
  String? _agent;

  Future<void> prepare() async {
    try {
      if (!Platform.isIOS) {
        _agent = _compose('18.7');
        return;
      }
      final info = await DeviceInfoPlugin().iosInfo;
      _agent = _compose(_normalize(info.systemVersion));
    } catch (_) {
      _agent = _compose('18.7');
    }
  }

  String get userAgent => _agent ?? _compose('18.7');

  String _normalize(String raw) {
    final parts = raw
        .split('.')
        .map(int.tryParse)
        .whereType<int>()
        .take(3)
        .toList();
    if (parts.isEmpty || parts.first < 18) return '18.7';
    return parts.join('.');
  }

  // GAME THEME CATEGORY: crash (partner identity suffix omitted)
  String _compose(String iosVersion) {
    final cpu = iosVersion.replaceAll('.', '_');
    return '${FlareConfig.uaProduct} ${FlareConfig.uaPlatformPrefix} $cpu '
        '${FlareConfig.uaPlatformSuffix} ${FlareConfig.uaEngine} '
        'Version/${FlareConfig.safariVersion} ${FlareConfig.uaMobileToken} '
        'Safari/${FlareConfig.safariTail}';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => userAgent);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
