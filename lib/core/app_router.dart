import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../presentation/screens/export_screen.dart';
import '../presentation/screens/generation_screen.dart';
import '../presentation/screens/image_capture_screen.dart';
import '../presentation/screens/image_cleaning_screen.dart';
import '../presentation/screens/onboarding_screen.dart';
import '../presentation/screens/parameters_screen.dart';
import '../presentation/widgets/adaptive_scaffold.dart';

/// Application route names
class AppRoutes {
  AppRoutes._();

  static const String onboarding = '/onboarding';
  static const String imageCapture = '/';
  static const String imageCleaning = '/cleaning';
  static const String parameters = '/parameters';
  static const String generation = '/generation';
  static const String export = '/export';
}

/// Application router — simple static routes.
/// Each screen drives its own navigation via WorkflowBloc events.
class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.imageCapture,
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.imageCapture,
        name: 'imageCapture',
        builder: (context, state) => const AdaptiveScaffold(
          child: ImageCaptureScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.imageCleaning,
        name: 'imageCleaning',
        builder: (context, state) => const AdaptiveScaffold(
          child: ImageCleaningScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.parameters,
        name: 'parameters',
        builder: (context, state) => const AdaptiveScaffold(
          child: ParametersScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.generation,
        name: 'generation',
        builder: (context, state) => const AdaptiveScaffold(
          child: GenerationScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.export,
        name: 'export',
        builder: (context, state) => const AdaptiveScaffold(
          child: ExportScreen(),
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Página não encontrada',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.imageCapture),
              child: const Text('Voltar ao início'),
            ),
          ],
        ),
      ),
    ),
  );
}
