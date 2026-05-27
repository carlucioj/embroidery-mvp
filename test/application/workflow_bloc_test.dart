import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:embroidery_mvp/application/workflow/workflow_bloc.dart';
import 'package:embroidery_mvp/application/workflow/workflow_persistence.dart';
import 'package:embroidery_mvp/domain/models/image_data.dart';
import 'package:embroidery_mvp/domain/models/workflow_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// No-op persistence — prevents real disk I/O during unit tests.
class _FakePersistence extends WorkflowPersistence {
  int saveCount = 0;
  int clearCount = 0;

  @override
  void scheduleSave(WorkflowBlocState state) => saveCount++;

  @override
  Future<void> saveWorkflowState(WorkflowBlocState state) async => saveCount++;

  @override
  Future<void> clearWorkflowState() async => clearCount++;
}

void main() {
  group('WorkflowBloc', () {
    late WorkflowBloc bloc;
    late _FakePersistence fakePersistence;

    setUp(() {
      fakePersistence = _FakePersistence();
      bloc = WorkflowBloc(persistence: fakePersistence);
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is imageCapture step', () {
      expect(bloc.state.currentStep, WorkflowStep.imageCapture);
      expect(bloc.state.capturedImage, isNull);
      expect(bloc.state.validationErrors, isEmpty);
    });

    group('WorkflowImageCaptured', () {
      final testImage = ImageData(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'test.jpg',
        extension: 'jpg',
        sizeBytes: 3,
      );

      blocTest<WorkflowBloc, WorkflowBlocState>(
        'stores captured image',
        build: () => WorkflowBloc(persistence: _FakePersistence()),
        act: (bloc) => bloc.add(WorkflowImageCaptured(testImage)),
        expect: () => [
          predicate<WorkflowBlocState>(
            (s) => s.capturedImage == testImage,
          ),
        ],
      );

      blocTest<WorkflowBloc, WorkflowBlocState>(
        'clears downstream data when new image is captured',
        build: () => WorkflowBloc(persistence: _FakePersistence()),
        seed: () => WorkflowBlocState(
          currentStep: WorkflowStep.imageCleaning,
          onboardingCompleted: false,
          stateHistory: const [],
          validationErrors: const [],
          cleanedImage: ProcessedImage(
            bytes: Uint8List(0),
            colorCount: 3,
            processingDurationMs: 100,
          ),
        ),
        act: (bloc) => bloc.add(WorkflowImageCaptured(testImage)),
        expect: () => [
          predicate<WorkflowBlocState>(
            (s) => s.capturedImage == testImage && s.cleanedImage == null,
          ),
        ],
      );
    });

    group('WorkflowAdvanceRequested', () {
      blocTest<WorkflowBloc, WorkflowBlocState>(
        'shows validation error when advancing without image',
        build: () => WorkflowBloc(persistence: _FakePersistence()),
        act: (bloc) => bloc.add(const WorkflowAdvanceRequested()),
        expect: () => [
          predicate<WorkflowBlocState>(
            (s) =>
                s.currentStep == WorkflowStep.imageCapture &&
                s.validationErrors.isNotEmpty,
          ),
        ],
      );

      blocTest<WorkflowBloc, WorkflowBlocState>(
        'advances to imageCleaning when image is captured',
        build: () => WorkflowBloc(persistence: _FakePersistence()),
        seed: () => WorkflowBlocState(
          currentStep: WorkflowStep.imageCapture,
          onboardingCompleted: false,
          stateHistory: const [],
          validationErrors: const [],
          capturedImage: ImageData(
            bytes: Uint8List.fromList([1, 2, 3]),
            filename: 'test.jpg',
            extension: 'jpg',
            sizeBytes: 3,
          ),
        ),
        act: (bloc) => bloc.add(const WorkflowAdvanceRequested()),
        expect: () => [
          predicate<WorkflowBlocState>(
            (s) => s.currentStep == WorkflowStep.imageCleaning,
          ),
        ],
      );
    });

    group('WorkflowGoBackRequested', () {
      blocTest<WorkflowBloc, WorkflowBlocState>(
        'goes back to imageCapture from imageCleaning',
        build: () => WorkflowBloc(persistence: _FakePersistence()),
        seed: () => const WorkflowBlocState(
          currentStep: WorkflowStep.imageCleaning,
          onboardingCompleted: false,
          stateHistory: [WorkflowStep.imageCapture],
          validationErrors: [],
        ),
        act: (bloc) => bloc.add(const WorkflowGoBackRequested()),
        expect: () => [
          predicate<WorkflowBlocState>(
            (s) => s.currentStep == WorkflowStep.imageCapture,
          ),
        ],
      );

      blocTest<WorkflowBloc, WorkflowBlocState>(
        'does nothing when already at imageCapture',
        build: () => WorkflowBloc(persistence: _FakePersistence()),
        act: (bloc) => bloc.add(const WorkflowGoBackRequested()),
        expect: () => <WorkflowBlocState>[],
      );
    });

    group('WorkflowReset', () {
      test('calls clearWorkflowState on persistence', () async {
        bloc.add(const WorkflowReset());
        await Future<void>.delayed(Duration.zero); // let async clear run
        expect(fakePersistence.clearCount, 1);
      });

      blocTest<WorkflowBloc, WorkflowBlocState>(
        'resets to initial state',
        build: () => WorkflowBloc(persistence: _FakePersistence()),
        seed: () => WorkflowBlocState(
          currentStep: WorkflowStep.generation,
          onboardingCompleted: true,
          stateHistory: const [
            WorkflowStep.imageCapture,
            WorkflowStep.imageCleaning,
            WorkflowStep.parameters,
          ],
          validationErrors: const [],
          capturedImage: ImageData(
            bytes: Uint8List.fromList([1, 2, 3]),
            filename: 'test.jpg',
            extension: 'jpg',
            sizeBytes: 3,
          ),
        ),
        act: (bloc) => bloc.add(const WorkflowReset()),
        expect: () => [
          predicate<WorkflowBlocState>(
            (s) =>
                s.currentStep == WorkflowStep.imageCapture &&
                s.capturedImage == null &&
                s.stateHistory.isEmpty,
          ),
        ],
      );
    });

    group('WorkflowOnboardingCompleted', () {
      blocTest<WorkflowBloc, WorkflowBlocState>(
        'marks onboarding as completed and advances to imageCapture',
        build: () => WorkflowBloc(persistence: _FakePersistence()),
        seed: () => const WorkflowBlocState(
          currentStep: WorkflowStep.onboarding,
          onboardingCompleted: false,
          stateHistory: [],
          validationErrors: [],
        ),
        act: (bloc) => bloc.add(const WorkflowOnboardingCompleted()),
        expect: () => [
          predicate<WorkflowBlocState>(
            (s) =>
                s.currentStep == WorkflowStep.imageCapture &&
                s.onboardingCompleted == true,
          ),
        ],
      );
    });

    group('isStepComplete', () {
      test('imageCapture is complete when image is captured', () {
        final state = WorkflowBlocState(
          currentStep: WorkflowStep.imageCapture,
          onboardingCompleted: false,
          stateHistory: const [],
          validationErrors: const [],
          capturedImage: ImageData(
            bytes: Uint8List.fromList([1, 2, 3]),
            filename: 'test.jpg',
            extension: 'jpg',
            sizeBytes: 3,
          ),
        );
        expect(state.isStepComplete(WorkflowStep.imageCapture), isTrue);
      });

      test('imageCapture is not complete without image', () {
        expect(
          bloc.state.isStepComplete(WorkflowStep.imageCapture),
          isFalse,
        );
      });
    });
  });
}
