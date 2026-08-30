# SyncFlow

An offline-first field-operations client: work orders are created and edited on
the device, stored in a local SQLite database, and reconciled with the backend
through an incremental sync engine that survives flaky connectivity.

Built with Flutter, Riverpod and Drift on a Clean Architecture split
(`domain` / `data` / `presentation`) with the repository pattern.

## Sync design

- **Incremental delta pull** — the client tracks the server clock from the last
  successful sync and only asks for records changed since then.
- **Conflict resolution** — a pluggable `ConflictResolver`: last-write-wins as
  the baseline, plus business rules that outrank timestamps (a work order closed
  in the field is never reopened by a stale server copy, a record deleted on the
  server but edited locally is escalated for manual review, and notes edited on
  both sides are merged against their common ancestor).
- **Durable outbox** — local writes are queued, coalesced per record, retried
  with exponential backoff (2s → 5min cap) and drained automatically once
  connectivity returns; version conflicts reported by the server are resolved
  with the same resolver rather than dropped.
- **Auth** — OAuth 2.0 / OpenID Connect password grant with refresh handling;
  tokens are kept in the platform keystore, never in plain preferences.

## Roadmap

- [x] Domain layer: entities, repository contracts, conflict and retry policies
- [x] Drift database: work orders, outbox, sync metadata
- [x] Sync engine: delta pull, outbox drain, conflict and retry handling
- [x] OAuth 2.0 / OIDC sign-in with secure token storage
- [x] Riverpod presentation layer: work order list, editor, sync status
- [x] Demo server for end-to-end sync
- [x] GitLab CI pipeline (analyze, test, build) and GitHub Actions mirror

## Development

```
flutter test
dart run build_runner build --delete-conflicting-outputs
```

The demo backend lives in `server/`:

```
cd server \&\& dart run syncflow_server
```

It serves the OAuth token endpoint and the delta/push API on port 8088 with a
demo user (`saha` / `1234`). The app defaults to `http://10.0.2.2:8088`
(Android emulator to host); on a real device pass
`--dart-define=SYNCFLOW_SERVER=http://<host-ip>:8088`.
