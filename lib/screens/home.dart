import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'dart:convert';

// Model to store WiFi fingerprint data for a location in a room
class WifiFingerprint {
  final String roomName;
  final String locationName; // e.g., "corner1", "center"
  final Map<String, int> signalStrengths; // BSSID -> RSSI

  WifiFingerprint({
    required this.roomName,
    required this.locationName,
    required this.signalStrengths,
  });

  Map<String, dynamic> toJson() => {
    'roomName': roomName,
    'locationName': locationName,
    'signalStrengths': signalStrengths,
  };

  factory WifiFingerprint.fromJson(Map<String, dynamic> json) {
    return WifiFingerprint(
      roomName: json['roomName'],
      locationName: json['locationName'],
      signalStrengths: Map<String, int>.from(json['signalStrengths']),
    );
  }
}

class RoomDetector extends StatefulWidget {
  const RoomDetector({Key? key}) : super(key: key);

  @override
  State<RoomDetector> createState() => _RoomDetectorState();
}

class _RoomDetectorState extends State<RoomDetector> {
  List<WifiFingerprint> _fingerprints = [];
  Set<String> _rooms = {};
  String? _currentRoom;
  bool _isCalibrating = false;
  String _calibrationLocation = 'corner1';
  String? _selectedRoom;
  final _roomController = TextEditingController();
  StreamSubscription<List<WiFiAccessPoint>>? _wifiScanSubscription;
  final _locations = ['corner1', 'corner2', 'corner3', 'corner4', 'center'];

  @override
  void initState() {
    super.initState();
    _loadFingerprints();
    _startWifiScanning();
  }

  @override
  void dispose() {
    _wifiScanSubscription?.cancel();
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _loadFingerprints() async {
    final prefs = await SharedPreferences.getInstance();
    final fingerprintsJson = prefs.getStringList('fingerprints') ?? [];

    setState(() {
      _fingerprints = fingerprintsJson
          .map((json) => WifiFingerprint.fromJson(jsonDecode(json)))
          .toList();
      _rooms = _fingerprints.map((f) => f.roomName).toSet();
    });
  }

  Future<void> _saveFingerprints() async {
    final prefs = await SharedPreferences.getInstance();
    final fingerprintsJson = _fingerprints
        .map((f) => jsonEncode(f.toJson()))
        .toList();
    await prefs.setStringList('fingerprints', fingerprintsJson);
  }

  void _startWifiScanning() {
    _wifiScanSubscription = Stream.periodic(const Duration(seconds: 1))
        .asyncMap((_) => _performScan())
        .listen(_processWifiResults);
  }

  Future<List<WiFiAccessPoint>> _performScan() async {
    await WiFiScan.instance.startScan();
    return await WiFiScan.instance.getScannedResults();
  }

  void _processWifiResults(List<WiFiAccessPoint> accessPoints) {
    if (!_isCalibrating) {
      _detectRoom(accessPoints);
    }
  }

  void _startCalibration(String roomName) {
    setState(() {
      _selectedRoom = roomName;
      _isCalibrating = true;
      _calibrationLocation = 'corner1';
    });
  }

  Future<void> _calibrateLocation(List<WiFiAccessPoint> accessPoints) async {
    if (_selectedRoom == null) return;

    // Create fingerprint for current location
    final fingerprint = WifiFingerprint(
      roomName: _selectedRoom!,
      locationName: _calibrationLocation,
      signalStrengths: Map.fromEntries(
        accessPoints.map((ap) => MapEntry(ap.bssid, ap.level)),
      ),
    );

    // Remove old fingerprint for this location if it exists
    _fingerprints.removeWhere((f) =>
    f.roomName == _selectedRoom && f.locationName == _calibrationLocation);

    setState(() {
      _fingerprints.add(fingerprint);
      _rooms.add(_selectedRoom!);
    });

    await _saveFingerprints();

    // Move to next location or finish calibration
    final currentIndex = _locations.indexOf(_calibrationLocation);
    if (currentIndex < _locations.length - 1) {
      setState(() {
        _calibrationLocation = _locations[currentIndex + 1];
      });
    } else {
      setState(() {
        _isCalibrating = false;
        _selectedRoom = null;
      });
    }
  }

  void _detectRoom(List<WiFiAccessPoint> accessPoints) {
    if (_fingerprints.isEmpty) return;

    print('Scanning and checking matrix...');

    final currentSignals = Map.fromEntries(
      accessPoints.map((ap) => MapEntry(ap.bssid, ap.level)),
    );

    for (final room in _rooms) {
      final roomFingerprints = _fingerprints.where((f) => f.roomName == room);

      // Initialize min and max values for each BSSID
      Map<String, int> minSignals = {};
      Map<String, int> maxSignals = {};

      for (final fingerprint in roomFingerprints) {
        fingerprint.signalStrengths.forEach((bssid, strength) {
          if (!minSignals.containsKey(bssid) || strength < minSignals[bssid]!) {
            minSignals[bssid] = strength;
          }
          if (!maxSignals.containsKey(bssid) || strength > maxSignals[bssid]!) {
            maxSignals[bssid] = strength;
          }
        });
      }

      // Check if current signals fall within min-max range
      bool isInsideMatrix = true;
      for (var bssid in currentSignals.keys) {
        if (minSignals.containsKey(bssid) &&
            maxSignals.containsKey(bssid) &&
            (currentSignals[bssid]! < minSignals[bssid]! ||
                currentSignals[bssid]! > maxSignals[bssid]!)) {
          isInsideMatrix = false;
          break;
        }
      }

      if (isInsideMatrix) {
        setState(() {
          _currentRoom = room;
        });
        return;
      }
    }

    // If no match is found, set room as unknown
    setState(() {
      _currentRoom = "Unknown";
    });
  }

  Future<void> _deleteRoom(String roomName) async {
    setState(() {
      _fingerprints.removeWhere((f) => f.roomName == roomName);
      _rooms.remove(roomName);
      if (_currentRoom == roomName) _currentRoom = null;
    });
    await _saveFingerprints();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room Detector'),
      ),
      body: Column(
        children: [
          // Current room display
          Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: Text(
              'Current Room: ${_currentRoom ?? "Unknown"}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),

          // Calibration status
          if (_isCalibrating)
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Calibrating ${_selectedRoom}: $_calibrationLocation'),
                  ElevatedButton(
                    onPressed: ()async => _calibrateLocation(await _performScan()),
                    child: const Text('Capture Location'),
                  ),
                ],
              ),
            ),

          // Room list
          Expanded(
            child: ListView.builder(
              itemCount: _rooms.length,
              itemBuilder: (context, index) {
                final room = _rooms.elementAt(index);
                return ListTile(
                  title: Text(room),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () => _startCalibration(room),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteRoom(room),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Add New Room'),
              content: TextField(
                controller: _roomController,
                decoration: const InputDecoration(labelText: 'Room Name'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (_roomController.text.isNotEmpty) {
                      _startCalibration(_roomController.text);
                      _roomController.clear();
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}