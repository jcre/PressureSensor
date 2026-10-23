/// Pressure units. Internally everything is stored in hPa (== mbar).
enum PressureUnit {
  psi('psi', 0.0145037738, 2, 0.05),
  mbar('mbar', 1.0, 0, 5),
  kPa('kPa', 0.1, 1, 0.5),
  bar('bar', 0.001, 3, 0.005);

  const PressureUnit(this.label, this.perHpa, this.decimals, this.step);

  final String label;

  /// Multiply a value in hPa by this to get a value in this unit.
  final double perHpa;

  /// Sensible number of decimals when displaying a gauge reading.
  final int decimals;

  /// Slider increment for thresholds, in this unit.
  final double step;

  double fromHpa(double hpa) => hpa * perHpa;

  double toHpa(double value) => value / perHpa;

  String format(double hpa, {int? decimals, bool withUnit = true}) {
    final v = fromHpa(hpa).toStringAsFixed(decimals ?? this.decimals);
    return withUnit ? '$v $label' : v;
  }

  static PressureUnit byName(String? name) =>
      PressureUnit.values.firstWhere((u) => u.name == name, orElse: () => PressureUnit.psi);
}

/// What the big number on screen represents.
enum PressureDisplay {
  /// Pressure above the surrounding air (what a pump gauge shows).
  gauge,

  /// Raw absolute pressure as reported by the sensor.
  absolute,
}

/// Where the "surrounding air" pressure used for gauge readings comes from.
enum ReferenceMode {
  /// A reading captured from the sensor before the raft is sealed ("Zero").
  capturedZero('Captured zero (sensor in open air)'),

  /// The phone's own barometer, offset-calibrated when you press Zero.
  /// Follows weather and altitude changes during a long trip.
  phoneBarometer('Phone barometer (calibrated at zero)'),

  /// Standard sea-level atmosphere, 1013.25 hPa.
  standardAtmosphere('Standard atmosphere (1013.25 hPa)');

  const ReferenceMode(this.label);

  final String label;

  static ReferenceMode byName(String? name) =>
      ReferenceMode.values.firstWhere((m) => m.name == name, orElse: () => ReferenceMode.capturedZero);
}

const double kStandardAtmosphereHpa = 1013.25;
