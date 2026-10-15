// Correção e preenchimento de team_shield_url para todos os atletas nas coleções:
// - championships/2026_fjf/player_stats
// - championships/2025_fjf/player_stats
// - players
// - fantasy_market_players
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import { listDocs, val, PROJECT } from './lib.mjs';

const DIR = import.meta.dirname;
const OUT = path.join(DIR, 'out');
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

let _token = null;
let _tokenAt = 0;
function getToken() {
  if (!_token || Date.now() - _tokenAt > 20 * 60 * 1000) {
    _token = execSync('gcloud auth print-access-token', { stdio: ['ignore', 'pipe', 'ignore'] })
      .toString()
      .trim();
    _tokenAt = Date.now();
  }
  return _token;
}

async function commitBatch(writes) {
  const url = `${BASE}:commit`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${getToken()}`,
      'x-goog-user-project': PROJECT,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ writes }),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Falha no batch commit: HTTP ${res.status} - ${errText}`);
  }

  return res.json();
}

console.log('--- 1. Mapeando escudos dos times a partir de atletas existentes e diretório de times ---');
const teamShields = {};

// 1.1 Coleta de atletas existentes que já possuem team_shield_url
for await (const d of listDocs('championships/2026_fjf/player_stats')) {
  const data = Object.fromEntries(Object.entries(d.fields ?? {}).map(([k, v]) => [k, val(v)]));
  if (data.team_id && data.team_shield_url && typeof data.team_shield_url === 'string' && data.team_shield_url.trim()) {
    teamShields[data.team_id] = data.team_shield_url.trim();
  }
}

// 1.2 Complementa com teams_directory
for await (const d of listDocs('teams_directory')) {
  const teamId = d.name.split('/').pop();
  const data = Object.fromEntries(Object.entries(d.fields ?? {}).map(([k, v]) => [k, val(v)]));
  if (data.shield_url && !teamShields[teamId]) {
    teamShields[teamId] = data.shield_url.trim();
  }
}

console.log('Mapa de escudos por team_id:');
console.table(Object.entries(teamShields).map(([teamId, shieldUrl]) => ({ teamId, shieldUrl })));

console.log('\n--- 2. Varrendo coleções de atletas para identificar registros incompletos ---');
const collections = [
  'championships/2026_fjf/player_stats',
  'championships/2025_fjf/player_stats',
  'players',
  'fantasy_market_players',
];

const updates = [];
const skipped = [];

for (const col of collections) {
  for await (const d of listDocs(col)) {
    const docPath = d.name.split('/documents/')[1];
    const data = Object.fromEntries(Object.entries(d.fields ?? {}).map(([k, v]) => [k, val(v)]));

    const currentShield = data.team_shield_url;
    const hasShield = typeof currentShield === 'string' && currentShield.trim().length > 0;

    if (!hasShield) {
      const teamId = data.team_id;
      const name = data.name || '(sem nome)';

      if (teamId && teamShields[teamId]) {
        updates.push({
          docPath,
          collection: col,
          docId: docPath.split('/').pop(),
          name,
          teamId,
          targetShield: teamShields[teamId],
        });
      } else {
        skipped.push({
          docPath,
          collection: col,
          name,
          teamId: teamId || '(sem team_id)',
          motivo: teamId ? 'Escudo não encontrado para este team_id' : 'Atleta não possui team_id cadastrado',
        });
      }
    }
  }
}

console.log(`\nAtletas elegíveis para atualização de escudo: ${updates.length}`);
if (skipped.length > 0) {
  console.log(`Registros ignorados (${skipped.length}):`);
  console.table(skipped);
}

// Resumo por coleção
const summary = {};
for (const u of updates) {
  summary[u.collection] = (summary[u.collection] || 0) + 1;
}
console.log('\nAtletas a atualizar por coleção:');
console.table(Object.entries(summary).map(([colecao, total]) => ({ colecao, atletas_para_corrigir: total })));

if (updates.length === 0) {
  console.log('Nenhum atleta precisa de correção.');
  process.exit(0);
}

// Salva plano
fs.writeFileSync(path.join(OUT, 'player_shields_fix_plan.json'), JSON.stringify({ updates, skipped }, null, 2));

console.log('\n--- 3. Aplicando correções no Firestore em batches seguros ---');
const BATCH_SIZE = 250;
const writes = updates.map((u) => ({
  update: {
    name: `projects/${PROJECT}/databases/(default)/documents/${u.docPath}`,
    fields: {
      team_shield_url: { stringValue: u.targetShield },
    },
  },
  updateMask: {
    fieldPaths: ['team_shield_url'],
  },
}));

let batchIndex = 0;
for (let i = 0; i < writes.length; i += BATCH_SIZE) {
  batchIndex++;
  const slice = writes.slice(i, i + BATCH_SIZE);
  process.stdout.write(`Gravando Lote ${batchIndex} (${slice.length} atletas)... `);
  const res = await commitBatch(slice);
  console.log(`OK (commitTime: ${res.commitTime})`);
}

console.log('\n✅ Todos os atletas foram corrigidos com sucesso!');
