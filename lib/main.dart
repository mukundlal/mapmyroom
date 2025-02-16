import 'package:flutter/material.dart';
import 'package:mapmyroom/screens/home.dart';

void main() {
  runApp(const MapMyRoomApp());
}
class MapMyRoomApp extends StatelessWidget {
  const MapMyRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: RoomDetector());
  }
}
