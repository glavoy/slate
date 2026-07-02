# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run on macOS (primary dev target)
flutter run -d macos

# Run tests
flutter test

# Lint
flutter analyze

# After adding any @freezed model or @riverpod provider, regenerate code
dart run build_runner build --delete-conflicting-outputs

# Build release APK
flutter build apk --release

# Build release macOS app
flutter build macos --release
```

`*.freezed.dart` and `*.g.dart` are gitignored — always regenerate locally after model/provider changes.

## Architecture

**Navigation:** No router. `MainScreen` uses an `IndexedStack` (all 5 screens stay mounted simultaneously) with adaptive navigation — `NavigationRail` on macOS/desktop, `NavigationBar` on Android. Each section is a self-contained `Scaffold` with its own `AppBar` (theme toggle + sign-out).

**State:** Riverpod with code generation (`@riverpod`). The standard pattern throughout is:

```
freezed model  →  Repository (local SQLite CRUD + sync scheduling)  →  @riverpod Notifier  →  Screen
```

**Local-first sync:** All reads and writes go through SQLite (`lib/local/local_database.dart`). Repositories write to SQLite first and mark rows `sync_status = 'pending'`, then call `SyncService.instance.schedulePush()`. `SyncService` (`lib/sync/sync_service.dart`) handles bidirectional push/pull with Supabase; Supabase Realtime is an acceleration path only (foregrounded app only). Providers listen to `SyncService.instance.changes` and call `ref.invalidateSelf()` when it fires — not direct Postgres channel subscriptions.

**Auth & RLS:** Supabase Auth (email + password). Every table has `user_id uuid default auth.uid()` and a `for all` RLS policy. App code never sets `user_id` on insert — Postgres fills it from the JWT.

**Sync conflict resolution:** The server is the single ordering authority: every table has an integer `version` column bumped by a server trigger, and each local row stores the last server version it was based on (`server_version`, NULL = never pushed). Pushes are compare-and-swap (`UPDATE … WHERE version = <baseline>` via `SyncRemote.casUpdate`) so a stale device can never silently overwrite a newer row; pull applies a remote row only when `remote.version > local.server_version`. True concurrent edits are resolved in `SyncService._resolveConflict`: winner by `client_modified_at` (client clock vs client clock), and for **notes** the losing content is preserved as a new "(conflicted copy …)" note — never silently discarded. A pending note edit also wins over a remote delete (the note is resurrected). The pull cursor is a per-table high-water mark (`pull_hwm_<table>` in `sync_meta`) on server `updated_at`. Soft-delete uses `sync_deleted_at` tombstones so deletes propagate. `SyncRemote` (`lib/sync/sync_remote.dart`) abstracts the Supabase calls; `test/sync_two_device_test.dart` runs two simulated devices against a `FakeSyncRemote` — extend those scenarios when touching the engine.

**Settings providers:** All `keepAlive: true` providers (`ThemeNotifier`, `DateFormatNotifier`, `TimeFormatNotifier`, etc.) require an explicit `.init()` call in `main()` before `runApp`. The `ProviderContainer` is initialized there and passed to `UncontrolledProviderScope`.

**Notes editor:** Uses `flutter_quill` for rich-text editing. The note body is stored in the `notes.content` TEXT column as a Quill Delta encoded with `jsonEncode(document.toDelta().toJson())`. The title is a separate plain `TextField` above the editor. Notes have a soft-delete (`deleted_at`) field for trash/restore. For previews / search, use the `noteBodyPreview(String content)` helper in `lib/widgets/note_editor_pane.dart`.

**Multiple FABs:** Because `IndexedStack` keeps all screens alive, every `FloatingActionButton` must have a unique `heroTag` (`'fab_tasks'`, `'fab_notes'`, `'fab_tracker'`, `'fab_tracker_metric'`).

**Task display:** Tasks are grouped by `dueDate` into `DateGroupCard` widgets inside `TaskSection`. Section headers use `SliverPersistentHeaderDelegate`; `shouldRebuild` must compare `theme.colorScheme` or theme changes won't reflect until navigation.

**Recurring tasks:** Completing a recurring task writes `series_id` and inserts the next occurrence in a single SQLite transaction inside `TaskRepository.markDone`. Future occurrences are projected on the calendar view.

**Auto-save pattern** (Notes editor, Journal, Simple List):

```dart
Timer? _debounce;
void _onChanged(String value) {
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 1200), () {
    // call provider save
  });
}
```

Always flush synchronously in `dispose()` to avoid losing the last edit.

## Credentials

`lib/env/env.dart` is gitignored. Create it locally:

```dart
abstract class Env {
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
}
```

## Supabase tables

`tasks`, `simple_list`, `notes`, `journal_entries`, `tracker_metrics`, `tracker_entries`. All have RLS enabled with `auth.uid() = user_id` policies. Realtime is enabled for all tables via the `supabase_realtime` publication. Two server-side triggers per table: `set_updated_at` stamps `updated_at`, `bump_version` increments `version` on every UPDATE — app code never sends either column. Schema changes go in `supabase/migrations/` and must be applied manually (SQL editor / CLI); keep `supabase/slate.json` in sync.

The local SQLite schema mirrors these tables and adds sync bookkeeping columns: `sync_status` (`'pending'`/`'synced'`), `client_modified_at`, `last_synced_at`, `sync_deleted_at`, `pending_delete`. See `lib/local/local_database.dart` for the full schema.
