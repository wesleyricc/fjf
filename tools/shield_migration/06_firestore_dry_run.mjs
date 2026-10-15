// Fase 4.1: Dry-run da migração no Firestore (SOMENTE LEITURA).
// Simula a aplicação do mapa_urls.json em todas as coleções de produção, sem gravar nada.
// Gera out/dry_run_plan.json com o planejamento exato de cada alteração.
import fs from 'node:fs';
import path from 'node:path';
import { listDocs, listCollectionIds, val } from './lib.mjs';

const DIR = import.meta.dirname;
const OUT = path.join(DIR, 'out');

const urlMap = JSON.parse(fs.readFileSync(path.join(OUT, 'mapa_urls.json'), 'utf8'));

console.log(`Carregado mapa com ${Object.keys(urlMap).length} URLs mapeadas.`);

// Configuração das coleções e campos a serem auditados/alterados
// [caminhoColecao, [campos]]
const plan = [];
const summaryByCollection = {};

async function auditCollection(colPath, targetFields) {
  let docCount = 0;
  let updateCount = 0;

  for await (const doc of listDocs(colPath)) {
    docCount++;
    const docPath = doc.name.split('/documents/')[1];
    const data = Object.fromEntries(
      Object.entries(doc.fields ?? {}).map(([k, v]) => [k, val(v)])
    );

    const changes = {};
    for (const field of targetFields) {
      const currentVal = data[field];
      if (typeof currentVal === 'string' && urlMap[currentVal]) {
        changes[field] = {
          from: currentVal,
          to: urlMap[currentVal],
        };
      }
    }

    if (Object.keys(changes).length > 0) {
      updateCount += Object.keys(changes).length;
      plan.push({
        docPath,
        collection: colPath,
        changes,
      });
    }
  }

  summaryByCollection[colPath] = {
    docsLidos: docCount,
    camposParaAtualizar: updateCount,
  };
}

console.log('\n--- Varrendo coleções globais ---');
await auditCollection('teams_directory', ['shield_url']);
await auditCollection('players', ['team_shield_url']);
await auditCollection('fantasy_market_players', ['team_shield_url']);

console.log('--- Varrendo temporadas ---');
const seasons = [];
for await (const d of listDocs('championships', ['name'])) {
  seasons.push(d.name.split('/').pop());
}

for (const season of seasons) {
  const subCols = await listCollectionIds(`championships/${season}`);
  
  if (subCols.includes('teams_participation')) {
    await auditCollection(`championships/${season}/teams_participation`, ['shield_url']);
  }
  if (subCols.includes('matches')) {
    await auditCollection(`championships/${season}/matches`, ['team_home_shield', 'team_away_shield']);
  }
  if (subCols.includes('player_stats')) {
    await auditCollection(`championships/${season}/player_stats`, ['team_shield_url']);
  }
  if (subCols.includes('disciplinary_log')) {
    await auditCollection(`championships/${season}/disciplinary_log`, ['teamLogoUrl']);
  }
}

// Salva o plano completo para auditoria e futura reversão (rollback)
const planFilePath = path.join(OUT, 'dry_run_plan.json');
fs.writeFileSync(planFilePath, JSON.stringify(plan, null, 2));

console.log('\n=== RESUMO DO DRY-RUN (SIMULAÇÃO) ===');
console.table(
  Object.entries(summaryByCollection).map(([colecao, info]) => ({
    colecao,
    docs_lidos: info.docsLidos,
    campos_a_atualizar: info.camposParaAtualizar,
  }))
);

const totalCampos = Object.values(summaryByCollection).reduce(
  (acc, cur) => acc + cur.camposParaAtualizar,
  0
);
console.log(`Total de documentos com alteração: ${plan.length}`);
console.log(`Total de campos que serão atualizados para WebP: ${totalCampos}`);
console.log(`Plano de auditoria salvo em: ${planFilePath}`);
