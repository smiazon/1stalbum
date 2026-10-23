-- new music every friday: the guestbook, in Supabase.
-- Paste this whole file into Supabase > SQL Editor > New query, and press Run. Safe to run again.
--
-- What's public:  public.signatures (names and where they sit on the square).
-- What's private: everything in the "private" schema, which the website can't read:
--                 contacts (name, email/phone, when), settings (your admin key), counters, presence.
-- Visitors can only change anything through the functions at the bottom, which enforce the rules.

create extension if not exists pgcrypto;
create extension if not exists unaccent;

-- ---------- tables ----------

create table if not exists public.signatures (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  color      text not null default '#1b1b1b',
  font       text not null default 'Caveat',
  x          real not null,          -- % across the square
  y          real not null,          -- % down the square
  rot        int  not null default 0,
  size       int  not null default 24,
  artist     boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.signatures enable row level security;
drop policy if exists "anyone can read signatures" on public.signatures;
create policy "anyone can read signatures" on public.signatures for select using (true);

create schema if not exists private;

create table if not exists private.settings (
  id        int primary key default 1 check (id = 1),
  admin_key text not null default encode(gen_random_bytes(18), 'hex'),   -- your owner key
  closes_at timestamptz not null default '2027-01-01 00:00:00-05'        -- 12 weeks, then we sign it
);
insert into private.settings default values on conflict do nothing;

create table if not exists private.contacts (
  signature_id uuid references public.signatures(id) on delete set null,
  name       text not null,
  contact    text not null,          -- normalised email or phone digits
  ip_hash    text,                   -- hashed, only to cap marks per network
  day        date not null,          -- the day in New York, for once-a-day
  created_at timestamptz not null default now()
);
create unique index if not exists contacts_once_a_day on private.contacts (contact, day);

create table if not exists private.counters (key text primary key, value bigint not null default 0);
create table if not exists private.presence (id text primary key, seen timestamptz not null);

-- ---------- helpers (private) ----------

create or replace function private.today() returns date language sql stable as $$
  select (now() at time zone 'America/New_York')::date
$$;

-- email lower-cased, or a phone number reduced to its digits; null if neither
create or replace function private.norm_contact(raw text) returns text language plpgsql immutable as $$
declare v text := lower(btrim(coalesce(raw, ''))); digits text;
begin
  if v ~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$' then return v; end if;
  digits := regexp_replace(v, '[^0-9]', '', 'g');
  if v ~ '^\+?[0-9\s().-]+$' and length(digits) between 7 and 15 then return digits; end if;
  return null;
end $$;

-- Slurs and hate terms only. Names are normalised (accents, leetspeak, spacing, repeated letters)
-- and checked as whole words, so names like Nigel, Scunthorpe or Spicy pass.
-- (Supabase keeps add-ons like unaccent in the "extensions" schema, hence the search_path)
create or replace function private.is_blocked(raw text) returns boolean language plpgsql stable
set search_path = public, extensions, pg_temp as $$
declare
  base text := lower(unaccent(coalesce(raw, '')));
  leet text := translate(base, '0134578@!|$9', 'oieastbaiisg');
  words text[] := array_remove(regexp_split_to_array(leet, '[^a-z]+'), '');
  squashed text := regexp_replace(leet, '[^a-z]', '', 'g');
  w text; v text; re text;
  blocked_words text[] := array[
    '^n+i+g+(?:[aeou]h?|[aeo]+rs?|[aeo]+z|as|let|s|z)?$', '^fag+(?:s|ot+s?|got+s?)?$', '^chinks?$', '^spics?$',
    '^kikes?$', '^wetbacks?$', '^beaners?$', '^gooks?$', '^tran+(?:y|ie)s?$', '^retard(?:s|ed)?$',
    '^dykes?$', '^cunts?$', '^kkk$', '^hitler$', '^coons?$'];
  blocked_anywhere text[] := array[
    'n+i+gg', 'fagg?ot', 'wetback', 'towelhead', 'raghead', 'hitler', 'siegheil', 'whitepower', 'kkk', 'gasthe', '1488'];
begin
  -- "n i g" style spacing: if every word is a single letter, read them as one word
  if array_length(words, 1) > 1 and (select bool_and(length(x) = 1) from unnest(words) x) then
    words := words || array_to_string(words, '');
  end if;
  foreach w in array coalesce(words, '{}') loop
    foreach v in array array[w, regexp_replace(w, '(.)\1+', '\1', 'g')] loop
      foreach re in array blocked_words loop
        if v ~ re then return true; end if;
      end loop;
    end loop;
  end loop;
  foreach re in array blocked_anywhere loop
    if base ~ re or squashed ~ re then return true; end if;
  end loop;
  return false;
end $$;

-- the visitor's network address, as Supabase passes it through
create or replace function private.client_ip() returns text language plpgsql stable as $$
declare h json;
begin
  h := nullif(current_setting('request.headers', true), '')::json;
  return nullif(btrim(split_part(coalesce(h->>'cf-connecting-ip', h->>'x-forwarded-for', ''), ',', 1)), '');
exception when others then return null;
end $$;

create or replace function private.is_admin(p_key text) returns boolean language sql stable as $$
  select exists (select 1 from private.settings where admin_key = p_key)
$$;

-- ---------- what the website can call ----------

-- Sign the square. One signature per email/phone per day, at most 3 per network per day.
create or replace function public.sign(p_name text, p_contact text, p_color text default null, p_x real default null, p_y real default null)
returns public.signatures language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
declare
  n text := left(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), 32);
  c text := private.norm_contact(p_contact);
  d date := private.today();
  ip text := private.client_ip();
  ih text := case when ip is null then null else encode(digest(ip, 'sha256'), 'hex') end;
  me boolean := c is not null and c = (select owner_email from private.settings);   -- the owner's email: no limits
  r public.signatures;
