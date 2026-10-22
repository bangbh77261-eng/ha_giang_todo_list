-- Optional contact details for the public Ha Giang trip roster.
alter table public.trip_participants
  add column if not exists phone text not null default '',
  add column if not exists map_location text not null default '';

create or replace function public.save_trip_participant_contact(
  p_password text,
  p_id uuid,
  p_phone text,
  p_map_location text
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
  if p_id is null then
    raise exception 'Chọn thành viên cần cập nhật.' using errcode = '22023';
  end if;
  if length(coalesce(p_phone, '')) > 32 then
    raise exception 'Số điện thoại tối đa 32 ký tự.' using errcode = '22023';
  end if;
  if length(coalesce(p_map_location, '')) > 300 then
    raise exception 'Địa điểm tối đa 300 ký tự.' using errcode = '22023';
  end if;

  update public.trip_participants
  set phone = btrim(coalesce(p_phone, '')),
      map_location = btrim(coalesce(p_map_location, ''))
  where id = p_id;

  if not found then
    raise exception 'Không tìm thấy thành viên cần cập nhật.' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.save_trip_participant_contact(text, uuid, text, text) from public;
grant execute on function public.save_trip_participant_contact(text, uuid, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
