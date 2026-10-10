// Tiny zero-dependency server: serves /public, stores guestbook marks, counts who's here.
// Run: node server.js
//
// Env (all optional):
//   PORT        port to listen on (default 3000)
//   DATA_DIR    where signatures/signers/keys live; point at a persistent disk in production
//   SITE_TZ     timezone that decides when "today" ends for the once-a-day rule (default America/New_York)
//   SIGN_SALT   secret salt for hashing emails/phones (otherwise generated into DATA_DIR/.salt)
//   ADMIN_KEY   owner key for removing marks (otherwise generated into DATA_DIR/.admin-key)
const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;
const PUBLIC = path.join(__dirname, 'public');
const DATA = process.env.DATA_DIR || __dirname;
fs.mkdirSync(DATA, { recursive: true });
const DB = path.join(DATA, 'signatures.json');      // public: what's painted on the canvas
const SIGNERS = path.join(DATA, 'signers.json');    // private: hashed contact -> last day signed
const CONTACTS = path.join(DATA, 'contacts.json');  // private, owner only: who signed and how to reach them
const HITS = path.join(DATA, 'hits.json');          // the visitor counter
const SALT_FILE = path.join(DATA, '.salt');
const ADMIN_FILE = path.join(DATA, '.admin-key');
const TZ = process.env.SITE_TZ || 'America/New_York';
const MAX_PER_IP_PER_DAY = 3;
// Signing is open for 12 weeks, then it closes and only the artist signs.
const ALBUM_OPENS = process.env.ALBUM_OPENS || '2026-10-09T00:00:00-04:00';
const ALBUM_CLOSES = process.env.ALBUM_CLOSES || '2027-01-01T00:00:00-05:00';   // a household or venue wifi can still sign, a script can't
const COLORS = ['#111111', '#d1232a', '#1f4fd1', '#14894a', '#7a2bc9', '#e0662a'];
const FONTS = ['Caveat', 'Reenie Beanie', 'Rock Salt', 'Homemade Apple', 'Nothing You Could Do'];
const PENS = ['#1b1b1b', '#1d3b8f', '#b3261e'];   // black, blue and red ballpoint
const STICKERS = ['⭐', '💖', '🌸', '🌙', '⚡', '🎵', '🔥', '🌈', '🦋', '🍒', '👁️', '✌️'];
const MAX_SIGS = 2000;

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript',
  '.json': 'application/json', '.mp3': 'audio/mpeg', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};

// write to a temp file then rename, so a crash mid-write never corrupts the data
const save = (f, data) => { fs.writeFileSync(f + '.tmp', JSON.stringify(data)); fs.renameSync(f + '.tmp', f); };
const readJSON = (f, fallback) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return fallback; } };
let signatures = readJSON(DB, []);
let signers = readJSON(SIGNERS, {});
let contacts = readJSON(CONTACTS, []);
let hits = readJSON(HITS, { count: 0 }).count || 0;
let hitsDirty = false;
setInterval(() => { if (hitsDirty) { save(HITS, { count: hits }); hitsDirty = false; } }, 5000).unref();

// Contacts are never stored in plain text, only as a salted hash used to enforce one mark per day.
let SALT = process.env.SIGN_SALT;
if (!SALT) {
  try { SALT = fs.readFileSync(SALT_FILE, 'utf8'); }
  catch { SALT = crypto.randomBytes(24).toString('hex'); fs.writeFileSync(SALT_FILE, SALT); }
}
function normalizeContact(raw) {
  const v = String(raw || '').trim().toLowerCase();
  if (/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v)) return v;
  const digits = v.replace(/[^\d]/g, '');
  if (/^\+?[\d\s().-]+$/.test(v) && digits.length >= 7 && digits.length <= 15) return digits;
  return null;
}
// Owner-only key for removing marks. Set ADMIN_KEY, or one is generated into .admin-key.
let ADMIN_KEY = process.env.ADMIN_KEY;
if (!ADMIN_KEY) {
  try { ADMIN_KEY = fs.readFileSync(ADMIN_FILE, 'utf8').trim(); }
  catch { ADMIN_KEY = crypto.randomBytes(18).toString('base64url'); fs.writeFileSync(ADMIN_FILE, ADMIN_KEY); }
}
const isAdmin = (req) => {
  const k = Buffer.from(String(req.headers['x-admin-key'] || ''));
  const a = Buffer.from(ADMIN_KEY);
  return k.length === a.length && crypto.timingSafeEqual(k, a);
};

