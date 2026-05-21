import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../application/workflow/workflow_bloc.dart';
import '../../core/app_router.dart';
import '../../domain/models/workflow_state.dart';

/// Listens to WorkflowBloc state changes and navigates to the correct screen.
///
/// Wrap this around the MaterialApp.router child to enable automatic
/// navigation driven by the BLoC state machine.
class WorkflowNavigator extends StatelessWidget {
  const WorkflowNavigator({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<WorkflowBloc, WorkflowBlocState>(
      listenWhen: (prev, curr) => prev.currentStep != curr.currentStep,
      listener: (context, state) {
        final path = _pathForStep(state.currentStep);
        try {
          context.go(path);
        } catch (_) {
          // Router not ready yet — ignore
        }
      },
      child: child,
    );
  }

  static String _pathForStep(WorkflowStep step) {
    switch (step) {
      case WorkflowStep.onboarding:
        return AppRoutes.onboarding;
      case WorkflowStep.imageCapture:
        return AppRoutes.imageCapture;
      case WorkflowStep.imageCleaning:
        return AppRoutes.imageCleaning;
      case WorkflowStep.parameters:
        return AppRoutes.parameters;
      case WorkflowStep.generation:
        return AppRoutes.generation;
      case WorkflowStep.export:
        return AppRoutes.export;
    }
  }
}
