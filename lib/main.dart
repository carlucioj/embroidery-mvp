import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'application/workflow/workflow_persistence.dart';
import 'core/server_config.dart';
import 'infrastructure/python/engine_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  await ServerConfig.load();

  // Launch Python engine in background (Windows Desktop — installed build only).
  // No-op in dev mode (no engine.exe) and on mobile platforms.
  // The HTTP client's retry logic handles transient unavailability during startup.
  EngineLauncher.start(); // fire-and-forget

  // Restore last session from disk (null if no session or restore fails)
  final persistence = WorkflowPersistence(prefs: prefs);
  final initialState = await persistence.loadWorkflowState();

  runApp(EmbroideryApp(prefs: prefs, initialWorkflowState: initialState));
}
