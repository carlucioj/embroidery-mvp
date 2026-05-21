import 'package:embroidery_mvp/domain/models/workflow_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkflowStep', () {
    group('linear progression', () {
      test('onboarding advances to imageCapture', () {
        expect(WorkflowStep.onboarding.next, WorkflowStep.imageCapture);
      });

      test('imageCapture advances to imageCleaning', () {
        expect(WorkflowStep.imageCapture.next, WorkflowStep.imageCleaning);
      });

      test('imageCleaning advances to parameters', () {
        expect(WorkflowStep.imageCleaning.next, WorkflowStep.parameters);
      });

      test('parameters advances to generation', () {
        expect(WorkflowStep.parameters.next, WorkflowStep.generation);
      });

      test('generation advances to export', () {
        expect(WorkflowStep.generation.next, WorkflowStep.export);
      });

      test('export has no next step', () {
        expect(WorkflowStep.export.next, isNull);
      });
    });

    group('back navigation', () {
      test('onboarding has no previous step', () {
        expect(WorkflowStep.onboarding.previous, isNull);
      });

      test('imageCapture has no previous step (first main step)', () {
        expect(WorkflowStep.imageCapture.previous, isNull);
      });

      test('imageCleaning goes back to imageCapture', () {
        expect(WorkflowStep.imageCleaning.previous, WorkflowStep.imageCapture);
      });

      test('parameters goes back to imageCleaning', () {
        expect(WorkflowStep.parameters.previous, WorkflowStep.imageCleaning);
      });

      test('generation goes back to parameters', () {
        expect(WorkflowStep.generation.previous, WorkflowStep.parameters);
      });

      test('export goes back to generation', () {
        expect(WorkflowStep.export.previous, WorkflowStep.generation);
      });
    });

    group('canGoBack', () {
      test('onboarding cannot go back', () {
        expect(WorkflowStep.onboarding.canGoBack, isFalse);
      });

      test('imageCapture cannot go back', () {
        expect(WorkflowStep.imageCapture.canGoBack, isFalse);
      });

      test('imageCleaning can go back', () {
        expect(WorkflowStep.imageCleaning.canGoBack, isTrue);
      });

      test('parameters can go back', () {
        expect(WorkflowStep.parameters.canGoBack, isTrue);
      });

      test('generation can go back', () {
        expect(WorkflowStep.generation.canGoBack, isTrue);
      });

      test('export can go back', () {
        expect(WorkflowStep.export.canGoBack, isTrue);
      });
    });

    group('step numbers', () {
      test('onboarding has no step number', () {
        expect(WorkflowStep.onboarding.stepNumber, isNull);
      });

      test('imageCapture is step 1', () {
        expect(WorkflowStep.imageCapture.stepNumber, 1);
      });

      test('export is step 5', () {
        expect(WorkflowStep.export.stepNumber, 5);
      });
    });

    group('labels', () {
      test('all steps have non-empty labels', () {
        for (final step in WorkflowStep.values) {
          expect(step.label, isNotEmpty);
        }
      });
    });
  });
}
