/// Represents a physical audio output device (speakers, headphones, etc.)
class AudioDevice {
  final String id;
  final String name;
  final String shortName;
  final bool isDefault;
  final bool isActive;
  final double volume; // master volume 0.0 - 1.0

  const AudioDevice({
    required this.id,
    required this.name,
    required this.shortName,
    this.isDefault = false,
    this.isActive = true,
    this.volume = 1.0,
  });

  AudioDevice copyWith({
    String? id,
    String? name,
    String? shortName,
    bool? isDefault,
    bool? isActive,
    double? volume,
  }) {
    return AudioDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
      volume: volume ?? this.volume,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioDevice && id == other.id && volume == other.volume;

  @override
  int get hashCode => Object.hash(id, volume);
}

/// Represents an application currently producing audio
class AudioSession {
  final String processId;
  final String processName;
  final String displayName;
  final String? subtitle;
  final double peakLevel; // 0.0 to 1.0
  final double volume; // 0.0 to 1.0 (per-app volume)
  final bool isMuted;
  final bool isActive;
  final String? assignedDeviceId;
  // Extra output device IDs being mirrored via WASAPI loopback
  final List<String> mirrorDeviceIds;
  // Additional PIDs for multi-process apps (e.g. browser tabs)
  final List<String> extraProcessIds;

  const AudioSession({
    required this.processId,
    required this.processName,
    required this.displayName,
    this.subtitle,
    this.peakLevel = 0.0,
    this.volume = 1.0,
    this.isMuted = false,
    this.isActive = true,
    this.assignedDeviceId,
    this.mirrorDeviceIds = const [],
    this.extraProcessIds = const [],
  });

  /// All PIDs belonging to this session (primary + grouped extras)
  List<String> get allProcessIds => [processId, ...extraProcessIds];

  AudioSession copyWith({
    String? processId,
    String? processName,
    String? displayName,
    String? subtitle,
    double? peakLevel,
    double? volume,
    bool? isMuted,
    bool? isActive,
    String? assignedDeviceId,
    List<String>? mirrorDeviceIds,
    List<String>? extraProcessIds,
  }) {
    return AudioSession(
      processId: processId ?? this.processId,
      processName: processName ?? this.processName,
      displayName: displayName ?? this.displayName,
      subtitle: subtitle ?? this.subtitle,
      peakLevel: peakLevel ?? this.peakLevel,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      isActive: isActive ?? this.isActive,
      assignedDeviceId: assignedDeviceId ?? this.assignedDeviceId,
      mirrorDeviceIds: mirrorDeviceIds ?? this.mirrorDeviceIds,
      extraProcessIds: extraProcessIds ?? this.extraProcessIds,
    );
  }
}

/// Auto-duck rule: when triggerApp is producing audio, lower targetApp's volume.
/// Example: when Discord is active → lower Spotify to 30%.
class DuckRule {
  final String id;
  final String triggerProcessName;  // app that triggers the duck
  final String targetProcessName;   // app whose volume gets lowered
  final double duckedVolume;        // 0.0 - 1.0, the volume to set when ducked
  final bool enabled;

  const DuckRule({
    required this.id,
    required this.triggerProcessName,
    required this.targetProcessName,
    this.duckedVolume = 0.3,
    this.enabled = true,
  });

  DuckRule copyWith({
    String? id,
    String? triggerProcessName,
    String? targetProcessName,
    double? duckedVolume,
    bool? enabled,
  }) {
    return DuckRule(
      id: id ?? this.id,
      triggerProcessName: triggerProcessName ?? this.triggerProcessName,
      targetProcessName: targetProcessName ?? this.targetProcessName,
      duckedVolume: duckedVolume ?? this.duckedVolume,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'triggerProcessName': triggerProcessName,
    'targetProcessName': targetProcessName,
    'duckedVolume': duckedVolume,
    'enabled': enabled,
  };

  factory DuckRule.fromJson(Map<String, dynamic> json) => DuckRule(
    id: json['id'] as String,
    triggerProcessName: json['triggerProcessName'] as String,
    targetProcessName: json['targetProcessName'] as String,
    duckedVolume: (json['duckedVolume'] as num).toDouble(),
    enabled: json['enabled'] as bool? ?? true,
  );
}

/// A saved routing profile
class RoutingProfile {
  final String id;
  final String name;
  final String icon;
  final Map<String, String> routes;      // processName -> deviceId
  final Map<String, double> volumes;     // processName -> volume (0.0-1.0)
  final List<DuckRule> duckRules;
  final Map<String, String> customNames; // processName -> custom display name

  const RoutingProfile({
    required this.id,
    required this.name,
    required this.icon,
    required this.routes,
    this.volumes = const {},
    this.duckRules = const [],
    this.customNames = const {},
  });

  RoutingProfile copyWith({
    String? id,
    String? name,
    String? icon,
    Map<String, String>? routes,
    Map<String, double>? volumes,
    List<DuckRule>? duckRules,
    Map<String, String>? customNames,
  }) {
    return RoutingProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      routes: routes ?? this.routes,
      volumes: volumes ?? this.volumes,
      duckRules: duckRules ?? this.duckRules,
      customNames: customNames ?? this.customNames,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'routes': routes,
    'volumes': volumes,
    'duckRules': duckRules.map((r) => r.toJson()).toList(),
    'customNames': customNames,
  };

  factory RoutingProfile.fromJson(Map<String, dynamic> json) => RoutingProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    icon: json['icon'] as String? ?? '🔊',
    routes: Map<String, String>.from(json['routes'] as Map? ?? {}),
    volumes: (json['volumes'] as Map?)?.map(
      (k, v) => MapEntry(k as String, (v as num).toDouble()),
    ) ?? {},
    duckRules: (json['duckRules'] as List?)
        ?.map((e) => DuckRule.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    customNames: Map<String, String>.from(json['customNames'] as Map? ?? {}),
  );
}
