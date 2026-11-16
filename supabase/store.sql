-- Urban Thread online store: catalogue, orders and security rules.
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Safe to run again (it updates functions/policies in place).
--
-- Who can do what:
--   • Anyone (the website)  → read products marked "online", read store
--                             settings, place an order (via place_order),
--                             track an order with phone + order number.
--   • Shop owner (POS app)  → everything: sync catalogue, upload photos,
--                             read and update orders.
--   The first account that signs in from the POS becomes the owner
--   (claim_shop); after that nobody else can.

-- ─── Owner ─────────────────────────────────────────────────
create table if not exists public.shop_admins (
  user_id uuid primary key references auth.users on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.shop_admins enable row level security;
drop policy if exists "admins: see self" on public.shop_admins;
create policy "admins: see self" on public.shop_admins
  for select to authenticated using (user_id = (select auth.uid()));

create or replace function public.is_shop_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from shop_admins where user_id = auth.uid());
$$;

create or replace function public.claim_shop() returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return false; end if;
  if exists (select 1 from shop_admins where user_id = auth.uid()) then
    return true;
  end if;
  if exists (select 1 from shop_admins) then return false; end if;
  insert into shop_admins (user_id) values (auth.uid());
  return true;
end $$;
revoke execute on function public.claim_shop() from public, anon;
grant execute on function public.claim_shop() to authenticated;
grant execute on function public.is_shop_admin() to anon, authenticated;

-- ─── Store settings ────────────────────────────────────────
create table if not exists public.store_settings (
  id int primary key default 1 check (id = 1),
  store_open boolean not null default true,
  delivery_fee numeric not null default 200,
  free_delivery_over numeric,          -- e.g. 5000; null = never free
  whatsapp text,                       -- shown on the website
  updated_at timestamptz not null default now()
);
insert into public.store_settings (id) values (1) on conflict (id) do nothing;
alter table public.store_settings enable row level security;
drop policy if exists "settings: public read" on public.store_settings;
create policy "settings: public read" on public.store_settings
  for select to anon, authenticated using (true);
drop policy if exists "settings: owner write" on public.store_settings;
create policy "settings: owner write" on public.store_settings
  for update to authenticated using (public.is_shop_admin())
  with check (public.is_shop_admin());

-- ─── Catalogue (pushed from the POS) ───────────────────────
-- ids are the POS's own design / product ids.
create table if not exists public.catalog_designs (
  id bigint primary key,
  name text not null,
  type text,
  description text,
  price numeric not null,
  photos text[] not null default '{}',
  online boolean not null default false,
  updated_at timestamptz not null default now()
);
create table if not exists public.catalog_variants (
  id bigint primary key,
  design_id bigint not null references public.catalog_designs (id)
    on delete cascade,
  size text,
  price numeric not null,
  stock int not null default 0,
  updated_at timestamptz not null default now()
);
create index if not exists catalog_variants_design on public.catalog_variants (design_id);

alter table public.catalog_designs enable row level security;
alter table public.catalog_variants enable row level security;

drop policy if exists "designs: public read online" on public.catalog_designs;
create policy "designs: public read online" on public.catalog_designs
  for select to anon, authenticated using (online or public.is_shop_admin());
drop policy if exists "designs: owner write" on public.catalog_designs;
create policy "designs: owner write" on public.catalog_designs
  for all to authenticated using (public.is_shop_admin())
  with check (public.is_shop_admin());

drop policy if exists "variants: public read online" on public.catalog_variants;
create policy "variants: public read online" on public.catalog_variants
  for select to anon, authenticated using (
    public.is_shop_admin() or exists (
      select 1 from public.catalog_designs d
      where d.id = design_id and d.online));
drop policy if exists "variants: owner write" on public.catalog_variants;
create policy "variants: owner write" on public.catalog_variants
  for all to authenticated using (public.is_shop_admin())
  with check (public.is_shop_admin());