begin
  if n = '' then raise exception 'add your name'; end if;
  if private.is_blocked(n) then raise exception 'let''s keep it kind. try another name.'; end if;
  if c is null then raise exception 'enter a valid email or phone number'; end if;
  if not me and now() >= (select closes_at from private.settings) then raise exception 'signing is closed. now we sign it.'; end if;
  if (select count(*) from public.signatures) >= 2000 then raise exception 'there''s no room left'; end if;
  if not me and exists (select 1 from private.contacts where contact = c and day = d) then
    raise exception 'you already signed today. come back tomorrow.';
  end if;
  if ih is not null then
    if exists (select 1 from private.contacts where ip_hash = ih and created_at > now() - interval '5 seconds') then
      raise exception 'slow down';
    end if;
    if not me and (select count(*) from private.contacts where ip_hash = ih and day = d) >= 3 then
      raise exception 'you already signed today. come back tomorrow.';
    end if;
  end if;

  insert into public.signatures (name, color, font, x, y, rot, size)
  values (
    n,
    case when p_color in ('#1b1b1b', '#1d3b8f', '#b3261e') then p_color else '#1b1b1b' end,
    (array['Caveat', 'Reenie Beanie', 'Rock Salt', 'Homemade Apple', 'Nothing You Could Do'])[1 + floor(random() * 5)::int],
    greatest(1, least(86, coalesce(p_x, 4 + random() * 78))),
    greatest(4, least(96, coalesce(p_y, 8 + random() * 84))),
    round((random() - 0.5) * 50)::int,
    18 + floor(random() * 14)::int
  ) returning * into r;

  insert into private.contacts (signature_id, name, contact, ip_hash, day, owner) values (r.id, n, c, ih, d, me);
  return r;
exception when unique_violation then
  raise exception 'you already signed today. come back tomorrow.';
end $$;

