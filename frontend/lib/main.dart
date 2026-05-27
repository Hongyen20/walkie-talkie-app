import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/room_list_screen.dart';
import 'models/user.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final saved = await StorageService.loadUser();

  runApp(MyApp(initialUser: saved));
}

class MyApp extends StatelessWidget {
  final Map<String, String>? initialUser;

  const MyApp({super.key, this.initialUser});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Walkie Talkie',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: initialUser != null
          ? RoomListScreen(
              user: User(
                id: initialUser!['user_id']!,
                token: initialUser!['token']!,
                username: initialUser!['username']!,
                displayName: initialUser!['display_name']!,
                inviteCode: initialUser!['invite_code']!,
              ),
            )
          : const LoginScreen(),
    );
  }
}
