# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run on macOS (primary dev target)
flutter run -d macos

# After adding any @freezed model or @riverpod provider, regenerate code
dart run build_runner build --delete-conflicting-outputs

# Lint
flutter analyze

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
freezed model  →  Repository (raw Supabase CRUD)  →  @riverpod Notifier  →  Screen
```

Every `AsyncNotifier` subscribes to a `PostgresChanges` channel in `build()` and calls `ref.onDispose(channel.unsubscribe)`.

**Auth & RLS:** Supabase Auth (email + password). Every table has `user_id uuid default auth.uid()` and a `for all` RLS policy. App code never sets `user_id` on insert — Postgres fills it from the JWT.

**Realtime writes (Simple List):** The scratchpad uses `state = AsyncValue.data(SimpleList.fromJson(payload.newRecord))` in the Realtime callback instead of `ref.invalidateSelf()`, to avoid a loading flash that breaks the typing experience. All other providers use `ref.invalidateSelf()`.

**Multiple FABs:** Because `IndexedStack` keeps all screens alive, every `FloatingActionButton` must have a unique `heroTag` (`'fab_tasks'`, `'fab_notes'`, `'fab_tracker'`, `'fab_tracker_metric'`).

**Task display:** Tasks are grouped by `dueDate` into `DateGroupCard` widgets inside `TaskSection`. The `TaskCard` widget is a plain row (no card chrome of its own) that sits inside a date group. Section headers use `SliverPersistentHeaderDelegate`; `shouldRebuild` must compare `theme.colorScheme` or theme changes won't reflect until navigation.

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

Always call the flush synchronously in `dispose()` to avoid losing the last edit.

## Credentials

`lib/env/env.dart` is gitignored. Create it locally:

```dart
abstract class Env {
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
}
```

## Supabase tables

`tasks`, `simple_list`, `notes`, `journal_entries`, `tracker_metrics`, `tracker_entries`. All have RLS enabled with `auth.uid() = user_id` policies. Realtime is enabled for all tables via the `supabase_realtime` publication.