-- Our signature: needs the admin key; no daily limit, works after signing closes, written larger.
create or replace function public.artist_sign(p_key text, p_name text, p_color text default null, p_x real default null, p_y real default null)
returns public.signatures language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
declare r public.signatures; n text := left(btrim(coalesce(p_name, '')), 32);
begin
  if not private.is_admin(p_key) then raise exception 'not allowed'; end if;
  if n = '' then raise exception 'add your name'; end if;
  insert into public.signatures (name, color, font, x, y, rot, size, artist)
  values (n,
    case when p_color in ('#1b1b1b', '#1d3b8f', '#b3261e') then p_color else '#1b1b1b' end,
    'Rock Salt', greatest(1, least(86, coalesce(p_x, 30))), greatest(4, least(96, coalesce(p_y, 80))),
    round((random() - 0.5) * 12)::int, 32, true)
  returning * into r;
  return r;
end $$;

create or replace function public.remove_signature(p_key text, p_id uuid) returns boolean
language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
begin
  if not private.is_admin(p_key) then raise exception 'not allowed'; end if;
  delete from public.signatures where id = p_id;
  return found;
end $$;

-- Everyone who signed, with their contact. Owner only.
create or replace function public.signers(p_key text)
returns table (signed_at timestamptz, name text, contact text, still_on_page boolean)
language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
begin
  if not private.is_admin(p_key) then raise exception 'not allowed'; end if;
  return query select c.created_at, c.name, c.contact, c.signature_id is not null
               from private.contacts c order by c.created_at;
end $$;

-- the visitor number: each visitor gets their own numbered copy
create or replace function public.hit() returns bigint
language sql security definer set search_path = public, private, extensions, pg_temp as $$
  insert into private.counters (key, value) values ('visits', 1)
  on conflict (key) do update set value = private.counters.value + 1
  returning value
$$;

-- who has the page open right now, plus the server's clock
create or replace function public.ping(p_id text) returns json
language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
declare n int;
begin
  if p_id is not null and length(p_id) between 1 and 24 then
    insert into private.presence (id, seen) values (p_id, now())
    on conflict (id) do update set seen = now();
  end if;
  delete from private.presence where seen < now() - interval '45 seconds';
  select count(*) into n from private.presence;
  return json_build_object('peers', greatest(1, n), 'now', floor(extract(epoch from now()) * 1000));
end $$;

-- ---------- paint: visitors paint on the square ----------
-- A painting is a list of strokes: { c: colour, s: brush size, p: [x0, y0, x1, y1, ...] } in 0..1000 square units.
-- Ink is limited: the length of every stroke times its brush size must stay under 60,000.

