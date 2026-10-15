// Diagnóstico SOMENTE LEITURA: encontra todos os atletas sem team_shield_url
// em 2026_fjf/player_stats, 2025_fjf/player_stats, players e fantasy_market_players.
import { listDocs, val } from './lib.mjs';

const collectionsToCheck = [
  'championships/2026_fjf/player_stats',
  'championships/2025_fjf/player_stats',
  'players',
  'fantasy_market_players',
];

// Carrega os escudos canônicos dos times a partir de teams_directory
console.log('--- 1. Carregando escudos dos times de teams_directory ---');
const teamShields = {};
for await (const doc of listDocs('teams_directory')) {
  const teamId = doc.name.split('/').pop();
  const data = Object.fromEntries(Object.entries(doc.fields ?? {}).map(([k, v]) => [k, val(v)]));
  if (data.shield_url) {
    teamShields[teamId] = data.shield_url;
  }
}
console.log('Escudos canônicos encontrados em teams_directory:');
console.table(Object.entries(teamShields).map(([teamId, shieldUrl]) => ({ teamId, shieldUrl })));

console.log('\n--- 2. Verificando atletas nas coleções ---');
const missingList = [];

for (const col of collectionsToCheck) {
  let total = 0;
  let missing = 0;
  let missingDetail = [];

  for await (const doc of listDocs(col)) {
    total++;
    const docId = doc.name.split('/').pop();
    const data = Object.fromEntries(Object.entries(doc.fields ?? {}).map(([k, v]) => [k, val(v)]));

    const shield = data.team_shield_url;
    const hasShield = typeof shield === 'string' && shield.trim().length > 0;

    if (!hasShield) {
      missing++;
      const teamId = data.team_id || '(sem team_id)';
      const name = data.name || '(sem nome)';
      missingDetail.push({ docId, name, teamId, currentShield: shield });
      missingList.push({ col, docId, docName: doc.name, name, teamId, currentShield: shield });
    }
  }

  console.log(`\nColeção: ${col}`);
  console.log(`Total de atletas: ${total} | Sem team_shield_url: ${missing}`);
  if (missingDetail.length > 0) {
    console.table(missingDetail);
  }
}

console.log(`\nTotal geral de atletas com team_shield_url ausente/vazio: ${missingList.length}`);
