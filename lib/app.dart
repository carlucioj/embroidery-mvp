import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'application/workflow/workflow_bloc.dart';
import 'core/app_router.dart';
import 'core/theme.dart';
import 'infrastructure/python/engine_launcher.dart';

/// Root widget of the Embroidery MVP application.
class EmbroideryApp extends StatefulWidget {
  const EmbroideryApp({
    required this.prefs,
    this.initialWorkflowState,
    super.key,
  });

  final SharedPreferences prefs;

  /// Pre-loaded workflow state restored from disk (null → fresh session).
  final WorkflowBlocState? initialWorkflowState;

  @override
  State<EmbroideryApp> createState() => _EmbroideryAppState();
}

class _EmbroideryAppState extends State<EmbroideryApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // Kill the Python engine when the app is fully closed.
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.detached) {
          EngineLauncher.stop();
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => WorkflowBloc(initialState: widget.initialWorkflowState),
      child: MaterialApp.router(
        title: 'Embroidery MVP',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        routerConfig: AppRouter.router,
      ),
    );
  }
}
