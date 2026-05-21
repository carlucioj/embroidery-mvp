import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/server_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved preferences
  final prefs = await SharedPreferences.getInstance();

  // Load server URL configuration
  await ServerConfig.load();

  runApp(EmbroideryApp(prefs: prefs));
}
