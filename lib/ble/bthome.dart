import 'dart:typed_data';

/// Minimal BTHome v2 (https://bthome.io) decoder. BTHome is an open format
/// for sensor advertisements; it is used here as a ready-made option in case
/// a tag is flashed with BTHome firmware (the nRF52810 in these tags can be).
class BTHome {
  static const serviceUuid = 'fcd2';

  /// Object id -> (data length, signed, factor). Only fixed-length objects;
  /// 0x53/0x54 (text/raw) are length-prefixed and handled separately.
  static const Map<int, (int, bool, double)> _objects = {
    0x00: (1, false, 1), // packet id
    0x01: (1, false, 1), // battery %
    0x02: (2, true, 0.01), // temperature °C
    0x03: (2, false, 0.01), // humidity %
    0x04: (3, false, 0.01), // pressure hPa
    0x05: (3, false, 0.01), // illuminance lux
    0x06: (2, false, 0.01), // mass kg
    0x07: (2, false, 0.01), // mass lb
    0x08: (2, true, 0.01), // dew point °C
    0x09: (1, false, 1), // count
    0x0A: (3, false, 0.001), // energy kWh
    0x0B: (3, false, 0.01), // power W
    0x0C: (2, false, 0.001), // voltage V
    0x0D: (2, false, 1), // pm2.5
    0x0E: (2, false, 1), // pm10
    0x12: (2, false, 1), // co2
    0x13: (2, false, 1), // tvoc
    0x14: (2, false, 0.01), // moisture %
    0x2E: (1, false, 1), // humidity %
    0x2F: (1, false, 1), // moisture %
    0x3A: (1, false, 1), // button event
    0x3C: (2, false, 1), // dimmer event
    0x3D: (2, false, 1), // count
    0x3E: (4, false, 1), // count
    0x3F: (2, true, 0.1), // rotation °
    0x40: (2, false, 1), // distance mm
    0x41: (2, false, 0.1), // distance m
    0x42: (3, false, 0.001), // duration s
    0x43: (2, false, 0.001), // current A
    0x44: (2, false, 0.01), // speed m/s
    0x45: (2, true, 0.1), // temperature °C
    0x46: (1, false, 0.1), // UV index
    0x47: (2, false, 0.1), // volume L
    0x48: (2, false, 1), // volume mL
    0x49: (2, false, 0.001), // flow m3/h
    0x4A: (2, false, 0.1), // voltage V
    0x4B: (3, false, 0.001), // gas m3
    0x4C: (4, false, 0.001), // gas m3
    0x4D: (4, false, 0.001), // energy kWh
    0x4E: (4, false, 0.001), // volume L
    0x4F: (4, false, 0.001), // water L
    0x50: (4, false, 1), // timestamp
    0x51: (2, false, 0.001), // acceleration m/s²
    0x52: (2, false, 0.001), // gyroscope °/s
    0x55: (4, false, 0.001), // volume storage L
    0x56: (2, false, 1), // conductivity µS/cm
    0x57: (1, true, 1), // temperature °C
    0x58: (1, true, 0.35), // temperature °C
    0x59: (1, true, 1), // count
    0x5A: (2, true, 1), // count
    0x5B: (4, true, 1), // count
    0x5C: (4, true, 0.01), // power W
    0x5D: (2, true, 0.001), // current A
    0x5E: (2, false, 0.01), // direction °
    0x5F: (2, false, 0.1), // precipitation mm
    0x60: (1, false, 1), // channel
    0x61: (2, false, 1), // rotational speed rpm
    0xF0: (2, false, 1), // device type id
    0xF1: (4, false, 1), // firmware version
    0xF2: (3, false, 1), // firmware version
  };

  /// Positions of the header and object-id bytes (everything that isn't a
  /// measurement), or null if this isn't unencrypted BTHome v2.
  static Set<int>? structureBytes(Uint8List data) {
    if (data.isEmpty || data[0] & 0x01 != 0 || (data[0] >> 5) & 0x07 != 2) return null;
    final out = <int>{0};
    var i = 1;
    while (i < data.length) {
      out.add(i);
      final id = data[i++];
      if (id == 0x53 || id == 0x54) {
        if (i >= data.length) break;
        out.add(i);
        i += 1 + data[i];
        continue;
      }
      final spec = _objects[id];
      if (spec == null) break;
      i += spec.$1;
    }
    return out;
  }

  /// Returns the decoded objects as id -> list of values (an id can repeat),
  /// or null if this is not an unencrypted BTHome v2 payload.
  static Map<int, List<double>>? decode(Uint8List data) {
    if (data.isEmpty) return null;
    final info = data[0];
    final encrypted = info & 0x01 != 0;
    final version = (info >> 5) & 0x07;
    if (version != 2 || encrypted) return null;

    final out = <int, List<double>>{};
    var i = 1;
    while (i < data.length) {
      final id = data[i++];
      if (id == 0x53 || id == 0x54) {
        if (i >= data.length) break;
        i += 1 + data[i];
        continue;
      }
      final spec = _objects[id];
      if (spec == null) break; // unknown object: we can't know its length
      final (len, signed, factor) = spec;
      if (i + len > data.length) break;
      var v = 0;
      for (var k = len - 1; k >= 0; k--) {
        v = (v << 8) | data[i + k];
      }
      if (signed && v & (1 << (len * 8 - 1)) != 0) v -= 1 << (len * 8);
      out.putIfAbsent(id, () => []).add(v * factor);
      i += len;
    }
    return out;
  }
}
