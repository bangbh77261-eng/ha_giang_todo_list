-- Shared participant roster for the Ha Giang trip.
create table if not exists public.trip_participants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint trip_participants_name_nonempty check (length(btrim(name)) > 0),
  constraint trip_participants_name_unique unique (name)
);

create index if not exists trip_participants_sort_order_idx
  on public.trip_participants (sort_order, id);

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
  ('Bá Huy', 1),
  ('Thanh Thanh', 2),
  ('Đắc Thành', 3),
  ('Ninh Giang', 4),
  ('Linh Su', 5),
  ('Linh 8', 6),
  ('Anh Trong', 7),
  ('Kim Luyên', 8),
  ('Hải Bằng', 9),
  ('Khách Mời', 10)
on conflict (name) do update
set sort_order = excluded.sort_order;

notify pgrst, 'reload schema';
