import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/interfaces/export_manager.dart';
import '../../domain/models/embroidery_design.dart';

/// Export manager for Mobile (Android/iOS).
///
/// Saves files to the Downloads folder and records export history.
class MobileExportManager implements ExportManager {
  MobileExportManager({SharedPreferences? prefs}) : _prefs = prefs;

  final SharedPreferences? _prefs;
  static const _uuid = Uuid();

  @override
  Future<ExportDestination?> selectDestination(String suggestedFilename) async {
    // On mobile, we always save to Downloads — no picker needed
    final downloadsDir = await _getDownloadsDirectory();
    final filePath = '${downloadsDir.path}/$suggestedFilename';
    return ExportDestination(path: filePath, isUsb: false);
  }

  @override
  Future<String?> validateDestination(
    ExportDestination destination,
    int requiredBytes,
  ) async {
    try {
      final dir = Directory(destination.path).parent;
      if (!dir.existsSync()) {
        return 'Pasta de destino não encontrada.';
      }
      return null;
    } catch (e) {
      return 'Não foi possível verificar o destino.';
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
      await file.parent.create(recursive: true);
      await file.writeAsBytes(design.fileBytes!);

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
      if (e.osError?.errorCode == 28) {
        message = 'Espaço insuficiente no dispositivo. Libere espaço e tente novamente.';
      } else {
        message = 'Erro ao salvar arquivo: ${e.message}';
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
    if (existing.length > 50) existing.removeAt(0);
    await prefs.setStringList('export_history', existing);
  }

  Future<Directory> _getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      // Android: /storage/emulated/0/Download
      return Directory('/storage/emulated/0/Download');
    } else if (Platform.isIOS) {
      // iOS: use Documents directory (accessible via Files app)
      return getApplicationDocumentsDirectory();
    }
    // Fallback
    return getTemporaryDirectory();
  }
}
