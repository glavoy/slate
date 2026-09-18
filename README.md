# Slate

A personal productivity app for macOS, Windows, and Android — tasks, notes, a to-do list, and a
metrics tracker — built with Flutter and Supabase, local-first with offline support.

## Features

### Tasks
- Title, due date, due time, and notes.
- **List view** groups active items into Overdue and Upcoming, with a separate Completed footer (undo or permanently delete).
- **Calendar view** (toggle in-page) shows a weekly or monthly grid; pick a day to see and manage that day's tasks.
- **Recurring tasks** — daily, weekly, monthly, yearly. Completing one occurrence schedules the next; future occurrences are projected on the calendar.
- New tasks default their due time to the next full hour.
- Right-click (desktop) opens an edit/delete menu; tap (mobile) opens the task, swipe to delete. Edit or delete a single occurrence or all remaining in a series.
- **In-app due task alerts** — a banner appears when a task comes due; snooze or dismiss it. All-day tasks (no due time) alert at a configurable hour. There are no OS-level push notifications.

### Notes
- Rich-text title + body editor (bold, italics, lists, etc.).
- Sorted by most recently edited, with search across title and body.
- Debounced auto-save while you type.
- Soft-delete with a Trash view to restore or permanently delete.

### To Do
- A single running rich-text checklist, separate from Tasks — a scratchpad-style list for quick items rather than dated tasks.

### Tracker
- Define custom metrics (name + optional unit), log values, and view a sparkline and stats for recent history.
- Can be hidden from the navigation in Settings if unused.

### Settings
- Light / dark mode.
- Configurable date format (e.g. `Mon Jan 5`, `Jan 5, 2026`, `5/1/2026`, `1/5/2026`, `2026-01-05`) and time format (12-hour / 24-hour).
- Show/hide completed tasks and the Tracker section; enable/disable due task alerts and set the all-day alert time.
- Account info and sign-out.

### Across the app
- **Email + password authentication** with per-user data isolation (Postgres RLS on every table).
- **Local-first with sync** — all reads and writes go through a local SQLite database first, so the app is fully usable offline; changes sync to Supabase in the background, with Realtime used as an acceleration path while the app is in the foreground. Conflicting edits are reconciled by last-modified time, and conflicting note edits are preserved as a "conflicted copy" rather than silently dropped.
- **Adaptive navigation** — `NavigationRail` on desktop (macOS/Windows/Linux), `NavigationBar` on mobile, across Tasks, Notes, Tracker, and To Do.

## Tech Stack

| Layer               | Technology                              |
| ------------------- | ---------------------------------------- |
| Framework           | Flutter (macOS, Windows, Android)        |
| Local database      | SQLite (local-first reads/writes)        |
| Backend / database  | Supabase (PostgreSQL with RLS)           |
| Authentication      | Supabase Auth (email + password)         |
| Sync                | Custom bidirectional push/pull, with Supabase Realtime as a foreground acceleration path |
| State management    | Riverpod (with code generation)          |
| Data models         | freezed + json_serializable              |
| Local preferences   | shared_preferences                       |
| Rich text editing   | flutter_quill                            |
| Calendar UI         | table_calendar                           |

## Architecture

The app follows a local-first, thin-layer pattern, repeated for every section:

```
freezed model  →  Repository (local SQLite CRUD + sync scheduling)  →  @riverpod Notifier  →  Screen / Widget
```

Repositories write to SQLite first and mark rows pending sync; a sync service then pushes and pulls
changes with Supabase in the background. Providers listen for sync updates and refresh automatically,
so every screen reflects both local edits and remote changes without a refresh button — and the app
keeps working when offline.

Authentication is enforced at the database — every table has `user_id uuid default auth.uid()` and a `for all` RLS policy. App code never sets `user_id` on insert; Postgres fills it from the JWT.
