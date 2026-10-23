// The sixteen stickers: 16×16 pixel art, outlined in black and cut out with a white edge.
// Each one is a little function: given the centre of a pixel, what colour is it (or nothing).
const STICKER_IDS = ['heart', 'star', 'moon', 'sun', 'flame', 'bolt', 'cherry', 'flower',
  'eye', 'rainbow', 'note', 'disc', 'smile', 'ghost', 'sparkle', 'crown',
  'halo', 'wing', 'headphones', 'cassette', 'vinyl', 'mic', 'kiss', 'rose',
  'cloud', 'snowflake', 'mushroom', 'alien', 'skull', 'gem', 'butterfly', 'planet'];   // keep in step with supabase.sql
const STICKER_ART = (() => {
  const C = {
    r: '#ef3340', R: '#b4182c', p: '#ff9cc0', P: '#f46a9b', o: '#ff8a1f', y: '#ffd23f', Y: '#eba300', g: '#3cc56a', G: '#1d8a43',
    b: '#3b82f6', v: '#9b5de5', V: '#6a35b8', w: '#ffffff', k: '#1b1b1b', s: '#d9d9de', S: '#9a9aa2', c: '#5ee1ff',
    C: '#bff4ff', D: '#3a3a40', l: '#a6ee5a',
  };
  const inC = (x, y, cx, cy, r) => (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
  const inE = (x, y, cx, cy, rx, ry) => ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1;
  const inPoly = (x, y, pts) => {
    let c = false;
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      const [xi, yi] = pts[i], [xj, yj] = pts[j];
      if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) c = !c;
    }
    return c;
  };
  const nearSeg = (x, y, ax, ay, bx, by, r) => {
    const L = (bx - ax) ** 2 + (by - ay) ** 2, t = Math.max(0, Math.min(1, ((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / L));
    return Math.hypot(x - ax - t * (bx - ax), y - ay - t * (by - ay)) <= r;
  };
  const star = (cx, cy, R, r, n = 5, turn = -Math.PI / 2) =>
    Array.from({ length: n * 2 }, (_, i) => { const a = turn + i * Math.PI / n, d = i % 2 ? r : R; return [cx + Math.cos(a) * d, cy + Math.sin(a) * d]; });
  const STAR = star(8, 8.7, 7.4, 3.1);
  const hue = (x, y, cx, cy, l = 62) => `hsl(${(Math.atan2(y - cy, x - cx) * 180 / Math.PI + 360) % 360} 95% ${l}%)`;

  const ART = {
    heart(x, y) {
      if (!(inC(x, y, 5, 6.2, 3.4) || inC(x, y, 11, 6.2, 3.4) || inPoly(x, y, [[1.8, 7.4], [14.2, 7.4], [8, 14.6]]))) return null;
      if (inC(x, y, 4.4, 5.2, 1.1)) return 'w';
      return x + (y - 6) * .9 > 13 ? 'R' : 'r';
    },
    star(x, y) {
      if (!inPoly(x, y, STAR)) return null;
      if (inC(x, y, 6.6, 7.6, .8)) return 'w';
      return (x - 8) * .55 + (y - 8.7) * .85 > 2.2 ? 'Y' : 'y';
    },
    moon(x, y) {
      if (!inC(x, y, 8, 8, 6.8) || inC(x, y, 11.6, 5.4, 5.6)) return null;
      return inC(x, y, 7.4, 7.4, 6.2) ? 'y' : 'Y';
    },
    sun(x, y) {
      const d = Math.hypot(x - 8, y - 8);
      if (d <= 4.3) return inC(x, y, 6.6, 6.6, 1) ? 'w' : 'y';
      const a = Math.atan2(y - 8, x - 8), near = Math.abs(((a / (Math.PI / 4)) % 1 + 1.5) % 1 - .5) * (Math.PI / 4);
      return d >= 5.7 && d <= 7.7 && near * d < .75 ? 'o' : null;
    },
    flame(x, y) {
      const outer = inC(x, y, 8, 10.6, 4.8) || inPoly(x, y, [[3.4, 10.4], [12.6, 10.4], [10.4, 4.6], [8.6, 1], [7.8, 5.4], [5.6, 3.6]]);
      if (!outer) return null;
      const inner = inC(x, y, 8, 11.8, 2.6) || inPoly(x, y, [[5.5, 11.6], [10.5, 11.6], [8.6, 6.2]]);
      return inner ? (inC(x, y, 8, 12.6, 1.2) ? 'w' : 'y') : 'o';
    },
    bolt(x, y) {
      if (!inPoly(x, y, [[10.2, .8], [3.2, 9.4], [7.6, 9.4], [5.4, 15.2], [13, 6], [8.6, 6], [11, .8]])) return null;
      return x < 6.6 && y < 9.6 ? 'w' : 'y';
    },
    cherry(x, y) {
      if (inE(x, y, 11.8, 3.4, 2.4, 1.3)) return 'g';
      if (inC(x, y, 4.8, 11.6, 3.2) || inC(x, y, 11.2, 12.2, 3.2)) {
        if (inC(x, y, 3.8, 10.6, .9) || inC(x, y, 10.2, 11.2, .9)) return 'w';
        return 'r';
      }
      if (nearSeg(x, y, 5.4, 8.6, 9.4, 2.4, .62) || nearSeg(x, y, 10.8, 9.2, 9.4, 2.4, .62)) return 'G';
      return null;
    },
    flower(x, y) {
      if (inC(x, y, 8, 8, 2.6)) return inC(x, y, 7.2, 7.2, .8) ? 'w' : 'y';
      for (let k = 0; k < 5; k++) {
        const a = -Math.PI / 2 + k * 2 * Math.PI / 5;
        if (inC(x, y, 8 + Math.cos(a) * 4.7, 8 + Math.sin(a) * 4.7, 2.6)) return k % 2 ? 'P' : 'p';
      }
      return null;
    },
    eye(x, y) {
      const half = 5.6 * (1 - ((x - 8) / 7.8) ** 2) - .2;
      if (Math.abs(y - 8) > half) return null;
      if (inC(x, y, 6.7, 6.7, .8)) return 'w';
      if (inC(x, y, 8, 8, 1.6)) return 'k';
      if (inC(x, y, 8, 8, 3.6)) return hue(x, y, 8, 8);
      return 'w';
    },
    rainbow(x, y) {
      if (inC(x, y, 2.4, 13.4, 1.9) || inC(x, y, 4.2, 14, 1.4) || inC(x, y, 13.6, 13.4, 1.9) || inC(x, y, 11.8, 14, 1.4)) return 'w';
      const d = Math.hypot(x - 8, y - 14);
      if (y > 14 || d > 7.9 || d < 2.4) return null;
      return ['r', 'o', 'y', 'g', 'b', 'v'][Math.min(5, Math.floor((7.9 - d) / ((7.9 - 2.4) / 6)))];
    },
    note(x, y) {
      const head = inE(x, y, 4.6, 12.8, 2.4, 1.8) || inE(x, y, 11.6, 11, 2.4, 1.8);
      const stem = (x > 6.1 && x < 7.4 && y > 3 && y < 12.6) || (x > 13.1 && x < 14.4 && y > 1.4 && y < 10.8);
      const beam = inPoly(x, y, [[6.1, 2.6], [14.4, .8], [14.4, 3.6], [6.1, 5.4]]);
      if (!head && !stem && !beam) return null;
      if (inC(x, y, 3.8, 12.1, .7) || inC(x, y, 10.8, 10.3, .7)) return 'w';
      return head ? 'v' : 'V';
    },
    disc(x, y) {
      const d = Math.hypot(x - 8, y - 8);
      if (d > 7.3 || d < 1.3) return null;
      if (d <= 2.8) return 's';
      return hue(x * 2, y * 2, 16, 16, 80);
    },
    smile(x, y) {
      if (!inC(x, y, 8, 8, 7.1)) return null;
      if (inE(x, y, 5.6, 6.2, .9, 1.6) || inE(x, y, 10.4, 6.2, .9, 1.6)) return 'k';
      const d = Math.hypot(x - 8, y - 7.6);
      if (d >= 3.8 && d <= 5 && y > 9.4) return 'k';
      if (inC(x, y, 3.8, 10, .9) || inC(x, y, 12.2, 10, .9)) return 'p';
      return 'y';
    },
    ghost(x, y) {
      const body = inC(x, y, 8, 7.4, 5.8) || (x > 2.2 && x < 13.8 && y > 7.4 && y < 13.4);
      const notch = y > 12 && Math.floor((x - 2.2) / 2.9) % 2 === 1;
      if (!body || notch || x < 2.2 || x > 13.8) return null;
      if (inE(x, y, 6, 7.4, .9, 1.5) || inE(x, y, 10, 7.4, .9, 1.5)) return 'k';
      return x > 12 ? 's' : 'w';
    },
    sparkle(x, y) {
      const big = Math.sqrt(Math.abs(x - 7.2)) + Math.sqrt(Math.abs(y - 8.8)) <= Math.sqrt(6.6);
      const little = Math.sqrt(Math.abs(x - 13.2)) + Math.sqrt(Math.abs(y - 3)) <= Math.sqrt(2.7);
      if (little) return 'y';
      if (!big) return null;
      return Math.sqrt(Math.abs(x - 7.2)) + Math.sqrt(Math.abs(y - 8.8)) <= Math.sqrt(2.2) ? 'w' : 'c';
    },
    crown(x, y) {
      if (!inPoly(x, y, [[1.6, 13.6], [1.6, 4.2], [5, 8.2], [8, 2.2], [11, 8.2], [14.4, 4.2], [14.4, 13.6]])) return null;
      if (inC(x, y, 8, 11.6, 1.3)) return 'r';
      if (inC(x, y, 4.4, 11.6, 1) || inC(x, y, 11.6, 11.6, 1)) return 'b';
      return y > 10 ? 'Y' : 'y';
    },
    halo(x, y) {
      if (!inE(x, y, 8, 8.4, 7.4, 3.6) || inE(x, y, 8, 8.4, 5, 1.7)) return null;
      if (inC(x, y, 3.6, 7, .8)) return 'w';
      return y < 8.4 ? 'y' : 'Y';
    },
    wing(x, y) {
      if (inE(x, y, 7.2, 3.6, 6, 2.3)) return 'w';                                   // the shoulder
      for (let k = 0; k < 5; k++) {                                                       // five long feathers, fanned
        const a = (24 + k * 16) * Math.PI / 180, L = 14 - k * 1.6, cx = 2.4 + Math.cos(a) * L / 2, cy = 3.4 + Math.sin(a) * L / 2;
        const u = (x - cx) * Math.cos(a) + (y - cy) * Math.sin(a), v = -(x - cx) * Math.sin(a) + (y - cy) * Math.cos(a);
        if ((u / (L / 2)) ** 2 + (v / 1.55) ** 2 <= 1) return k % 2 ? 's' : 'w';
      }
      return null;
    },
    headphones(x, y) {
      if ((x > 1.2 && x < 4.8 && y > 8 && y < 14.4) || (x > 11.2 && x < 14.8 && y > 8 && y < 14.4)) return inC(x, y, 2.4, 9.4, .7) || inC(x, y, 12.4, 9.4, .7) ? 'p' : 'r';
      const d = Math.hypot(x - 8, y - 9);
      return d >= 5.4 && d <= 6.9 && y < 9.4 ? 'D' : null;
    },
    cassette(x, y) {
      if (!(x > .6 && x < 15.4 && y > 2.6 && y < 13.4)) return null;
      if (inC(x, y, 5.2, 7, .6) || inC(x, y, 10.8, 7, .6)) return 'w';
      if (inC(x, y, 5.2, 7, 1.7) || inC(x, y, 10.8, 7, 1.7)) return 'k';
      if (x > 2 && x < 14 && y > 4 && y < 9.6) return y < 5.2 ? 'r' : 'y';
      if (inPoly(x, y, [[3.4, 13.4], [4.6, 10.6], [11.4, 10.6], [12.6, 13.4]])) return 'S';
      return 'D';
    },
    vinyl(x, y) {
      const d = Math.hypot(x - 8, y - 8);
      if (d > 7.3 || d < .9) return null;
      if (d <= 2.6) return inC(x, y, 7.2, 7.2, .6) ? 'w' : 'r';
      const a = Math.atan2(y - 8, x - 8);
      if (Math.abs(a + 2.2) < .32 && d > 3.4) return 'S';
      return (d > 4.2 && d < 4.7) || (d > 5.7 && d < 6.2) ? 'D' : 'k';
    },
    mic(x, y) {
      if (inC(x, y, 8, 5, 3.9)) return inC(x, y, 6.6, 3.6, .8) ? 'w' : (Math.floor(x) + Math.floor(y)) % 2 ? 's' : 'S';
      if (x > 6.4 && x < 9.6 && y > 8.6 && y < 9.8) return 'Y';
      if (inPoly(x, y, [[6.4, 9.8], [9.6, 9.8], [9, 15.4], [7, 15.4]])) return 'D';
      return null;
    },
    kiss(x, y) {
      if (!inE(x, y, 8, 9, 7.3, 4.2) || (y < 6.6 && Math.abs(x - 8) < 1.4)) return null;
      if (Math.abs(y - 9.1 + Math.abs(x - 8) * .12) < .55 && Math.abs(x - 8) < 6) return 'R';
      if (inC(x, y, 10.2, 11, .8)) return 'p';
      return 'r';
    },
    rose(x, y) {
      if (inC(x, y, 8, 6, 4.8)) {
        const d = Math.hypot(x - 8.3, y - 6.2), a = Math.atan2(y - 6.2, x - 8.3);
        return Math.abs(((d - a * .55) % 1.8 + 1.8) % 1.8 - .9) < .3 ? 'R' : 'r';
      }
      if (inE(x, y, 5, 12.6, 2.4, 1.1) || inE(x, y, 11, 11.8, 2.4, 1.1)) return 'g';
      if (x > 7.4 && x < 8.6 && y > 10 && y < 15.6) return 'G';
      return null;
    },
    cloud(x, y) {
      if (!(inC(x, y, 4.8, 9.6, 3.2) || inC(x, y, 8.8, 7.4, 4.2) || inC(x, y, 12.2, 9.8, 3.1) || (x > 4 && x < 12.6 && y > 9.4 && y < 12.9))) return null;
      if (inC(x, y, 7.4, 5.8, .9)) return 'w';
      return y > 11.4 ? 's' : 'w';
    },
    snowflake(x, y) {
      if (inC(x, y, 8, 8, 1.3)) return 'w';
      for (let k = 0; k < 6; k++) {
        const a = Math.PI / 2 + k * Math.PI / 3, ex = 8 + Math.cos(a) * 7, ey = 8 + Math.sin(a) * 7;
        if (nearSeg(x, y, 8, 8, ex, ey, .55)) return 'c';
        const bx = 8 + Math.cos(a) * 4.4, by = 8 + Math.sin(a) * 4.4;
        for (const t of [.75, -.75]) if (nearSeg(x, y, bx, by, bx + Math.cos(a + t) * 2.2, by + Math.sin(a + t) * 2.2, .5)) return 'C';
      }
      return null;
    },
    mushroom(x, y) {
      if (inE(x, y, 8, 7.6, 7.3, 5.6) && y < 8.6) {
        if (inC(x, y, 4.8, 5.4, 1.2) || inC(x, y, 9.8, 4, 1.3) || inC(x, y, 12.6, 7, .9) || inC(x, y, 7.4, 7.4, .9)) return 'w';
        return 'r';
      }
      if (x > 5.2 && x < 10.8 && y >= 8.6 && y < 14.6) return y < 9.6 ? 'S' : x > 9.4 ? 's' : 'w';
      return null;
    },
    alien(x, y) {
      if (!(inE(x, y, 8, 6.8, 6.3, 5.6) || inPoly(x, y, [[3, 8], [13, 8], [8, 15.2]]))) return null;
      const tilt = (cx) => ((x - cx) * .9 + (y - 8.4) * (cx < 8 ? .45 : -.45));
      if (inE(x, y, 5.3, 8.6, 1.9, 1.2) && tilt(5.3) > -2.2) return inC(x, y, 5, 8.2, .5) ? 'w' : 'k';
      if (inE(x, y, 10.7, 8.6, 1.9, 1.2)) return inC(x, y, 10.4, 8.2, .5) ? 'w' : 'k';
      return inC(x, y, 5.4, 3.8, .9) ? 'w' : 'l';
    },
    skull(x, y) {
      const head = inC(x, y, 8, 7, 6.3) || (x > 4.4 && x < 11.6 && y > 9 && y < 14.6);
      if (!head) return null;
      if (inC(x, y, 5.6, 7.6, 1.7) || inC(x, y, 10.4, 7.6, 1.7) || inPoly(x, y, [[8, 9.4], [6.9, 11.4], [9.1, 11.4]])) return 'k';
      if (y > 12.4 && (Math.abs(x - 6.6) < .4 || Math.abs(x - 8) < .4 || Math.abs(x - 9.4) < .4)) return 'S';
      return x > 11 || (y > 12 && x > 10.2) ? 's' : 'w';
    },
    gem(x, y) {
      if (!inPoly(x, y, [[1.6, 6], [4.8, 2], [11.2, 2], [14.4, 6], [8, 15]])) return null;
      if (y < 6) return x < 5.6 ? 'w' : x < 10.4 ? 'C' : 'c';
      return x < 6 ? 'C' : x < 10 ? 'c' : 'b';
    },
    butterfly(x, y) {
      if (nearSeg(x, y, 8, 3.6, 5.6, .8, .45) || nearSeg(x, y, 8, 3.6, 10.4, .8, .45)) return 'k';
      if (x > 7.3 && x < 8.7 && y > 3.2 && y < 14) return 'k';
      if (inC(x, y, 4.2, 5.4, 1.1) || inC(x, y, 11.8, 5.4, 1.1)) return 'y';
      if (inE(x, y, 4.6, 5.8, 3.6, 3.9) || inE(x, y, 11.4, 5.8, 3.6, 3.9)) return 'o';
      if (inE(x, y, 5.2, 11.4, 2.8, 2.7) || inE(x, y, 10.8, 11.4, 2.8, 2.7)) return 'v';
      return null;
    },
    planet(x, y) {
      const ball = inC(x, y, 8, 8, 4.7), ring = inE(x, y, 8, 8.6, 7.8, 2.3) && !inE(x, y, 8, 8.6, 5.9, 1.2);
      if (ring && (y > 8.6 || !ball)) return 'c';
      if (!ball) return null;
      if (inC(x, y, 6.4, 5.8, .8)) return 'w';
      return (y > 6.4 && y < 7.4) || (y > 10 && y < 11) ? 'o' : 'y';
    },
  };

  const out = {};
  const G = 20, O = 2;                                   // 16 pixels of art, room for an outline and a white edge
  for (const id of STICKER_IDS) {
    const px = Array.from({ length: G }, () => Array(G).fill(null));
    for (let j = 0; j < 16; j++) for (let i = 0; i < 16; i++) {
      const c = ART[id](i + .5, j + .5);
      if (c) px[j + O][i + O] = C[c] || c;
    }
    const filled = (i, j) => i >= 0 && j >= 0 && i < G && j < G && px[j][i];
    const ring = (colour, near) => {
      const add = [];
      for (let j = 0; j < G; j++) for (let i = 0; i < G; i++) if (!px[j][i] && near.some(([a, b]) => filled(i + a, j + b))) add.push([i, j]);
      add.forEach(([i, j]) => { px[j][i] = colour; });
    };
    ring(C.k, [[1, 0], [-1, 0], [0, 1], [0, -1]]);                                         // the black line
    ring(C.w, [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]);      // the cut-out edge
    const cv = document.createElement('canvas'); cv.width = cv.height = G;
    const g = cv.getContext('2d');
    px.forEach((row, j) => row.forEach((c, i) => { if (c) { g.fillStyle = c; g.fillRect(i, j, 1, 1); } }));
    out[id] = cv;
  }
  return out;
})();
