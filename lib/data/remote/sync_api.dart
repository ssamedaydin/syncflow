import 'package:dio/dio.dart';

import '../../domain/entities/work_order.dart';

class DeltaPage {
  const DeltaPage({required this.changes, required this.serverTime});

  final List<WorkOrder> changes;
  final DateTime serverTime;
}

class VersionConflictException implements Exception {
  const VersionConflictException(this.remote);

  final WorkOrder remote;
}

abstract class SyncApi {
  Future<DeltaPage> pullChanges({DateTime? since});

  Future<WorkOrder> pushChange(WorkOrder order);
}

class HttpSyncApi implements SyncApi {
  HttpSyncApi(this._dio);

  final Dio _dio;

  @override
  Future<DeltaPage> pullChanges({DateTime? since}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/work-orders/delta',
      queryParameters: {
        if (since != null) 'since': since.toUtc().toIso8601String(),
      },
    );
    final data = response.data ?? const {};
    final items = (data['changes'] as List<dynamic>? ?? const [])
        .map((item) => WorkOrder.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    return DeltaPage(
      changes: items,
      serverTime: DateTime.parse(data['serverTime'] as String).toUtc(),
    );
  }

  @override
  Future<WorkOrder> pushChange(WorkOrder order) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/work-orders/${order.id}',
        data: order.toJson(),
      );
      return WorkOrder.fromJson(response.data!);
    } on DioException catch (error) {
      final response = error.response;
      if (response?.statusCode == 409) {
        final remote = response!.data['remote'] as Map<String, dynamic>;
        throw VersionConflictException(WorkOrder.fromJson(remote));
      }
      rethrow;
    }
  }
}