// ---- name filter -------------------------------------------------------------
// Names are normalised (accents, leetspeak, spacing, repeated letters) so "n 1 g g @"
// style dodges still match. It only targets slurs and hate terms; anything else
// that slips through can be removed with the admin link.
const LEET = { 0: 'o', 1: 'i', '!': 'i', '|': 'i', 3: 'e', 4: 'a', '@': 'a', 5: 's', $: 's', 7: 't', 8: 'b', 9: 'g' };
// Whole words (after normalising), so names like Nigel, Scunthorpe or Spicy pass.
const BLOCKED_WORDS = [
  /^n+i+g+(?:[aeou]h?|[aeo]+rs?|[aeo]+z|as|let|s|z)?$/, /^fag+(?:s|ot+s?|got+s?)?$/, /^chinks?$/, /^spics?$/,
  /^kikes?$/, /^wetbacks?$/, /^beaners?$/, /^gooks?$/, /^tran+(?:y|ie)s?$/, /^retard(?:s|ed)?$/,
  /^dykes?$/, /^cunts?$/, /^kkk$/, /^hitler$/, /^coons?$/,
];
// Roots distinctive enough to catch even when spaced out or glued to other words.
const BLOCKED_ANYWHERE = [
  /n+i+gg/, /fagg?ot/, /wetback/, /towelhead/, /raghead/, /hitler/, /siegheil/, /whitepower/,
  /kkk/, /gasthe/, /1488/,
];
function isBlocked(name) {
  const base = name.toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '');
  const leet = base.replace(/[0134578@!|$9]/g, (c) => LEET[c] || c);
  const words = leet.split(/[^a-z]+/).filter(Boolean);
  // "n i g" style spacing: if every word is a single letter, read them as one word
  if (words.length > 1 && words.every((w) => w.length === 1)) words.push(words.join(''));
  const variants = (w) => [w, w.replace(/(.)\1+/g, '$1')];
  if (words.some((w) => variants(w).some((v) => BLOCKED_WORDS.some((re) => re.test(v))))) return true;
  const squashed = leet.replace(/[^a-z]/g, '');
  return BLOCKED_ANYWHERE.some((re) => re.test(base) || re.test(squashed));
}

const hash = (c) => crypto.createHash('sha256').update(SALT + c).digest('hex');
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: TZ }); // YYYY-MM-DD in SITE_TZ
const num = (v, lo, hi) => (typeof v === 'number' && isFinite(v) ? Math.min(hi, Math.max(lo, v)) : null);

const lastPost = new Map();  // ip -> timestamp, light spam guard
let ipDay = today(), ipCount = new Map();  // ip -> marks today

// behind a host's proxy the real visitor is the first x-forwarded-for entry
const clientIp = (req) => String(req.headers['x-forwarded-for'] || '').split(',')[0].trim() || req.socket.remoteAddress;
const cookie = (req, k) => (String(req.headers.cookie || '').match(new RegExp('(?:^|; )' + k + '=([^;]*)')) || [])[1];

function sendJSON(res, code, body, headers = {}) {
  res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...headers });
  res.end(JSON.stringify(body));
}

// ---- peers: who has the page open right now ----------------------------------
const seen = new Map(); // visitor id -> last ping
function handlePing(req, res) {
  let raw = '';
  req.on('data', (c) => { raw += c; if (raw.length > 200) req.destroy(); });
  req.on('end', () => {
    let id = '';
    try { id = String(JSON.parse(raw).id || '').slice(0, 24); } catch {}
    const t = Date.now();
    if (id) seen.set(id, t);
    for (const [k, v] of seen) if (t - v > 45000) seen.delete(k);
    sendJSON(res, 200, { peers: Math.max(1, seen.size), now: t });
  });
}

