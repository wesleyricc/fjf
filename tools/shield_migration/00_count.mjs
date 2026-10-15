// Fase 0 - passo 1: descobre a estrutura e CONTA documentos (custo mínimo de leituras).
import { listCollectionIds, countDocs, listDocs } from './lib.mjs';

const root = await listCollectionIds();
console.log('Coleções raiz:', root.join(', '));

const rows = [];
for (const c of ['teams_directory', 'players', 'fantasy_market_players', 'voting_stats', 'photo_albums', 'sponsors']) {
  rows.push([c, await countDocs(c)]);
}

// Temporadas
const seasons = [];
for await (const d of listDocs('championships', ['name'])) {
  seasons.push(d.name.split('/').pop());
}
console.log('Temporadas:', seasons.join(', '));
rows.push(['championships', seasons.length]);

const subs = new Set();
for (const s of seasons) {
  const ids = await listCollectionIds(`championships/${s}`);
  ids.forEach((i) => subs.add(i));
  for (const sub of ids) {
    rows.push([`championships/${s}/${sub}`, await countDocs(`championships/${s}/${sub}`)]);
  }
}
console.log('Subcoleções por temporada:', [...subs].join(', '));
console.table(rows.map(([colecao, docs]) => ({ colecao, docs })));
