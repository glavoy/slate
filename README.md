# Slate

A personal task manager for macOS and Android, built with Flutter and Supabase.

## Features

- **Tasks** — title, due date, due time, and notes
- **Overdue & upcoming** — tasks are automatically grouped and overdue items are highlighted
- **Recurring tasks** — daily, weekly, monthly, or yearly recurrence; each completion generates the next occurrence automatically
- **Edit & delete options** — edit or delete a single task or all remaining tasks in a recurring series
- **Completed tasks** — mark tasks done, undo mistakes, or permanently delete completed tasks
- **Calendar view** — weekly and monthly views with projected recurring task occurrences
- **Real-time sync** — changes on any device appear instantly on all others via Supabase Realtime
- **Light / dark mode** — manual toggle, persisted across sessions

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter |
| Backend / database | Supabase (PostgreSQL) |
| Real-time sync | Supabase Realtime |
| State management | Riverpod |
| Data models | freezed + json_serializable |
| Calendar | table_calendar |

## Platforms

- macOS (desktop)
- Android

## Setup

### 1. Supabase

Create a free project at [supabase.com](https://supabase.com) and run the following SQL:

```sql
create type recurrence_type as enum ('none', 'daily', 'weekly', 'monthly', 'yearly');

create table public.tasks (
  id           uuid primary key default gen_random_uuid(),
  title        text not null check (char_length(title) > 0),
  due_date     date not null,
  due_time     time,
  notes        text,
  is_done      boolean not null default false,
  recurrence   recurrence_type not null default 'none',
  series_id    uuid,
  created_at   timestamptz not null default now(),
  completed_at timestamptz
);

create index tasks_due_date_idx on public.tasks (due_date);
create index tasks_series_id_idx on public.tasks (series_id);
```

Enable Realtime for the `tasks` table via **Database → Publications → supabase_realtime**.

### 2. Credentials

Create `lib/env/env.dart`:

```dart
abstract class Env {
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
}
```

### 3. Install dependencies & generate code

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### 4. Run

```bash
# macOS
flutter run -d macos

# Android
flutter run -d <device-id>
```

## Project Structure

```
lib/
  main.dart                  # Entry point, Supabase initialisation
  app.dart                   # MaterialApp, theming
  env/
    env.dart                 # Credentials (gitignored)
  models/
    task.dart                # Freezed Task model
    recurrence.dart          # RecurrenceType enum
    calendar_entry.dart      # Calendar occurrence model
  repositories/
    task_repository.dart     # All Supabase queries
  providers/
    supabase_provider.dart   # SupabaseClient provider
    task_providers.dart      # Task state + Realtime subscription
    theme_provider.dart      # Light/dark mode state
    calendar_providers.dart  # Calendar occurrence map
  screens/
    main_screen.dart         # Bottom navigation wrapper
    home_screen.dart         # Tasks list (overdue + upcoming + completed)
    calendar_screen.dart     # Calendar view
  widgets/
    task_card.dart           # Task row with right-click / swipe actions
    task_section.dart        # Sliver section for task lists
    completed_task_card.dart # Completed task row with undo/delete
    add_edit_task_sheet.dart # Bottom sheet for create/edit
  utils/
    date_utils.dart          # Date/time formatting and recurrence logic
    calendar_utils.dart      # Occurrence map builder
```
