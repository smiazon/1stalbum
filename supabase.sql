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
  r public.signatures;
begin
  if n = '' then raise exception 'add your name'; end if;
  if private.is_blocked(n) then raise exception 'let''s keep it kind. try another name.'; end if;
  if c is null then raise exception 'enter a valid email or phone number'; end if;
  if now() >= (select closes_at from private.settings) then raise exception 'signing is closed. now we sign it.'; end if;
  if (select count(*) from public.signatures) >= 2000 then raise exception 'there''s no room left'; end if;
  if exists (select 1 from private.contacts where contact = c and day = d) then
    raise exception 'you already signed today. come back tomorrow.';
  end if;
  if ih is not null then
    if exists (select 1 from private.contacts where ip_hash = ih and created_at > now() - interval '5 seconds') then
      raise exception 'slow down';
    end if;
    if (select count(*) from private.contacts where ip_hash = ih and day = d) >= 3 then
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

  insert into private.contacts (signature_id, name, contact, ip_hash, day) values (r.id, n, c, ih, d);
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

-- only these functions are open to the website; the helpers and private tables are not
revoke all on schema private from public;
revoke all on all functions in schema private from public;
grant execute on function public.sign(text, text, text, real, real) to anon, authenticated;
grant execute on function public.artist_sign(text, text, text, real, real) to anon, authenticated;
grant execute on function public.remove_signature(text, uuid) to anon, authenticated;
grant execute on function public.signers(text) to anon, authenticated;
grant execute on function public.hit() to anon, authenticated;
grant execute on function public.ping(text) to anon, authenticated;
grant select on public.signatures to anon, authenticated;
revoke insert, update, delete on public.signatures from anon, authenticated;

-- Your owner key (keep it secret): run   select admin_key from private.settings;
