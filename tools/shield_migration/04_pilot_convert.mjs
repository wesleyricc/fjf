// Fase 1 (100% LOCAL): converte os 8 escudos para WebP e gera folha de comparação PNG x WebP.
// Nada é enviado ao Storage nem gravado no Firestore.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import sharp from 'sharp';

const DIR = import.meta.dirname;
const ORIG = path.join(DIR, 'work', 'originals');
const WEBP = path.join(DIR, 'work', 'webp');
const PREVIEW = path.join(DIR, 'work', 'preview');
fs.mkdirSync(WEBP, { recursive: true });
fs.mkdirSync(PREVIEW, { recursive: true });

// sha(URL) -> time, vindo da Fase 0
const lines = fs.readFileSync(path.join(DIR, 'out', 'shields.csv'), 'utf8').split('\n').slice(1);
const teamBySha = new Map();
for (const l of lines) {
  const m = l.match(/^"([^"]*)","([^"]*)"/);
  if (m && m[2]) teamBySha.set(m[1], m[2]);
}

const VARIANTS = [
  { id: '192_q80', size: 192, opts: { quality: 80, alphaQuality: 90 } },
  { id: '256_q80', size: 256, opts: { quality: 80, alphaQuality: 90 } },
  { id: '256_q90', size: 256, opts: { quality: 90, alphaQuality: 100 } },
];

const hash = (b) => crypto.createHash('sha1').update(b).digest('hex').slice(0, 8);

// Achata sobre uma cor de fundo numa largura/altura caixa -> RGB cru (para PSNR)
async function flat(buf, box, bg) {
  return sharp(buf)
    .resize({ width: box, height: box, fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 }, kernel: 'lanczos3' })
    .flatten({ background: bg })
    .raw()
    .toBuffer();
}
function psnr(a, b) {
  let se = 0;
  for (let i = 0; i < a.length; i++) { const d = a[i] - b[i]; se += d * d; }
  const mse = se / a.length;
  return mse === 0 ? Infinity : 10 * Math.log10((255 * 255) / mse);
}

const seen = new Map(); // hash conteúdo -> time
const teams = [];
for (const f of fs.readdirSync(ORIG).filter((f) => f.endsWith('.png'))) {
  const buf = fs.readFileSync(path.join(ORIG, f));
  const h = hash(buf);
  const team = teamBySha.get(f.replace('.png', '')) ?? f;
  if (seen.has(h)) continue; // cópia idêntica (URL legada do cabeludos)
  seen.set(h, team);
  teams.push({ team, file: f, buf });
}
teams.sort((a, b) => a.team.localeCompare(b.team));

const results = [];
for (const t of teams) {
  const row = { team: t.team, orig_KB: +(t.buf.length / 1024).toFixed(1) };
  for (const v of VARIANTS) {
    const out = await sharp(t.buf)
      .resize({ width: v.size, height: v.size, fit: 'inside', withoutEnlargement: true, kernel: 'lanczos3' })
      .webp(v.opts)
      .toBuffer();
    fs.writeFileSync(path.join(WEBP, `${t.team}_${v.id}.webp`), out);
    row[`${v.id}_KB`] = +(out.length / 1024).toFixed(1);
    // PSNR a 300 px (pior caso: ~100 dp em tela 3x), sobre fundo branco e escuro
    const w = { r: 255, g: 255, b: 255 }, d = { r: 24, g: 24, b: 28 };
    const p = Math.min(
      psnr(await flat(t.buf, 300, w), await flat(out, 300, w)),
      psnr(await flat(t.buf, 300, d), await flat(out, 300, d)),
    );
    row[`${v.id}_PSNR`] = +p.toFixed(1);
  }
  fs.copyFileSync(path.join(ORIG, t.file), path.join(PREVIEW, `${t.team}.png`));
  results.push(row);
}
console.table(results);
const sum = (k) => results.reduce((a, r) => a + r[k], 0);
console.log(`Original: ${sum('orig_KB').toFixed(0)} KB`);
for (const v of VARIANTS) console.log(`${v.id}: ${sum(`${v.id}_KB`).toFixed(0)} KB | PSNR mínimo: ${Math.min(...results.map((r) => r[`${v.id}_PSNR`]))} dB`);
console.log('(PSNR > 40 dB = diferença praticamente invisível; 35-40 = muito boa)');

// ---- Folha de comparação em HTML ----
for (const t of teams) for (const v of VARIANTS) fs.copyFileSync(path.join(WEBP, `${t.team}_${v.id}.webp`), path.join(PREVIEW, `${t.team}_${v.id}.webp`));

const cols = [
  { label: 'PNG original', src: (t) => `${t}.png` },
  { label: 'WebP 256 q80', src: (t) => `${t}_256_q80.webp` },
  { label: 'WebP 192 q80', src: (t) => `${t}_192_q80.webp` },
];
const sizes = [24, 48, 100, 300];
const bg = (c) => `style="background:${c}"`;
const cell = (src, bgc) =>
  `<div class="cell" ${bg(bgc)}>${sizes.map((s) => `<img src="${src}" style="height:${s}px">`).join('')}</div>`;
const html = `<!doctype html><meta charset="utf-8"><title>Comparação de escudos</title>
<style>
body{font:13px system-ui;margin:16px;background:#eee}
h2{margin:18px 0 4px}
.grid{display:grid;grid-template-columns:repeat(${cols.length},1fr);gap:8px}
.head{font-weight:700;padding:4px}
.cell{display:flex;align-items:flex-end;gap:14px;padding:10px;border-radius:8px;border:1px solid #ccc}
.legend{color:#555;margin-bottom:8px}
</style>
<div class="legend">Alturas exibidas: 24 · 48 · 100 · 300 px (o 300 simula ~100&nbsp;dp em tela 3×). Cada time em fundo claro (acima) e escuro (abaixo).</div>
${teams.map((t) => `<h2>${t.team}</h2><div class="grid">
${cols.map((c) => `<div class="head">${c.label}</div>`).join('')}
${cols.map((c) => cell(c.src(t.team), '#fff')).join('')}
${cols.map((c) => cell(c.src(t.team), '#18181c')).join('')}
</div>`).join('')}`;
fs.writeFileSync(path.join(PREVIEW, 'index.html'), html);
console.log('\nFolha: ' + path.join(PREVIEW, 'index.html'));
