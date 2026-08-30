import '../entities/work_order.dart';

enum ConflictOutcome { keepLocal, keepRemote, manual }

class ConflictDecision {
  const ConflictDecision(this.outcome, this.merged, this.reason);

  final ConflictOutcome outcome;
  final WorkOrder merged;
  final String reason;
}

abstract class ConflictResolver {
  ConflictDecision resolve({
    required WorkOrder local,
    required WorkOrder remote,
    required WorkOrder? base,
  });
}

class LastWriteWinsResolver implements ConflictResolver {
  const LastWriteWinsResolver();

  @override
  ConflictDecision resolve({
    required WorkOrder local,
    required WorkOrder remote,
    required WorkOrder? base,
  }) {
    if (remote.updatedAt.isAfter(local.updatedAt)) {
      return ConflictDecision(
        ConflictOutcome.keepRemote,
        remote.copyWith(syncState: SyncState.synced),
        'Sunucu kaydı daha yeni',
      );
    }
    if (local.updatedAt.isAfter(remote.updatedAt)) {
      return ConflictDecision(
        ConflictOutcome.keepLocal,
        local.copyWith(
          version: remote.version,
          syncState: SyncState.pendingUpload,
        ),
        'Yerel kayıt daha yeni',
      );
    }
    return ConflictDecision(
      ConflictOutcome.keepRemote,
      remote.copyWith(syncState: SyncState.synced),
      'Zaman damgaları eşit, sunucu tercih edildi',
    );
  }
}

class BusinessRuleResolver implements ConflictResolver {
  const BusinessRuleResolver({this.fallback = const LastWriteWinsResolver()});

  final ConflictResolver fallback;

  static const _terminalStates = {
    WorkOrderStatus.completed,
    WorkOrderStatus.cancelled,
  };

  @override
  ConflictDecision resolve({
    required WorkOrder local,
    required WorkOrder remote,
    required WorkOrder? base,
  }) {
    if (remote.deleted && !local.deleted) {
      return ConflictDecision(
        ConflictOutcome.manual,
        local.copyWith(syncState: SyncState.conflicted),
        'Kayıt sunucuda silinmiş, yerelde değiştirilmiş',
      );
    }

    final remoteTerminal = _terminalStates.contains(remote.status);
    final localTerminal = _terminalStates.contains(local.status);

    if (remoteTerminal && !localTerminal) {
      return ConflictDecision(
        ConflictOutcome.keepRemote,
        remote.copyWith(syncState: SyncState.synced),
        'Sunucuda kapatılmış iş emri yeniden açılamaz',
      );
    }

    if (localTerminal && !remoteTerminal) {
      return ConflictDecision(
        ConflictOutcome.keepLocal,
        local.copyWith(
          version: remote.version,
          syncState: SyncState.pendingUpload,
        ),
        'Sahada kapatılan iş emri korunur',
      );
    }

    if (local.notes != remote.notes &&
        base != null &&
        local.notes != base.notes &&
        remote.notes != base.notes) {
      final mergedNotes = _mergeNotes(local.notes, remote.notes);
      final winner = fallback.resolve(local: local, remote: remote, base: base);
      return ConflictDecision(
        winner.outcome,
        winner.merged.copyWith(
          notes: mergedNotes,
          syncState: SyncState.pendingUpload,
        ),
        'Not alanı iki tarafta da değişti, birleştirildi',
      );
    }

    return fallback.resolve(local: local, remote: remote, base: base);
  }

  String _mergeNotes(String local, String remote) {
    if (local.isEmpty) return remote;
    if (remote.isEmpty) return local;
    return '$remote\n---\n$local';
  }
}
