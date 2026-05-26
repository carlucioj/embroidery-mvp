import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/models/embroidery_design.dart';
import '../../domain/models/embroidery_parameters.dart';
import '../../domain/models/image_data.dart';
import '../../domain/models/workflow_state.dart';
import 'workflow_persistence.dart';
import 'workflow_state_data.dart';

// Re-export so all consumers of workflow_bloc.dart get WorkflowBlocState
// without needing a separate import.
export 'workflow_state_data.dart';

part 'workflow_event.dart';

/// BLoC that manages the embroidery workflow state machine.
///
/// Enforces linear progression through workflow steps and preserves state
/// when navigating backwards. All state changes are persisted to disk via
/// [WorkflowPersistence] so sessions survive app restarts.
class WorkflowBloc extends Bloc<WorkflowEvent, WorkflowBlocState> {
  WorkflowBloc({
    WorkflowBlocState? initialState,
    WorkflowPersistence? persistence,
  })  : _persistence = persistence ?? WorkflowPersistence(),
        super(initialState ?? const WorkflowBlocState.initial()) {
    on<WorkflowAdvanceRequested>(_onAdvanceRequested);
    on<WorkflowGoBackRequested>(_onGoBackRequested);
    on<WorkflowImageCaptured>(_onImageCaptured);
    on<WorkflowImageCleaned>(_onImageCleaned);
    on<WorkflowParametersSet>(_onParametersSet);
    on<WorkflowDesignGenerated>(_onDesignGenerated);
    on<WorkflowExportCompleted>(_onExportCompleted);
    on<WorkflowReset>(_onReset);
    on<WorkflowOnboardingCompleted>(_onOnboardingCompleted);
  }

  final WorkflowPersistence _persistence;

  @override
  void onChange(Change<WorkflowBlocState> change) {
    super.onChange(change);
    // Debounced fire-and-forget: keeps session in sync without blocking UI
    _persistence.scheduleSave(change.nextState);
  }

  void _onAdvanceRequested(
    WorkflowAdvanceRequested event,
    Emitter<WorkflowBlocState> emit,
  ) {
    final currentStep = state.currentStep;
    final nextStep = currentStep.next;

    if (nextStep == null) return; // Already at last step

    // Validate current step before advancing
    final errors = _validateStep(currentStep, state);
    if (errors.isNotEmpty) {
      emit(state.copyWith(validationErrors: errors));
      return;
    }

    emit(state.copyWith(
      currentStep: nextStep,
      validationErrors: [],
      stateHistory: [...state.stateHistory, currentStep],
    ));
  }

  void _onGoBackRequested(
    WorkflowGoBackRequested event,
    Emitter<WorkflowBlocState> emit,
  ) {
    final previousStep = state.currentStep.previous;
    if (previousStep == null) return; // Already at first step

    final newHistory = List<WorkflowStep>.from(state.stateHistory);
    if (newHistory.isNotEmpty) newHistory.removeLast();

    emit(state.copyWith(
      currentStep: previousStep,
      validationErrors: [],
      stateHistory: newHistory,
    ));
  }

  void _onImageCaptured(
    WorkflowImageCaptured event,
    Emitter<WorkflowBlocState> emit,
  ) {
    emit(state.copyWith(
      capturedImage: event.image,
      // Clear downstream data when image changes
      cleanedImage: null,
      parameters: null,
      generatedDesign: null,
    ));
  }

  void _onImageCleaned(
    WorkflowImageCleaned event,
    Emitter<WorkflowBlocState> emit,
  ) {
    emit(state.copyWith(
      cleanedImage: event.processedImage,
      // Clear downstream data when cleaned image changes
      generatedDesign: null,
    ));
  }

  void _onParametersSet(
    WorkflowParametersSet event,
    Emitter<WorkflowBlocState> emit,
  ) {
    emit(state.copyWith(
      parameters: event.parameters,
      // Clear downstream data when parameters change
      generatedDesign: null,
    ));
  }

  void _onDesignGenerated(
    WorkflowDesignGenerated event,
    Emitter<WorkflowBlocState> emit,
  ) {
    emit(state.copyWith(generatedDesign: event.design));
  }

  void _onExportCompleted(
    WorkflowExportCompleted event,
    Emitter<WorkflowBlocState> emit,
  ) {
    emit(state.copyWith(exportedFilePath: event.filePath));
  }

  void _onReset(
    WorkflowReset event,
    Emitter<WorkflowBlocState> emit,
  ) {
    emit(const WorkflowBlocState.initial());
    // Clear persisted session immediately (no debounce — we want instant wipe)
    _persistence.clearWorkflowState().catchError((_) {});
  }

  void _onOnboardingCompleted(
    WorkflowOnboardingCompleted event,
    Emitter<WorkflowBlocState> emit,
  ) {
    emit(state.copyWith(
      currentStep: WorkflowStep.imageCapture,
      onboardingCompleted: true,
    ));
  }

  /// Validate the current step and return a list of error messages.
  List<String> _validateStep(WorkflowStep step, WorkflowBlocState state) {
    switch (step) {
      case WorkflowStep.onboarding:
        return [];
      case WorkflowStep.imageCapture:
        if (state.capturedImage == null) {
          return ['Selecione uma imagem para continuar.'];
        }
        return [];
      case WorkflowStep.imageCleaning:
        if (state.cleanedImage == null) {
          return ['Clique em "Limpar Arte" para processar a imagem.'];
        }
        return [];
      case WorkflowStep.parameters:
        if (state.parameters == null) {
          return ['Configure os parâmetros de bordado para continuar.'];
        }
        return state.parameters!.validate();
      case WorkflowStep.generation:
        if (state.generatedDesign == null) {
          return ['Clique em "Gerar Bordado" para criar o design.'];
        }
        return [];
      case WorkflowStep.export:
        return [];
    }
  }
}
