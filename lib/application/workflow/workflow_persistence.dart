import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../domain/models/workflow_state.dart';

/// Handles persistence of workflow preferences across app sessions.
///
/// Saves and restores lightweight preferences (last format, last hoop,
/// onboarding status). Full workflow state (images, design) is not
/// persisted as it would require too much storage.
class WorkflowPersistence {
  WorkflowPersistence({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;

  /// Save that onboarding has been completed.
  Future<void> saveOnboardingCompleted() async {
    final prefs = await _getPrefs();
    await prefs.setBool(PrefsKeys.onboardingCompleted, true);
  }

  /// Whether onboarding has been completed on this device.
  Future<bool> isOnboardingCompleted() async {
    final prefs = await _getPrefs();
    return prefs.getBool(PrefsKeys.onboardingCompleted) ?? false;
  }

  /// Save the last used output format extension.
  Future<void> saveLastOutputFormat(String formatExtension) async {
    final prefs = await _getPrefs();
    await prefs.setString(PrefsKeys.lastOutputFormat, formatExtension);
  }

  /// Get the last used output format extension, or null if not set.
  Future<String?> getLastOutputFormat() async {
    final prefs = await _getPrefs();
    return prefs.getString(PrefsKeys.lastOutputFormat);
  }

  /// Save the last used hoop size ID.
  Future<void> saveLastHoopSize(String hoopId) async {
    final prefs = await _getPrefs();
    await prefs.setString(PrefsKeys.lastHoopSize, hoopId);
  }

  /// Get the last used hoop size ID, or null if not set.
  Future<String?> getLastHoopSize() async {
    final prefs = await _getPrefs();
    return prefs.getString(PrefsKeys.lastHoopSize);
  }

  /// Save pending feedback for later submission.
  Future<void> savePendingFeedback(Map<String, dynamic> feedback) async {
    final prefs = await _getPrefs();
    final existing = prefs.getStringList(PrefsKeys.pendingFeedback) ?? [];
    existing.add(jsonEncode(feedback));
    await prefs.setStringList(PrefsKeys.pendingFeedback, existing);
  }

  /// Get all pending feedback items.
  Future<List<Map<String, dynamic>>> getPendingFeedback() async {
    final prefs = await _getPrefs();
    final jsonList = prefs.getStringList(PrefsKeys.pendingFeedback) ?? [];
    return jsonList
        .map((s) => jsonDecode(s) as Map<String, dynamic>)
        .toList();
  }

  /// Clear all pending feedback (after successful submission).
  Future<void> clearPendingFeedback() async {
    final prefs = await _getPrefs();
    await prefs.remove(PrefsKeys.pendingFeedback);
  }

  /// Determine the initial workflow step based on saved preferences.
  Future<WorkflowStep> getInitialStep() async {
    final onboardingDone = await isOnboardingCompleted();
    if (!onboardingDone) return WorkflowStep.onboarding;
    return WorkflowStep.imageCapture;
  }

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }
}