-- ─── Orders ────────────────────────────────────────────────
create table if not exists public.orders (
  id bigint generated always as identity primary key,
  order_no text not null unique,
  customer_name text not null,
  phone text not null,                 -- 03XXXXXXXXX
  address text not null,
  area text,
  city text not null default 'Lahore',
  notes text,
  payment text not null default 'COD',
  status text not null default 'pending' check (status in (
    'pending', 'confirmed', 'packed', 'out_for_delivery', 'delivered',
    'cancelled', 'rejected')),
  subtotal numeric not null,
  delivery_fee numeric not null,
  total numeric not null,
  pos_bill_number text,                -- set when accepted in the POS
  status_note text,                    -- e.g. reason for rejection
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.order_items (
  id bigint generated always as identity primary key,
  order_id bigint not null references public.orders (id) on delete cascade,
  variant_id bigint not null,
  design_id bigint not null,
  name text not null,
  size text,
  price numeric not null,
  quantity int not null check (quantity between 1 and 20)
);
create index if not exists orders_status on public.orders (status, created_at);
create index if not exists order_items_order on public.order_items (order_id);

alter table public.orders enable row level security;
alter table public.order_items enable row level security;
-- No public access at all: customers go through the functions below.
drop policy if exists "orders: owner all" on public.orders;
create policy "orders: owner all" on public.orders
  for all to authenticated using (public.is_shop_admin())
  with check (public.is_shop_admin());
drop policy if exists "order_items: owner all" on public.order_items;
create policy "order_items: owner all" on public.order_items
  for all to authenticated using (public.is_shop_admin())
  with check (public.is_shop_admin());

-- Normalise a Pakistani mobile to 03XXXXXXXXX, or null if invalid.
create or replace function public.normalize_pk_phone(p text) returns text
language plpgsql immutable as $$
declare d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
begin
  if d like '0092%' then d := substr(d, 5);
  elsif d like '92%' then d := substr(d, 3);
  elsif d like '0%' then d := substr(d, 2);
  end if;
  if d ~ '^3\d{9}$' then return '0' || d; end if;
  return null;
end $$;

-- Place an order. Prices and stock come from the catalogue, never from
-- the browser. items: [{"variant_id": 12, "quantity": 2}, ...]
create or replace function public.place_order(
  p_name text, p_phone text, p_address text, p_area text,
  p_notes text, p_items jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_phone text := normalize_pk_phone(p_phone);
  v_settings store_settings;
  v_item jsonb;
  v_var record;
  v_qty int;
  v_subtotal numeric := 0;
  v_fee numeric;
  v_order_id bigint;
  v_no text;
  v_lines int := 0;
begin
  select * into v_settings from store_settings where id = 1;
  if not coalesce(v_settings.store_open, false) then
    raise exception 'The store is not taking orders right now.';
  end if;
  if length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'Please enter your name.';
  end if;
  if v_phone is null then
    raise exception 'Please enter a valid mobile number (03XX-XXXXXXX).';
  end if;
  if length(trim(coalesce(p_address, ''))) < 8 then
    raise exception 'Please enter your full delivery address.';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 20 then
    raise exception 'Your cart is empty or too large.';
  end if;
  -- Simple spam guard: max 5 open orders per phone.
  if (select count(*) from orders where phone = v_phone
        and status in ('pending', 'confirmed', 'packed')) >= 5 then
    raise exception 'You already have several open orders. Please contact us on WhatsApp.';
  end if;

  -- Validate every line first.
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item ->> 'quantity')::int;
    if v_qty is null or v_qty < 1 or v_qty > 20 then
      raise exception 'Invalid quantity.';
    end if;
    select v.id, v.size, v.price, v.stock, d.id as design_id, d.name
      into v_var
      from catalog_variants v join catalog_designs d on d.id = v.design_id
      where v.id = (v_item ->> 'variant_id')::bigint and d.online;
    if not found then
      raise exception 'An item in your cart is no longer available.';
    end if;
    if v_var.stock < v_qty then
      raise exception '% (%) has only % left.', v_var.name,
        coalesce(v_var.size, 'one size'), v_var.stock;
    end if;
    v_subtotal := v_subtotal + v_var.price * v_qty;
    v_lines := v_lines + 1;
  end loop;

  v_fee := case
    when v_settings.free_delivery_over is not null
         and v_subtotal >= v_settings.free_delivery_over then 0
    else v_settings.delivery_fee end;

  -- Unique order number like UT-251113-4821.
  loop
    v_no := 'UT-' || to_char(now() at time zone 'Asia/Karachi', 'YYMMDD')
            || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
    exit when not exists (select 1 from orders where order_no = v_no);
  end loop;

  insert into orders (order_no, customer_name, phone, address, area, notes,
                      subtotal, delivery_fee, total)
  values (v_no, trim(p_name), v_phone, trim(p_address),
          nullif(trim(coalesce(p_area, '')), ''),
          nullif(trim(coalesce(p_notes, '')), ''),
          v_subtotal, v_fee, v_subtotal + v_fee)
  returning id into v_order_id;

  insert into order_items (order_id, variant_id, design_id, name, size,
                           price, quantity)
  select v_order_id, v.id, d.id, d.name, v.size, v.price,
         (i ->> 'quantity')::int
    from jsonb_array_elements(p_items) i
    join catalog_variants v on v.id = (i ->> 'variant_id')::bigint
    join catalog_designs d on d.id = v.design_id;

  return jsonb_build_object('order_no', v_no, 'total', v_subtotal + v_fee,
                            'delivery_fee', v_fee);
end $$;
revoke execute on function public.place_order(text, text, text, text, text, jsonb) from public;
grant execute on function public.place_order(text, text, text, text, text, jsonb) to anon, authenticated;

-- Track an order: needs both the order number and the phone it was
-- placed with, so order numbers alone reveal nothing.
create or replace function public.track_order(p_order_no text, p_phone text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'order_no', o.order_no, 'status', o.status, 'status_note', o.status_note,
    'created_at', o.created_at, 'updated_at', o.updated_at,
    'subtotal', o.subtotal, 'delivery_fee', o.delivery_fee, 'total', o.total,
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'name', i.name, 'size', i.size, 'price', i.price,
        'quantity', i.quantity)) from order_items i where i.order_id = o.id),
      '[]'::jsonb))
  from orders o
  where upper(o.order_no) = upper(trim(p_order_no))
    and o.phone = normalize_pk_phone(p_phone);
$$;
revoke execute on function public.track_order(text, text) from public;
grant execute on function public.track_order(text, text) to anon, authenticated;

-- ─── Product photos (public images, owner uploads) ─────────
insert into storage.buckets (id, name, public)
values ('product-photos', 'product-photos', true)
on conflict (id) do update set public = true;

drop policy if exists "photos: owner upload" on storage.objects;
create policy "photos: owner upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-photos' and public.is_shop_admin());
drop policy if exists "photos: owner update" on storage.objects;
create policy "photos: owner update" on storage.objects
  for update to authenticated
  using (bucket_id = 'product-photos' and public.is_shop_admin());
drop policy if exists "photos: owner delete" on storage.objects;
create policy "photos: owner delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-photos' and public.is_shop_admin());

-- ─── Realtime: instant new-order alerts in the POS ────────
-- Lets the POS hear about new orders the moment they're placed. Realtime
-- respects the RLS above, so only the shop owner receives them.
-- Safe to run again.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end $$;