create table if not exists public.drawings (
  id         uuid primary key default gen_random_uuid(),
  strokes    jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.drawings enable row level security;
drop policy if exists "anyone can see drawings" on public.drawings;
create policy "anyone can see drawings" on public.drawings for select using (true);
alter table private.contacts add column if not exists drawing_id uuid references public.drawings(id) on delete set null;

-- checks a painting, rebuilds it with only the allowed fields, and measures its ink
create or replace function private.clean_strokes(p jsonb, out strokes jsonb, out ink numeric)
language plpgsql stable set search_path = public, private, extensions, pg_temp as $$
-- A signature is a list of marks: brush strokes {c, s, p}, words {k:'tx'} and stickers {k:'st'}.
declare
  st jsonb; n int; i int; total int := 0; sz int; col text; arr int[]; clean jsonb := '[]'::jsonb;
  kind text; v text; texts int := 0; stickers int := 0;
  sticker_ids constant text[] := array['heart','star','moon','sun','flame','bolt','cherry','flower',
                                       'eye','rainbow','note','disc','smile','ghost','sparkle','crown',
                                       'halo','wing','headphones','cassette','vinyl','mic','kiss','rose',
                                       'cloud','snowflake','mushroom','alien','skull','gem','butterfly','planet'];
begin
  ink := 0;
  if p is null or jsonb_typeof(p) <> 'array' or jsonb_array_length(p) = 0 then raise exception 'paint something first'; end if;
  if jsonb_array_length(p) > 150 then raise exception 'too many strokes'; end if;
  for st in select value from jsonb_array_elements(p) loop
    if jsonb_typeof(st) <> 'object' then raise exception 'bad stroke'; end if;
    kind := st->>'k';
    if kind in ('tx', 'st') then
      if coalesce(jsonb_typeof(st->'x'), '') <> 'number' or coalesce(jsonb_typeof(st->'y'), '') <> 'number' then raise exception 'bad stroke'; end if;
    end if;

    if kind = 'tx' then                                   -- words, in one of the five hands
      texts := texts + 1;
      if texts > 3 then raise exception 'three words at most'; end if;
      v := left(btrim(regexp_replace(coalesce(st->>'v', ''), '\s+', ' ', 'g')), 40);
      if v = '' then raise exception 'type something first'; end if;
      if private.is_blocked(v) then raise exception 'let''s keep it kind. try other words.'; end if;
      col := st->>'c';
      if col is null or col !~ '^#[0-9a-fA-F]{6}$' then raise exception 'unknown colour'; end if;
      clean := clean || jsonb_build_array(jsonb_build_object(
        'k', 'tx', 'v', v, 'c', col,
        'f', greatest(0, least(4, coalesce(round((st->>'f')::numeric), 0)))::int,
        'x', greatest(0, least(1000, round((st->>'x')::numeric)))::int,
        'y', greatest(0, least(1000, round((st->>'y')::numeric)))::int,
        'z', case when (st->>'z') in ('30', '50', '80') then (st->>'z')::int else 50 end,
        'r', greatest(-20, least(20, coalesce(round((st->>'r')::numeric), 0)))::int));

    elsif kind = 'st' then                                -- a sticker
      stickers := stickers + 1;
      if stickers > 8 then raise exception 'eight stickers at most'; end if;
      if not coalesce(st->>'id' = any(sticker_ids), false) then raise exception 'unknown sticker'; end if;
      clean := clean || jsonb_build_array(jsonb_build_object(
        'k', 'st', 'id', st->>'id',
        'x', greatest(0, least(1000, round((st->>'x')::numeric)))::int,
        'y', greatest(0, least(1000, round((st->>'y')::numeric)))::int,
        'z', case when (st->>'z') in ('60', '100', '160') then (st->>'z')::int else 100 end));

    elsif kind is null then                               -- a brush stroke
      col := st->>'c';
      sz := (st->>'s')::int;
      if col is null or col !~ '^#[0-9a-fA-F]{6}$' then raise exception 'unknown colour'; end if;
      if sz is null or sz not in (5, 12, 24) then raise exception 'unknown brush'; end if;
      if jsonb_typeof(st->'p') <> 'array' then raise exception 'bad stroke'; end if;
      n := jsonb_array_length(st->'p');
      if n < 2 or n % 2 = 1 then raise exception 'bad stroke'; end if;
      total := total + n / 2;
      if total > 3000 then raise exception 'too much paint'; end if;
      select array_agg(greatest(0, least(1000, round(e.v::numeric)))::int order by e.o)
        into arr from jsonb_array_elements_text(st->'p') with ordinality as e(v, o);
      if n = 2 then ink := ink + sz * sz;          -- a dot
      else
        i := 3;
        while i <= n loop
          ink := ink + sqrt(power(arr[i] - arr[i - 2], 2) + power(arr[i + 1] - arr[i - 1], 2)) * sz;
          i := i + 2;
        end loop;
      end if;
      clean := clean || jsonb_build_array(jsonb_build_object('c', col, 's', sz, 'p', to_jsonb(arr)));

    else
      raise exception 'bad stroke';
    end if;
  end loop;
  strokes := clean;
end $$;

-- Paint on the square. Same rules as signing: one per email/phone per day, at most 3 per network per day.
create or replace function public.draw(p_name text, p_contact text, p_strokes jsonb)
returns public.drawings language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
declare
  n text := left(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), 32);
  c text := private.norm_contact(p_contact);
  d date := private.today();
  ip text := private.client_ip();
  ih text := case when ip is null then null else encode(digest(ip, 'sha256'), 'hex') end;
  cs record;
  me boolean := c is not null and c = (select owner_email from private.settings);   -- the owner's email: no limits
  r public.drawings;
