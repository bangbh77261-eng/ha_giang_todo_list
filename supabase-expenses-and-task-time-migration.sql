-- Run this in the Supabase SQL Editor to add estimated expenses, optional task times, and live device sessions.

grant usage on schema public to anon, authenticated;

create table if not exists public.device_sessions (
  id uuid primary key,
  device_cookie text not null,
  user_name text not null,
  device_name text not null,
  logged_in_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  logged_out_at timestamptz
);

alter table public.device_sessions enable row level security;

drop policy if exists "Anyone can read device sessions" on public.device_sessions;
create policy "Anyone can read device sessions"
  on public.device_sessions
  for select
  to anon, authenticated
  using (true);

grant select on public.device_sessions to anon, authenticated;

-- Keep one current row per browser/device; old duplicate login rows are folded into the latest one.
with ranked_sessions as (
  select id,
         row_number() over (
           partition by device_cookie
           order by logged_in_at desc, last_seen_at desc, id desc
         ) as rn
  from public.device_sessions
)
delete from public.device_sessions as ds
using ranked_sessions as ranked
where ds.id = ranked.id and ranked.rn > 1;

create unique index if not exists device_sessions_device_cookie_uidx
  on public.device_sessions (device_cookie);

do $$
begin
  if not exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    create publication supabase_realtime for table public.device_sessions;
  elsif not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'device_sessions'
  ) and not exists (
    select 1 from pg_publication
    where pubname = 'supabase_realtime' and puballtables
  ) then
    alter publication supabase_realtime add table public.device_sessions;
  end if;
end;
$$;

create table if not exists public.assigned_tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(btrim(title)) > 0),
  assignee text not null check (length(btrim(assignee)) > 0),
  description text not null default '',
  status text not null default 'Chưa bắt đầu',
  due_date date,
  due_time time without time zone,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.assigned_tasks
  add column if not exists due_time time without time zone;

alter table public.assigned_tasks enable row level security;

drop policy if exists "Anyone can read assigned tasks" on public.assigned_tasks;
create policy "Anyone can read assigned tasks"
  on public.assigned_tasks
  for select
  to anon, authenticated
  using (true);

grant select on public.assigned_tasks to anon, authenticated;

create table if not exists public.trip_participants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint trip_participants_name_nonempty check (length(btrim(name)) > 0),
  constraint trip_participants_name_unique unique (name)
);

alter table public.trip_participants enable row level security;

drop policy if exists "Anyone can read trip participants" on public.trip_participants;
create policy "Anyone can read trip participants"
  on public.trip_participants
  for select
  to anon, authenticated
  using (true);

grant select on public.trip_participants to anon, authenticated;

insert into public.trip_participants (name, sort_order)
values
  ('Bá Huy', 1), ('Thanh Thanh', 2), ('Đắc Thành', 3), ('Ninh Giang', 4),
  ('Linh Su', 5), ('Linh 8', 6), ('Anh Trong', 7), ('Kim Luyên', 8),
  ('Hải Bằng', 9), ('Khách Mời', 10)
on conflict (name) do update set sort_order = excluded.sort_order;

drop function if exists public.register_device_session(text, uuid, text, text, text);

