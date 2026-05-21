import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/workflow/workflow_bloc.dart';
import '../../application/workflow/workflow_persistence.dart';

/// Data for a single onboarding slide
class _OnboardingSlide {
  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
}

/// First-run onboarding screen with up to 5 illustrated slides.
///
/// Shows the complete workflow at a glance so the user knows
/// what to expect before starting. Can be skipped at any time.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _slides = [
    _OnboardingSlide(
      icon: Icons.waving_hand,
      title: 'Bem-vindo ao Embroidery MVP!',
      description:
          'Transforme qualquer imagem em um arquivo de bordado em apenas 5 passos simples. '
          'Sem conhecimento técnico necessário.',
      color: Color(0xFF8B4513),
    ),
    _OnboardingSlide(
      icon: Icons.add_photo_alternate_outlined,
      title: 'Passo 1: Importe sua Arte',
      description:
          'Tire uma foto pelo celular ou importe uma imagem do computador. '
          'Funciona com JPG, PNG e BMP.',
      color: Color(0xFF2E7D32),
    ),
    _OnboardingSlide(
      icon: Icons.auto_fix_high_outlined,
      title: 'Passo 2: Limpe a Arte',
      description:
          'Com um único toque, removemos o fundo e simplificamos as cores '
          'automaticamente para o bordado.',
      color: Color(0xFF1565C0),
    ),
    _OnboardingSlide(
      icon: Icons.tune_outlined,
      title: 'Passo 3: Configure o Bordado',
      description:
          'Escolha o bastidor, o tecido e o tamanho. '
          'Selecione o formato compatível com sua máquina.',
      color: Color(0xFF6A1B9A),
    ),
    _OnboardingSlide(
      icon: Icons.save_alt_outlined,
      title: 'Passo 4 e 5: Visualize e Exporte',
      description:
          'Veja uma prévia dos pontos antes de salvar. '
          'Exporte direto para o pendrive ou dispositivo.',
      color: Color(0xFFE65100),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _skip() => _complete();

  void _next() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _complete();
    }
  }

  Future<void> _complete() async {
    // Persist that onboarding is done
    await WorkflowPersistence().saveOnboardingCompleted();
    if (mounted) {
      context.read<WorkflowBloc>().add(const WorkflowOnboardingCompleted());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = _currentPage == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _skip,
                child: const Text('Pular'),
              ),
            ),

            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return _SlidePage(slide: slide);
                },
              ),
            ),

            // Page indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == i
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 24),

            // Navigation button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(isLast ? 'Começar' : 'Próximo'),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SlidePage extends StatelessWidget {
  const _SlidePage({required this.slide});

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon in a colored circle
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: slide.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              slide.icon,
              size: 56,
              color: slide.color,
            ),
          ),

          const SizedBox(height: 32),

          Text(
            slide.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          Text(
            slide.description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
