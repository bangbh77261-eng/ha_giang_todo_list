-- Record who paid each expense and validate against the shared participant list.
alter table public.estimated_expenses
  add column if not exists paid_by text;

drop function if exists public.save_estimated_expense(text, uuid, text, numeric, text, text);

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

revoke all on function public.save_estimated_expense(text, uuid, text, numeric, text, text, text) from public;
grant execute on function public.save_estimated_expense(text, uuid, text, numeric, text, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
