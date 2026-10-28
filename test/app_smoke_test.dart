import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:raft_pressure/main.dart';
import 'package:raft_pressure/models/trip.dart';
import 'package:raft_pressure/services/alert_service.dart';
import 'package:raft_pressure/services/barometer_service.dart';
import 'package:raft_pressure/services/ble_scanner.dart';
import 'package:raft_pressure/services/database.dart';
import 'package:raft_pressure/services/demo.dart';
import 'package:raft_pressure/services/live_monitor.dart';
import 'package:raft_pressure/services/settings_store.dart';
import 'package:raft_pressure/services/trip_recorder.dart';
import 'package:raft_pressure/ui/trip_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Drives the real screens in demo mode. Set SCREENSHOT_DIR to also save PNGs
/// of each screen (with real fonts), handy for checking layouts without a phone.
void main() {
  final shotDir = Platform.environment['SCREENSHOT_DIR'];
  final shotKey = GlobalKey();

  setUpAll(() async {
    // Plugins that don't exist in the test VM.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in ['vibration']) {
      messenger.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async => Directory.systemTemp.path);
    messenger.setMockMessageHandler('dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage(<Object?>[]));
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await _loadFonts();
  });

  Future<void> shot(WidgetTester tester, String name) async {
    if (shotDir == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$shotDir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('demo mode drives the live view, alerts, inspector and trip screens', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    late SettingsStore settings;
    late TripDatabase db;
    await tester.runAsync(() async {
      settings = await SettingsStore.load();
      db = await TripDatabase.open(path: inMemoryDatabasePath);
    });
    settings.keepScreenOn = false; // no wakelock plugin in tests
    final scanner = BleScanner();
    final barometer = BarometerService()..hpa = 1010.4;
    final alerts = AlertService();
    final monitor = LiveMonitor(scanner: scanner, settings: settings, barometer: barometer, alerts: alerts);
    final recorder = TripRecorder(db: db, monitor: monitor, settings: settings);
    final demo = DemoController(settings: settings, scanner: scanner, barometer: barometer);
    await tester.runAsync(() => demo.setEnabled(true));

    // Four minutes of simulated history: zero, inflate, start paddling.
    final now = DateTime.now();
    const history = 240;
    for (var t = 0; t <= history; t++) {
      scanner.inject(DemoSimulation.packet(Duration(seconds: t), now.subtract(Duration(seconds: history - t))));
    }
    demo.restart(at: const Duration(seconds: history));

    await tester.pumpWidget(RepaintBoundary(
      key: shotKey,
      child: MultiProvider(
        providers: [
          Provider.value(value: db),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: scanner),
          ChangeNotifierProvider.value(value: barometer),
          ChangeNotifierProvider.value(value: alerts),
          ChangeNotifierProvider.value(value: monitor),
          ChangeNotifierProvider.value(value: recorder),
          ChangeNotifierProvider.value(value: demo),
        ],
        child: const RaftPressureApp(),
      ),
    ));
    await settle(tester);

    expect(find.text('Live'), findsOneWidget);
    expect(find.textContaining('Demo mode'), findsOneWidget);
    expect(monitor.latest!.gaugeHpa, greaterThan(90));
    await shot(tester, '1_home');

    // Alerts
    await tester.tap(find.byTooltip('Alerts'));
    await settle(tester);
    expect(find.text('Fully inflated (high)'), findsOneWidget);
    await shot(tester, '2_alerts');
    await tester.pageBack();
    await settle(tester);

    // Inspector
    await tester.tap(find.text('Inspector'));
    await settle(tester);
    expect(find.text('Service 0xfcd2  (10 bytes)'), findsOneWidget);
    await shot(tester, '3_inspector');
    await tester.pageBack();
    await settle(tester);

    // Settings
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    expect(find.text('Units'), findsOneWidget);
    await shot(tester, '4_settings');
    await tester.pageBack();
    await settle(tester);

    // A finished trip with a pressure-coloured track.
    late int tripId;
    await tester.runAsync(() async {
      final t0 = DateTime.now().subtract(const Duration(minutes: 20));
      final trip = await db.insertTrip(Trip(name: 'Demo paddle', startedAt: t0, endedAt: t0.add(const Duration(minutes: 20))));
      tripId = trip.id!;
      final readings = <Reading>[];
      final points = <TrackPoint>[];
      for (var t = 0; t <= 1200; t += 2) {
        final at = t0.add(Duration(seconds: t));
        final g = DemoSimulation.gaugeHpa(Duration(seconds: t));
        readings.add(Reading(
            time: at,
            absHpa: DemoSimulation.ambientHpa + g,
            gaugeHpa: g,
            temperatureC: DemoSimulation.temperatureC(Duration(seconds: t))));
        if (t >= 70) points.add(DemoSimulation.position(Duration(seconds: t - 70), at));
      }
      await db.insertReadings(tripId, readings);
      await db.insertTrackPoints(tripId, points);
    });
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(builder: (_) => TripDetailScreen(tripId: tripId)));
    await settle(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await settle(tester);
    expect(find.text('Demo paddle'), findsOneWidget);
    expect(find.text('Distance'), findsOneWidget);
    await shot(tester, '5_trip');

    await tester.pumpWidget(const SizedBox());
    demo.dispose();
    alerts.dispose();
    recorder.dispose();
    monitor.dispose();
    scanner.dispose();
  });
}

Future<void> _loadFonts() async {
  final root = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  if (!Directory(root).existsSync()) return;
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = await File('$root/$f').readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  await load('monospace', ['Roboto-Medium.ttf']);
}
