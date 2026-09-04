-- Baseline for a new Slate database. The production database predates CLI
-- migrations, so this version is recorded as already applied there.

do $$ begin
  create type public.recurrence_type as enum (
    'none', 'daily', 'weekly', 'monthly', 'yearly'
  );
exception when duplicate_object then null;
end $$;

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) > 0),
  due_date date not null,
  notes text,
  is_done boolean not null default false,
  recurrence public.recurrence_type not null default 'none',
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  series_id uuid,
  due_time time,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  updated_at timestamptz not null default now(),
  sync_deleted_at timestamptz,
  version bigint not null default 1,
  client_modified_at timestamptz
);

create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null default '',
  content text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  pinned boolean not null default false,
  deleted_at timestamptz,
  sync_deleted_at timestamptz,
  version bigint not null default 1,
  client_modified_at timestamptz
);

create table if not exists public.simple_list (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  content text not null default '• ',
  updated_at timestamptz not null default now(),
  sync_deleted_at timestamptz,
  version bigint not null default 1,
  client_modified_at timestamptz
);

create table if not exists public.tracker_metrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  unit text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sync_deleted_at timestamptz,
  version bigint not null default 1,
  client_modified_at timestamptz
);

create table if not exists public.tracker_entries (
  id uuid primary key default gen_random_uuid(),
  metric_id uuid not null references public.tracker_metrics(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  value numeric not null,
  recorded_at timestamptz not null default now(),
  note text,
  updated_at timestamptz not null default now(),
  sync_deleted_at timestamptz,
  version bigint not null default 1,
  client_modified_at timestamptz
);

create index if not exists tasks_series_id_idx on public.tasks(series_id);
create index if not exists tasks_user_id_idx on public.tasks(user_id);
create index if not exists tasks_user_updated_idx on public.tasks(user_id, updated_at);
create index if not exists notes_updated_at_idx on public.notes(updated_at desc);
create index if not exists notes_user_id_idx on public.notes(user_id);
create index if not exists notes_user_updated_idx on public.notes(user_id, updated_at);
create index if not exists simple_list_user_updated_idx on public.simple_list(user_id, updated_at);
create index if not exists tracker_metrics_user_idx on public.tracker_metrics(user_id);
create index if not exists tracker_metrics_user_updated_idx on public.tracker_metrics(user_id, updated_at);
create index if not exists tracker_entries_metric_idx on public.tracker_entries(metric_id, recorded_at desc);
create index if not exists tracker_entries_user_updated_idx on public.tracker_entries(user_id, updated_at);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.bump_version()
returns trigger language plpgsql as $$
begin
  new.version := coalesce(old.version, 0) + 1;
  return new;
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'tasks', 'notes', 'simple_list', 'tracker_metrics', 'tracker_entries'
  ] loop
    execute format('drop trigger if exists set_updated_at on public.%I', table_name);
    execute format(
      'create trigger set_updated_at before insert or update on public.%I '
      'for each row execute function public.set_updated_at()',
      table_name
    );
    execute format('drop trigger if exists bump_version on public.%I', table_name);
    execute format(
      'create trigger bump_version before update on public.%I '
      'for each row execute function public.bump_version()',
      table_name
    );
  end loop;
end;
$$;

alter table public.tasks enable row level security;
alter table public.notes enable row level security;
alter table public.simple_list enable row level security;
alter table public.tracker_metrics enable row level security;
alter table public.tracker_entries enable row level security;

drop policy if exists "Users access own tasks" on public.tasks;
create policy "Users access own tasks" on public.tasks
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users access own notes" on public.notes;
create policy "Users access own notes" on public.notes
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users access own simple list" on public.simple_list;
create policy "Users access own simple list" on public.simple_list
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users access own metrics" on public.tracker_metrics;
create policy "Users access own metrics" on public.tracker_metrics
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users access own entries" on public.tracker_entries;
create policy "Users access own entries" on public.tracker_entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'tasks', 'notes', 'simple_list', 'tracker_metrics', 'tracker_entries'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    end if;
  end loop;
end;
$$;
