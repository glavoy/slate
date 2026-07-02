-- Add server-authoritative row versioning for conflict-safe sync.
--
-- Why: the previous sync engine pushed whole rows with a blind upsert and
-- decided conflicts by comparing a device's wall clock against the server's
-- clock. A device holding a stale pending edit could silently overwrite a newer
-- row, and clock skew could make one device reject the other's changes.
--
-- This migration makes the server the single ordering authority:
--   * version            bigint, starts at 1, bumped by trigger on every UPDATE.
--                        Clients never send it. Pushes become compare-and-swap
--                        (UPDATE ... WHERE version = <last seen>), so a stale
--                        push can never overwrite a newer row — it surfaces as a
--                        conflict the client resolves explicitly.
--   * client_modified_at timestamptz, supplied by clients. Only used to pick a
--                        winner between two genuinely concurrent edits
--                        (client clock vs client clock — never client vs server).
--
-- Additive and safe: no existing columns or rows are altered. Old app builds
-- keep working (they simply ignore both columns). Apply BEFORE running the
-- client release that uses compare-and-swap pushes.

alter table public.tasks           add column if not exists version bigint not null default 1;
alter table public.notes           add column if not exists version bigint not null default 1;
alter table public.journal_entries add column if not exists version bigint not null default 1;
alter table public.simple_list     add column if not exists version bigint not null default 1;
alter table public.tracker_metrics add column if not exists version bigint not null default 1;
alter table public.tracker_entries add column if not exists version bigint not null default 1;

alter table public.tasks           add column if not exists client_modified_at timestamptz;
alter table public.notes           add column if not exists client_modified_at timestamptz;
alter table public.journal_entries add column if not exists client_modified_at timestamptz;
alter table public.simple_list     add column if not exists client_modified_at timestamptz;
alter table public.tracker_metrics add column if not exists client_modified_at timestamptz;
alter table public.tracker_entries add column if not exists client_modified_at timestamptz;

create or replace function public.bump_version()
returns trigger
language plpgsql
as $$
begin
  new.version := coalesce(old.version, 0) + 1;
  return new;
end;
$$;

-- One BEFORE UPDATE trigger per synced table (INSERT keeps the default of 1).
drop trigger if exists bump_version on public.tasks;
create trigger bump_version
  before update on public.tasks
  for each row execute function public.bump_version();

drop trigger if exists bump_version on public.notes;
create trigger bump_version
  before update on public.notes
  for each row execute function public.bump_version();

drop trigger if exists bump_version on public.journal_entries;
create trigger bump_version
  before update on public.journal_entries
  for each row execute function public.bump_version();

drop trigger if exists bump_version on public.simple_list;
create trigger bump_version
  before update on public.simple_list
  for each row execute function public.bump_version();

drop trigger if exists bump_version on public.tracker_metrics;
create trigger bump_version
  before update on public.tracker_metrics
  for each row execute function public.bump_version();

drop trigger if exists bump_version on public.tracker_entries;
create trigger bump_version
  before update on public.tracker_entries
  for each row execute function public.bump_version();
