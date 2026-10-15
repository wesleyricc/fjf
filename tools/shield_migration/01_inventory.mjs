// Fase 0 - passo 2 (SOMENTE LEITURA): varre o Firestore de produção e inventaria TODAS as URLs
// de imagem encontradas, com coleção/campo de origem. Não grava nada.
//
// Saídas (tools/shield_migration/out/):
//   occurrences.csv -> uma linha por (documento, campo, URL)
//   urls.csv        -> uma linha por URL única, com onde aparece
import fs from 'node:fs';
import path from 'node:path';
import { listCollectionIds, listDocs, val } from './lib.mjs';

const OUT = path.join(import.meta.dirname, 'out');
fs.mkdirSync(OUT, { recursive: true });

// Coleções globais pequenas que podem conter escudos. (fantasy_teams/orders/bolao_* etc. ficam de fora.)
const GLOBAL = ['teams_directory', 'players', 'fantasy_market_players', 'voting_stats'];

const urlRe = /^https?:\/\//i;

function walk(node, p, cb) {
  if (typeof node === 'string') {
    if (urlRe.test(node)) cb(p, node);
  } else if (Array.isArray(node)) {
    node.forEach((n) => walk(n, `${p}[]`, cb));
  } else if (node && typeof node === 'object') {
    for (const [k, v] of Object.entries(node)) walk(v, p ? `${p}.${k}` : k, cb);
  }
}

const occ = [];
const readCounts = {};

async function scan(collectionPath) {
  let n = 0;
  for await (const d of listDocs(collectionPath)) {
    n++;
    const docPath = d.name.split('/documents/')[1];
    const data = Object.fromEntries(Object.entries(d.fields ?? {}).map(([k, v]) => [k, val(v)]));
    walk(data, '', (field, url) => occ.push({ doc: docPath, collection: collectionPath, field, url }));
  }
  readCounts[collectionPath] = n;
}

for (const c of GLOBAL) await scan(c);

const seasons = [];
for await (const d of listDocs('championships', ['name'])) seasons.push(d.name.split('/').pop());
for (const s of seasons) {
  for (const sub of await listCollectionIds(`championships/${s}`)) {
    await scan(`championships/${s}/${sub}`);
  }
}

const csv = (v) => `"${String(v ?? '').replaceAll('"', '""')}"`;

fs.writeFileSync(
  path.join(OUT, 'occurrences.csv'),
  ['doc,collection,field,url', ...occ.map((o) => [o.doc, o.collection, o.field, o.url].map(csv).join(','))].join('\n'),
);

// Agrupa por URL única
const byUrl = new Map();
for (const o of occ) {
  // normaliza o nome da coleção para agrupar por tipo (troca a temporada por {temporada})
  const col = o.collection.replace(/^championships\/[^/]+\//, 'championships/{temporada}/');
  const where = `${col}:${o.field}`;
  if (!byUrl.has(o.url)) byUrl.set(o.url, { count: 0, where: new Map() });
  const e = byUrl.get(o.url);
  e.count++;
  e.where.set(where, (e.where.get(where) ?? 0) + 1);
}

const rows = [...byUrl.entries()].map(([url, e]) => {
  let u;
  try { u = new URL(url); } catch { u = { host: '?', pathname: '' }; }
  const filename = decodeURIComponent(u.pathname.split('/').pop() || '');
  return {
    url,
    host: u.host,
    pathname: decodeURIComponent(u.pathname),
    ext: (filename.split('.').pop() || '').toLowerCase(),
    occurrences: e.count,
    where: [...e.where.entries()].map(([k, n]) => `${k}(${n})`).join(' | '),
  };
});

fs.writeFileSync(
  path.join(OUT, 'urls.csv'),
  ['host,ext,occurrences,pathname,where,url', ...rows.map((r) => [r.host, r.ext, r.occurrences, r.pathname, r.where, r.url].map(csv).join(','))].join('\n'),
);

// ---- Resumo no console ----
console.log('\nDocumentos lidos por coleção:');
console.table(Object.entries(readCounts).map(([colecao, docs]) => ({ colecao, docs })));
console.log(`Total de leituras (docs): ${Object.values(readCounts).reduce((a, b) => a + b, 0)}`);
console.log(`Ocorrências de URL: ${occ.length} | URLs únicas: ${rows.length}`);

const group = (keyFn) => {
  const m = new Map();
  for (const r of rows) m.set(keyFn(r), (m.get(keyFn(r)) ?? 0) + 1);
  return [...m.entries()].sort((a, b) => b[1] - a[1]).map(([k, n]) => ({ chave: k, urls_unicas: n }));
};
console.log('\nPor host:'); console.table(group((r) => r.host));
console.log('\nPor extensão:'); console.table(group((r) => r.ext));

// Tipos de campo (coleção normalizada + campo) -> quantas ocorrências
const fieldMap = new Map();
for (const o of occ) {
  const k = `${o.collection.replace(/^championships\/[^/]+\//, 'championships/{temporada}/')} :: ${o.field}`;
  fieldMap.set(k, (fieldMap.get(k) ?? 0) + 1);
}
console.log('\nOcorrências por coleção :: campo:');
console.table([...fieldMap.entries()].sort().map(([campo, ocorrencias]) => ({ campo, ocorrencias })));
