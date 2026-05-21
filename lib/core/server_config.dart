import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';

/// Manages the server URL configuration at runtime.
///
/// Allows the user to point the app to a local or remote server.
/// Default: http://localhost:8000 (local Python server)
class ServerConfig {
  ServerConfig._();

  static const String _prefKey = 'server_url';
  static const String defaultUrl = 'http://localhost:8000';

  static String _currentUrl = defaultUrl;

  /// Current server URL (no trailing slash)
  static String get url => _currentUrl;

  /// Load saved URL from preferences on app startup
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUrl = prefs.getString(_prefKey) ?? defaultUrl;
    ProcessingConfig.apiBaseUrl = _currentUrl;
  }

  /// Save a new server URL and apply immediately
  static Future<void> save(String url) async {
    _currentUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    ProcessingConfig.apiBaseUrl = _currentUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _currentUrl);
  }

  /// Reset to default localhost
  static Future<void> reset() => save(defaultUrl);

  /// Check if the server is reachable (GET /health)
  static Future<bool> checkHealth() async {
    try {
      final uri = Uri.parse('$_currentUrl/health');
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
