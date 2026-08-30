import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncflow/data/auth/auth_interceptor.dart';
import 'package:syncflow/data/auth/oauth_repository.dart';
import 'package:syncflow/data/auth/token_storage.dart';
import 'package:syncflow/domain/auth/auth_session.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, {int status = 200}) =>
    ResponseBody.fromString(
      '{"access_token":"${body['access_token']}",'
      '"refresh_token":"${body['refresh_token']}",'
      '"expires_in":${body['expires_in']},"sub":"${body['sub']}"}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ResponseBody _emptyJson({int status = 200}) => ResponseBody.fromString(
  '{}',
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  late DateTime now;

  setUp(() => now = DateTime.utc(2026, 8, 30, 10));

  test('giriş token alır ve güvenli depoya yazar', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.httpClientAdapter = _StubAdapter(
      (options) async => _json({
        'access_token': 'access-1',
        'refresh_token': 'refresh-1',
        'expires_in': 900,
        'sub': 'saha',
      }),
    );
    final storage = InMemoryTokenStorage();
    final repository = OAuthRepository(
      dio: dio,
      storage: storage,
      clock: () => now,
    );

    final session = await repository.signIn(username: 'saha', password: '1234');

    expect(session.accessToken, 'access-1');
    expect(session.expiresAt, now.add(const Duration(seconds: 900)));
    expect((await storage.read())!.refreshToken, 'refresh-1');
  });

  test('hatalı kimlik bilgisi anlamlı hata döndürür', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.httpClientAdapter = _StubAdapter(
      (options) async =>
          ResponseBody.fromString('{"error":"invalid_grant"}', 400),
    );
    final repository = OAuthRepository(
      dio: dio,
      storage: InMemoryTokenStorage(),
      clock: () => now,
    );

    expect(
      () => repository.signIn(username: 'saha', password: 'yanlis'),
      throwsA(isA<AuthException>()),
    );
  });

  test('süresi dolan oturum istek öncesi yenilenir', () async {
    final storage = InMemoryTokenStorage();
    await storage.write(
      AuthSession(
        accessToken: 'eski',
        refreshToken: 'refresh-1',
        expiresAt: now.subtract(const Duration(minutes: 5)),
        subject: 'saha',
      ),
    );
    final authDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    authDio.httpClientAdapter = _StubAdapter(
      (options) async => _json({
        'access_token': 'yeni',
        'refresh_token': 'refresh-2',
        'expires_in': 900,
        'sub': 'saha',
      }),
    );
    final repository = OAuthRepository(
      dio: authDio,
      storage: storage,
      clock: () => now,
    );

    final apiDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    final adapter = _StubAdapter((options) async => _emptyJson());
    apiDio.httpClientAdapter = adapter;
    apiDio.interceptors.add(
      AuthInterceptor(auth: repository, clock: () => now),
    );

    await apiDio.get<Map<String, dynamic>>('/work-orders/delta');

    expect(adapter.requests.single.headers['Authorization'], 'Bearer yeni');
    expect((await storage.read())!.accessToken, 'yeni');
  });

  test('geçerli oturumda yenileme yapılmaz', () async {
    final storage = InMemoryTokenStorage();
    await storage.write(
      AuthSession(
        accessToken: 'gecerli',
        refreshToken: 'refresh-1',
        expiresAt: now.add(const Duration(minutes: 30)),
        subject: 'saha',
      ),
    );
    final authDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    final authAdapter = _StubAdapter(
      (options) async => _emptyJson(status: 500),
    );
    authDio.httpClientAdapter = authAdapter;

    final apiDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    apiDio.httpClientAdapter = _StubAdapter((options) async => _emptyJson());
    apiDio.interceptors.add(
      AuthInterceptor(
        auth: OAuthRepository(dio: authDio, storage: storage, clock: () => now),
        clock: () => now,
      ),
    );

    await apiDio.get<Map<String, dynamic>>('/work-orders/delta');

    expect(authAdapter.requests, isEmpty);
  });

  test('çıkışta oturum silinir', () async {
    final storage = InMemoryTokenStorage();
    await storage.write(
      AuthSession(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: now.add(const Duration(hours: 1)),
        subject: 'saha',
      ),
    );
    final repository = OAuthRepository(
      dio: Dio(),
      storage: storage,
      clock: () => now,
    );

    await repository.signOut();

    expect(await storage.read(), isNull);
  });

  test('oturum süresi payla birlikte değerlendirilir', () {
    final session = AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: now.add(const Duration(seconds: 30)),
      subject: 'saha',
    );

    expect(session.isExpired(now), isTrue);
    expect(session.isExpired(now, leeway: Duration.zero), isFalse);
  });
}
