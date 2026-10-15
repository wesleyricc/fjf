// Fase 0 - passo 3 (SOMENTE LEITURA): baixa cada escudo único e mede formato/dimensões/tamanho.
// Os originais são salvos em work/originals/ para reaproveitar nas fases seguintes.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import sharp from 'sharp';

const DIR = import.meta.dirname;
const OUT = path.join(DIR, 'out');
const ORIG = path.join(DIR, 'work', 'originals');
fs.mkdirSync(ORIG, { recursive: true });

// --- CSV simples (campos entre aspas) ---
function parseCsv(text) {
  const rows = [];
  let row = [], cur = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"' && text[i + 1] === '"') { cur += '"'; i++; }
      else if (c === '"') q = false;
      else cur += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n') { row.push(cur); rows.push(row); row = []; cur = ''; }
    else if (c !== '\r') cur += c;
  }
  if (cur || row.length) { row.push(cur); rows.push(row); }
  const [head, ...body] = rows;
  return body.map((r) => Object.fromEntries(head.map((h, i) => [h, r[i]])));
}

const occ = parseCsv(fs.readFileSync(path.join(OUT, 'occurrences.csv'), 'utf8'));
const isShieldField = (f) => /shield|logo/i.test(f);

// URL -> onde aparece
const urls = new Map();
for (const o of occ.filter((o) => isShieldField(o.field))) {
  const col = o.collection.replace(/^championships\/[^/]+\//, 'championships/{temporada}/');
  if (!urls.has(o.url)) urls.set(o.url, { refs: 0, where: new Set(), docs: new Set() });
  const e = urls.get(o.url);
  e.refs++;
  e.where.add(`${col}:${o.field}`);
  e.docs.add(o.doc);
}

// Nome do time via teams_directory / teams_participation (shield_url -> doc id)
const teamIdByUrl = new Map();
for (const o of occ) {
  if (o.field === 'shield_url') teamIdByUrl.set(o.url, o.doc.split('/').pop());
}

const results = [];
for (const [url, e] of urls) {
  const r = {
    sha: crypto.createHash('sha1').update(url).digest('hex').slice(0, 8),
    team_doc_id: teamIdByUrl.get(url) ?? '',
    host: new URL(url).host,
    refs: e.refs,
    docs: e.docs.size,
    where: [...e.where].join(' | '),
    url,
  };
  try {
    const res = await fetch(url);
    r.status = res.status;
    r.content_type = res.headers.get('content-type') ?? '';
    r.cache_control = res.headers.get('cache-control') ?? '';
    r.cors = res.headers.get('access-control-allow-origin') ?? '';
    if (res.ok) {
      const buf = Buffer.from(await res.arrayBuffer());
      const meta = await sharp(buf).metadata();
      r.bytes = buf.length;
      r.format = meta.format;
      r.width = meta.width;
      r.height = meta.height;
      r.alpha = !!meta.hasAlpha;
      fs.writeFileSync(path.join(ORIG, `${r.sha}.${meta.format}`), buf);
    }
  } catch (err) {
    r.error = String(err.message ?? err);
  }
  results.push(r);
}

const cols = ['sha', 'team_doc_id', 'host', 'status', 'format', 'width', 'height', 'alpha', 'bytes', 'content_type', 'cache_control', 'cors', 'refs', 'docs', 'where', 'error', 'url'];
const csv = (v) => `"${String(v ?? '').replaceAll('"', '""')}"`;
fs.writeFileSync(
  path.join(OUT, 'shields.csv'),
  [cols.join(','), ...results.map((r) => cols.map((c) => csv(r[c])).join(','))].join('\n'),
);

console.log(`\nEscudos únicos: ${results.length}`);
console.table(
  results.map((r) => ({
    sha: r.sha, time: r.team_doc_id, host: r.host.replace('.googleapis.com', ''), http: r.status,
    fmt: r.format, dim: r.width ? `${r.width}x${r.height}` : '', alpha: r.alpha, KB: r.bytes ? (r.bytes / 1024).toFixed(1) : '',
    refs: r.refs, docs: r.docs, cache: r.cache_control, cors: r.cors, erro: r.error ?? '',
  })),
);
const total = results.reduce((a, r) => a + (r.bytes ?? 0), 0);
console.log(`Soma dos escudos únicos: ${(total / 1024).toFixed(1)} KB`);
const weighted = results.reduce((a, r) => a + (r.bytes ?? 0) * r.refs, 0);
console.log(`Soma ponderada pelas referências (aprox. se todas as cópias fossem baixadas): ${(weighted / 1024 / 1024).toFixed(2)} MB`);
