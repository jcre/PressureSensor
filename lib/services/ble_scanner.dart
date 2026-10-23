import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../ble/adv_packet.dart';

/// Owns the BLE scanner. The tags only *broadcast* their readings, so there is
/// no connection: we just listen to every advertisement.
///
/// Two modes:
///  * discovery – unfiltered scan, used by the "Find sensor" and inspector
///    screens;
///  * monitoring – scan filtered to the active sensor's id. Android keeps
///    filtered scans running with the screen off; unfiltered ones get paused.
class BleScanner extends ChangeNotifier {
  final _packets = StreamController<AdvPacket>.broadcast();

  /// Every advertisement received, from any device.
  Stream<AdvPacket> get packets => _packets.stream;

  /// Latest advertisement per device (for the device list).
  final Map<String, AdvPacket> seen = {};

  BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;
  bool scanning = false;
  String? error;

  String? _monitoredId;
  int _discoveryUsers = 0;
  bool _started = false;
  StreamSubscription<List<ScanResult>>? _resultsSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  Timer? _restartTimer;
  Timer? _notifyTimer;
  DateTime _lastPacket = DateTime.fromMillisecondsSinceEpoch(0);

  bool get discovering => _discoveryUsers > 0;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (!await FlutterBluePlus.isSupported) {
      error = 'Bluetooth LE is not supported on this device';
      notifyListeners();
      return;
    }
    FlutterBluePlus.setLogLevel(LogLevel.warning, color: false);
    _resultsSub = FlutterBluePlus.onScanResults.listen(_onResults, onError: (Object e) {
      error = 'Scan error: $e';
      notifyListeners();
    });
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      adapterState = s;
      notifyListeners();
      if (s == BluetoothAdapterState.on) _restart();
    });
    // Android stops scans that run for more than 30 minutes, and some phones
    // silently stall them, so restart periodically and if data dries up.
    _restartTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final quiet = DateTime.now().difference(_lastPacket);
      if (_shouldScan && (quiet > const Duration(seconds: 30) || _scanAge > const Duration(minutes: 10))) {
        _restart();
      }
    });
  }

  DateTime _scanStarted = DateTime.now();
  Duration get _scanAge => DateTime.now().difference(_scanStarted);

  bool get _shouldScan => discovering || _monitoredId != null;

  /// Sets the sensor to follow in monitoring mode (null = none).
  void monitor(String? deviceId) {
    if (_monitoredId == deviceId) return;
    _monitoredId = deviceId;
    _restart();
  }

  void beginDiscovery() {
    _discoveryUsers++;
    if (_discoveryUsers == 1) {
      seen.clear();
      _restart();
    }
  }

  void endDiscovery() {
    if (_discoveryUsers == 0) return;
    _discoveryUsers--;
    if (_discoveryUsers == 0) _restart();
  }

  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final denied = statuses.entries.where((e) => !e.value.isGranted && !e.value.isLimited).map((e) => e.key);
    // BLUETOOTH_SCAN/CONNECT don't exist before Android 12 and report as denied
    // there; location is what matters on old versions.
    if (denied.contains(Permission.locationWhenInUse) && denied.contains(Permission.bluetoothScan)) {
      error = 'Bluetooth/location permission is needed to read the sensor';
      notifyListeners();
      return false;
    }
    return true;
  }

  bool _restarting = false;
  bool _restartPending = false;

  Future<void> _restart() async {
    if (!_started) return;
    if (_restarting) {
      _restartPending = true;
      return;
    }
    _restarting = true;
    try {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
      if (!_shouldScan || adapterState != BluetoothAdapterState.on) {
        scanning = false;
        notifyListeners();
        return;
      }
      if (!await ensurePermissions()) return;
      await FlutterBluePlus.startScan(
        withRemoteIds: discovering || _monitoredId == null ? const [] : [_monitoredId!],
        continuousUpdates: true,
        oneByOne: true,
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: true,
      );
      _scanStarted = DateTime.now();
      _lastPacket = DateTime.now(); // grace period before the stall check
      scanning = true;
      error = null;
    } catch (e) {
      scanning = false;
      error = 'Could not start scan: $e';
    } finally {
      _restarting = false;
      notifyListeners();
      if (_restartPending) {
        _restartPending = false;
        _restart();
      }
    }
  }

  void _onResults(List<ScanResult> results) {
    for (final r in results) {
      final ad = r.advertisementData;
      final id = r.device.remoteId.str;
      final name = ad.advName.isNotEmpty ? ad.advName : r.device.platformName;
      final packet = AdvPacket(
        deviceId: id,
        name: name,
        rssi: r.rssi,
        time: r.timeStamp,
        serviceData: {for (final e in ad.serviceData.entries) e.key.str128: e.value},
        manufacturerData: ad.manufacturerData,
        serviceUuids: [for (final u in ad.serviceUuids) AdvPacket.normalizeUuid(u.str128)],
        txPower: ad.txPowerLevel,
        connectable: ad.connectable,
      );
      _deliver(packet);
    }
  }

  /// Feeds a packet in as if it had been received (used by demo mode).
  void inject(AdvPacket packet) => _deliver(packet);

  void _deliver(AdvPacket packet) {
    _lastPacket = DateTime.now();
    seen[packet.deviceId] = packet;
    _packets.add(packet);
    // Device lists don't need to redraw on every packet.
    _notifyTimer ??= Timer(const Duration(milliseconds: 300), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  Future<void> turnOnBluetooth() async {
    if (Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _resultsSub?.cancel();
    _adapterSub?.cancel();
    _restartTimer?.cancel();
    _notifyTimer?.cancel();
    _packets.close();
    super.dispose();
  }
}
