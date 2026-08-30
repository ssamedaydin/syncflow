import 'package:dio/dio.dart';

import '../../domain/auth/auth_session.dart';

class AuthInterceptor extends Interceptor {
  const AuthInterceptor({required this.auth, this.clock = utcNow});

  static DateTime utcNow() => DateTime.now().toUtc();

  final AuthRepository auth;
  final DateTime Function() clock;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    var session = await auth.currentSession();
    if (session != null && session.isExpired(clock())) {
      try {
        session = await auth.refresh(session);
      } catch (_) {
        await auth.signOut();
        session = null;
      }
    }
    if (session != null) {
      options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    }
    handler.next(options);
  }
}