begin
  if n = '' then raise exception 'add your name'; end if;
  if private.is_blocked(n) then raise exception 'let''s keep it kind. try another name.'; end if;
  if c is null then raise exception 'enter a valid email or phone number'; end if;
  if not me and now() >= (select closes_at from private.settings) then raise exception 'signing is closed. now we sign it.'; end if;
  if (select count(*) from public.drawings) >= 1200 then raise exception 'there''s no room left'; end if;
  select * into cs from private.clean_strokes(p_strokes);
  if cs.ink > 61800 then raise exception 'out of ink'; end if;
  if not me and exists (select 1 from private.contacts where contact = c and day = d) then
    raise exception 'you already signed today. come back tomorrow.';
  end if;
  if ih is not null then
    if exists (select 1 from private.contacts where ip_hash = ih and created_at > now() - interval '5 seconds') then
      raise exception 'slow down';
    end if;
    if not me and (select count(*) from private.contacts where ip_hash = ih and day = d) >= 3 then
      raise exception 'you already signed today. come back tomorrow.';
    end if;
  end if;
  insert into public.drawings (strokes) values (cs.strokes) returning * into r;
  insert into private.contacts (drawing_id, name, contact, ip_hash, day, owner) values (r.id, n, c, ih, d, me);
  return r;
exception when unique_violation then
  raise exception 'you already signed today. come back tomorrow.';
end $$;

create or replace function public.remove_drawing(p_key text, p_id uuid) returns boolean
language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
begin
  if not private.is_admin(p_key) then raise exception 'not allowed'; end if;
  delete from public.drawings where id = p_id;
  return found;
end $$;

-- the signer list counts paintings too
create or replace function public.signers(p_key text)
returns table (signed_at timestamptz, name text, contact text, still_on_page boolean)
language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
begin
  if not private.is_admin(p_key) then raise exception 'not allowed'; end if;
  return query select c.created_at, c.name, c.contact, (c.signature_id is not null or c.drawing_id is not null)
               from private.contacts c order by c.created_at;
end $$;

-- ---------- the owner: unlimited, and counted ----------
-- With the owner key, the artist can sign and paint as often as they like. Every one is recorded
-- under the owner's email, so it counts in the totals and the signer list like anyone else's.
alter table private.settings add column if not exists owner_email text not null default 'smiazon@gmail.com';
alter table private.contacts add column if not exists owner boolean not null default false;
drop index if exists private.contacts_once_a_day;
create unique index if not exists contacts_once_a_day on private.contacts (contact, day) where not owner;

create or replace function public.artist_draw(p_key text, p_strokes jsonb, p_name text default null)
returns public.drawings language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
declare cs record; r public.drawings; n text := left(btrim(coalesce(p_name, '')), 32);
begin
  if not private.is_admin(p_key) then raise exception 'not allowed'; end if;
  select * into cs from private.clean_strokes(p_strokes);
  if cs.ink > 61800 then raise exception 'out of ink'; end if;        -- one painting's worth each time, as many times as you like
  insert into public.drawings (strokes) values (cs.strokes) returning * into r;
  insert into private.contacts (drawing_id, name, contact, day, owner)
  values (r.id, coalesce(nullif(n, ''), 'us'), (select owner_email from private.settings), private.today(), true);
  return r;
end $$;

-- our written signature, now recorded too
create or replace function public.artist_sign(p_key text, p_name text, p_color text default null, p_x real default null, p_y real default null)
returns public.signatures language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
declare r public.signatures; n text := left(btrim(coalesce(p_name, '')), 32);
begin
  if not private.is_admin(p_key) then raise exception 'not allowed'; end if;
  if n = '' then raise exception 'add your name'; end if;
  insert into public.signatures (name, color, font, x, y, rot, size, artist)
  values (n,
    case when p_color ~ '^#[0-9a-fA-F]{6}$' then p_color else '#1b1b1b' end,
    'Rock Salt', greatest(1, least(86, coalesce(p_x, 30))), greatest(4, least(96, coalesce(p_y, 80))),
    round((random() - 0.5) * 12)::int, 32, true)
  returning * into r;
  insert into private.contacts (signature_id, name, contact, day, owner)
  values (r.id, n, (select owner_email from private.settings), private.today(), true);
  return r;
