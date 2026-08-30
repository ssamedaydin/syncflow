import '../entities/work_order.dart';

abstract class WorkOrderRepository {
  Stream<List<WorkOrder>> watchAll();

  Future<List<WorkOrder>> getAll();

  Future<void> upsertLocal(WorkOrder order);

  Future<void> markDeleted(String id);

  Future<SyncSummary> sync();
}

class SyncSummary {
  const SyncSummary({
    required this.pulled,
    required this.pushed,
    required this.conflicts,
    required this.failures,
  });

  const SyncSummary.empty()
    : pulled = 0,
      pushed = 0,
      conflicts = 0,
      failures = 0;

  final int pulled;
  final int pushed;
  final int conflicts;
  final int failures;

  bool get hasChanges => pulled > 0 || pushed > 0;
}
