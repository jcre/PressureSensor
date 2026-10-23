import 'package:xml/xml.dart';

import '../models/trip.dart';
import '../models/units.dart';

const gpxPressureNs = 'https://github.com/jcre/PressureSensor/gpx/v1';

class Gpx {
  /// GPX 1.1 track with the raft's gauge pressure at each point, interpolated
  /// from the sensor readings, in a custom extension:
  ///   `<extensions><rp:gauge_hpa>…</rp:gauge_hpa><rp:gauge unit="psi">…</rp:gauge></extensions>`
  static String export(Trip trip, List<TrackPoint> track, List<Reading> readings, PressureUnit unit) {
    final b = XmlBuilder();
    b.processing('xml', 'version="1.0" encoding="UTF-8"');
    b.element('gpx', nest: () {
      b.attribute('version', '1.1');
      b.attribute('creator', 'Raft Pressure');
      b.attribute('xmlns', 'http://www.topografix.com/GPX/1/1');
      b.attribute('xmlns:rp', gpxPressureNs);
      b.element('metadata', nest: () {
        b.element('name', nest: trip.name);
        b.element('time', nest: trip.startedAt.toUtc().toIso8601String());
      });
      b.element('trk', nest: () {
        b.element('name', nest: trip.name);
        if (trip.notes.isNotEmpty) b.element('desc', nest: trip.notes);
        b.element('trkseg', nest: () {
          for (final p in track) {
            b.element('trkpt', nest: () {
              b.attribute('lat', p.lat.toStringAsFixed(7));
              b.attribute('lon', p.lon.toStringAsFixed(7));
              if (p.elevation != null) b.element('ele', nest: p.elevation!.toStringAsFixed(1));
              b.element('time', nest: p.time.toUtc().toIso8601String());
              final g = gaugeAt(readings, p.time);
              if (g != null) {
                b.element('extensions', nest: () {
                  b.element('rp:gauge_hpa', nest: g.toStringAsFixed(2));
                  b.element('rp:gauge', nest: () {
                    b.attribute('unit', unit.label);
                    b.text(unit.fromHpa(g).toStringAsFixed(unit.decimals + 1));
                  });
                });
              }
            });
          }
        });
      });
    });
    return b.buildDocument().toXmlString(pretty: true);
  }

  /// Reads track points (trkpt, falling back to rtept/wpt) from any GPX file,
  /// e.g. one recorded on a watch, so it can be overlaid with pressure.
  static List<TrackPoint> parse(String xml) {
    final doc = XmlDocument.parse(xml);
    Iterable<XmlElement> pts = doc.findAllElements('trkpt');
    if (pts.isEmpty) pts = doc.findAllElements('rtept');
    if (pts.isEmpty) pts = doc.findAllElements('wpt');
    final out = <TrackPoint>[];
    for (final e in pts) {
      final lat = double.tryParse(e.getAttribute('lat') ?? '');
      final lon = double.tryParse(e.getAttribute('lon') ?? '');
      final timeStr = e.getElement('time')?.innerText;
      final time = timeStr == null ? null : DateTime.tryParse(timeStr.trim());
      if (lat == null || lon == null || time == null) continue;
      out.add(TrackPoint(
        time: time.toLocal(),
        lat: lat,
        lon: lon,
        elevation: double.tryParse(e.getElement('ele')?.innerText.trim() ?? ''),
      ));
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  static String readingsCsv(List<Reading> readings, PressureUnit unit) {
    final sb = StringBuffer('time_iso,abs_hpa,gauge_hpa,gauge_${unit.label},temp_c,battery_pct,rssi\n');
    for (final r in readings) {
      sb.writeln([
        r.time.toUtc().toIso8601String(),
        r.absHpa.toStringAsFixed(2),
        r.gaugeHpa.toStringAsFixed(2),
        unit.fromHpa(r.gaugeHpa).toStringAsFixed(unit.decimals + 1),
        r.temperatureC?.toStringAsFixed(2) ?? '',
        r.batteryPct?.toStringAsFixed(0) ?? '',
        r.rssi?.toString() ?? '',
      ].join(','));
    }
    return sb.toString();
  }
}