end $$;

grant execute on function public.artist_draw(text, jsonb, text) to anon, authenticated;

-- ---------- never erase ----------
-- Nothing on the canvas is ever deleted. "Remove" only hides a mark (restorable), and the database
-- refuses any delete or wipe of the canvas and the signer list, even one typed into the SQL editor.
alter table public.signatures add column if not exists hidden boolean not null default false;
alter table public.drawings add column if not exists hidden boolean not null default false;
drop policy if exists "anyone can read signatures" on public.signatures;
create policy "anyone can read signatures" on public.signatures for select using (not hidden);
drop policy if exists "anyone can see drawings" on public.drawings;
create policy "anyone can see drawings" on public.drawings for select using (not hidden);

create or replace function private.never_erase() returns trigger language plpgsql as $$
begin
  raise exception 'the canvas is never erased. use remove in owner mode to hide a mark instead.';
end $$;
drop trigger if exists never_erase on public.signatures;
create trigger never_erase before delete on public.signatures for each row execute function private.never_erase();
drop trigger if exists never_wipe on public.signatures;
create trigger never_wipe before truncate on public.signatures for each statement execute function private.never_erase();
drop trigger if exists never_erase on public.drawings;
create trigger never_erase before delete on public.drawings for each row execute function private.never_erase();
drop trigger if exists never_wipe on public.drawings;
create trigger never_wipe before truncate on public.drawings for each statement execute function private.never_erase();
drop trigger if exists never_erase on private.contacts;
create trigger never_erase before delete on private.contacts for each row execute function private.never_erase();
drop trigger if exists never_wipe on private.contacts;
create trigger never_wipe before truncate on private.contacts for each statement execute function private.never_erase();

create or replace function public.remove_signature(p_key text, p_id uuid) returns boolean
language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
begin
  if not private.is_admin(p_key) then raise exception 'not allowed'; end if;
  update public.signatures set hidden = true where id = p_id and not hidden;
  return found;
end $$;

create or replace function public.remove_drawing(p_key text, p_id uuid) returns boolean
language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
begin
  if not private.is_admin(p_key) then raise exception 'not allowed'; end if;
  update public.drawings set hidden = true where id = p_id and not hidden;
  return found;
end $$;

-- bring a hidden mark back
create or replace function public.restore_mark(p_key text, p_id uuid) returns boolean
language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
declare n int;
begin
  if not private.is_admin(p_key) then raise exception 'not allowed'; end if;
  update public.signatures set hidden = false where id = p_id and hidden;
  get diagnostics n = row_count;
  update public.drawings set hidden = false where id = p_id and hidden;
  return n > 0 or found;
end $$;

create or replace function public.signers(p_key text)
returns table (signed_at timestamptz, name text, contact text, still_on_page boolean)
language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
begin
  if not private.is_admin(p_key) then raise exception 'not allowed'; end if;
  return query
    select c.created_at, c.name, c.contact,
           coalesce((select not s.hidden from public.signatures s where s.id = c.signature_id), false)
        or coalesce((select not d.hidden from public.drawings d where d.id = c.drawing_id), false)
    from private.contacts c order by c.created_at;
end $$;

-- ---------- backups ----------
-- everything: the canvas (hidden marks included) and the signer list
create or replace function private.everything() returns jsonb language sql stable as $$
  select jsonb_build_object(
    'taken_at', now(),
    'signatures', coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at) from public.signatures s), '[]'),
    'drawings',   coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at) from public.drawings d), '[]'),
    'contacts',   coalesce((select jsonb_agg(to_jsonb(c) - 'ip_hash' order by c.created_at) from private.contacts c), '[]')
  )
