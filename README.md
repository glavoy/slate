# Slate

A personal productivity app for macOS and Android — tasks, notes, journal, and tracker — built with Flutter and Supabase.

## Features

### Tasks
- Title, due date, due time, and notes.
- **List view** groups active items into Overdue and Upcoming, with a separate Completed footer (undo or permanently delete).
- **Calendar view** (toggle in-page) shows a weekly or monthly grid; pick a day to see and manage that day's tasks.
- **Recurring tasks** — daily, weekly, monthly, yearly. Completing one occurrence schedules the next; future occurrences are projected on the calendar.
- **Simple List** — a pinned scratchpad shared across both views with bullet-prefix auto-formatting.
- Right-click (desktop) or tap (mobile) to edit; swipe to delete; edit a single occurrence or all remaining in a series.

### Notes
- Free-form title + body, sorted by most recently edited.
- Debounced auto-save while you type.

### Journal
- One entry per day. Today's entry pinned at the top with an always-open editor; older entries collapse below.

### Tracker
- Define custom metrics (name + optional unit), log values, and view a sparkline of recent history.

### Settings
- Light / dark mode.
- Configurable date format (e.g. `Mon Jan 5`, `Jan 5, 2026`, `5/1/2026`, `1/5/2026`, `2026-01-05`) and time format (12-hour / 24-hour).
- Account info and sign-out.

### Across the app
- **Email + password authentication** with per-user data isolation (Postgres RLS on every table).
- **Real-time sync** — edits made on one device appear on others within seconds.
- **Adaptive navigation** — `NavigationRail` on desktop, `NavigationBar` on mobile.

## Tech Stack

| Layer              | Technology                              |
| ------------------ | --------------------------------------- |
| Framework          | Flutter (macOS + Android)               |
| Backend / database | Supabase (PostgreSQL with RLS)          |
| Authentication     | Supabase Auth (email + password)        |
| Real-time sync     | Supabase Realtime (PostgresChanges)     |
| State management   | Riverpod (with code generation)         |
| Data models        | freezed + json_serializable             |
| Local preferences  | shared_preferences                      |
| Calendar UI        | table_calendar                          |

## Architecture

The app follows a thin-layer pattern, repeated for every section:

```
freezed model  →  Repository (Supabase CRUD)  →  @riverpod Notifier  →  Screen / Widget
```

Each `AsyncNotifier` opens a Postgres-changes channel in `build()` and disposes it on tear-down, so every screen reflects remote edits without a refresh button.

Authentication is enforced at the database — every table has `user_id uuid default auth.uid()` and a `for all` RLS policy. App code never sets `user_id` on insert; Postgres fills it from the JWT.
