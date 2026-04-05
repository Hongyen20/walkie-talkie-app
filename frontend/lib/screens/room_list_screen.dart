import 'package:flutter/material.dart';
import '../models/user.dart';

class RoomListScreen extends StatelessWidget {
  final User user;
  const RoomListScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Hello, ${user.displayName}',
          style: const TextStyle(color: Color(0xFF39FF14)),
        ),
      ),
      body: const Center(
        child: Text(
          'Room List — Coming soon',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}