import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sales/api/api%20config.dart';

class AuthResult {
  final bool ok;
  final String? username;
  final String? error;
  AuthResult.success(this.username) : ok = true, error = null;
  AuthResult.failure(this.error) : ok = false, username = null;
}

/// Calls POST /api/login on the Sales Bill API.
class AuthApi {
  static Future<AuthResult> login(String username, String password) async {
    final uri = Uri.parse('$salesBillApiBaseUrl/api/login');
    final trimmedUser = username.trim();
    final trimmedPass = password.trim();

    try {
      final res = await http
          .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': trimmedUser,
          'password': trimmedPass,
        }),
      )
          .timeout(const Duration(seconds: 12));

      Map<String, dynamic> body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        return AuthResult.failure(
          'Server returned an unexpected response. Check that the phone can reach $salesBillApiBaseUrl',
        );
      }

      if (res.statusCode == 200 && body['ok'] == true) {
        return AuthResult.success(body['user']?['username'] as String?);
      }
      return AuthResult.failure(body['error'] as String? ?? 'Login failed');
    } on http.ClientException {
      return AuthResult.failure(
        'Cannot reach server at $salesBillApiBaseUrl. Use Wi‑Fi or mobile data that can access the VPS.',
      );
    } catch (_) {
      return AuthResult.failure(
        'Cannot reach server at $salesBillApiBaseUrl. Check internet and try again.',
      );
    }
  }

  static Future<bool> checkServerReachable() async {
    final uri = Uri.parse('$salesBillApiBaseUrl/api/health');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}