create or replace function public.register_device_session(
  p_password text,
  p_session_id uuid,
  p_device_id text,
  p_user_name text,
  p_device_name text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not coalesce(public.check_edit_password(p_password), false) then
    raise exception 'Mật khẩu không đúng.' using errcode = '28000';
  end if;
  if p_session_id is null or nullif(btrim(p_device_id), '') is null
     or nullif(btrim(p_user_name), '') is null or nullif(btrim(p_device_name), '') is null then
    raise exception 'Thông tin đăng nhập thiết bị chưa đầy đủ.' using errcode = '22023';
  end if;

  insert into public.device_sessions (id, device_cookie, user_name, device_name)
  values (p_session_id, btrim(p_device_id), btrim(p_user_name), btrim(p_device_name))
  on conflict (device_cookie) do update
  set id = excluded.id,
      user_name = excluded.user_name,
      device_name = excluded.device_name,
      logged_in_at = now(),
      last_seen_at = now(),
      logged_out_at = null;
end;
$$;

create or replace function public.touch_device_session(p_session_id uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.device_sessions
  set last_seen_at = now()
  where id = p_session_id and logged_out_at is null;
$$;

create or replace function public.close_device_session(p_session_id uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.device_sessions
  set logged_out_at = coalesce(logged_out_at, now()),
      last_seen_at = now()
  where id = p_session_id;
$$;

create table if not exists public.estimated_expenses (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(btrim(title)) > 0),
  amount numeric(14, 0) not null check (amount >= 0),
  note text not null default '',
  image_url text,
  paid_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.estimated_expenses add column if not exists paid_by text;

alter table public.estimated_expenses enable row level security;

drop policy if exists "Anyone can read estimated expenses" on public.estimated_expenses;
create policy "Anyone can read estimated expenses"
  on public.estimated_expenses
  for select
  to anon, authenticated
  using (true);

grant select on public.estimated_expenses to anon, authenticated;

drop function if exists public.save_estimated_expense(text, uuid, text, numeric, text, text);

create or replace function public.save_assigned_task_with_time(
  p_password text,
  p_id uuid,
  p_title text,
  p_assignee text,
  p_description text,
  p_status text,
  p_due_date date,
  p_due_time time without time zone
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if not coalesce(public.check_edit_password(p_password), false) then
    raise exception 'Mật khẩu không đúng.' using errcode = '28000';
  end if;
  if nullif(btrim(p_title), '') is null or nullif(btrim(p_assignee), '') is null then
    raise exception 'Tên công việc và người phụ trách là bắt buộc.' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.assigned_tasks (title, assignee, description, status, due_date, due_time)
    values (btrim(p_title), btrim(p_assignee), coalesce(p_description, ''), coalesce(p_status, 'Chưa bắt đầu'), p_due_date, p_due_time)
    returning id into v_id;
  else
    update public.assigned_tasks
    set title = btrim(p_title),
        assignee = btrim(p_assignee),
        description = coalesce(p_description, ''),
        status = coalesce(p_status, 'Chưa bắt đầu'),
        due_date = p_due_date,
        due_time = p_due_time
    where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'Không tìm thấy công việc cần sửa.' using errcode = 'P0002';
    end if;
  end if;
end;
$$;

create or replace function public.save_estimated_expense(
  p_password text,
  p_id uuid,
  p_title text,
  p_amount numeric,
  p_note text,
  p_image_url text,
  p_paid_by text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if not coalesce(public.check_edit_password(p_password), false) then
    raise exception 'Mật khẩu không đúng.' using errcode = '28000';
  end if;
  if nullif(btrim(p_title), '') is null then
    raise exception 'Tên khoản chi là bắt buộc.' using errcode = '22023';
  end if;
  if p_amount is null or p_amount < 0 then
    raise exception 'Số tiền phải bằng hoặc lớn hơn 0.' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.trip_participants where name = nullif(btrim(p_paid_by), '')
  ) then
    raise exception 'Chọn người đã chi trong danh sách thành viên.' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.estimated_expenses (title, amount, note, image_url, paid_by)
    values (btrim(p_title), round(p_amount), coalesce(p_note, ''), nullif(btrim(p_image_url), ''), btrim(p_paid_by))
    returning id into v_id;
  else
    update public.estimated_expenses
    set title = btrim(p_title),
        amount = round(p_amount),
        note = coalesce(p_note, ''),
        image_url = nullif(btrim(p_image_url), ''),
        paid_by = btrim(p_paid_by),
        updated_at = now()
    where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'Không tìm thấy khoản chi cần sửa.' using errcode = 'P0002';
    end if;
  end if;
end;
$$;

create or replace function public.delete_assigned_task(p_password text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not coalesce(public.check_edit_password(p_password), false) then
    raise exception 'Mật khẩu không đúng.' using errcode = '28000';
  end if;

  delete from public.assigned_tasks where id = p_id;
  if not found then
    raise exception 'Không tìm thấy công việc cần xóa.' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.delete_estimated_expense(p_password text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not coalesce(public.check_edit_password(p_password), false) then
    raise exception 'Mật khẩu không đúng.' using errcode = '28000';
  end if;

  delete from public.estimated_expenses where id = p_id;
  if not found then
    raise exception 'Không tìm thấy khoản chi cần xóa.' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.save_assigned_task_with_time(text, uuid, text, text, text, text, date, time without time zone) from public;
revoke all on function public.save_estimated_expense(text, uuid, text, numeric, text, text, text) from public;
revoke all on function public.register_device_session(text, uuid, text, text, text) from public;
revoke all on function public.touch_device_session(uuid) from public;
revoke all on function public.close_device_session(uuid) from public;
revoke all on function public.delete_assigned_task(text, uuid) from public;
revoke all on function public.delete_estimated_expense(text, uuid) from public;

grant execute on function public.save_assigned_task_with_time(text, uuid, text, text, text, text, date, time without time zone) to anon, authenticated;
grant execute on function public.save_estimated_expense(text, uuid, text, numeric, text, text, text) to anon, authenticated;
grant execute on function public.register_device_session(text, uuid, text, text, text) to anon, authenticated;
grant execute on function public.touch_device_session(uuid) to anon, authenticated;
grant execute on function public.close_device_session(uuid) to anon, authenticated;
grant execute on function public.delete_assigned_task(text, uuid) to anon, authenticated;
grant execute on function public.delete_estimated_expense(text, uuid) to anon, authenticated;

notify pgrst, 'reload schema';
