import { execSync } from 'node:child_process';
import { PROJECT, listDocs } from './shield_migration/lib.mjs';

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
  if (writes.length === 0) return;
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

async function run() {
  console.log('🚀 Iniciando sincronização de fotos e escudos em disciplinary_log...');
  
  const seasons = ['2026_fjf', '2025_fjf'];
  
  for (const season of seasons) {
    console.log(`\n--- Temporada: ${season} ---`);
    
    // 1. Carregar mapa de player_stats da temporada
    const playerMap = new Map();
    for await (const pDoc of listDocs(`championships/${season}/player_stats`)) {
      const pid = pDoc.name.split('/').pop();
      const f = pDoc.fields || {};
      playerMap.set(pid, {
        name: f.name?.stringValue || '',
        photo_url: f.photo_url?.stringValue || '',
        team_name: f.team_name?.stringValue || '',
        team_shield_url: f.team_shield_url?.stringValue || '',
      });
    }
    console.log(`Carregados ${playerMap.size} atletas de player_stats (${season}).`);

    // 2. Carregar /players globais como fallback
    const globalPlayers = new Map();
    for await (const gDoc of listDocs('players')) {
      const pid = gDoc.name.split('/').pop();
      const f = gDoc.fields || {};
      globalPlayers.set(pid, {
        name: f.name?.stringValue || '',
        photo_url: f.photo_url?.stringValue || '',
        team_name: f.team_name?.stringValue || '',
        team_shield_url: f.team_shield_url?.stringValue || '',
      });
    }

    // 3. Processar disciplinary_log
    const writes = [];
    for await (const logDoc of listDocs(`championships/${season}/disciplinary_log`)) {
      const f = logDoc.fields || {};
      const pid = f.playerId?.stringValue || '';
      const currentPhoto = f.playerPhotoUrl?.stringValue || '';
      const currentTeam = f.teamName?.stringValue || '';
      const currentShield = f.teamLogoUrl?.stringValue || '';

      const pInfo = playerMap.get(pid) || globalPlayers.get(pid);
      if (!pInfo) {
        console.warn(`  [AVISO] Atleta ID ${pid} não encontrado para ${logDoc.name.split('/').pop()}`);
        continue;
      }

      const updates = {};
      const updateMask = [];

      if (!currentPhoto && pInfo.photo_url) {
        updates.playerPhotoUrl = { stringValue: pInfo.photo_url };
        updateMask.push('playerPhotoUrl');
      }
      if (!currentTeam && pInfo.team_name) {
        updates.teamName = { stringValue: pInfo.team_name };
        updateMask.push('teamName');
      }
      if (!currentShield && pInfo.team_shield_url) {
        updates.teamLogoUrl = { stringValue: pInfo.team_shield_url };
        updateMask.push('teamLogoUrl');
      }

      if (updateMask.length > 0) {
        console.log(`  Atualizando log ${logDoc.name.split('/').pop()} (${pInfo.name}): +${updateMask.join(', ')}`);
        writes.push({
          update: {
            name: logDoc.name,
            fields: {
              ...f,
              ...updates,
            },
          },
          updateMask: {
            fieldPaths: updateMask,
          },
        });
      } else {
        console.log(`  Log ${logDoc.name.split('/').pop()} (${pInfo.name}) já possui todos os dados.`);
      }
    }

    if (writes.length > 0) {
      console.log(`Enviando batch com ${writes.length} atualizações para ${season}...`);
      await commitBatch(writes);
      console.log(`✅ Sucesso para ${season}!`);
    } else {
      console.log(`Nenhuma atualização necessária para ${season}.`);
    }
  }

  console.log('\n🎉 Sincronização concluída com sucesso!');
}

run().catch((e) => {
  console.error('❌ Erro na execução:', e);
  process.exit(1);
});
