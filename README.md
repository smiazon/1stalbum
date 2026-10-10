# 1stalbum

new music every friday. one song a week for 12 weeks, album out jan 1st.

The page counts down to the next Friday in words, plays each week's song once it's out (no pause, only start over),
and has a blank white square that visitors sign for the twelve weeks. On January 1st signing closes and we sign it too.

- **Site:** GitHub Pages, published from the `docs/` folder on `main` (Settings → Pages → Deploy from a branch).
- **Guestbook:** a free Supabase project, set up by `supabase.sql`.

## Setting up the guestbook (once)

1. Create a free project at https://supabase.com.
2. Open **SQL Editor → New query**, paste all of `supabase.sql`, press **Run**.
3. In **Project Settings → API**, copy the **Project URL** and the **anon / publishable key**.
4. Put them in the `BACKEND` block near the top of the script in `docs/index.html`, commit and push.
   (Both are safe to publish: visitors can only do what the functions in `supabase.sql` allow.)
5. Your owner key: in the SQL Editor run `select admin_key from private.settings;`. Keep it secret.

Until step 4 is done, the page works but signing says "the guestbook opens soon."

## Each Friday

The twelve release times are the `SONGS` list at the top of the script in `docs/index.html`
(midnight Eastern, Oct 16 2026 to Jan 1 2027). When a song is finished:

1. Put the mp3 in `docs/tracks/` (e.g. `docs/tracks/01.mp3`).
2. Set that week's `src`, e.g. `{ at: '2026-10-16T00:00:00-04:00', src: 'tracks/01.mp3' }`.
3. Commit and push before midnight. Its number turns into a play link at exactly its Friday.

## Owner mode

Open `https://smiazon.github.io/1stalbum/#admin=<owner key>`:

- **Sign it as us:** tap a spot, type the name, press sign. No email needed, works after signing closes, written larger.
- **Remove a signature:** click it.
- **Who signed:** click **signers (csv)** top right for every name, email or phone, and time.

## Rules (enforced in the database)

- One signature per email or phone per day (New York time), and at most 3 per network per day.
- Slurs and hate terms are refused (`private.is_blocked` in `supabase.sql`).
- Signing closes on Jan 1 2027 for guests (`private.settings.closes_at`).
- Emails and phones are never shown on the page; only the owner key can read them.

## Preview locally

```
npm start            # http://localhost:3000
```
