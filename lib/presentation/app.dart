import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'login_screen.dart';
import 'providers.dart';
import 'theme.dart';
import 'work_orders_screen.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _AuthGate()),
    ],
  );
});

class SyncFlowApp extends ConsumerWidget {
  const SyncFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'SyncFlow',
      theme: SyncFlowTheme.light(),
      darkTheme: SyncFlowTheme.dark(),
      routerConfig: ref.watch(_routerProvider),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(sessionProvider)
        .when(
          data: (session) =>
              session == null ? const LoginScreen() : const WorkOrdersScreen(),
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) =>
              Scaffold(body: Center(child: Text('Oturum okunamadı: $error'))),
        );
  }
}
