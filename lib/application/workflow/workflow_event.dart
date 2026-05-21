part of 'workflow_bloc.dart';

/// Base class for all workflow events
abstract class WorkflowEvent extends Equatable {
  const WorkflowEvent();

  @override
  List<Object?> get props => [];
}

/// Request to advance to the next workflow step
class WorkflowAdvanceRequested extends WorkflowEvent {
  const WorkflowAdvanceRequested();
}

/// Request to go back to the previous workflow step
class WorkflowGoBackRequested extends WorkflowEvent {
  const WorkflowGoBackRequested();
}

/// An image was captured or imported
class WorkflowImageCaptured extends WorkflowEvent {
  const WorkflowImageCaptured(this.image);

  final ImageData image;

  @override
  List<Object?> get props => [image];
}

/// An image was cleaned (background removed, colors reduced)
class WorkflowImageCleaned extends WorkflowEvent {
  const WorkflowImageCleaned(this.processedImage);

  final ProcessedImage processedImage;

  @override
  List<Object?> get props => [processedImage];
}

/// Embroidery parameters were configured
class WorkflowParametersSet extends WorkflowEvent {
  const WorkflowParametersSet(this.parameters);

  final EmbroideryParameters parameters;

  @override
  List<Object?> get props => [parameters];
}

/// An embroidery design was generated
class WorkflowDesignGenerated extends WorkflowEvent {
  const WorkflowDesignGenerated(this.design);

  final EmbroideryDesign design;

  @override
  List<Object?> get props => [design];
}

/// Export was completed successfully
class WorkflowExportCompleted extends WorkflowEvent {
  const WorkflowExportCompleted(this.filePath);

  final String filePath;

  @override
  List<Object?> get props => [filePath];
}

/// Reset the entire workflow to initial state
class WorkflowReset extends WorkflowEvent {
  const WorkflowReset();
}

/// Onboarding was completed or skipped
class WorkflowOnboardingCompleted extends WorkflowEvent {
  const WorkflowOnboardingCompleted();
}
