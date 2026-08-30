import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/auth/auth_interceptor.dart';
import '../data/auth/oauth_repository.dart';
import '../data/auth/token_storage.dart';
import '../data/local/database.dart';
import '../data/remote/sync_api.dart';
import '../data/repositories/work_order_repository_impl.dart';
import '../domain/auth/auth_session.dart';
import '../domain/entities/work_order.dart';
import '../domain/repositories/work_order_repository.dart';

const serverBaseUrl = String.fromEnvironment(
  'SYNCFLOW_SERVER',
  defaultValue: 'http://10.0.2.2:8088',
);

final databaseProvider = Provider<SyncDatabase>((ref) {
  final database = SyncDatabase();
  ref.onDispose(database.close);
  return database;
});

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => const SecureTokenStorage(),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => OAuthRepository(
    dio: Dio(BaseOptions(baseUrl: serverBaseUrl)),
    storage: ref.watch(tokenStorageProvider),
  ),
);

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: serverBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  dio.interceptors.add(
    AuthInterceptor(auth: ref.watch(authRepositoryProvider)),
  );
  return dio;
});

final workOrderRepositoryProvider = Provider<WorkOrderRepository>(
  (ref) => WorkOrderRepositoryImpl(
    database: ref.watch(databaseProvider),
    api: HttpSyncApi(ref.watch(dioProvider)),
  ),
);

final sessionProvider = FutureProvider<AuthSession?>(
  (ref) => ref.watch(authRepositoryProvider).currentSession(),
);

final workOrdersProvider = StreamProvider<List<WorkOrder>>(
  (ref) => ref.watch(workOrderRepositoryProvider).watchAll(),
);

final pendingCountProvider = StreamProvider<int>((ref) async* {
  final database = ref.watch(databaseProvider);
  yield await database.pendingCount();
  await for (final _ in database.watchWorkOrders()) {
    yield await database.pendingCount();
  }
});

final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
  yield online(await connectivity.checkConnectivity());
  await for (final results in connectivity.onConnectivityChanged) {
    yield online(results);
  }
});

class SyncController extends AsyncNotifier<SyncSummary> {
  @override
  Future<SyncSummary> build() async {
    ref.listen(connectivityProvider, (previous, next) {
      final cameOnline =
          (previous?.value ?? false) == false && (next.value ?? false);
      if (cameOnline) run();
    });
    return const SyncSummary.empty();
  }

  Future<void> run() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(workOrderRepositoryProvider).sync(),
    );
  }
}

final syncControllerProvider =
    AsyncNotifierProvider<SyncController, SyncSummary>(SyncController.new);
