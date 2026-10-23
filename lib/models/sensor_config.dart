import '../ble/decoder.dart';

/// A tag the user has chosen to monitor.
class SensorConfig {
  const SensorConfig({
    required this.id,
    required this.name,
    this.profile = const DecoderProfile(),
    this.zeroHpa,
    this.phoneOffsetHpa = 0,
  });

  /// BLE remote id (MAC address on Android, a per-phone UUID on iOS).
  final String id;
  final String name;
  final DecoderProfile profile;

  /// Absolute pressure captured with the "Zero" button (sensor in open air).
  final double? zeroHpa;

  /// sensor − phone barometer, captured at zero. Lets the phone barometer act
  /// as the ambient reference even though the two sensors disagree slightly.
  final double phoneOffsetHpa;

  SensorConfig copyWith({
    String? name,
    DecoderProfile? profile,
    double? zeroHpa,
    double? phoneOffsetHpa,
  }) =>
      SensorConfig(
        id: id,
        name: name ?? this.name,
        profile: profile ?? this.profile,
        zeroHpa: zeroHpa ?? this.zeroHpa,
        phoneOffsetHpa: phoneOffsetHpa ?? this.phoneOffsetHpa,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'profile': profile.toJson(),
        if (zeroHpa != null) 'zeroHpa': zeroHpa,
        'phoneOffsetHpa': phoneOffsetHpa,
      };

  factory SensorConfig.fromJson(Map<String, dynamic> j) => SensorConfig(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Sensor',
        profile: j['profile'] is Map
            ? DecoderProfile.fromJson(Map<String, dynamic>.from(j['profile'] as Map))
            : const DecoderProfile(),
        zeroHpa: (j['zeroHpa'] as num?)?.toDouble(),
        phoneOffsetHpa: (j['phoneOffsetHpa'] as num?)?.toDouble() ?? 0,
      );
}
