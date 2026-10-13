-- Upkeep Ledger schema.
-- One household holds the family's things, tasks and history. Every table is
-- locked by row level security so only members of that household can see or
-- change its rows. Family members join by being invited by email.

create extension if not exists pgcrypto;

-- ---------- Tables ----------

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  created_at timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  display_name text check (char_length(display_name) <= 60),
  email text,
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create table public.household_invites (
  household_id uuid not null references public.households (id) on delete cascade,
  email text not null check (email = lower(email) and position('@' in email) > 1),
  invited_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (household_id, email)
);

create table public.assets (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  kind text not null default 'other',
  detail text not null default '' check (char_length(detail) <= 120),
  unit text not null default '' check (unit in ('', 'mi', 'km', 'hr')),
  meter double precision check (meter >= 0),
  meter_date date,
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (id, household_id)
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  asset_id uuid not null,
  name text not null check (char_length(name) between 1 and 100),
  days integer check (days > 0),
  meter double precision check (meter > 0),
  notes text not null default '' check (char_length(notes) <= 500),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (asset_id, household_id) references public.assets (id, household_id) on delete cascade
);

create table public.logs (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  asset_id uuid not null,
  task_id uuid references public.tasks (id) on delete set null,
  task_name text not null default '',
  done_on date not null,
  meter double precision check (meter >= 0),
  note text not null default '' check (char_length(note) <= 500),
  done_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (asset_id, household_id) references public.assets (id, household_id) on delete cascade
);

create index assets_household_idx on public.assets (household_id);
create index tasks_household_idx on public.tasks (household_id);
create index tasks_asset_idx on public.tasks (asset_id);
create index logs_household_idx on public.logs (household_id);
create index logs_task_idx on public.logs (task_id);
create index logs_asset_idx on public.logs (asset_id);
create index household_members_user_idx on public.household_members (user_id);

-- ---------- Membership helpers ----------

create or replace function public.is_member(hid uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.household_members
    where household_id = hid and user_id = auth.uid()
  );
$$;

create or replace function public.is_owner(hid uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.household_members
    where household_id = hid and user_id = auth.uid() and role = 'owner'
  );
$$;

-- Creates a household with the caller as its owner.
create or replace function public.create_household(p_name text, p_display_name text default null)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  hid uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in first';
  end if;
  insert into public.households (name) values (trim(p_name)) returning id into hid;
  insert into public.household_members (household_id, user_id, role, display_name, email)
  values (hid, auth.uid(), 'owner', nullif(trim(p_display_name), ''), lower(auth.jwt() ->> 'email'));
  return hid;
end;
$$;

-- Adds the caller to every household that invited their (verified) email.
create or replace function public.claim_invites()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  n integer;
  e text := lower(auth.jwt() ->> 'email');
begin
  if auth.uid() is null or e is null then
    return 0;
  end if;
  insert into public.household_members (household_id, user_id, role, email)
  select household_id, auth.uid(), 'member', e
  from public.household_invites
  where email = e
  on conflict do nothing;
  get diagnostics n = row_count;
  delete from public.household_invites where email = e;
  return n;
end;
$$;

revoke execute on function public.is_member(uuid) from public, anon;
revoke execute on function public.is_owner(uuid) from public, anon;
revoke execute on function public.create_household(text, text) from public, anon;
revoke execute on function public.claim_invites() from public, anon;
grant execute on function public.is_member(uuid) to authenticated;
grant execute on function public.is_owner(uuid) to authenticated;
grant execute on function public.create_household(text, text) to authenticated;
grant execute on function public.claim_invites() to authenticated;

-- ---------- Row level security ----------

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.household_invites enable row level security;
alter table public.assets enable row level security;
alter table public.tasks enable row level security;
alter table public.logs enable row level security;

create policy "members read their household" on public.households
  for select to authenticated using (public.is_member(id));
create policy "owners rename their household" on public.households
  for update to authenticated using (public.is_owner(id)) with check (public.is_owner(id));

create policy "members see each other" on public.household_members
  for select to authenticated using (public.is_member(household_id));
create policy "people edit their own name" on public.household_members
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "owners remove members, anyone can leave" on public.household_members
  for delete to authenticated
  using (user_id = auth.uid() or public.is_owner(household_id));

-- Only the display name is editable directly; role and email change through the functions above.
revoke update on public.household_members from authenticated;
grant update (display_name) on public.household_members to authenticated;

create policy "members see invites" on public.household_invites
  for select to authenticated using (public.is_member(household_id));
create policy "owners invite" on public.household_invites
  for insert to authenticated with check (public.is_owner(household_id));
create policy "owners cancel invites" on public.household_invites
  for delete to authenticated using (public.is_owner(household_id));

create policy "members manage things" on public.assets
  for all to authenticated
  using (public.is_member(household_id)) with check (public.is_member(household_id));
create policy "members manage tasks" on public.tasks
  for all to authenticated
  using (public.is_member(household_id)) with check (public.is_member(household_id));
create policy "members manage history" on public.logs
  for all to authenticated
  using (public.is_member(household_id)) with check (public.is_member(household_id));

-- ---------- Live updates ----------

alter publication supabase_realtime add table public.assets, public.tasks, public.logs, public.household_members;
