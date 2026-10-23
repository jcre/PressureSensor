import 'adv_packet.dart';
import 'bthome.dart';
import 'field_spec.dart';

enum DecoderKind {
  /// Recognise known open formats (currently BTHome v2) automatically.
  auto('Automatic (BTHome)'),

  /// User-defined byte layout, usually found with the field finder.
  custom('Custom byte layout');

  const DecoderKind(this.label);

  final String label;

  static DecoderKind byName(String? name) =>
      DecoderKind.values.firstWhere((k) => k.name == name, orElse: () => DecoderKind.auto);
}

/// How to turn a sensor's advertisement into numbers.
class DecoderProfile {
  const DecoderProfile({this.kind = DecoderKind.auto, this.pressure, this.temperature, this.battery});

  final DecoderKind kind;

  /// Must produce absolute pressure in hPa.
  final FieldSpec? pressure;

  /// Must produce °C.
  final FieldSpec? temperature;

  /// Must produce %.
  final FieldSpec? battery;

  DecoderProfile copyWith({
    DecoderKind? kind,
    FieldSpec? pressure,
    FieldSpec? temperature,
    FieldSpec? battery,
    bool clearPressure = false,
    bool clearTemperature = false,
    bool clearBattery = false,
  }) =>
      DecoderProfile(
        kind: kind ?? this.kind,
        pressure: clearPressure ? null : pressure ?? this.pressure,
        temperature: clearTemperature ? null : temperature ?? this.temperature,
        battery: clearBattery ? null : battery ?? this.battery,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (pressure != null) 'pressure': pressure!.toJson(),
        if (temperature != null) 'temperature': temperature!.toJson(),
        if (battery != null) 'battery': battery!.toJson(),
      };

  factory DecoderProfile.fromJson(Map<String, dynamic> j) {
    FieldSpec? f(String k) => j[k] is Map ? FieldSpec.fromJson(Map<String, dynamic>.from(j[k] as Map)) : null;
    return DecoderProfile(
      kind: DecoderKind.byName(j['kind'] as String?),
      pressure: f('pressure'),
      temperature: f('temperature'),
      battery: f('battery'),
    );
  }
}

class SensorValues {
  const SensorValues({this.pressureHpa, this.temperatureC, this.batteryPct});

  final double? pressureHpa;
  final double? temperatureC;
  final double? batteryPct;

  bool get isEmpty => pressureHpa == null && temperatureC == null && batteryPct == null;
}

class AdvDecoder {
  static SensorValues decode(AdvPacket packet, DecoderProfile profile) {
    switch (profile.kind) {
      case DecoderKind.auto:
        return decodeKnownFormats(packet);
      case DecoderKind.custom:
        return SensorValues(
          pressureHpa: profile.pressure?.read(packet),
          temperatureC: profile.temperature?.read(packet),
          batteryPct: profile.battery?.read(packet),
        );
    }
  }

  static SensorValues decodeKnownFormats(AdvPacket packet) {
    final bthome = packet.serviceData[BTHome.serviceUuid];
    if (bthome != null) {
      final objs = BTHome.decode(bthome);
      if (objs != null) {
        return SensorValues(
          pressureHpa: objs[0x04]?.first,
          temperatureC: (objs[0x02] ?? objs[0x45] ?? objs[0x57])?.first,
          batteryPct: objs[0x01]?.first,
        );
      }
    }
    return const SensorValues();
  }
}
