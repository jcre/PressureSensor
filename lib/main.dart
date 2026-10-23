import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/alert_service.dart';
import 'services/barometer_service.dart';
import 'services/ble_scanner.dart';
import 'services/database.dart';
import 'services/demo.dart';
import 'services/live_monitor.dart';
import 'services/settings_store.dart';
import 'services/trip_recorder.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = await SettingsStore.load();
  final db = await TripDatabase.open();
  await db.closeDanglingTrips();
  final scanner = BleScanner();
  final barometer = BarometerService()..start();
  final alerts = AlertService();
  await alerts.init();
  final monitor = LiveMonitor(scanner: scanner, settings: settings, barometer: barometer, alerts: alerts);
  final recorder = TripRecorder(db: db, monitor: monitor, settings: settings);
  final demo = DemoController(settings: settings, scanner: scanner, barometer: barometer);

  runApp(MultiProvider(
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
  ));

  // Ask for permissions after the first frame so the dialogs have a window.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await scanner.ensurePermissions();
    await alerts.requestPermission();
    await scanner.start();
  });
}

class RaftPressureApp extends StatelessWidget {
  const RaftPressureApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFE8590C); // packraft orange
    return MaterialApp(
      title: 'Raft Pressure',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
