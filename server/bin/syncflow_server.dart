import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

final _store = WorkOrderStore();
final _issuedTokens = <String, String>{};

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8088;

  final router = Router()
    ..post('/oauth/token', _issueToken)
    ..get('/work-orders/delta', _delta)
    ..put('/work-orders/<id>', _push);

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'SyncFlow server: http://${server.address.host}:${server.port} '
    '(demo kullanıcı: saha / 1234)',
  );
}

Future<Response> _issueToken(Request request) async {
  final body = Uri.splitQueryString(await request.readAsString());
  final grant = body['grant_type'];

  if (grant == 'refresh_token') {
    final subject = _issuedTokens[body['refresh_token']];
    if (subject == null) {
      return _json({'error': 'invalid_grant'}, status: 400);
    }
    return _json(_tokenResponse(subject));
  }

  final username = body['username'];
  final password = body['password'];
  if (username != 'saha' || password != '1234') {
    return _json({'error': 'invalid_grant'}, status: 400);
  }
  return _json(_tokenResponse(username!));
}

Map<String, dynamic> _tokenResponse(String subject) {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final refreshToken = 'refresh-$subject-$stamp';
  _issuedTokens[refreshToken] = subject;
  return {
    'access_token': 'access-$subject-$stamp',
    'refresh_token': refreshToken,
    'token_type': 'Bearer',
    'expires_in': 900,
    'sub': subject,
  };
}

Response _delta(Request request) {
  if (!_authorized(request)) return _json({'error': 'unauthorized'}, status: 401);
  final sinceParam = request.url.queryParameters['since'];
  final since = sinceParam == null ? null : DateTime.parse(sinceParam).toUtc();
  return _json({
    'changes': _store.changedSince(since),
    'serverTime': DateTime.now().toUtc().toIso8601String(),
  });
}

Future<Response> _push(Request request, String id) async {
  if (!_authorized(request)) return _json({'error': 'unauthorized'}, status: 401);
  final incoming = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final existing = _store.find(id);

  if (existing != null && (incoming['version'] as int) < (existing['version'] as int)) {
    return _json({'error': 'version_conflict', 'remote': existing}, status: 409);
  }

  final accepted = _store.upsert(id, incoming);
  return _json(accepted);
}

bool _authorized(Request request) {
  final header = request.headers['authorization'];
  return header != null && header.startsWith('Bearer access-');
}

Response _json(Object body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);

class WorkOrderStore {
  WorkOrderStore() {
    final now = DateTime.now().toUtc();
    upsert('wo-1001', {
      'id': 'wo-1001',
      'title': 'Klima bakımı',
      'customer': 'Acme Lojistik',
      'status': 'pending',
      'notes': 'Filtre değişimi talep edildi.',
      'updatedAt': now.toIso8601String(),
      'version': 1,
      'deleted': false,
    });
    upsert('wo-1002', {
      'id': 'wo-1002',
      'title': 'Jeneratör kontrolü',
      'customer': 'Kuzey Enerji',
      'status': 'inProgress',
      'notes': '',
      'updatedAt': now.toIso8601String(),
      'version': 1,
      'deleted': false,
    });
  }

  final _orders = <String, Map<String, dynamic>>{};

  Map<String, dynamic>? find(String id) => _orders[id];

  List<Map<String, dynamic>> changedSince(DateTime? since) {
    final all = _orders.values.toList();
    if (since == null) return all;
    return all
        .where(
          (order) =>
              DateTime.parse(order['updatedAt'] as String).toUtc().isAfter(since),
        )
        .toList();
  }

  Map<String, dynamic> upsert(String id, Map<String, dynamic> order) {
    final existing = _orders[id];
    final version = existing == null ? 1 : (existing['version'] as int) + 1;
    final stored = {
      ...order,
      'id': id,
      'version': version,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    _orders[id] = stored;
    return stored;
  }
}
