class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.subject,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
    subject: json['subject'] as String,
  );

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String subject;

  bool isExpired(
    DateTime now, {
    Duration leeway = const Duration(minutes: 1),
  }) => now.add(leeway).isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'subject': subject,
  };
}

abstract class AuthRepository {
  Future<AuthSession?> currentSession();

  Future<AuthSession> signIn({
    required String username,
    required String password,
  });

  Future<AuthSession> refresh(AuthSession session);

  Future<void> signOut();
}
