import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'application/workflow/workflow_bloc.dart';
import 'core/app_router.dart';
import 'core/theme.dart';

/// Root widget of the Embroidery MVP application.
class EmbroideryApp extends StatelessWidget {
  const EmbroideryApp({
    required this.prefs,
    this.initialWorkflowState,
    super.key,
  });

  final SharedPreferences prefs;

  /// Pre-loaded workflow state restored from disk (null → fresh session).
  final WorkflowBlocState? initialWorkflowState;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => WorkflowBloc(initialState: initialWorkflowState),
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
