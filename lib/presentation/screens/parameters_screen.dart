import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../application/workflow/workflow_bloc.dart';
import '../../core/app_router.dart';
import '../../core/constants.dart';
import '../../domain/models/embroidery_parameters.dart';
import '../../domain/models/workflow_state.dart';
import '../widgets/contextual_help_button.dart';

/// Step 3: Embroidery parameters screen.
///
/// Lets the user configure:
/// - Hoop size (organized by category)
/// - Fabric type
/// - Design size (with proportional lock)
/// - Output format (organized by manufacturer)
class ParametersScreen extends StatefulWidget {
  const ParametersScreen({super.key});

  @override
  State<ParametersScreen> createState() => _ParametersScreenState();
}

class _ParametersScreenState extends State<ParametersScreen> {
  HoopSize? _selectedHoop;
  FabricType? _selectedFabric;
  EmbroideryFormat? _selectedFormat;

  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  bool _maintainAspectRatio = true;
  bool _widthChanging = false;
  bool _heightChanging = false;

  double? _originalAspectRatio;

  @override
  void initState() {
    super.initState();
    // Load saved preferences
    _loadDefaults();
  }

  void _loadDefaults() {
    // Default to first rectangular hoop and cotton fabric
    _selectedHoop = HoopSizes.rectangular.first;
    _selectedFabric = FabricTypes.cotton;
    _selectedFormat = OutputFormats.all.first;
    _widthController.text = '100';
    _heightController.text = '100';
    _originalAspectRatio = 1.0;
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _onWidthChanged(String value) {
    if (_widthChanging) return;
    final width = double.tryParse(value);
    if (width == null || width <= 0) return;

    if (_maintainAspectRatio && _originalAspectRatio != null) {
      _heightChanging = true;
      final newHeight = width / _originalAspectRatio!;
      _heightController.text = newHeight.toStringAsFixed(1);
      _heightChanging = false;
    }

    _clampToHoop();
  }

  void _onHeightChanged(String value) {
    if (_heightChanging) return;
    final height = double.tryParse(value);
    if (height == null || height <= 0) return;

    if (_maintainAspectRatio && _originalAspectRatio != null) {
      _widthChanging = true;
      final newWidth = height * _originalAspectRatio!;
      _widthController.text = newWidth.toStringAsFixed(1);
      _widthChanging = false;
    }

    _clampToHoop();
  }

  void _clampToHoop() {
    if (_selectedHoop == null) return;
    final w = double.tryParse(_widthController.text) ?? 0;
    final h = double.tryParse(_heightController.text) ?? 0;

    bool clamped = false;
    double newW = w;
    double newH = h;

    if (w > _selectedHoop!.widthMm) {
      newW = _selectedHoop!.widthMm;
      clamped = true;
    }
    if (h > _selectedHoop!.heightMm) {
      newH = _selectedHoop!.heightMm;
      clamped = true;
    }

    if (clamped) {
      setState(() {
        _widthController.text = newW.toStringAsFixed(1);
        _heightController.text = newH.toStringAsFixed(1);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tamanho ajustado para caber no bastidor '
            '(${_selectedHoop!.widthMm.toStringAsFixed(0)} × '
            '${_selectedHoop!.heightMm.toStringAsFixed(0)} mm).',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _fitToHoop() {
    if (_selectedHoop == null) return;
    final w = double.tryParse(_widthController.text) ?? 100;
    final h = double.tryParse(_heightController.text) ?? 100;
    if (w <= 0 || h <= 0) return;

    final aspectRatio = w / h;
    final hoopAspect = _selectedHoop!.widthMm / _selectedHoop!.heightMm;

    double newW, newH;
    if (aspectRatio > hoopAspect) {
      newW = _selectedHoop!.widthMm;
      newH = newW / aspectRatio;
    } else {
      newH = _selectedHoop!.heightMm;
      newW = newH * aspectRatio;
    }

    setState(() {
      _widthController.text = newW.toStringAsFixed(1);
      _heightController.text = newH.toStringAsFixed(1);
    });
  }

  void _applyAndAdvance() {
    if (_selectedHoop == null || _selectedFabric == null || _selectedFormat == null) {
      return;
    }

    final params = EmbroideryParameters(
      hoop: _selectedHoop!,
      fabric: _selectedFabric!,
      designWidthMm: double.tryParse(_widthController.text) ?? 100,
      designHeightMm: double.tryParse(_heightController.text) ?? 100,
      outputFormat: _selectedFormat!,
      maintainAspectRatio: _maintainAspectRatio,
    );

    context.read<WorkflowBloc>()
      ..add(WorkflowParametersSet(params))
      ..add(const WorkflowAdvanceRequested());
    context.go(AppRoutes.generation);
  }

  void _goBack() {
    context.read<WorkflowBloc>().add(const WorkflowGoBackRequested());
    context.go(AppRoutes.imageCleaning);
  }

  bool get _isValid =>
      _selectedHoop != null && _selectedFabric != null && _selectedFormat != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parâmetros de Bordado'),
        actions: const [
          ContextualHelpButton(step: WorkflowStep.parameters),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(
              stepNumber: 3,
              title: 'Configure o Bordado',
              subtitle: 'Escolha o bastidor, tecido, tamanho e formato.',
            ),
            const SizedBox(height: 24),

            // ── Hoop selection ──────────────────────────────────────────
            const _SectionLabel(label: 'Bastidor'),
            const SizedBox(height: 8),
            _HoopSelector(
              selected: _selectedHoop,
              onChanged: (hoop) {
                setState(() => _selectedHoop = hoop);
                _clampToHoop();
              },
            ),

            const SizedBox(height: 20),

            // ── Fabric selection ────────────────────────────────────────
            const _SectionLabel(label: 'Tipo de Tecido'),
            const SizedBox(height: 8),
            _FabricSelector(
              selected: _selectedFabric,
              onChanged: (f) => setState(() => _selectedFabric = f),
            ),

            const SizedBox(height: 20),

            // ── Design size ─────────────────────────────────────────────
            const _SectionLabel(label: 'Tamanho do Design (mm)'),
            const SizedBox(height: 8),
            _SizeControls(
              widthController: _widthController,
              heightController: _heightController,
              maintainAspectRatio: _maintainAspectRatio,
              hoopWidth: _selectedHoop?.widthMm,
              hoopHeight: _selectedHoop?.heightMm,
              onWidthChanged: _onWidthChanged,
              onHeightChanged: _onHeightChanged,
              onToggleAspectRatio: () =>
                  setState(() => _maintainAspectRatio = !_maintainAspectRatio),
              onFitToHoop: _fitToHoop,
            ),

            const SizedBox(height: 20),

            // ── Output format ───────────────────────────────────────────
            const _SectionLabel(label: 'Formato de Saída'),
            const SizedBox(height: 8),
            _FormatSelector(
              selected: _selectedFormat,
              onChanged: (f) => setState(() => _selectedFormat = f),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: StepNavigationButtons(
        onBack: _goBack,
        onNext: _isValid ? _applyAndAdvance : null,
        nextLabel: 'Gerar Bordado',
        nextEnabled: _isValid,
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
  });

  final int stepNumber;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Passo $stepNumber de 5',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _HoopSelector extends StatelessWidget {
  const _HoopSelector({required this.selected, required this.onChanged});

  final HoopSize? selected;
  final ValueChanged<HoopSize> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<HoopSize>(
      initialValue: selected,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      hint: const Text('Selecione o bastidor'),
      items: [
        const DropdownMenuItem(
          enabled: false,
          value: null,
          child: Text('── Redondos ──',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        ...HoopSizes.round.map((h) => DropdownMenuItem(
              value: h,
              child: Text(h.label),
            )),
        const DropdownMenuItem(
          enabled: false,
          value: null,
          child: Text('── Retangulares ──',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        ...HoopSizes.rectangular.map((h) => DropdownMenuItem(
              value: h,
              child: Text(h.label),
            )),
        const DropdownMenuItem(
          enabled: false,
          value: null,
          child: Text('── Especiais ──',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        ...HoopSizes.special.map((h) => DropdownMenuItem(
              value: h,
              child: Text(h.label),
            )),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _FabricSelector extends StatelessWidget {
  const _FabricSelector({required this.selected, required this.onChanged});

  final FabricType? selected;
  final ValueChanged<FabricType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: FabricTypes.all.map((fabric) {
        final isSelected = selected?.id == fabric.id;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: ListTile(
            leading: Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(fabric.label,
                style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(fabric.description),
            onTap: () => onChanged(fabric),
          ),
        );
      }).toList(),
    );
  }
}

class _SizeControls extends StatelessWidget {
  const _SizeControls({
    required this.widthController,
    required this.heightController,
    required this.maintainAspectRatio,
    required this.onWidthChanged,
    required this.onHeightChanged,
    required this.onToggleAspectRatio,
    required this.onFitToHoop,
    this.hoopWidth,
    this.hoopHeight,
  });

  final TextEditingController widthController;
  final TextEditingController heightController;
  final bool maintainAspectRatio;
  final double? hoopWidth;
  final double? hoopHeight;
  final ValueChanged<String> onWidthChanged;
  final ValueChanged<String> onHeightChanged;
  final VoidCallback onToggleAspectRatio;
  final VoidCallback onFitToHoop;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: widthController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Largura (mm)',
                  border: const OutlineInputBorder(),
                  suffixText: hoopWidth != null
                      ? 'máx ${hoopWidth!.toStringAsFixed(0)}'
                      : null,
                ),
                onChanged: onWidthChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: IconButton(
                icon: Icon(
                  maintainAspectRatio ? Icons.lock : Icons.lock_open,
                  color: maintainAspectRatio
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                tooltip: maintainAspectRatio
                    ? 'Proporção travada'
                    : 'Proporção livre',
                onPressed: onToggleAspectRatio,
              ),
            ),
            Expanded(
              child: TextFormField(
                controller: heightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Altura (mm)',
                  border: const OutlineInputBorder(),
                  suffixText: hoopHeight != null
                      ? 'máx ${hoopHeight!.toStringAsFixed(0)}'
                      : null,
                ),
                onChanged: onHeightChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onFitToHoop,
          icon: const Icon(Icons.fit_screen, size: 18),
          label: const Text('Ajustar ao Bastidor'),
        ),
      ],
    );
  }
}

class _FormatSelector extends StatelessWidget {
  const _FormatSelector({required this.selected, required this.onChanged});

  final EmbroideryFormat? selected;
  final ValueChanged<EmbroideryFormat> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<EmbroideryFormat>(
      initialValue: selected,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      hint: const Text('Selecione o formato'),
      items: OutputFormats.all
          .map((f) => DropdownMenuItem(
                value: f,
                child: Text(f.displayName),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
