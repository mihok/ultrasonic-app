import 'package:flutter/material.dart';

import 'cleaning/cleaning_controller.dart';
import 'ui/home_page.dart';

class UltrasonicApp extends StatelessWidget {
  const UltrasonicApp({super.key, required this.controller});

  final CleaningController controller;

  static const _seed = Color(0xFF00ACC1);

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Ultrasonic',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seed)),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.dark,
      ),
    ),
    home: HomePage(controller: controller),
  );
}
