-- Opt-in live locations for trip members.
-- Run after the participant roster and device_sessions migrations.
create table if not exists public.trip_participant_locations (
  participant_id uuid primary key
    references public.trip_participants(id) on delete cascade,
  device_cookie text not null,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_m double precision check (accuracy_m is null or accuracy_m between 0 and 100000),
  updated_at timestamptz not null default now()
);

create index if not exists trip_participant_locations_updated_at_idx
  on public.trip_participant_locations (updated_at desc);

alter table public.trip_participant_locations enable row level security;
revoke all on public.trip_participant_locations from public, anon, authenticated;

create or replace function public.get_live_trip_participant_locations(
  p_password text,
  p_device_id text
)
returns table (
  participant_id uuid,
  latitude double precision,
  longitude double precision,
  accuracy_m double precision,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not coalesce(public.check_edit_password(p_password), false) then
    raise exception 'Mật khẩu không đúng.' using errcode = '28000';
  end if;
  if not exists (
    select 1 from public.device_sessions
    where device_cookie = nullif(btrim(p_device_id), '')
      and logged_out_at is null
      and last_seen_at > now() - interval '3 minutes'
  ) then
    raise exception 'Đăng nhập thiết bị trước khi xem vị trí trực tiếp.' using errcode = '28000';
  end if;

  delete from public.trip_participant_locations as stale_location
  where stale_location.updated_at < now() - interval '90 seconds';

  return query
  select location.participant_id, location.latitude, location.longitude,
         location.accuracy_m, location.updated_at
  from public.trip_participant_locations as location
  where location.updated_at >= now() - interval '90 seconds'
  order by location.updated_at desc;
end;
$$;

create or replace function public.share_trip_participant_location(
  p_password text,
  p_device_id text,
  p_participant_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_m double precision
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_participant_name text;
  v_device_id text := nullif(btrim(p_device_id), '');
begin
  if not coalesce(public.check_edit_password(p_password), false) then
    raise exception 'Mật khẩu không đúng.' using errcode = '28000';
  end if;
  if v_device_id is null or p_participant_id is null then
    raise exception 'Thiếu thông tin thành viên hoặc thiết bị.' using errcode = '22023';
  end if;
  if p_latitude is null or p_latitude not between -90 and 90
     or p_longitude is null or p_longitude not between -180 and 180 then
    raise exception 'Tọa độ GPS không hợp lệ.' using errcode = '22023';
  end if;
  if p_accuracy_m is not null and (p_accuracy_m < 0 or p_accuracy_m > 100000) then
    raise exception 'Độ chính xác GPS không hợp lệ.' using errcode = '22023';
  end if;

  select name into v_participant_name
  from public.trip_participants
  where id = p_participant_id;
  if v_participant_name is null then
    raise exception 'Không tìm thấy thành viên.' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from public.device_sessions
    where device_cookie = v_device_id
      and user_name = v_participant_name
      and logged_out_at is null
      and last_seen_at > now() - interval '3 minutes'
  ) then
    raise exception 'Đăng nhập bằng tên của bạn trước khi chia sẻ GPS.' using errcode = '28000';
  end if;

  insert into public.trip_participant_locations (
    participant_id, device_cookie, latitude, longitude, accuracy_m, updated_at
  ) values (
    p_participant_id, v_device_id, p_latitude, p_longitude, p_accuracy_m, now()
  )
  on conflict (participant_id) do update
  set device_cookie = excluded.device_cookie,
      latitude = excluded.latitude,
      longitude = excluded.longitude,
      accuracy_m = excluded.accuracy_m,
      updated_at = now();
end;
$$;

create or replace function public.stop_trip_participant_location(
  p_password text,
  p_device_id text,
  p_participant_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_participant_name text;
  v_device_id text := nullif(btrim(p_device_id), '');
begin
  if not coalesce(public.check_edit_password(p_password), false) then
    raise exception 'Mật khẩu không đúng.' using errcode = '28000';
  end if;
  select name into v_participant_name
  from public.trip_participants
  where id = p_participant_id;
  if v_participant_name is null then
    raise exception 'Không tìm thấy thành viên.' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from public.device_sessions
    where device_cookie = v_device_id
      and user_name = v_participant_name
      and logged_out_at is null
  ) then
    raise exception 'Thiết bị này chưa đăng nhập với thành viên đã chọn.' using errcode = '28000';
  end if;

  delete from public.trip_participant_locations
  where participant_id = p_participant_id and device_cookie = v_device_id;
end;
$$;

create or replace function public.clear_trip_location_on_session_close()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if (old.logged_out_at is null and new.logged_out_at is not null)
     or old.user_name is distinct from new.user_name then
    delete from public.trip_participant_locations
    where device_cookie = old.device_cookie;
  end if;
  return new;
end;
$$;

drop trigger if exists clear_trip_location_after_session_close on public.device_sessions;
create trigger clear_trip_location_after_session_close
after update of logged_out_at, user_name on public.device_sessions
for each row execute function public.clear_trip_location_on_session_close();

revoke all on function public.get_live_trip_participant_locations(text, text) from public;
revoke all on function public.share_trip_participant_location(text, text, uuid, double precision, double precision, double precision) from public;
revoke all on function public.stop_trip_participant_location(text, text, uuid) from public;
revoke all on function public.clear_trip_location_on_session_close() from public;
grant execute on function public.get_live_trip_participant_locations(text, text) to anon, authenticated;
grant execute on function public.share_trip_participant_location(text, text, uuid, double precision, double precision, double precision) to anon, authenticated;
grant execute on function public.stop_trip_participant_location(text, text, uuid) to anon, authenticated;

notify pgrst, 'reload schema';
