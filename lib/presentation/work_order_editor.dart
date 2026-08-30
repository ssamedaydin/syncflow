import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/entities/work_order.dart';
import 'providers.dart';
import 'theme.dart';

Future<void> showWorkOrderEditor(
  BuildContext context,
  WidgetRef ref, {
  WorkOrder? existing,
}) async {
  final result = await showModalBottomSheet<WorkOrder>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: WorkOrderEditor(existing: existing),
    ),
  );
  if (result == null) return;
  await ref.read(workOrderRepositoryProvider).upsertLocal(result);
}

class WorkOrderEditor extends StatefulWidget {
  const WorkOrderEditor({super.key, this.existing});

  final WorkOrder? existing;

  @override
  State<WorkOrderEditor> createState() => _WorkOrderEditorState();
}

class _WorkOrderEditorState extends State<WorkOrderEditor> {
  late final TextEditingController _title;
  late final TextEditingController _customer;
  late final TextEditingController _notes;
  late WorkOrderStatus _status;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _customer = TextEditingController(text: existing?.customer ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _status = existing?.status ?? WorkOrderStatus.pending;
  }

  @override
  void dispose() {
    _title.dispose();
    _customer.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    final customer = _customer.text.trim();
    if (title.isEmpty || customer.isEmpty) return;
    final existing = widget.existing;
    final now = DateTime.now().toUtc();
    Navigator.of(context).pop(
      WorkOrder(
        id: existing?.id ?? 'wo-${now.microsecondsSinceEpoch}',
        title: title,
        customer: customer,
        status: _status,
        notes: _notes.text.trim(),
        updatedAt: now,
        version: existing?.version ?? 1,
        syncState: SyncState.pendingUpload,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return Padding(
      padding: const EdgeInsets.all(SyncFlowSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEditing ? 'İş emrini düzenle' : 'Yeni iş emri',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: SyncFlowSpacing.md),
          TextField(
            controller: _title,
            autofocus: !isEditing,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Başlık'),
          ),
          const SizedBox(height: SyncFlowSpacing.md),
          TextField(
            controller: _customer,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Müşteri'),
          ),
          const SizedBox(height: SyncFlowSpacing.md),
          DropdownButtonFormField<WorkOrderStatus>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Durum'),
            items: const [
              DropdownMenuItem(
                value: WorkOrderStatus.pending,
                child: Text('Bekliyor'),
              ),
              DropdownMenuItem(
                value: WorkOrderStatus.inProgress,
                child: Text('Devam ediyor'),
              ),
              DropdownMenuItem(
                value: WorkOrderStatus.completed,
                child: Text('Tamamlandı'),
              ),
              DropdownMenuItem(
                value: WorkOrderStatus.cancelled,
                child: Text('İptal'),
              ),
            ],
            onChanged: (value) =>
                setState(() => _status = value ?? WorkOrderStatus.pending),
          ),
          const SizedBox(height: SyncFlowSpacing.md),
          TextField(
            controller: _notes,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notlar'),
          ),
          const SizedBox(height: SyncFlowSpacing.lg),
          FilledButton(onPressed: _save, child: const Text('Kaydet')),
        ],
      ),
    );
  }
}