$$;

-- a full copy, for the owner's own backups
create or replace function public.export_all(p_key text) returns jsonb
language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
begin
  if not private.is_admin(p_key) then raise exception 'not allowed'; end if;
  return private.everything();
end $$;

-- nightly snapshots inside the database, kept 90 days
create table if not exists private.snapshots (taken_at timestamptz primary key default now(), data jsonb not null);
create or replace function private.take_snapshot() returns void
language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
begin
  insert into private.snapshots (data) values (private.everything()) on conflict do nothing;
  delete from private.snapshots where taken_at < now() - interval '90 days';
end $$;

grant execute on function public.restore_mark(text, uuid) to anon, authenticated;
grant execute on function public.export_all(text) to anon, authenticated;

-- ---------- the owner's dashboard ----------
-- visits per day (from when this was added; earlier visits only exist in the running total)
create table if not exists private.visits_daily (day date primary key, visits bigint not null default 0);

create or replace function public.hit() returns bigint
language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
declare total bigint;
begin
  insert into private.counters (key, value) values ('visits', 1)
  on conflict (key) do update set value = private.counters.value + 1
  returning value into total;
  insert into private.visits_daily (day, visits) values (private.today(), 1)
  on conflict (day) do update set visits = private.visits_daily.visits + 1;
  return total;
end $$;

-- everything the dashboard shows, in one call. Owner only.
create or replace function public.owner_dashboard(p_key text) returns jsonb
language plpgsql security definer set search_path = public, private, extensions, pg_temp as $$
begin
  if not private.is_admin(p_key) then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'now', now(),
    'visits_total', coalesce((select value from private.counters where key = 'visits'), 0),
    'visits_by_day', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'visits', visits) order by day) from private.visits_daily), '[]'),
    'here_now', (select count(*) from private.presence where seen > now() - interval '45 seconds'),
    'signers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'at', c.created_at,
        'name', c.name,
        'contact', c.contact,
        'kind', case when c.drawing_id is not null then 'painting' when c.signature_id is not null then 'name' else '?' end,
        'showing', coalesce((select not s.hidden from public.signatures s where s.id = c.signature_id), false)
                or coalesce((select not d.hidden from public.drawings d where d.id = c.drawing_id), false),
        'owner', c.owner
      ) order by c.created_at desc)
      from private.contacts c), '[]'),
    'names_on_canvas', (select count(*) from public.signatures where not hidden),
    'paintings_on_canvas', (select count(*) from public.drawings where not hidden),
    'hidden', (select count(*) from public.signatures where hidden) + (select count(*) from public.drawings where hidden)
  );
end $$;

grant execute on function public.owner_dashboard(text) to anon, authenticated;

-- only these functions are open to the website; the helpers and private tables are not
revoke all on schema private from public;
revoke all on all functions in schema private from public;
grant execute on function public.sign(text, text, text, real, real) to anon, authenticated;
grant execute on function public.artist_sign(text, text, text, real, real) to anon, authenticated;
grant execute on function public.remove_signature(text, uuid) to anon, authenticated;
grant execute on function public.signers(text) to anon, authenticated;
grant execute on function public.hit() to anon, authenticated;
grant execute on function public.ping(text) to anon, authenticated;
grant execute on function public.draw(text, text, jsonb) to anon, authenticated;
grant execute on function public.remove_drawing(text, uuid) to anon, authenticated;
grant select on public.signatures to anon, authenticated;
grant select on public.drawings to anon, authenticated;
revoke insert, update, delete on public.signatures from anon, authenticated;
revoke insert, update, delete on public.drawings from anon, authenticated;

-- Your owner key (keep it secret): run   select admin_key from private.settings;

-- ---------- Supabase only: run the nightly snapshot at 3:17 am Eastern (07:17 UTC) ----------
create extension if not exists pg_cron;
select cron.schedule('1stalbum-nightly-backup', '17 7 * * *', 'select private.take_snapshot()');
select private.take_snapshot();
