enum WorkOrderStatus { pending, inProgress, completed, cancelled }

enum SyncState { synced, pendingUpload, conflicted }

class WorkOrder {
  const WorkOrder({
    required this.id,
    required this.title,
    required this.customer,
    required this.status,
    required this.notes,
    required this.updatedAt,
    required this.version,
    required this.syncState,
    this.deleted = false,
  });

  final String id;
  final String title;
  final String customer;
  final WorkOrderStatus status;
  final String notes;
  final DateTime updatedAt;
  final int version;
  final SyncState syncState;
  final bool deleted;

  WorkOrder copyWith({
    String? title,
    String? customer,
    WorkOrderStatus? status,
    String? notes,
    DateTime? updatedAt,
    int? version,
    SyncState? syncState,
    bool? deleted,
  }) => WorkOrder(
    id: id,
    title: title ?? this.title,
    customer: customer ?? this.customer,
    status: status ?? this.status,
    notes: notes ?? this.notes,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
    syncState: syncState ?? this.syncState,
    deleted: deleted ?? this.deleted,
  );

  factory WorkOrder.fromJson(Map<String, dynamic> json) => WorkOrder(
    id: json['id'] as String,
    title: json['title'] as String,
    customer: json['customer'] as String,
    status: WorkOrderStatus.values.byName(json['status'] as String),
    notes: json['notes'] as String? ?? '',
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    version: json['version'] as int,
    syncState: SyncState.synced,
    deleted: json['deleted'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'customer': customer,
    'status': status.name,
    'notes': notes,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'version': version,
    'deleted': deleted,
  };
}
