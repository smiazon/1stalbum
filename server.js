// Local preview only: serves docs/ at http://localhost:3000 (the live site is GitHub Pages).
// The guestbook talks to Supabase directly, so there's no API here.
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;
const DOCS = path.join(__dirname, 'docs');
const TYPES = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.json': 'application/json',
  '.mp3': 'audio/mpeg', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};

http.createServer((req, res) => {
  const urlPath = decodeURIComponent(req.url.split('?')[0]);
  const file = path.normalize(path.join(DOCS, urlPath === '/' ? 'index.html' : urlPath));
  if (!file.startsWith(DOCS)) { res.writeHead(403); return res.end(); }
  fs.stat(file, (err, stat) => {
    if (err || !stat.isFile()) { res.writeHead(404); return res.end('not found'); }
    const type = TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream';
    const range = /bytes=(\d*)-(\d*)/.exec(req.headers.range || '');
    if (range) {   // so audio can stream
      const start = parseInt(range[1], 10) || 0;
      const end = range[2] ? parseInt(range[2], 10) : stat.size - 1;
      res.writeHead(206, { 'Content-Type': type, 'Accept-Ranges': 'bytes', 'Content-Range': `bytes ${start}-${end}/${stat.size}`, 'Content-Length': end - start + 1 });
      return fs.createReadStream(file, { start, end }).pipe(res);
    }
    res.writeHead(200, { 'Content-Type': type, 'Content-Length': stat.size, 'Accept-Ranges': 'bytes' });
    fs.createReadStream(file).pipe(res);
  });
}).listen(PORT, () => console.log(`preview → http://localhost:${PORT}`));