function handleSign(req, res) {
  const ip = clientIp(req);
  const now = Date.now();
  if (isAdmin(req)) return handleArtistSign(req, res);
  if (now >= new Date(ALBUM_CLOSES).getTime()) return sendJSON(res, 403, { error: 'signing is closed. now we sign it.' });
  if (now - (lastPost.get(ip) || 0) < 5000) return sendJSON(res, 429, { error: 'slow down' });
  const tooSoon = { error: 'you already signed today. come back tomorrow.' };
  if (cookie(req, 'signed') === today()) return sendJSON(res, 409, tooSoon);
  if (ipDay !== today()) { ipDay = today(); ipCount = new Map(); }
  if ((ipCount.get(ip) || 0) >= MAX_PER_IP_PER_DAY) return sendJSON(res, 409, tooSoon);

  let raw = '';
  req.on('data', (c) => { raw += c; if (raw.length > 2000) req.destroy(); });
  req.on('end', () => {
    let data;
    try { data = JSON.parse(raw); } catch { return sendJSON(res, 400, { error: 'bad json' }); }
    const name = String(data.name || '').replace(/\s+/g, ' ').trim().slice(0, 32);
    if (!name) return sendJSON(res, 400, { error: 'add your name' });
    if (isBlocked(name)) return sendJSON(res, 400, { error: "let's keep the guestbook kind. try another name." });
    const contact = normalizeContact(data.contact);
    if (!contact) return sendJSON(res, 400, { error: 'enter a valid email or phone number' });
    const who = hash(contact);
    if (signers[who] === today()) return sendJSON(res, 409, tooSoon);
    if (signatures.length >= MAX_SIGS) return sendJSON(res, 403, { error: 'the guestbook is full' });

    const x = num(data.x, 1, 86), y = num(data.y, 4, 96);
    const sx = num(data.sx, 4, 96), sy = num(data.sy, 4, 96);

    const sig = {
      id: crypto.randomBytes(6).toString('hex'),
      name,
      color: PENS.includes(data.color) ? data.color : COLORS.includes(data.color) ? data.color : PENS[0],
      font: FONTS[Math.floor(Math.random() * FONTS.length)],
      x: x ?? 4 + Math.random() * 78,   // % across the canvas
      y: y ?? 8 + Math.random() * 84,   // % down the canvas
      rot: Math.round((Math.random() - 0.5) * 50),
      size: Math.round(18 + Math.random() * 14),
      sticker: STICKERS.includes(data.sticker) ? data.sticker : null,
      sx: sx ?? null, sy: sy ?? null,   // sticker spot, placed on its own
      srot: Math.round((Math.random() - 0.5) * 40),
      at: now,
    };
    signatures.push(sig);
    lastPost.set(ip, now);
    ipCount.set(ip, (ipCount.get(ip) || 0) + 1);
    signers[who] = today();
    contacts.push({ id: sig.id, name, contact, at: new Date(now).toISOString() });
    save(CONTACTS, contacts);
    console.log(`signed: ${name}`);
    save(DB, signatures);
    save(SIGNERS, signers);
    // remember this browser too, until the day rolls over
    sendJSON(res, 201, sig, { 'Set-Cookie': `signed=${today()}; Max-Age=86400; Path=/; SameSite=Lax; HttpOnly` });
  });
}

// The artist's signature: no daily limit, allowed after signing closes, written larger.
function handleArtistSign(req, res) {
  let raw = '';
  req.on('data', (c) => { raw += c; if (raw.length > 2000) req.destroy(); });
  req.on('end', () => {
    let data;
    try { data = JSON.parse(raw); } catch { return sendJSON(res, 400, { error: 'bad json' }); }
    const name = String(data.name || '').replace(/\s+/g, ' ').trim().slice(0, 32);
    if (!name) return sendJSON(res, 400, { error: 'add your name' });
    const sig = {
      id: crypto.randomBytes(6).toString('hex'), name, artist: true,
      color: PENS.includes(data.color) ? data.color : PENS[0],
      font: 'Rock Salt',
      x: num(data.x, 1, 86) ?? 30, y: num(data.y, 4, 96) ?? 80,
      rot: Math.round((Math.random() - 0.5) * 12), size: 32, at: Date.now(),
    };
    signatures.push(sig);
    save(DB, signatures);
    sendJSON(res, 201, sig);
  });
}

