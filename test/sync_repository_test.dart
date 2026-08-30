import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncflow/data/local/database.dart';
import 'package:syncflow/data/remote/sync_api.dart';
import 'package:syncflow/data/repositories/work_order_repository_impl.dart';
import 'package:syncflow/domain/entities/work_order.dart';
import 'package:syncflow/domain/sync/retry_policy.dart';

class FakeSyncApi implements SyncApi {
  FakeSyncApi({this.serverTime});

  final pushed = <WorkOrder>[];
  List<WorkOrder> remoteChanges = const [];
  DateTime? serverTime;
  Object? pushError;

  @override
  Future<DeltaPage> pullChanges({DateTime? since}) async {
    lastSince = since;
    return DeltaPage(
      changes: remoteChanges,
      serverTime: serverTime ?? DateTime.utc(2026, 8, 30, 12),
    );
  }

  DateTime? lastSince;

  @override
  Future<WorkOrder> pushChange(WorkOrder order) async {
    final error = pushError;
    if (error != null) {
      pushError = null;
      throw error;
    }
    pushed.add(order);
    return order.copyWith(version: order.version + 1);
  }
}

WorkOrder makeOrder({
  String id = 'wo-1',
  String title = 'Klima bakımı',
  String notes = '',
  WorkOrderStatus status = WorkOrderStatus.pending,
  required DateTime updatedAt,
  int version = 1,
  SyncState syncState = SyncState.synced,
  bool deleted = false,
}) => WorkOrder(
  id: id,
  title: title,
  customer: 'Acme',
  status: status,
  notes: notes,
  updatedAt: updatedAt,
  version: version,
  syncState: syncState,
  deleted: deleted,
);

void main() {
  late SyncDatabase database;
  late FakeSyncApi api;
  late DateTime now;
  late WorkOrderRepositoryImpl repository;

  setUp(() {
    database = SyncDatabase(DatabaseConnection(NativeDatabase.memory()));
    api = FakeSyncApi();
    now = DateTime.utc(2026, 8, 30, 10);
    repository = WorkOrderRepositoryImpl(
      database: database,
      api: api,
      clock: () => now,
    );
  });

  tearDown(() => database.close());

  test('yerel değişiklik outbox üzerinden sunucuya gider', () async {
    await repository.upsertLocal(
      makeOrder(updatedAt: now, syncState: SyncState.pendingUpload),
    );
    expect(await database.pendingCount(), 1);

    final summary = await repository.sync();

    expect(summary.pushed, 1);
    expect(api.pushed.single.id, 'wo-1');
    expect(await database.pendingCount(), 0);
    final stored = await database.findWorkOrder('wo-1');
    expect(stored!.syncState, SyncState.synced);
    expect(stored.version, 2);
  });

  test('delta çekimi yalnız son senkron sonrasını ister', () async {
    api.remoteChanges = [makeOrder(updatedAt: now, version: 3)];
    await repository.sync();
    expect(api.lastSince, isNull);

    api.remoteChanges = const [];
    await repository.sync();
    expect(api.lastSince, DateTime.utc(2026, 8, 30, 12));
  });

  test(
    'sunucudan gelen kayıt yerel dokunulmamış kaydın üzerine yazılır',
    () async {
      api.remoteChanges = [
        makeOrder(updatedAt: now, title: 'Sunucu başlığı', version: 5),
      ];

      final summary = await repository.sync();

      expect(summary.pulled, 1);
      final stored = await database.findWorkOrder('wo-1');
      expect(stored!.title, 'Sunucu başlığı');
      expect(stored.syncState, SyncState.synced);
    },
  );

  test('çekimde çakışan kayıt iş kuralıyla çözülür', () async {
    await repository.upsertLocal(
      makeOrder(
        updatedAt: now,
        status: WorkOrderStatus.completed,
        syncState: SyncState.pendingUpload,
      ),
    );
    api.remoteChanges = [
      makeOrder(
        updatedAt: now.add(const Duration(hours: 1)),
        status: WorkOrderStatus.inProgress,
        version: 9,
      ),
    ];

    final summary = await repository.sync();

    expect(summary.conflicts, 0);
    expect(api.pushed.single.status, WorkOrderStatus.completed);
    final stored = await database.findWorkOrder('wo-1');
    expect(stored!.status, WorkOrderStatus.completed);
    expect(stored.version, 10);
    expect(stored.syncState, SyncState.synced);
  });

  test('gönderimde sürüm çakışması sunucu sürümüne uyarlanır', () async {
    await repository.upsertLocal(
      makeOrder(updatedAt: now, syncState: SyncState.pendingUpload),
    );
    api.pushError = VersionConflictException(
      makeOrder(
        updatedAt: now.add(const Duration(hours: 2)),
        title: 'Sunucu güncelledi',
        version: 12,
      ),
    );

    final summary = await repository.sync();

    expect(summary.conflicts, 1);
    final stored = await database.findWorkOrder('wo-1');
    expect(stored!.title, 'Sunucu güncelledi');
    expect(await database.pendingCount(), 0);
  });

  test('ağ hatası kaydı kuyrukta bırakır ve yeniden dener', () async {
    await repository.upsertLocal(
      makeOrder(updatedAt: now, syncState: SyncState.pendingUpload),
    );
    api.pushError = DioException(
      requestOptions: RequestOptions(path: '/work-orders/wo-1'),
      message: 'bağlantı yok',
    );

    final failed = await repository.sync();
    expect(failed.failures, 1);
    expect(await database.pendingCount(), 1);

    now = now.add(const Duration(minutes: 10));
    final retried = await repository.sync();

    expect(retried.pushed, 1);
    expect(await database.pendingCount(), 0);
  });

  test(
    'deneme sınırı dolan işlem kuyruktan düşer ve çakışma olarak işaretlenir',
    () async {
      repository = WorkOrderRepositoryImpl(
        database: database,
        api: api,
        retryPolicy: const RetryPolicy(maxAttempts: 1),
        clock: () => now,
      );
      await repository.upsertLocal(
        makeOrder(updatedAt: now, syncState: SyncState.pendingUpload),
      );
      api.pushError = DioException(
        requestOptions: RequestOptions(path: '/work-orders/wo-1'),
        message: 'sunucu hatası',
      );

      await repository.sync();

      expect(await database.pendingCount(), 0);
      final stored = await database.findWorkOrder('wo-1');
      expect(stored!.syncState, SyncState.conflicted);
    },
  );

  test(
    'aynı kayda art arda yapılan değişiklikler tek kuyruk girişine iner',
    () async {
      final order = makeOrder(
        updatedAt: now,
        syncState: SyncState.pendingUpload,
      );
      await repository.upsertLocal(order);
      await repository.upsertLocal(order.copyWith(title: 'İkinci düzenleme'));
      await repository.upsertLocal(order.copyWith(title: 'Üçüncü düzenleme'));

      expect(await database.pendingCount(), 1);

      final summary = await repository.sync();

      expect(summary.pushed, 1);
      expect(api.pushed.single.title, 'Üçüncü düzenleme');
    },
  );

  test('silme işlemi kuyruğa alınır ve listeden çıkar', () async {
    await repository.upsertLocal(
      makeOrder(updatedAt: now, syncState: SyncState.pendingUpload),
    );
    await repository.sync();

    await repository.markDeleted('wo-1');
    final visible = await database.watchWorkOrders().first;

    expect(visible, isEmpty);
    expect(await database.pendingCount(), 1);
  });
}
