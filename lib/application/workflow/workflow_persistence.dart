import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../domain/models/embroidery_design.dart';
import '../../domain/models/embroidery_parameters.dart';
import '../../domain/models/image_data.dart';
import '../../domain/models/workflow_state.dart';
import 'workflow_state_data.dart'; // standalone (not a part file)

/// Handles full persistence of the workflow session across app restarts.
///
/// Lightweight data (step, parameters) is stored in SharedPreferences as JSON.
/// Binary data (image bytes, embroidery file) is stored as files in the app's
/// documents directory under `embroidery_session/`.
///
/// Saves are debounced at 500ms to prevent redundant writes when the user
/// is rapidly changing fields (e.g. typing dimensions).
class WorkflowPersistence {
  WorkflowPersistence({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;
  Timer? _saveDebounce;

  static const _sessionDirName = 'embroidery_session';
  static const _capturedFile = 'captured.bin';
  static const _cleanedFile = 'cleaned.bin';
  static const _designBinFile = 'design.bin';
  static const _designJsonFile = 'design.json';

  // ── Public save/load/clear ─────────────────────────────────────────────────

  /// Schedule a debounced save (500ms). Safe to call on every state change.
  void scheduleSave(WorkflowBlocState state) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      saveWorkflowState(state).catchError((_) {});
    });
  }

  /// Persist the full workflow state immediately.
  Future<void> saveWorkflowState(WorkflowBlocState state) async {
    try {
      final prefs = await _getPrefs();

      await prefs.setBool(PrefsKeys.workflowHasSession, true);
      await prefs.setString(
          PrefsKeys.workflowCurrentStep, state.currentStep.name);

      // Captured image
      if (state.capturedImage != null) {
        await prefs.setString(
          PrefsKeys.workflowCapturedMeta,
          jsonEncode(state.capturedImage!.toJson()),
        );
        await _writeFile(_capturedFile, state.capturedImage!.bytes);
      } else {
        await prefs.remove(PrefsKeys.workflowCapturedMeta);
        await _deleteFile(_capturedFile);
      }

      // Cleaned image
      if (state.cleanedImage != null) {
        await prefs.setString(
          PrefsKeys.workflowCleanedMeta,
          jsonEncode(state.cleanedImage!.toJson()),
        );
        await _writeFile(_cleanedFile, state.cleanedImage!.bytes);
      } else {
        await prefs.remove(PrefsKeys.workflowCleanedMeta);
        await _deleteFile(_cleanedFile);
      }

      // Parameters
      if (state.parameters != null) {
        await prefs.setString(
          PrefsKeys.workflowParameters,
          jsonEncode(state.parameters!.toJson()),
        );
      } else {
        await prefs.remove(PrefsKeys.workflowParameters);
      }

      // Generated design
      if (state.generatedDesign != null) {
        final design = state.generatedDesign!;
        await _writeTextFile(_designJsonFile, design.toJsonString());
        if (design.fileBytes != null) {
          await _writeFile(_designBinFile, design.fileBytes!);
        }
      } else {
        await _deleteFile(_designJsonFile);
        await _deleteFile(_designBinFile);
      }
    } catch (e) {
      // Persistence failures are non-fatal — log and continue
      // ignore: avoid_print
      print('[WorkflowPersistence] save failed: $e');
    }
  }

  /// Restore the last saved session. Returns null if no session exists
  /// or if the saved data is incomplete/corrupt.
  Future<WorkflowBlocState?> loadWorkflowState() async {
    try {
      final prefs = await _getPrefs();
      if (!(prefs.getBool(PrefsKeys.workflowHasSession) ?? false)) return null;

      final stepName = prefs.getString(PrefsKeys.workflowCurrentStep);
      final currentStep = WorkflowStep.values.firstWhere(
        (s) => s.name == stepName,
        orElse: () => WorkflowStep.imageCapture,
      );

      final capturedImage = await _restoreCapturedImage(prefs);
      final cleanedImage = await _restoreCleanedImage(prefs);
      final parameters = _restoreParameters(prefs);
      final generatedDesign = await _restoreDesign();

      return WorkflowBlocState(
        currentStep: currentStep,
        onboardingCompleted:
            prefs.getBool(PrefsKeys.onboardingCompleted) ?? false,
        stateHistory: const [],
        validationErrors: const [],
        capturedImage: capturedImage,
        cleanedImage: cleanedImage,
        parameters: parameters,
        generatedDesign: generatedDesign,
      );
    } catch (e) {
      // Corrupt session: start fresh rather than crash
      // ignore: avoid_print
      print('[WorkflowPersistence] load failed (starting fresh): $e');
      return null;
    }
  }

  /// Delete all session data (called on WorkflowReset).
  Future<void> clearWorkflowState() async {
    _saveDebounce?.cancel();
    try {
      final prefs = await _getPrefs();
      for (final key in [
        PrefsKeys.workflowHasSession,
        PrefsKeys.workflowCurrentStep,
        PrefsKeys.workflowCapturedMeta,
        PrefsKeys.workflowCleanedMeta,
        PrefsKeys.workflowParameters,
      ]) {
        await prefs.remove(key);
      }
      for (final name in [
        _capturedFile,
        _cleanedFile,
        _designBinFile,
        _designJsonFile,
      ]) {
        await _deleteFile(name);
      }
    } catch (_) {}
  }

  // ── Existing lightweight prefs ─────────────────────────────────────────────

  Future<void> saveOnboardingCompleted() async {
    final prefs = await _getPrefs();
    await prefs.setBool(PrefsKeys.onboardingCompleted, true);
  }

  Future<bool> isOnboardingCompleted() async {
    final prefs = await _getPrefs();
    return prefs.getBool(PrefsKeys.onboardingCompleted) ?? false;
  }

  Future<void> saveLastOutputFormat(String formatExtension) async {
    final prefs = await _getPrefs();
    await prefs.setString(PrefsKeys.lastOutputFormat, formatExtension);
  }

  Future<String?> getLastOutputFormat() async {
    final prefs = await _getPrefs();
    return prefs.getString(PrefsKeys.lastOutputFormat);
  }

  Future<void> saveLastHoopSize(String hoopId) async {
    final prefs = await _getPrefs();
    await prefs.setString(PrefsKeys.lastHoopSize, hoopId);
  }

  Future<String?> getLastHoopSize() async {
    final prefs = await _getPrefs();
    return prefs.getString(PrefsKeys.lastHoopSize);
  }

  Future<void> savePendingFeedback(Map<String, dynamic> feedback) async {
    final prefs = await _getPrefs();
    final existing = prefs.getStringList(PrefsKeys.pendingFeedback) ?? [];
    existing.add(jsonEncode(feedback));
    await prefs.setStringList(PrefsKeys.pendingFeedback, existing);
  }

  Future<List<Map<String, dynamic>>> getPendingFeedback() async {
    final prefs = await _getPrefs();
    final jsonList = prefs.getStringList(PrefsKeys.pendingFeedback) ?? [];
    return jsonList
        .map((s) => jsonDecode(s) as Map<String, dynamic>)
        .toList();
  }

  Future<void> clearPendingFeedback() async {
    final prefs = await _getPrefs();
    await prefs.remove(PrefsKeys.pendingFeedback);
  }

  Future<WorkflowStep> getInitialStep() async {
    final onboardingDone = await isOnboardingCompleted();
    if (!onboardingDone) return WorkflowStep.onboarding;
    return WorkflowStep.imageCapture;
  }

  // ── Restore helpers ────────────────────────────────────────────────────────

  Future<ImageData?> _restoreCapturedImage(SharedPreferences prefs) async {
    final metaJson = prefs.getString(PrefsKeys.workflowCapturedMeta);
    if (metaJson == null) return null;
    final bytes = await _readFile(_capturedFile);
    if (bytes == null) return null;
    final meta = jsonDecode(metaJson) as Map<String, dynamic>;
    return ImageData(
      bytes: bytes,
      filename: meta['filename'] as String,
      extension: meta['extension'] as String,
      sizeBytes: meta['sizeBytes'] as int,
      widthPx: meta['widthPx'] as int?,
      heightPx: meta['heightPx'] as int?,
    );
  }

  Future<ProcessedImage?> _restoreCleanedImage(SharedPreferences prefs) async {
    final metaJson = prefs.getString(PrefsKeys.workflowCleanedMeta);
    if (metaJson == null) return null;
    final bytes = await _readFile(_cleanedFile);
    if (bytes == null) return null;
    final meta = jsonDecode(metaJson) as Map<String, dynamic>;
    final complexityJson = meta['complexity'] as Map<String, dynamic>?;
    return ProcessedImage(
      bytes: bytes,
      colorCount: meta['colorCount'] as int,
      processingDurationMs: meta['processingDurationMs'] as int,
      dominantColors: (meta['dominantColors'] as List? ?? [])
          .map((c) => c as int)
          .toList(),
      complexity:
          complexityJson != null ? ImageComplexity.fromJson(complexityJson) : null,
    );
  }

  EmbroideryParameters? _restoreParameters(SharedPreferences prefs) {
    final paramsJson = prefs.getString(PrefsKeys.workflowParameters);
    if (paramsJson == null) return null;
    return EmbroideryParameters.fromJson(
        jsonDecode(paramsJson) as Map<String, dynamic>);
  }

  Future<EmbroideryDesign?> _restoreDesign() async {
    final jsonStr = await _readTextFile(_designJsonFile);
    if (jsonStr == null) return null;
    final fileBytes = await _readFile(_designBinFile);
    final base = EmbroideryDesign.fromJsonString(jsonStr);
    // Reconstruct with fileBytes (not included in toJson)
    return EmbroideryDesign(
      id: base.id,
      created: base.created,
      stitchPaths: base.stitchPaths,
      colorChanges: base.colorChanges,
      colors: base.colors,
      metrics: base.metrics,
      validation: base.validation,
      fileBytes: fileBytes,
    );
  }

  // ── File I/O ───────────────────────────────────────────────────────────────

  Future<Directory> _getSessionDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$_sessionDirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _writeFile(String name, Uint8List bytes) async {
    final dir = await _getSessionDir();
    await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
  }

  Future<void> _writeTextFile(String name, String content) async {
    final dir = await _getSessionDir();
    await File('${dir.path}/$name').writeAsString(content, flush: true);
  }

  Future<Uint8List?> _readFile(String name) async {
    final dir = await _getSessionDir();
    final file = File('${dir.path}/$name');
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  }

  Future<String?> _readTextFile(String name) async {
    final dir = await _getSessionDir();
    final file = File('${dir.path}/$name');
    if (!await file.exists()) return null;
    return await file.readAsString();
  }

  Future<void> _deleteFile(String name) async {
    try {
      final dir = await _getSessionDir();
      final file = File('${dir.path}/$name');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();
}
