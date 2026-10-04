import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/cleaning/cleaning_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = CleaningController()..init();
  runApp(UltrasonicApp(controller: controller));
}
