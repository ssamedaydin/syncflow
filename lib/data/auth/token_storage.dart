import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/auth/auth_session.dart';

abstract class TokenStorage {
  Future<AuthSession?> read();

  Future<void> write(AuthSession session);

  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  const SecureTokenStorage([
    this.storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(storageNamespace: 'syncflow'),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    ),
  ]);

  static const _key = 'syncflow.session';

  final FlutterSecureStorage storage;

  @override
  Future<AuthSession?> read() async {
    final raw = await storage.read(key: _key);
    if (raw == null) return null;
    return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> write(AuthSession session) =>
      storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => storage.delete(key: _key);
}

class InMemoryTokenStorage implements TokenStorage {
  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
