begin;

create or replace function public.save_trip_participant_avatar_for_device(
  p_device_cookie text,
  p_participant_id uuid,
  p_avatar_url text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_avatar_url text;
begin
  if p_device_cookie is null or length(p_device_cookie) < 16 then
    raise exception 'UNAUTHORIZED_DEVICE' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.device_sessions
    where device_cookie = p_device_cookie
      and logged_out_at is null
      and last_seen_at > now() - interval '10 minutes'
  ) then
    raise exception 'UNAUTHORIZED_DEVICE' using errcode = '28000';
  end if;

  v_avatar_url := nullif(btrim(p_avatar_url), '');
  if v_avatar_url is not null and (
    length(v_avatar_url) > 2048
    or v_avatar_url !~* '^https://uijplnwxyrhlgmenzyls[.]supabase[.]co/storage/v1/object/public/trip-images/[a-z0-9_-]{16,80}/image[.](jpg|jpeg|png|webp)$'
  ) then
    raise exception 'INVALID_AVATAR_URL' using errcode = '22023';
  end if;

  update public.trip_participants
  set avatar_url = v_avatar_url
  where id = p_participant_id;

  if not found then
    raise exception 'PARTICIPANT_NOT_FOUND' using errcode = 'P0002';
  end if;

  return true;
end;
$$;

revoke all on function public.save_trip_participant_avatar_for_device(text, uuid, text) from public;
grant execute on function public.save_trip_participant_avatar_for_device(text, uuid, text) to anon, authenticated;

commit;
