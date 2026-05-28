import 'dart:io';

import 'package:http/http.dart' as http;

/// Manages the lifecycle of the bundled Python backend subprocess.
///
/// On Windows Desktop (installed app) the engine lives at:
///   `<flutter_exe_dir>\engine\embroidery_backend.exe`
///
/// In dev mode the file won't be found and [start] is a no-op — the
/// developer is expected to run `python api_server.py` manually.
///
/// On Android / iOS there is no subprocess — the HTTP client talks to
/// a remote server configured via [ServerConfig].
class EngineLauncher {
  EngineLauncher._();

  static Process? _process;
  static bool _started = false;

  static const String _host = '127.0.0.1';
  static const int _port = 8000;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Launch the engine subprocess (Windows Desktop only).
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  /// Never throws: failures are swallowed so the app still starts.
  static Future<void> start() async {
    if (!Platform.isWindows) return;
    if (_started) return;

    final enginePath = _resolveEnginePath();
    if (enginePath == null) return; // dev mode — server managed externally

    try {
      _process = await Process.start(
        enginePath,
        ['--host', _host, '--port', '$_port'],
      );
      _started = true;
    } catch (_) {
      // Engine failed to start. The HTTP client will surface the error to
      // the user when they attempt an action that requires the server.
    }
  }

  /// Terminate the engine subprocess. Safe to call when not running.
  static Future<void> stop() async {
    _process?.kill();
    _process = null;
    _started = false;
  }

  /// Returns true if the engine HTTP server is currently responding.
  static Future<bool> isReady() async {
    try {
      final response = await http
          .get(Uri.parse('http://$_host:$_port/health'))
          .timeout(const Duration(seconds: 1));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  /// Returns the path to `engine\embroidery_backend.exe` relative to the
  /// Flutter executable, or null when the file is absent (dev mode).
  static String? _resolveEnginePath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidate = '$exeDir\\engine\\embroidery_backend.exe';
    return File(candidate).existsSync() ? candidate : null;
  }
}
