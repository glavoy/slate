alter table public.tasks
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists sync_deleted_at timestamptz;

alter table public.notes
  add column if not exists sync_deleted_at timestamptz;

alter table public.journal_entries
  add column if not exists sync_deleted_at timestamptz;

create unique index if not exists journal_entries_user_entry_date_key
  on public.journal_entries (user_id, entry_date);

alter table public.simple_list
  add column if not exists sync_deleted_at timestamptz;

alter table public.tracker_metrics
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists sync_deleted_at timestamptz;

alter table public.tracker_entries
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists sync_deleted_at timestamptz;

create index if not exists tasks_user_updated_idx
  on public.tasks (user_id, updated_at);

create index if not exists notes_user_updated_idx
  on public.notes (user_id, updated_at);

create index if not exists journal_entries_user_updated_idx
  on public.journal_entries (user_id, updated_at);

create index if not exists simple_list_user_updated_idx
  on public.simple_list (user_id, updated_at);

create index if not exists tracker_metrics_user_updated_idx
  on public.tracker_metrics (user_id, updated_at);

create index if not exists tracker_entries_user_updated_idx
  on public.tracker_entries (user_id, updated_at);
