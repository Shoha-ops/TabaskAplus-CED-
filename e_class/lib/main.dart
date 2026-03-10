import 'package:e_class/main_screen.dart';
import 'package:e_class/screens/authenticate.dart';
import 'package:e_class/services/auth_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // 1. Храним текущий цвет здесь
  Color _themeColor = Colors.deepPurple;

  // 2. Функция для смены цвета
  void _changeTheme(Color color) {
    setState(() {
      _themeColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamProvider<User?>.value(
      value: AuthService().user,
      initialData: null,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'e-Class',
        // 3. Подставляем цвет в тему
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _themeColor),
          useMaterial3: true,
        ),
        // 4. Используем Wrapper для выбора экрана
        home: Wrapper(onColorChange: _changeTheme),
      ),
    );
  }
}

class Wrapper extends StatelessWidget {
  final Function(Color) onColorChange;
  const Wrapper({super.key, required this.onColorChange});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);

    // return either Home (MainScreen) or Authenticate widget
    if (user == null) {
      return const Authenticate();
    } else {
      return MainScreen(onColorChange: onColorChange);
    }
  }
}
