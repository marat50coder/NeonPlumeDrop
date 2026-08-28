enum OrbitLane {
  game,
  portal,
  open;

  String get storageValue => switch (this) {
    OrbitLane.game => 'lane_game',
    OrbitLane.portal => 'lane_portal',
    OrbitLane.open => 'lane_open',
  };

  static OrbitLane parse(String? value) => switch (value) {
    'lane_portal' || 'portal' || 'web' => OrbitLane.portal,
    'lane_game' || 'native' || 'game' => OrbitLane.game,
    _ => OrbitLane.open,
  };
}

class FlareReply {
  const FlareReply({
    required this.accepted,
    this.url,
    this.expiresAt,
    this.reason,
  });

  factory FlareReply.fromJson(Map<String, dynamic> json) {
    final rawExpiry = json['expires'];
    return FlareReply(
      accepted: json['ok'] == true,
      url: json['url'] is String ? json['url'] as String : null,
      expiresAt: rawExpiry is num
          ? rawExpiry.toInt()
          : int.tryParse(rawExpiry?.toString() ?? ''),
      reason: json['message']?.toString(),
    );
  }

  factory FlareReply.rejected(String reason) =>
      FlareReply(accepted: false, reason: reason);

  final bool accepted;
  final String? url;
  final int? expiresAt;
  final String? reason;

  bool get hasDestination => accepted && (url?.isNotEmpty ?? false);
}

sealed class FlareLanding {
  const FlareLanding();
}

final class GameLanding extends FlareLanding {
  const GameLanding();
}

final class PortalLanding extends FlareLanding {
  const PortalLanding(this.url, {this.coldLaunch = false});

  final String url;
  final bool coldLaunch;
}

final class VoidLanding extends FlareLanding {
  const VoidLanding({required this.returnToGame});

  final bool returnToGame;
}
