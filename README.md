# new music every friday

One song, every Friday, for twelve weeks. Each one made that week, from nothing. January 1st, the album.

The page counts down to the next Friday in words ("song one arrives in six days…"), with a hairline showing how much of
the week has gone. Below it, 01 to 12: each Friday the next number becomes playable. Beside it is a blank white square
that visitors sign for the twelve weeks; on January 1st it closes and we sign it too.

No dependencies. Node 18+.

```
npm start            # http://localhost:3000
```

## Each Friday

The twelve release times are the `SONGS` list at the top of the script in `public/index.html`
(midnight Eastern, Oct 16 2026 to Jan 1 2027). When a song is finished:

1. Put the mp3 in `public/tracks/` (e.g. `public/tracks/01.mp3`).
2. Set that week's `src`, e.g. `{ at: '2026-10-16T00:00:00-04:00', src: 'tracks/01.mp3' }`.
3. Deploy before midnight. Its number turns into a play link at exactly its Friday.

Songs play to the end. No pause, only start over.

## The 12 weeks

The signing window is set on the server: `ALBUM_OPENS` (default `2026-10-09T00:00:00-04:00`) and `ALBUM_CLOSES`
(default `2027-01-01T00:00:00-05:00`, twelve weeks later). After it closes, guests can't sign; the page says so.

**Signing it ourselves:** open `https://yoursite/#admin=<ADMIN_KEY>`, tap where the signature should go, type the name and press sign.
No email is needed, it works before or after the cover closes, and it's written larger in marker. In the same mode, clicking any
signature on the cover removes it.

## Deploying

**Render (one click):** open https://render.com/deploy?repo=https://github.com/smiazon/1stalbum, sign in with GitHub,
and approve. `render.yaml` sets up the server, a 1 GB persistent disk for signatures, and random `ADMIN_KEY` / `SIGN_SALT`
values (find `ADMIN_KEY` under Environment in the dashboard). Disks need the Starter instance.

**Anywhere else:**

Any host that runs Node works (Render, Railway, Fly.io, a VPS). Start command: `npm start`. The host sets `PORT`.

Set these environment variables:

| var | why |
| --- | --- |
| `DATA_DIR` | Path to a **persistent disk/volume**. The guestbook, once-a-day records and visitor count are saved here. Without one, most hosts wipe them on every deploy. |
| `ADMIN_KEY` | Your owner key: sign the cover as the artist and remove signatures (see above). Keep it secret. |
| `SIGN_SALT` | Any long random string. Emails/phones are only stored as salted hashes. |
| `ALBUM_OPENS` / `ALBUM_CLOSES` | Optional. The 12-week signing window. |
| `SITE_TZ` | Optional. When "today" ends for the once-a-day rule. Default `America/New_York`. |

## Who signed

Every signature's name, email or phone, and time is kept in `DATA_DIR/contacts.json`. It's never shown on the page or
sent to visitors. To download it, open `https://yoursite/#admin=<ADMIN_KEY>` and click **signers (csv)** in the top right.
Each new signature is also printed to the server log (`signed: <name>`), so you can watch them arrive on your host's log page.

The page tells signers "only we see your email or phone". If you plan to email or text people, say so on the page first.

## Signing rules

- One signature per person per day, checked three ways: hashed email/phone, a browser cookie, and at most 3 marks per network per day (so shared wifi still works).
- Slurs and hate terms are blocked on the server (see `isBlocked` in `server.js`). Anything else can be removed with the admin link.
