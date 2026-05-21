import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../domain/models/workflow_state.dart';

/// Navigation style based on screen size
enum NavigationStyle {
  /// Sidebar navigation for Desktop (≥ 1024px)
  sidebarDesktop,

  /// Bottom tabs navigation for Mobile (< 1024px)
  bottomTabsMobile,
}

/// Platform type detected at runtime
enum PlatformType {
  desktop,
  mobile,
}

/// Contextual help text for each workflow step
class ContextualHelp {
  const ContextualHelp({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
}

/// Controller that manages adaptive UI behavior based on platform and screen size.
///
/// Determines navigation style, layout configuration, and provides
/// contextual help for each workflow step.
class AdaptiveUIController {
  const AdaptiveUIController();

  /// Determine the navigation style based on screen width.
  NavigationStyle getNavigationStyle(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= LayoutBreakpoints.desktopMinWidth
        ? NavigationStyle.sidebarDesktop
        : NavigationStyle.bottomTabsMobile;
  }

  /// Determine the platform type.
  PlatformType getPlatformType(BuildContext context) {
    final style = getNavigationStyle(context);
    return style == NavigationStyle.sidebarDesktop
        ? PlatformType.desktop
        : PlatformType.mobile;
  }

  /// Get contextual help for the given workflow step.
  ContextualHelp getContextualHelp(WorkflowStep step) {
    switch (step) {
      case WorkflowStep.onboarding:
        return const ContextualHelp(
          title: 'Bem-vindo!',
          description: 'Siga os passos para criar seu bordado.',
        );
      case WorkflowStep.imageCapture:
        return const ContextualHelp(
          title: 'Passo 1: Importar Imagem',
          description: 'Selecione uma foto ou imagem do seu computador ou celular. '
              'Formatos aceitos: JPG, PNG, BMP.',
        );
      case WorkflowStep.imageCleaning:
        return const ContextualHelp(
          title: 'Passo 2: Limpar Arte',
          description: 'Clique em "Limpar Arte" para remover o fundo e '
              'simplificar as cores automaticamente.',
        );
      case WorkflowStep.parameters:
        return const ContextualHelp(
          title: 'Passo 3: Configurar Parâmetros',
          description: 'Escolha o bastidor, tecido, tamanho e formato '
              'de arquivo para sua máquina de bordado.',
        );
      case WorkflowStep.generation:
        return const ContextualHelp(
          title: 'Passo 4: Gerar Bordado',
          description: 'Clique em "Gerar Bordado" para criar os caminhos '
              'de pontos. Você verá uma prévia antes de exportar.',
        );
      case WorkflowStep.export:
        return const ContextualHelp(
          title: 'Passo 5: Exportar',
          description: 'Salve o arquivo no seu pendrive ou dispositivo '
              'para usar na máquina de bordado.',
        );
    }
  }

  /// Get the list of workflow steps to show in navigation (excluding onboarding).
  List<WorkflowStep> get navigationSteps => [
        WorkflowStep.imageCapture,
        WorkflowStep.imageCleaning,
        WorkflowStep.parameters,
        WorkflowStep.generation,
        WorkflowStep.export,
      ];

  /// Get the icon for a workflow step.
  IconData getStepIcon(WorkflowStep step) {
    switch (step) {
      case WorkflowStep.onboarding:
        return Icons.info_outline;
      case WorkflowStep.imageCapture:
        return Icons.add_photo_alternate_outlined;
      case WorkflowStep.imageCleaning:
        return Icons.auto_fix_high_outlined;
      case WorkflowStep.parameters:
        return Icons.tune_outlined;
      case WorkflowStep.generation:
        return Icons.preview_outlined;
      case WorkflowStep.export:
        return Icons.save_alt_outlined;
    }
  }

  /// Get the active icon for a workflow step.
  IconData getStepIconActive(WorkflowStep step) {
    switch (step) {
      case WorkflowStep.onboarding:
        return Icons.info;
      case WorkflowStep.imageCapture:
        return Icons.add_photo_alternate;
      case WorkflowStep.imageCleaning:
        return Icons.auto_fix_high;
      case WorkflowStep.parameters:
        return Icons.tune;
      case WorkflowStep.generation:
        return Icons.preview;
      case WorkflowStep.export:
        return Icons.save_alt;
    }
  }
}
