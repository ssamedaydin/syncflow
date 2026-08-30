import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/entities/work_order.dart';
import 'providers.dart';
import 'theme.dart';
import 'work_order_editor.dart';

class WorkOrdersScreen extends ConsumerWidget {
  const WorkOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(workOrdersProvider);
    final syncState = ref.watch(syncControllerProvider);

    ref.listen(syncControllerProvider, (previous, next) {
      final summary = next.value;
      if (next.isLoading || summary == null) return;
      final message = summary.hasChanges
          ? '${summary.pulled} kayıt alındı, ${summary.pushed} kayıt gönderildi'
          : 'Her şey güncel';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('İş emirleri'),
        actions: [
          IconButton(
            tooltip: 'Çıkış yap',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
              ref.invalidate(sessionProvider);
            },
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(36),
          child: _SyncStatusBar(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'İş emri ekle',
        onPressed: () => showWorkOrderEditor(context, ref),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncControllerProvider.notifier).run(),
        child: orders.when(
          data: (items) => items.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('Henüz iş emri yok')),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(SyncFlowSpacing.sm),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _WorkOrderTile(order: items[index]),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('Kayıtlar okunamadı: $error')),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(SyncFlowSpacing.md),
        child: FilledButton.icon(
          onPressed: syncState.isLoading
              ? null
              : () => ref.read(syncControllerProvider.notifier).run(),
          icon: syncState.isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: Text(syncState.isLoading ? 'Eşitleniyor…' : 'Şimdi eşitle'),
        ),
      ),
    );
  }
}

class _SyncStatusBar extends ConsumerWidget {
  const _SyncStatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final online = ref.watch(connectivityProvider).value ?? true;
    final pending = ref.watch(pendingCountProvider).value ?? 0;
    final background = online
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.errorContainer;
    final foreground = online
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onErrorContainer;

    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SyncFlowSpacing.md,
          vertical: SyncFlowSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              size: 18,
              color: foreground,
            ),
            const SizedBox(width: SyncFlowSpacing.sm),
            Expanded(
              child: Text(
                online ? 'Çevrimiçi' : 'Çevrimdışı — değişiklikler kuyrukta',
                style: theme.textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ),
            if (pending > 0)
              Text(
                '$pending bekleyen',
                style: theme.textTheme.bodySmall?.copyWith(color: foreground),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkOrderTile extends ConsumerWidget {
  const _WorkOrderTile({required this.order});

  final WorkOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: () => showWorkOrderEditor(context, ref, existing: order),
        leading: Icon(
          _statusIcon(order.status),
          color: theme.colorScheme.primary,
        ),
        title: Text(order.title),
        subtitle: Text('${order.customer} · ${_statusLabel(order.status)}'),
        trailing: _SyncBadge(state: order.syncState),
      ),
    );
  }

  static IconData _statusIcon(WorkOrderStatus status) => switch (status) {
    WorkOrderStatus.pending => Icons.schedule,
    WorkOrderStatus.inProgress => Icons.play_circle_outline,
    WorkOrderStatus.completed => Icons.check_circle_outline,
    WorkOrderStatus.cancelled => Icons.cancel_outlined,
  };

  static String _statusLabel(WorkOrderStatus status) => switch (status) {
    WorkOrderStatus.pending => 'Bekliyor',
    WorkOrderStatus.inProgress => 'Devam ediyor',
    WorkOrderStatus.completed => 'Tamamlandı',
    WorkOrderStatus.cancelled => 'İptal',
  };
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.state});

  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, tooltip) = switch (state) {
      SyncState.synced => (Icons.cloud_done, scheme.primary, 'Eşitlendi'),
      SyncState.pendingUpload => (
        Icons.cloud_upload_outlined,
        scheme.outline,
        'Gönderim bekliyor',
      ),
      SyncState.conflicted => (
        Icons.error_outline,
        scheme.error,
        'Çakışma: elle çözüm gerekiyor',
      ),
    };
    return Tooltip(
      message: tooltip,
      child: Icon(icon, color: color, size: 20),
    );
  }
}
