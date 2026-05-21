/// Represents the possible states in the embroidery workflow.
///
/// The workflow follows a strict linear progression:
/// Onboarding → ImageCapture → ImageCleaning → Parameters → Generation → Export
enum WorkflowStep {
  /// First-run onboarding guide (max 5 screens)
  onboarding,

  /// Step 1: Capture or import an image
  imageCapture,

  /// Step 2: Clean the image (remove background, reduce colors)
  imageCleaning,

  /// Step 3: Configure embroidery parameters (hoop, fabric, size, format)
  parameters,

  /// Step 4: Generate stitch paths and preview
  generation,

  /// Step 5: Export the embroidery file
  export,
}

extension WorkflowStepExtension on WorkflowStep {
  /// Human-readable label for this step
  String get label {
    switch (this) {
      case WorkflowStep.onboarding:
        return 'Introdução';
      case WorkflowStep.imageCapture:
        return 'Importar Imagem';
      case WorkflowStep.imageCleaning:
        return 'Limpar Arte';
      case WorkflowStep.parameters:
        return 'Parâmetros';
      case WorkflowStep.generation:
        return 'Gerar Bordado';
      case WorkflowStep.export:
        return 'Exportar';
    }
  }

  /// Step number (1-based) for display, null for onboarding
  int? get stepNumber {
    switch (this) {
      case WorkflowStep.onboarding:
        return null;
      case WorkflowStep.imageCapture:
        return 1;
      case WorkflowStep.imageCleaning:
        return 2;
      case WorkflowStep.parameters:
        return 3;
      case WorkflowStep.generation:
        return 4;
      case WorkflowStep.export:
        return 5;
    }
  }

  /// Returns the next step in the workflow, or null if this is the last step
  WorkflowStep? get next {
    switch (this) {
      case WorkflowStep.onboarding:
        return WorkflowStep.imageCapture;
      case WorkflowStep.imageCapture:
        return WorkflowStep.imageCleaning;
      case WorkflowStep.imageCleaning:
        return WorkflowStep.parameters;
      case WorkflowStep.parameters:
        return WorkflowStep.generation;
      case WorkflowStep.generation:
        return WorkflowStep.export;
      case WorkflowStep.export:
        return null;
    }
  }

  /// Returns the previous step in the workflow, or null if this is the first step
  WorkflowStep? get previous {
    switch (this) {
      case WorkflowStep.onboarding:
        return null;
      case WorkflowStep.imageCapture:
        return null; // Cannot go back from first step
      case WorkflowStep.imageCleaning:
        return WorkflowStep.imageCapture;
      case WorkflowStep.parameters:
        return WorkflowStep.imageCleaning;
      case WorkflowStep.generation:
        return WorkflowStep.parameters;
      case WorkflowStep.export:
        return WorkflowStep.generation;
    }
  }

  /// Whether this step can be navigated back from
  bool get canGoBack => previous != null;

  /// Whether this step is part of the main workflow (not onboarding)
  bool get isMainWorkflow => this != WorkflowStep.onboarding;
}
