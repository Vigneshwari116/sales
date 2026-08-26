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
    try {
      final res = await http
          .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      )
          .timeout(const Duration(seconds: 8));

      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && body['ok'] == true) {
        return AuthResult.success(body['user']?['username'] as String?);
      }
      return AuthResult.failure(body['error'] as String? ?? 'Login failed');
    } catch (e) {
      return AuthResult.failure('Could not reach the server. Check your connection.');
    }
  }
}