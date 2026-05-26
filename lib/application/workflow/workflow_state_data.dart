import 'package:equatable/equatable.dart';

import '../../domain/models/embroidery_design.dart';
import '../../domain/models/embroidery_parameters.dart';
import '../../domain/models/image_data.dart';
import '../../domain/models/workflow_state.dart';

/// Immutable state for the workflow BLoC.
///
/// Holds all data accumulated through the workflow steps.
class WorkflowBlocState extends Equatable {
  const WorkflowBlocState({
    required this.currentStep,
    required this.onboardingCompleted,
    required this.stateHistory,
    required this.validationErrors,
    this.capturedImage,
    this.cleanedImage,
    this.parameters,
    this.generatedDesign,
    this.exportedFilePath,
  });

  /// Creates the initial state for a new workflow session
  const WorkflowBlocState.initial()
      : currentStep = WorkflowStep.imageCapture,
        onboardingCompleted = false,
        stateHistory = const [],
        validationErrors = const [],
        capturedImage = null,
        cleanedImage = null,
        parameters = null,
        generatedDesign = null,
        exportedFilePath = null;

  /// Current step in the workflow
  final WorkflowStep currentStep;

  /// Whether the onboarding guide has been completed
  final bool onboardingCompleted;

  /// History of visited steps (for back navigation)
  final List<WorkflowStep> stateHistory;

  /// Current validation errors (empty if valid)
  final List<String> validationErrors;

  /// Image captured/imported in step 1
  final ImageData? capturedImage;

  /// Processed image from step 2
  final ProcessedImage? cleanedImage;

  /// Embroidery parameters from step 3
  final EmbroideryParameters? parameters;

  /// Generated embroidery design from step 4
  final EmbroideryDesign? generatedDesign;

  /// Path of the exported file from step 5
  final String? exportedFilePath;

  /// Whether the current step has validation errors
  bool get hasErrors => validationErrors.isNotEmpty;

  /// Whether the given step has been completed
  bool isStepComplete(WorkflowStep step) {
    switch (step) {
      case WorkflowStep.onboarding:
        return onboardingCompleted;
      case WorkflowStep.imageCapture:
        return capturedImage != null;
      case WorkflowStep.imageCleaning:
        return cleanedImage != null;
      case WorkflowStep.parameters:
        return parameters != null && parameters!.validate().isEmpty;
      case WorkflowStep.generation:
        return generatedDesign != null;
      case WorkflowStep.export:
        return exportedFilePath != null;
    }
  }

  // Sentinel object used to distinguish "not provided" from explicit null
  static const _absent = Object();

  WorkflowBlocState copyWith({
    WorkflowStep? currentStep,
    bool? onboardingCompleted,
    List<WorkflowStep>? stateHistory,
    List<String>? validationErrors,
    Object? capturedImage = _absent,
    Object? cleanedImage = _absent,
    Object? parameters = _absent,
    Object? generatedDesign = _absent,
    Object? exportedFilePath = _absent,
  }) {
    return WorkflowBlocState(
      currentStep: currentStep ?? this.currentStep,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      stateHistory: stateHistory ?? this.stateHistory,
      validationErrors: validationErrors ?? this.validationErrors,
      capturedImage: identical(capturedImage, _absent)
          ? this.capturedImage
          : capturedImage as ImageData?,
      cleanedImage: identical(cleanedImage, _absent)
          ? this.cleanedImage
          : cleanedImage as ProcessedImage?,
      parameters: identical(parameters, _absent)
          ? this.parameters
          : parameters as EmbroideryParameters?,
      generatedDesign: identical(generatedDesign, _absent)
          ? this.generatedDesign
          : generatedDesign as EmbroideryDesign?,
      exportedFilePath: identical(exportedFilePath, _absent)
          ? this.exportedFilePath
          : exportedFilePath as String?,
    );
  }

  @override
  List<Object?> get props => [
        currentStep,
        onboardingCompleted,
        stateHistory,
        validationErrors,
        capturedImage,
        cleanedImage,
        parameters,
        generatedDesign,
        exportedFilePath,
      ];
}
