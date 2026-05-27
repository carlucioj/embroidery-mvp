import 'dart:convert';
import 'dart:io';

/// Represents a removable drive detected on the system.
class UsbDrive {
  const UsbDrive({required this.letter, this.label});

  /// Drive letter with colon, e.g. "E:"
  final String letter;

  /// Volume label, e.g. "BROTHER" or null if unlabeled
  final String? label;

  /// Human-readable name for the UI
  String get displayName {
    final l = label;
    return (l != null && l.isNotEmpty) ? '$l ($letter)' : letter;
  }

  @override
  String toString() => 'UsbDrive($displayName)';
}

/// Detects removable drives on Windows using PowerShell/WMI.
///
/// Returns an empty list on non-Windows platforms or when no removable
/// drives are connected. All errors are swallowed — caller never crashes.
class UsbDriveDetector {
  /// Returns currently connected removable drives.
  ///
  /// Uses `Win32_LogicalDisk.DriveType == 2` (removable media).
  /// Typical embroidery machines (Brother, Babylock) appear as DriveType 2
  /// when connected via USB.
  Future<List<UsbDrive>> detectRemovableDrives() async {
    if (!Platform.isWindows) return [];

    try {
      // ConvertTo-Json behaves differently for 0, 1, and N items:
      //   0 items → null / empty
      //   1 item  → plain object {}
      //   N items → array [{}]
      // -Compress keeps it on one line; easier to detect null vs empty string.
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'Get-WmiObject Win32_LogicalDisk'
          r' | Where-Object { $_.DriveType -eq 2 }'
          r' | Select-Object Caption,VolumeName'
          r' | ConvertTo-Json -Compress',
        ],
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      if (result.exitCode != 0) return [];

      final output = (result.stdout as String).trim();
      if (output.isEmpty || output == 'null') return [];

      return _parse(output);
    } catch (_) {
      return [];
    }
  }

  List<UsbDrive> _parse(String json) {
    try {
      final decoded = jsonDecode(json);
      final List<dynamic> items = decoded is List ? decoded : [decoded];

      return items
          .whereType<Map<String, dynamic>>()
          .map((m) => UsbDrive(
                letter: (m['Caption'] as String? ?? '').trim(),
                label: (m['VolumeName'] as String?)?.trim(),
              ))
          .where((d) => d.letter.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
