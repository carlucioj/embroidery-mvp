import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/workflow/workflow_bloc.dart';
import '../../domain/models/workflow_state.dart';
import '../controllers/adaptive_ui_controller.dart';

/// Adaptive scaffold that shows sidebar navigation on Desktop
/// and bottom tab navigation on Mobile.
///
/// Automatically adapts based on screen width:
/// - ≥ 1024px: sidebar with step labels
/// - < 1024px: bottom navigation bar with icons
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    required this.child,
    super.key,
  });

  final Widget child;

  static const _uiController = AdaptiveUIController();

  @override
  Widget build(BuildContext context) {
    final style = _uiController.getNavigationStyle(context);

    return BlocBuilder<WorkflowBloc, WorkflowBlocState>(
      builder: (context, state) {
        if (style == NavigationStyle.sidebarDesktop) {
          return _DesktopScaffold(state: state, child: child);
        } else {
          return _MobileScaffold(state: state, child: child);
        }
      },
    );
  }
}

/// Desktop layout with fixed sidebar navigation
class _DesktopScaffold extends StatelessWidget {
  const _DesktopScaffold({required this.state, required this.child});

  final WorkflowBlocState state;
  final Widget child;

  static const _uiController = AdaptiveUIController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = _uiController.navigationSteps;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 220,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App logo/title
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Embroidery\nMVP',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const Divider(),
                // Step list
                ...steps.map((step) => _SidebarItem(
                      step: step,
                      isActive: state.currentStep == step,
                      isCompleted: state.isStepComplete(step),
                    )),
                const Spacer(),
                // Feedback button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    onPressed: () => _showFeedbackDialog(context),
                    icon: const Icon(Icons.feedback_outlined, size: 18),
                    label: const Text('Enviar Feedback'),
                  ),
                ),
              ],
            ),
          ),
          // Main content
          Expanded(child: child),
        ],
      ),
    );
  }

  void _showFeedbackDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _FeedbackDialog(),
    );
  }
}

/// Mobile layout with bottom navigation bar
class _MobileScaffold extends StatelessWidget {
  const _MobileScaffold({required this.state, required this.child});

  final WorkflowBlocState state;
  final Widget child;

  static const _uiController = AdaptiveUIController();

  @override
  Widget build(BuildContext context) {
    final steps = _uiController.navigationSteps;
    final currentIndex = steps.indexOf(state.currentStep).clamp(0, steps.length - 1);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (_) {
          // Navigation is controlled by the workflow BLoC — tapping
          // a step only works if the user has already reached it.
        },
        destinations: steps.map((step) {
          final isCompleted = state.isStepComplete(step);
          return NavigationDestination(
            icon: Icon(
              isCompleted
                  ? Icons.check_circle_outline
                  : _uiController.getStepIcon(step),
            ),
            selectedIcon: Icon(_uiController.getStepIconActive(step)),
            label: step.label,
            tooltip: step.label,
          );
        }).toList(),
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _FeedbackDialog(),
        ),
        tooltip: 'Enviar Feedback',
        child: const Icon(Icons.feedback_outlined),
      ),
    );
  }
}

/// Sidebar navigation item for Desktop
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.step,
    required this.isActive,
    required this.isCompleted,
  });

  final WorkflowStep step;
  final bool isActive;
  final bool isCompleted;

  static const _uiController = AdaptiveUIController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isActive
        ? theme.colorScheme.primary
        : isCompleted
            ? theme.colorScheme.secondary
            : theme.colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: isActive
          ? BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: ListTile(
        dense: true,
        leading: Icon(
          isCompleted
              ? Icons.check_circle
              : isActive
                  ? _uiController.getStepIconActive(step)
                  : _uiController.getStepIcon(step),
          color: color,
          size: 20,
        ),
        title: Text(
          step.label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: step.stepNumber != null
            ? Text(
                'Passo ${step.stepNumber}',
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              )
            : null,
      ),
    );
  }
}

/// Simple feedback dialog
class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _controller = TextEditingController();
  int _rating = 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enviar Feedback'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Como foi sua experiência?'),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              return IconButton(
                icon: Icon(
                  star <= _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                onPressed: () => setState(() => _rating = star),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Descreva o problema ou sugestão...',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            // TODO: submit feedback via FeedbackController
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Obrigado pelo seu feedback!'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
