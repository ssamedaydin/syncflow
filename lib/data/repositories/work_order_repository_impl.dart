import 'package:dio/dio.dart';

import '../../domain/entities/work_order.dart';
import '../../domain/repositories/work_order_repository.dart';
import '../../domain/sync/conflict_resolver.dart';
import '../../domain/sync/retry_policy.dart';
import '../local/database.dart';
import '../remote/sync_api.dart';

class WorkOrderRepositoryImpl implements WorkOrderRepository {
  const WorkOrderRepositoryImpl({
    required this.database,
    required this.api,
    this.resolver = const BusinessRuleResolver(),
    this.retryPolicy = const RetryPolicy(),
    this.clock = utcNow,
  });

  static DateTime utcNow() => DateTime.now().toUtc();

  final SyncDatabase database;
  final SyncApi api;
  final ConflictResolver resolver;
  final RetryPolicy retryPolicy;
  final DateTime Function() clock;

  @override
  Stream<List<WorkOrder>> watchAll() => database.watchWorkOrders();

  @override
  Future<List<WorkOrder>> getAll() => database.allWorkOrders();

  @override
  Future<void> upsertLocal(WorkOrder order) async {
    final now = clock();
    final existing = await database.findWorkOrder(order.id);
    final updated = order.copyWith(
      updatedAt: now,
      syncState: SyncState.pendingUpload,
    );
    await database.saveWorkOrder(
      updated,
      baseSnapshot: existing?.syncState == SyncState.synced ? existing : null,
    );
    await database.enqueue(updated, now);
  }

  @override
  Future<void> markDeleted(String id) async {
    final existing = await database.findWorkOrder(id);
    if (existing == null) return;
    await upsertLocal(existing.copyWith(deleted: true));
  }

  @override
  Future<SyncSummary> sync() async {
    final pulled = await _pull();
    final result = await _drainOutbox();
    return SyncSummary(
      pulled: pulled.pulled,
      pushed: result.pushed,
      conflicts: pulled.conflicts + result.conflicts,
      failures: result.failures,
    );
  }

  Future<({int pulled, int conflicts})> _pull() async {
    final since = await database.lastSyncedAt();
    final page = await api.pullChanges(since: since);
    var conflicts = 0;

    for (final remote in page.changes) {
      final local = await database.findWorkOrder(remote.id);
      if (local == null || local.syncState == SyncState.synced) {
        await database.saveWorkOrder(
          remote.copyWith(syncState: SyncState.synced),
          baseSnapshot: remote,
        );
        continue;
      }
      final base = await database.findBaseSnapshot(remote.id);
      final decision = resolver.resolve(
        local: local,
        remote: remote,
        base: base,
      );
      if (decision.outcome != ConflictOutcome.keepLocal) conflicts++;
      await database.saveWorkOrder(decision.merged, baseSnapshot: remote);
      if (decision.merged.syncState == SyncState.pendingUpload) {
        await database.enqueue(decision.merged, clock());
      }
    }

    await database.setLastSyncedAt(page.serverTime);
    return (pulled: page.changes.length, conflicts: conflicts);
  }

  Future<({int pushed, int conflicts, int failures})> _drainOutbox() async {
    final now = clock();
    final operations = await database.dueOperations(now);
    var pushed = 0;
    var conflicts = 0;
    var failures = 0;

    for (final operation in operations) {
      final order = WorkOrder.fromJson(operation.payload);
      try {
        final accepted = await api.pushChange(order);
        await database.saveWorkOrder(
          accepted.copyWith(syncState: SyncState.synced),
          baseSnapshot: accepted,
        );
        await database.removeOperation(operation.id);
        pushed++;
      } on VersionConflictException catch (conflict) {
        conflicts++;
        await _resolvePushConflict(operation, order, conflict.remote);
      } on DioException catch (error) {
        failures++;
        await _scheduleRetry(operation, error);
      }
    }

    return (pushed: pushed, conflicts: conflicts, failures: failures);
  }

  Future<void> _resolvePushConflict(
    PendingOperation operation,
    WorkOrder local,
    WorkOrder remote,
  ) async {
    final base = await database.findBaseSnapshot(local.id);
    final decision = resolver.resolve(local: local, remote: remote, base: base);
    await database.saveWorkOrder(decision.merged, baseSnapshot: remote);
    await database.removeOperation(operation.id);
    if (decision.merged.syncState == SyncState.pendingUpload) {
      await database.enqueue(decision.merged, clock());
    }
  }

  Future<void> _scheduleRetry(
    PendingOperation operation,
    DioException error,
  ) async {
    final attempts = operation.attempts + 1;
    if (!retryPolicy.shouldRetry(attempts)) {
      await database.removeOperation(operation.id);
      final order = WorkOrder.fromJson(operation.payload);
      await database.saveWorkOrder(
        order.copyWith(syncState: SyncState.conflicted),
      );
      return;
    }
    await database.rescheduleOperation(
      id: operation.id,
      attempts: attempts,
      nextAttemptAt: clock().add(retryPolicy.delayFor(attempts)),
      error: error.message ?? 'bilinmeyen hata',
    );
  }
}
