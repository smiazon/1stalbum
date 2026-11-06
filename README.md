# 1stalbum

new music every friday. one song a week for 12 weeks, album out jan 1st.

The page is a message, late at night: no interface, just lines arriving one at a time, as if someone is
typing to you. A greeting that knows what time it is where you are, what the project is, this week's song
("play it"), how many others are listening right now, the countdown, the songs before it, the cover everyone
signs (a live thumbnail; tap to sign with paint, words and stickers), and "miko says hi" (she peeks up
from the bottom; her eyes follow you, and she likes being petted).

Play takes the whole screen with a small bar (play/pause, time, a draggable line, back). Songs one and two
keep their original visuals (the angel, the render); the rest get a warm light breathing with the song.
Songs play straight from the mp3; the visuals read a spectrum computed from the same file.

- `docs/img/miko.png` + `miko.json`: Miko cut out from our photo, with eye positions.
- `docs/stickers.js`: the 32 pixel stickers. Their ids must match `sticker_ids` in `supabase.sql`.

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
2. Set that week's `src` and `title`, e.g. `{ at: '2026-10-16T00:00:00-04:00', src: 'tracks/01.mp3', title: 'im so inlove' }`.
3. Commit and push before midnight. Its number turns into a play link at exactly its Friday.

## Owner mode

Open `https://smiazon.github.io/1stalbum/#admin=<owner key>`:

(Or just sign with smiazon@gmail.com: that email has no daily limit, on any device.)

- **paint:** sign as many times as you like, saved under your email.
- **write:** tap a spot, type the name, press sign. Our signature, in marker, works after signing closes.
- **hide:** tap a mark to hide it. Nothing is ever deleted.
- **signers:** every name, email or phone, and time, as a csv. (Or the dashboard: `owner.html#admin=<owner key>`.)
- **artwork:** the signed album as a 3000×3000 image, every signature in place.
  Signatures stay saved from day one through Jan 1; nothing resets between weeks.

## Rules (enforced in the database)

- One signature per email or phone per day (New York time), and at most 3 per network per day.
- Slurs and hate terms are refused (`private.is_blocked` in `supabase.sql`).
- Signing closes on Jan 1 2027 for guests (`private.settings.closes_at`).
- Emails and phones are never shown on the page; only the owner key can read them.

## Preview locally

```
npm start            # http://localhost:3000
```

## Nothing is ever erased, and there are backups

- **Hide, never delete.** In owner mode, "hide" only hides a mark from the page; it stays in the database. The database
  refuses any delete or wipe of the canvas and the signer list (even typed into the SQL editor).
- **Bring a mark back:** in the SQL editor, `update public.drawings set hidden = false where id = '<id>';`
  (or `public.signatures`), or call `restore_mark(<owner key>, <id>)`. To see hidden ones:
  `select id, created_at from public.drawings where hidden;`
- **Nightly snapshots in the database** at 3:17 am Eastern, kept 90 days (`private.snapshots`), with the canvas,
  hidden marks and the signer list. To see them: `select taken_at from private.snapshots order by taken_at desc;`
- **Daily copies on the Mac** at 3:23 am (and at login) in `~/1stalbum backups` (also linked as Documents → 1stalbum backups),
  by `tools/backup.sh` via `~/Library/LaunchAgents/com.smiazon.1stalbum-backup.plist`. To include hidden marks and the
  signer list, save the owner key in `~/.1stalbum-owner-key`. Run one by hand: `bash tools/backup.sh`.
  To stop it: `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.smiazon.1stalbum-backup.plist`.
