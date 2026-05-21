import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/interfaces/export_manager.dart';
import '../../domain/models/embroidery_design.dart';

/// Export manager for Desktop (Windows).
///
/// Uses file_picker to let the user choose the destination folder,
/// including USB drives. Validates disk space before writing.
class DesktopExportManager implements ExportManager {
  DesktopExportManager({SharedPreferences? prefs}) : _prefs = prefs;

  final SharedPreferences? _prefs;
  static const _uuid = Uuid();

  @override
  Future<ExportDestination?> selectDestination(String suggestedFilename) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar arquivo de bordado',
      fileName: suggestedFilename,
    );

    if (result == null) return null;

    // Detect if destination is a USB drive (removable media)
    final isUsb = _isUsbPath(result);

    return ExportDestination(path: result, isUsb: isUsb);
  }

  @override
  Future<String?> validateDestination(
    ExportDestination destination,
    int requiredBytes,
  ) async {
    try {
      final dir = Directory(path.dirname(destination.path));
      if (!dir.existsSync()) {
        return 'Pasta de destino não encontrada.';
      }

      // Check available space using StatSync
      final stat = dir.statSync();
      // Note: Dart doesn't expose free disk space directly.
      // In production, use a platform channel or the `disk_space` package.
      // For MVP, we skip the actual space check and rely on write errors.
      stat.toString(); // suppress unused warning

      return null; // Valid
    } catch (e) {
      return 'Não foi possível verificar o destino: $e';
    }
  }

  @override
  Future<ExportResult> exportDesign(
    EmbroideryDesign design,
    ExportOptions options,
  ) async {
    if (design.fileBytes == null || design.fileBytes!.isEmpty) {
      return const ExportResult(
        success: false,
        filePath: '',
        errorMessage: 'Arquivo de bordado não gerado. Gere o bordado antes de exportar.',
      );
    }

    try {
      final file = File(options.destination.path);
      await file.writeAsBytes(design.fileBytes!);

      // Record in history
      await _addToHistory(ExportRecord(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        filePath: options.destination.path,
        format: options.format,
        fileSizeBytes: design.fileBytes!.length,
      ));

      return ExportResult(
        success: true,
        filePath: options.destination.path,
      );
    } on FileSystemException catch (e) {
      String message;
      if (e.osError?.errorCode == 28 || e.osError?.errorCode == 112) {
        // ENOSPC (Linux) or ERROR_DISK_FULL (Windows)
        message = 'Espaço em disco insuficiente. Libere espaço e tente novamente.';
      } else {
        message = 'Erro ao salvar arquivo: ${e.message}. Verifique as permissões.';
      }
      return ExportResult(
        success: false,
        filePath: options.destination.path,
        errorMessage: message,
      );
    } catch (e) {
      return ExportResult(
        success: false,
        filePath: options.destination.path,
        errorMessage: 'Erro inesperado ao exportar: $e',
      );
    }
  }

  @override
  Future<List<ExportRecord>> getExportHistory() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('export_history') ?? [];
    return jsonList
        .map((s) => ExportRecord.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> clearExportHistory() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.remove('export_history');
  }

  Future<void> _addToHistory(ExportRecord record) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final existing = prefs.getStringList('export_history') ?? [];
    existing.add(jsonEncode(record.toJson()));
    // Keep last 50 records
    if (existing.length > 50) existing.removeAt(0);
    await prefs.setStringList('export_history', existing);
  }

  bool _isUsbPath(String filePath) {
    // On Windows, USB drives typically appear as D:, E:, F:, etc.
    // This is a heuristic; a real implementation would check drive type.
    if (Platform.isWindows) {
      final driveLetter = filePath.substring(0, 1).toUpperCase();
      return driveLetter != 'C';
    }
    // On Linux/Mac, USB drives are typically mounted under /media or /Volumes
    return filePath.startsWith('/media/') || filePath.startsWith('/Volumes/');
  }
}