function serveStatic(req, res) {
  const urlPath = decodeURIComponent(req.url.split('?')[0]);
  let file = path.normalize(path.join(PUBLIC, urlPath === '/' ? 'index.html' : urlPath));
  if (!file.startsWith(PUBLIC)) { res.writeHead(403); return res.end(); }

  fs.stat(file, (err, stat) => {
    if (err || !stat.isFile()) { res.writeHead(404); return res.end('not found'); }
    const type = TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream';
    const range = req.headers.range;

    // Range requests, so audio streams
    if (range) {
      const [s, e] = range.replace('bytes=', '').split('-');
      const start = parseInt(s, 10) || 0;
      const end = e ? parseInt(e, 10) : stat.size - 1;
      if (start >= stat.size || end >= stat.size) {
        res.writeHead(416, { 'Content-Range': `bytes */${stat.size}` });
        return res.end();
      }
      res.writeHead(206, {
        'Content-Type': type, 'Accept-Ranges': 'bytes',
        'Content-Range': `bytes ${start}-${end}/${stat.size}`, 'Content-Length': end - start + 1,
      });
      return fs.createReadStream(file, { start, end }).pipe(res);
    }
    res.writeHead(200, {
      'Content-Type': type, 'Content-Length': stat.size, 'Accept-Ranges': 'bytes',
      'Cache-Control': type.startsWith('text/html') ? 'no-cache' : 'public, max-age=3600',
      'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'same-origin',
    });
    fs.createReadStream(file).pipe(res);
  });
}

http.createServer((req, res) => {
  if (req.url === '/api/signatures' && req.method === 'GET') return sendJSON(res, 200, signatures);
  if (req.url === '/api/signatures' && req.method === 'POST') return handleSign(req, res);
  if (req.url === '/api/ping' && req.method === 'POST') return handlePing(req, res);
  if (req.url === '/api/signing' && req.method === 'GET') return sendJSON(res, 200, { opens: ALBUM_OPENS, closes: ALBUM_CLOSES, now: Date.now() });
  if (req.url === '/api/hit' && req.method === 'POST') { hits++; hitsDirty = true; return sendJSON(res, 200, { count: hits }); }
  // owner only: everyone who signed, with their contact, as a spreadsheet
  if (req.url === '/api/signers.csv' && req.method === 'GET') {
    if (!isAdmin(req)) return sendJSON(res, 403, { error: 'not allowed' });
    const cell = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    const live = new Set(signatures.map((s) => s.id));
    const rows = [['signed at', 'name', 'email or phone', 'still on the page']]
      .concat(contacts.map((c) => [c.at, c.name, c.contact, live.has(c.id) ? 'yes' : 'removed']));
    res.writeHead(200, {
      'Content-Type': 'text/csv; charset=utf-8', 'Cache-Control': 'no-store',
      'Content-Disposition': `attachment; filename="signers-${today()}.csv"`,
    });
    return res.end(rows.map((r) => r.map(cell).join(',')).join('\n'));
  }
  if (req.url.startsWith('/api/signatures/') && req.method === 'DELETE') {
    if (!isAdmin(req)) return sendJSON(res, 403, { error: 'not allowed' });
    const id = req.url.split('/').pop();
    const before = signatures.length;
    signatures = signatures.filter((s) => s.id !== id);
    if (signatures.length === before) return sendJSON(res, 404, { error: 'not found' });
    save(DB, signatures);
    return sendJSON(res, 200, { ok: true });
  }
  if (req.method === 'GET' || req.method === 'HEAD') return serveStatic(req, res);
  res.writeHead(405); res.end();
}).listen(PORT, () => {
  console.log(`new music every friday → http://localhost:${PORT}`);
  console.log(`owner link (remove marks): /#admin=<ADMIN_KEY, or the key in ${ADMIN_FILE}>`);
});
