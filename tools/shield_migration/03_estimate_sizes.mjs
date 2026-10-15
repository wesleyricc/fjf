// Estimativa NUMÉRICA local (não envia nada): tamanho em WebP para diferentes resoluções/qualidades.
// A avaliação visual fica para a Fase 1.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import sharp from 'sharp';

const ORIG = path.join(import.meta.dirname, 'work', 'originals');
const files = fs.readdirSync(ORIG).filter((f) => f.endsWith('.png'));

const hash = (b) => crypto.createHash('sha1').update(b).digest('hex').slice(0, 8);
console.log('Hash do CONTEÚDO (detecta cópias idênticas com URLs diferentes):');
for (const f of files) console.log(' ', f, hash(fs.readFileSync(path.join(ORIG, f))));

const variants = [
  { nome: 'max128 q80', size: 128, opts: { quality: 80, alphaQuality: 90 } },
  { nome: 'max192 q80', size: 192, opts: { quality: 80, alphaQuality: 90 } },
  { nome: 'max256 q80', size: 256, opts: { quality: 80, alphaQuality: 90 } },
  { nome: 'max192 lossless', size: 192, opts: { lossless: true } },
];

const rows = [];
const totals = Object.fromEntries(variants.map((v) => [v.nome, 0]));
let totalOrig = 0;
for (const f of files) {
  const buf = fs.readFileSync(path.join(ORIG, f));
  totalOrig += buf.length;
  const row = { arquivo: f, orig_KB: +(buf.length / 1024).toFixed(1) };
  for (const v of variants) {
    const out = await sharp(buf)
      .resize({ width: v.size, height: v.size, fit: 'inside', withoutEnlargement: true })
      .webp(v.opts)
      .toBuffer();
    row[v.nome + ' KB'] = +(out.length / 1024).toFixed(1);
    totals[v.nome] += out.length;
  }
  rows.push(row);
}
console.table(rows);
console.log(`Original total: ${(totalOrig / 1024).toFixed(0)} KB`);
for (const v of variants) {
  const t = totals[v.nome];
  console.log(`${v.nome.padEnd(16)} total ${(t / 1024).toFixed(0)} KB  (-${((1 - t / totalOrig) * 100).toFixed(0)}%)`);
}
