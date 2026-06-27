-- Make updated_at server-authoritative.
--
-- Why: the app's incremental sync uses each row's updated_at as the cursor for
-- "what changed since I last pulled". Previously the client supplied updated_at
-- (its own wall clock) on every upsert, so two devices with even slightly
-- different clocks could permanently miss each other's changes. By forcing the
-- server to stamp updated_at = now() on every INSERT/UPDATE, every row carries a
-- single monotonic clock (the database's), which the client uses as a reliable
-- high-water mark.
--
-- This migration is additive and safe: it adds one function and one trigger per
-- table. No columns or rows are altered. Apply it BEFORE (or together with) the
-- client release that stops sending updated_at.

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- One BEFORE INSERT OR UPDATE trigger per synced table.
drop trigger if exists set_updated_at on public.tasks;
create trigger set_updated_at
  before insert or update on public.tasks
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at on public.notes;
create trigger set_updated_at
  before insert or update on public.notes
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at on public.journal_entries;
create trigger set_updated_at
  before insert or update on public.journal_entries
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at on public.simple_list;
create trigger set_updated_at
  before insert or update on public.simple_list
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at on public.tracker_metrics;
create trigger set_updated_at
  before insert or update on public.tracker_metrics
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at on public.tracker_entries;
create trigger set_updated_at
  before insert or update on public.tracker_entries
  for each row execute function public.set_updated_at();
