# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run on macOS (primary dev target)
flutter run -d macos

# Run tests
flutter test

# Run a single test file, or a single test by name
flutter test test/sync_two_device_test.dart
flutter test test/sync_two_device_test.dart --plain-name 'conflict'

# Lint
flutter analyze

# After adding any @freezed model or @riverpod provider, regenerate code
dart run build_runner build --delete-conflicting-outputs

# Build release APK
flutter build apk --release

# Build release macOS app
flutter build macos --release
```

Run `dart format .` and `flutter analyze` before committing. Release versioning convention
(user-facing version + always-incrementing build number) is documented in `build.txt`.

`*.freezed.dart` and `*.g.dart` are gitignored — always regenerate locally after model/provider changes.

## Architecture

**Navigation:** No router. `MainScreen` uses an `IndexedStack` (all visible sections stay mounted simultaneously) with adaptive navigation — `NavigationRail` on macOS/desktop, `NavigationBar` on Android. The primary destinations are Tasks, Notes, Tracker, and To Do; Settings is also available from the navigation UI. Section-to-screen names do not all match: Tasks is `HomeScreen` (`lib/screens/home_screen.dart`) and To Do is `TodoScreen`, a thin wrapper around `SimpleListSection` backed by the `simple_list` table.

**State:** Riverpod with code generation (`@riverpod`). The standard pattern throughout is:

```
freezed model  →  Repository (local SQLite CRUD + sync scheduling)  →  @riverpod Notifier  →  Screen
```

**Local-first sync:** All reads and writes go through SQLite (`lib/local/local_database.dart`). Repositories write to SQLite first and mark rows `sync_status = 'pending'`, then call `SyncService.instance.schedulePush()`. `SyncService` (`lib/sync/sync_service.dart`) handles bidirectional push/pull with Supabase; Supabase Realtime is an acceleration path only (foregrounded app only). Providers listen to `SyncService.instance.changes` and call `ref.invalidateSelf()` when it fires — not direct Postgres channel subscriptions.

**Auth & RLS:** Supabase Auth (email + password). Every table has `user_id uuid default auth.uid()` and a `for all` RLS policy. App code never sets `user_id` on insert — Postgres fills it from the JWT.

**Sync conflict resolution:** The server is the single ordering authority: every table has an integer `version` column bumped by a server trigger, and each local row stores the last server version it was based on (`server_version`, NULL = never pushed). Pushes are compare-and-swap (`UPDATE … WHERE version = <baseline>` via `SyncRemote.casUpdate`) so a stale device can never silently overwrite a newer row; pull applies a remote row only when `remote.version > local.server_version`. True concurrent edits are resolved in `SyncService._resolveConflict`: winner by `client_modified_at` (client clock vs client clock), and for **notes** the losing content is preserved as a new "(conflicted copy …)" note — never silently discarded. A pending note edit also wins over a remote delete (the note is resurrected). The pull cursor is a per-table high-water mark (`pull_hwm_<table>` in `sync_meta`) on server `updated_at`. Soft-delete uses `sync_deleted_at` tombstones so deletes propagate. `SyncRemote` (`lib/sync/sync_remote.dart`) abstracts the Supabase calls; `test/sync_two_device_test.dart` runs two simulated devices against a `FakeSyncRemote` — extend those scenarios when touching the engine.

**Settings providers:** All `keepAlive: true` providers (`ThemeNotifier`, `DateFormatNotifier`, `TimeFormatNotifier`, etc.) require an explicit `.init()` call in `main()` before `runApp`. The `ProviderContainer` is initialized there and passed to `UncontrolledProviderScope`.

**Rich text:** `lib/widgets/rich_text_editor.dart` holds the shared `flutter_quill` helpers used by both the Notes editor and the To Do list — `documentFromStoredContent` (tolerates legacy plain-text rows), `serializeDocument`, focus/selection fixups. Use these rather than touching Quill's `Document`/`Delta` APIs directly.

**Sign-out boundary:** All sign-out paths go through `SessionService` (`lib/services/session_service.dart`), which signs out of Supabase, pauses sync without flushing pending writes, and clears cached local data. `app.dart` calls `clearSignedOutData()` as a safety net for externally initiated sign-outs. Never call `client.auth.signOut()` directly.

**Notes editor:** Uses `flutter_quill` for rich-text editing. The note body is stored in the `notes.content` TEXT column as a Quill Delta encoded with `jsonEncode(document.toDelta().toJson())`. The title is a separate plain `TextField` above the editor. Notes have a soft-delete (`deleted_at`) field for trash/restore. For previews / search, use the `noteBodyPreview(String content)` helper in `lib/widgets/note_editor_pane.dart`.

**Multiple FABs:** Because `IndexedStack` keeps all screens alive, every `FloatingActionButton` must have a unique `heroTag` (`'fab_tasks'`, `'fab_notes'`, `'fab_tracker'`, `'fab_tracker_metric'`).

**Task display:** Tasks are grouped by `dueDate` into `DateGroupCard` widgets inside `TaskSection`. Section headers use `SliverPersistentHeaderDelegate`; `shouldRebuild` must compare `theme.colorScheme` or theme changes won't reflect until navigation.

**Recurring tasks:** Completing a recurring task writes `series_id` and inserts the next occurrence in a single SQLite transaction inside `TaskRepository.markDone`. Future occurrences are projected on the calendar view.

**Due task alerts:** In-app only — there are deliberately no macOS/Android/Windows OS notifications. `DueTaskBanner` (`lib/widgets/due_task_banner.dart`) is mounted above the `IndexedStack` in `MainScreen`, so it shows in every section and sits above each screen's own `AppBar`. The "is this task alerting right now?" decision is the pure `shouldAlert` in `lib/services/task_alert_rules.dart` (no DB, no Riverpod) — keep it that way so it stays unit-testable and so an OS notification path could reuse it later. `dueAlertsProvider` derives from `taskListProvider`, which already self-invalidates every minute, so **do not add another timer**; worst-case latency on a due instant or an expiring snooze is ~60s. All-day tasks (no `due_time`) resolve their due instant against a configurable day-start hour via `resolveDueAt` in `lib/utils/date_utils.dart`. Alerts older than `alertBackfillWindow` (24h) are suppressed so a week away from the app doesn't produce a wall of banners.

**Auto-save pattern** (Notes editor and To Do list):

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

`tasks`, `simple_list`, `notes`, `tracker_metrics`, and `tracker_entries`. All have RLS enabled with `auth.uid() = user_id` policies. Realtime is enabled for all tables via the `supabase_realtime` publication. Two server-side triggers per table: `set_updated_at` stamps `updated_at`, `bump_version` increments `version` on every UPDATE — app code never sends either column.

Use the Supabase CLI for all schema changes. Create a timestamped migration with `supabase migration new <description>`, validate it against a fresh local stack with `supabase start` and `supabase db reset`, then deploy it with `supabase db push`. Verify local and remote history with `supabase migration list`. `supabase/slate.json` is the checked-in snapshot of the linked remote public schema; regenerate it after a schema change with `supabase db dump --linked --schema public` and update the snapshot.

The local SQLite schema mirrors these tables and adds sync bookkeeping columns: `sync_status` (`'pending'`/`'synced'`), `client_modified_at`, `last_synced_at`, `sync_deleted_at`, `pending_delete`. See `lib/local/local_database.dart` for the full schema.

`task_alerts` is the one **local-only** table — in-app due alert state (snooze/dismiss) that never leaves the device. It has no Supabase counterpart and is deliberately absent from `_syncedTables`, `SyncService._columnsFor`, and `_boolColumns`; do not add it to any of them. `clearCachedData()` wipes it on sign-out alongside the synced tables. Rows are keyed on the occurrence's resolved due instant (`due_at`), so editing a dismissed task's date or time re-arms its alert rather than staying silently dismissed.

## Other docs in the repo

`AGENTS.md` covers coding style and PR conventions. `README.md` is a user-facing feature
overview and is partly stale — it still describes a Journal section (removed, see
`supabase/migrations/20260904000000_remove_journal_entries.sql`) and repositories talking
directly to Supabase (they are now local-first via SQLite). Trust this file and the code
over `README.md` on architecture.
