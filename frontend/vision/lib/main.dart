import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const ContextAidApp());
}

class ContextAidApp extends StatelessWidget {
  const ContextAidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ContextAid',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}