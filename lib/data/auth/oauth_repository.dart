import 'package:dio/dio.dart';

import '../../domain/auth/auth_session.dart';
import 'token_storage.dart';

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OAuthRepository implements AuthRepository {
  const OAuthRepository({
    required this.dio,
    required this.storage,
    this.clientId = 'syncflow-mobile',
    this.clock = utcNow,
  });

  static DateTime utcNow() => DateTime.now().toUtc();

  final Dio dio;
  final TokenStorage storage;
  final String clientId;
  final DateTime Function() clock;

  @override
  Future<AuthSession?> currentSession() => storage.read();

  @override
  Future<AuthSession> signIn({
    required String username,
    required String password,
  }) async {
    final session = await _requestToken({
      'grant_type': 'password',
      'client_id': clientId,
      'username': username,
      'password': password,
      'scope': 'openid profile work_orders',
    });
    await storage.write(session);
    return session;
  }

  @override
  Future<AuthSession> refresh(AuthSession session) async {
    final refreshed = await _requestToken({
      'grant_type': 'refresh_token',
      'client_id': clientId,
      'refresh_token': session.refreshToken,
    });
    await storage.write(refreshed);
    return refreshed;
  }

  @override
  Future<void> signOut() => storage.clear();

  Future<AuthSession> _requestToken(Map<String, String> form) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/oauth/token',
        data: form,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = response.data ?? const {};
      final expiresIn = data['expires_in'] as int? ?? 3600;
      return AuthSession(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
        expiresAt: clock().add(Duration(seconds: expiresIn)),
        subject: data['sub'] as String? ?? form['username'] ?? 'unknown',
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 400 || status == 401) {
        throw const AuthException('Kullanıcı adı veya parola hatalı');
      }
      throw const AuthException('Kimlik sunucusuna ulaşılamadı');
    }
  }
}
