import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/entities/work_order.dart';
import '../../domain/sync/retry_policy.dart';

part 'database.g.dart';

@DataClassName('WorkOrderRow')
class WorkOrders extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get customer => text()();
  TextColumn get status => text()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer()();
  TextColumn get syncState => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  TextColumn get baseSnapshot => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('OutboxRow')
class OutboxEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityId => text()();
  TextColumn get payload => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get nextAttemptAt => dateTime()();
  TextColumn get lastError => text().nullable()();
}

@DataClassName('SyncMetadataRow')
class SyncMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [WorkOrders, OutboxEntries, SyncMetadata])
class SyncDatabase extends _$SyncDatabase {
  SyncDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'syncflow'));

  @override
  int get schemaVersion => 1;

  Stream<List<WorkOrder>> watchWorkOrders() {
    final query = select(workOrders)
      ..where((row) => row.deleted.equals(false))
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return query.watch().map(
      (rows) => rows.map(_toEntity).toList(growable: false),
    );
  }

  Future<List<WorkOrder>> allWorkOrders() async {
    final rows = await select(workOrders).get();
    return rows.map(_toEntity).toList(growable: false);
  }

  Future<WorkOrder?> findWorkOrder(String id) async {
    final row = await (select(
      workOrders,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  Future<WorkOrder?> findBaseSnapshot(String id) async {
    final row = await (select(
      workOrders,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    final snapshot = row?.baseSnapshot;
    if (snapshot == null) return null;
    return WorkOrder.fromJson(jsonDecode(snapshot) as Map<String, dynamic>);
  }

  Future<void> saveWorkOrder(WorkOrder order, {WorkOrder? baseSnapshot}) {
    return into(workOrders).insertOnConflictUpdate(
      WorkOrdersCompanion.insert(
        id: order.id,
        title: order.title,
        customer: order.customer,
        status: order.status.name,
        notes: Value(order.notes),
        updatedAt: order.updatedAt,
        version: order.version,
        syncState: order.syncState.name,
        deleted: Value(order.deleted),
        baseSnapshot: Value(
          baseSnapshot == null ? null : jsonEncode(baseSnapshot.toJson()),
        ),
      ),
    );
  }

  Future<void> enqueue(WorkOrder order, DateTime now) async {
    await (delete(
      outboxEntries,
    )..where((row) => row.entityId.equals(order.id))).go();
    await into(outboxEntries).insert(
      OutboxEntriesCompanion.insert(
        entityId: order.id,
        payload: jsonEncode(order.toJson()),
        createdAt: now,
        nextAttemptAt: now,
      ),
    );
  }

  Future<List<PendingOperation>> dueOperations(DateTime now) async {
    final query = select(outboxEntries)
      ..where((row) => row.nextAttemptAt.isSmallerOrEqualValue(now))
      ..orderBy([(row) => OrderingTerm.asc(row.id)]);
    final rows = await query.get();
    return rows
        .map(
          (row) => PendingOperation(
            id: row.id,
            entityId: row.entityId,
            payload: jsonDecode(row.payload) as Map<String, dynamic>,
            attempts: row.attempts,
            createdAt: row.createdAt,
            lastError: row.lastError,
          ),
        )
        .toList(growable: false);
  }

  Future<int> pendingCount() async {
    final countExp = outboxEntries.id.count();
    final query = selectOnly(outboxEntries)..addColumns([countExp]);
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  Future<void> removeOperation(int id) =>
      (delete(outboxEntries)..where((row) => row.id.equals(id))).go();

  Future<void> rescheduleOperation({
    required int id,
    required int attempts,
    required DateTime nextAttemptAt,
    required String error,
  }) {
    return (update(outboxEntries)..where((row) => row.id.equals(id))).write(
      OutboxEntriesCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(nextAttemptAt),
        lastError: Value(error),
      ),
    );
  }

  Future<DateTime?> lastSyncedAt() async {
    final row = await (select(
      syncMetadata,
    )..where((table) => table.key.equals('lastSyncedAt'))).getSingleOrNull();
    if (row == null) return null;
    return DateTime.parse(row.value).toUtc();
  }

  Future<void> setLastSyncedAt(DateTime value) {
    return into(syncMetadata).insertOnConflictUpdate(
      SyncMetadataCompanion.insert(
        key: 'lastSyncedAt',
        value: value.toUtc().toIso8601String(),
      ),
    );
  }

  WorkOrder _toEntity(WorkOrderRow row) => WorkOrder(
    id: row.id,
    title: row.title,
    customer: row.customer,
    status: WorkOrderStatus.values.byName(row.status),
    notes: row.notes,
    updatedAt: row.updatedAt.toUtc(),
    version: row.version,
    syncState: SyncState.values.byName(row.syncState),
    deleted: row.deleted,
  );
}
