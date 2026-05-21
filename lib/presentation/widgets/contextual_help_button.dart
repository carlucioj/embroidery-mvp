import 'package:flutter/material.dart';

import '../../domain/models/workflow_state.dart';
import '../controllers/adaptive_ui_controller.dart';

/// A small "?" button that shows contextual help for the current workflow step.
///
/// Displays a tooltip/dialog with a short description (max 3 lines)
/// explaining what the user should do in this step.
class ContextualHelpButton extends StatelessWidget {
  const ContextualHelpButton({
    required this.step,
    super.key,
  });

  final WorkflowStep step;

  static const _uiController = AdaptiveUIController();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.help_outline, size: 20),
      tooltip: 'Ajuda',
      onPressed: () => _showHelp(context),
    );
  }

  void _showHelp(BuildContext context) {
    final help = _uiController.getContextualHelp(step);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.help_outline),
        title: Text(help.title),
        content: Text(
          help.description,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }
}

/// A progress indicator widget with a descriptive stage label.
///
/// Used during image processing and embroidery generation to give
/// the user clear feedback on what is happening.
class ProcessingProgressIndicator extends StatelessWidget {
  const ProcessingProgressIndicator({
    required this.progress,
    required this.stage,
    super.key,
  });

  /// Progress value from 0.0 to 1.0
  final double progress;

  /// Human-readable description of the current stage
  final String stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(
          value: progress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 8),
        Text(
          stage,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// A validation error banner shown below form fields.
class ValidationErrorBanner extends StatelessWidget {
  const ValidationErrorBanner({
    required this.errors,
    super.key,
  });

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    if (errors.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: errors
            .map(
              (e) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

/// A success confirmation widget shown after completing a step.
class StepSuccessConfirmation extends StatelessWidget {
  const StepSuccessConfirmation({
    required this.message,
    super.key,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Navigation buttons (Back / Next) used at the bottom of each step screen.
class StepNavigationButtons extends StatelessWidget {
  const StepNavigationButtons({
    required this.onNext,
    this.onBack,
    this.nextLabel = 'Continuar',
    this.nextEnabled = true,
    this.isLoading = false,
    super.key,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextLabel;
  final bool nextEnabled;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (onBack != null) ...[
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Voltar'),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton(
              onPressed: nextEnabled && !isLoading ? onNext : null,
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(nextLabel),
            ),
          ),
        ],
      ),
    );
  }
}
