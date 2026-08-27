/// Parses AppsFlyer conversion-data payloads into organic / non-organic.
///
/// Kept free of the native SDK so unit tests can cover the mapping without
/// spinning up AppsFlyer.
library;

enum AttributionKind { unknown, organic, nonOrganic }

extension AttributionKindX on AttributionKind {
  String get analyticsValue => switch (this) {
    AttributionKind.unknown => 'unknown',
    AttributionKind.organic => 'organic',
    AttributionKind.nonOrganic => 'non_organic',
  };
}

class AttributionSnapshot {
  const AttributionSnapshot({
    required this.kind,
    this.mediaSource = '',
    this.campaign = '',
    this.isFirstLaunch = false,
  });

  final AttributionKind kind;
  final String mediaSource;
  final String campaign;
  final bool isFirstLaunch;

  static const unknown = AttributionSnapshot(kind: AttributionKind.unknown);
}

/// Unwraps the nested map AppsFlyer Flutter plugin returns and reads
/// `af_status` (`Organic` / `Non-organic`).
AttributionSnapshot parseAppsFlyerConversion(dynamic raw) {
  final root = _asStringMap(raw);
  if (root.isEmpty) return AttributionSnapshot.unknown;

  final inner = _asStringMap(root['payload'] ?? root['data'] ?? root);
  final status = '${inner['af_status'] ?? root['af_status']}'.trim();
  final kind = switch (status.toLowerCase()) {
    'organic' => AttributionKind.organic,
    'non-organic' ||
    'nonorganic' ||
    'non_organic' => AttributionKind.nonOrganic,
    _ => AttributionKind.unknown,
  };

  bool firstLaunch = false;
  final first = inner['is_first_launch'] ?? root['is_first_launch'];
  if (first is bool) {
    firstLaunch = first;
  } else {
    firstLaunch = '$first'.toLowerCase() == 'true';
  }

  return AttributionSnapshot(
    kind: kind,
    mediaSource: '${inner['media_source'] ?? root['media_source'] ?? ''}',
    campaign: '${inner['campaign'] ?? root['campaign'] ?? ''}',
    isFirstLaunch: firstLaunch,
  );
}

Map<String, dynamic> _asStringMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry('$key', val));
  }
  return const {};
}
