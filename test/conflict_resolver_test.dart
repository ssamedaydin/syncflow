import 'package:flutter_test/flutter_test.dart';
import 'package:syncflow/domain/entities/work_order.dart';
import 'package:syncflow/domain/sync/conflict_resolver.dart';

WorkOrder order({
  String id = 'wo-1',
  String notes = '',
  WorkOrderStatus status = WorkOrderStatus.pending,
  required DateTime updatedAt,
  int version = 1,
  SyncState syncState = SyncState.synced,
  bool deleted = false,
}) => WorkOrder(
  id: id,
  title: 'Klima bakımı',
  customer: 'Acme',
  status: status,
  notes: notes,
  updatedAt: updatedAt,
  version: version,
  syncState: syncState,
  deleted: deleted,
);

void main() {
  final base = DateTime.utc(2026, 8, 30, 9);
  final later = base.add(const Duration(minutes: 10));

  group('LastWriteWinsResolver', () {
    const resolver = LastWriteWinsResolver();

    test('daha yeni sunucu kaydı kazanır', () {
      final decision = resolver.resolve(
        local: order(updatedAt: base, syncState: SyncState.pendingUpload),
        remote: order(updatedAt: later, version: 2),
        base: null,
      );

      expect(decision.outcome, ConflictOutcome.keepRemote);
      expect(decision.merged.syncState, SyncState.synced);
    });

    test('daha yeni yerel kayıt sunucu sürümünü devralır', () {
      final decision = resolver.resolve(
        local: order(updatedAt: later, syncState: SyncState.pendingUpload),
        remote: order(updatedAt: base, version: 7),
        base: null,
      );

      expect(decision.outcome, ConflictOutcome.keepLocal);
      expect(decision.merged.version, 7);
      expect(decision.merged.syncState, SyncState.pendingUpload);
    });

    test('eşit zaman damgasında sunucu tercih edilir', () {
      final decision = resolver.resolve(
        local: order(updatedAt: base, syncState: SyncState.pendingUpload),
        remote: order(updatedAt: base, version: 3),
        base: null,
      );

      expect(decision.outcome, ConflictOutcome.keepRemote);
    });
  });

  group('BusinessRuleResolver', () {
    const resolver = BusinessRuleResolver();

    test('sunucuda kapatılan iş emri yerelde yeniden açılamaz', () {
      final decision = resolver.resolve(
        local: order(
          updatedAt: later,
          status: WorkOrderStatus.inProgress,
          syncState: SyncState.pendingUpload,
        ),
        remote: order(
          updatedAt: base,
          status: WorkOrderStatus.completed,
          version: 4,
        ),
        base: null,
      );

      expect(decision.outcome, ConflictOutcome.keepRemote);
      expect(decision.merged.status, WorkOrderStatus.completed);
    });

    test('sahada kapatılan iş emri sunucu daha yeni olsa da korunur', () {
      final decision = resolver.resolve(
        local: order(
          updatedAt: base,
          status: WorkOrderStatus.completed,
          syncState: SyncState.pendingUpload,
        ),
        remote: order(
          updatedAt: later,
          status: WorkOrderStatus.inProgress,
          version: 5,
        ),
        base: null,
      );

      expect(decision.outcome, ConflictOutcome.keepLocal);
      expect(decision.merged.status, WorkOrderStatus.completed);
      expect(decision.merged.version, 5);
    });

    test('sunucuda silinmiş kayıt yerelde değiştiyse elle çözüme kalır', () {
      final decision = resolver.resolve(
        local: order(updatedAt: later, syncState: SyncState.pendingUpload),
        remote: order(updatedAt: base, deleted: true, version: 2),
        base: null,
      );

      expect(decision.outcome, ConflictOutcome.manual);
      expect(decision.merged.syncState, SyncState.conflicted);
    });

    test('iki tarafta da değişen notlar birleştirilir', () {
      final decision = resolver.resolve(
        local: order(
          updatedAt: later,
          notes: 'Kompresör değişti',
          syncState: SyncState.pendingUpload,
        ),
        remote: order(
          updatedAt: base,
          notes: 'Müşteri randevuyu öne aldı',
          version: 3,
        ),
        base: order(updatedAt: base, notes: 'İlk kayıt'),
      );

      expect(decision.merged.notes, contains('Kompresör değişti'));
      expect(decision.merged.notes, contains('Müşteri randevuyu öne aldı'));
      expect(decision.merged.syncState, SyncState.pendingUpload);
    });

    test('tek taraf değiştiyse birleştirme yapılmaz', () {
      final decision = resolver.resolve(
        local: order(
          updatedAt: later,
          notes: 'Sadece yerel not',
          syncState: SyncState.pendingUpload,
        ),
        remote: order(updatedAt: base, notes: 'İlk kayıt', version: 2),
        base: order(updatedAt: base, notes: 'İlk kayıt'),
      );

      expect(decision.merged.notes, 'Sadece yerel not');
    });
  });
}
