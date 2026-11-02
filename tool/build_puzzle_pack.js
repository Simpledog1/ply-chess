// Builds Ply's starter puzzle pack from the official Lichess puzzle CSV
// (CC0). Usage: node tool/build_puzzle_pack.js <lichess_db_puzzle.csv.zst> assets/puzzles/lichess_starter.csv
// Needs Node 22.15+ (zstd). Built for 1.4.0 from the 2026-11-01 export
// (sha256 7b0d235fa40cfd7fdb7df1fec56a96b3b6ee1496b32ed2eb05be90d0ebf94253).
// Selection is deterministic (fixed seed).
const fs = require('fs');
const zlib = require('zlib');
const readline = require('readline');
const [, , input, output] = process.argv;

const BANDS = []; for (let r = 600; r < 2800; r += 100) BANDS.push(r);
const PER_BAND = 370, PER_THEME = 45;
const NON_MOTIF = new Set(['opening','middlegame','endgame','short','long','veryLong','oneMove','advantage','crushing','equality','mate','master','masterVsMaster','superGM','mateIn1','mateIn2','mateIn3','mateIn4','mateIn5']);
let seed = 20261102;
const rand = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
// Per band: reservoir per primary theme.
const res = BANDS.map(() => new Map());
let seen = 0, kept = 0;

// The file is pzstd output: each zstd frame is preceded by a skippable
// frame holding its size. Node's decoder rejects skippable frames, so feed
// only the real frames.
const { Readable } = require('stream');
let pending = 0;
function* frames2(buf) {
  let o = 0;
  while (o < buf.length) {
    const magic = buf.readUInt32LE(o);
    if ((magic & 0xFFFFFFF0) === 0x184D2A50) {
      const size = buf.readUInt32LE(o + 4);
      if (size === 4) { pending = buf.readUInt32LE(o + 8); }
      o += 8 + size; continue;
    }
    if (!pending) throw new Error('frame without size at ' + o);
    const end = o + pending; pending = 0;
    for (let i = o; i < end; i += 1 << 20) yield buf.subarray(i, Math.min(i + (1 << 20), end));
    o = end;
  }
}
const rl = readline.createInterface({ input: Readable.from(frames2(fs.readFileSync(input))).pipe(zlib.createZstdDecompress()), crlfDelay: Infinity });
rl.on('line', (line) => {
  if (line.startsWith('PuzzleId')) return;
  seen++;
  const f = line.split(',');
  const rating = +f[3], rd = +f[4], pop = +f[5], plays = +f[6];
  const moves = f[2].split(' ');
  // Strong puzzles are rarer: accept a little more rating uncertainty there.
  const strong = rating >= 2500;
  if (!(rd <= (strong ? 100 : 80) && pop >= (strong ? 80 : 85) && plays >= (strong ? 300 : 1000) && moves.length <= 10)) return;
  const band = Math.floor((rating - 600) / 100);
  if (band < 0 || band >= BANDS.length) return;
  const themes = f[7].split(' ');
  const motif = themes.find((t) => !NON_MOTIF.has(t)) || (themes.includes('mate') ? 'mate' : 'other');
  kept++;
  const m = res[band];
  let r = m.get(motif); if (!r) { r = { n: 0, items: [] }; m.set(motif, r); }
  r.n++;
  const row = [f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], ''].join(',');
  if (r.items.length < PER_THEME) r.items.push(row);
  else { const j = Math.floor(rand() * r.n); if (j < PER_THEME) r.items[j] = row; }
});
rl.on('close', () => {
  const out = ['PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags'];
  const perBand = [];
  res.forEach((m) => {
    // Round-robin over themes so no single motif dominates a band.
    const lists = [...m.values()].map((r) => r.items.slice());
    const picked = [];
    while (picked.length < PER_BAND && lists.some((l) => l.length)) {
      for (const l of lists) { if (l.length && picked.length < PER_BAND) picked.push(l.pop()); }
    }
    perBand.push(picked.length);
    out.push(...picked);
  });
  fs.writeFileSync(output, out.join('\n') + '\n');
  console.log(JSON.stringify({ seen, eligible: kept, written: out.length - 1, perBand }));
});
