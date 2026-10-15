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
  console.log('🚀 Iniciando recálculo de Craque do Jogo (man_of_the_match_awards)...');
  
  const seasons = ['2026_fjf', '2025_fjf'];
  
  for (const season of seasons) {
    console.log(`\n--- Temporada: ${season} ---`);
    
    // 1. Contar MOTMs das partidas finalizadas
    const motmCounts = new Map();
    let finishedMatches = 0;
    
    for await (const mDoc of listDocs(`championships/${season}/matches`)) {
      const f = mDoc.fields || {};
      const status = f.status?.stringValue || '';
      if (status !== 'finished') continue;
      finishedMatches++;

      const motm = f.stats_applied?.mapValue?.fields?.man_of_the_match?.stringValue 
        || f.man_of_the_match?.stringValue 
        || '';
        
      if (motm) {
        motmCounts.set(motm, (motmCounts.get(motm) || 0) + 1);
      }
    }
    
    console.log(`Partidas finalizadas: ${finishedMatches}. Craques encontrados: ${motmCounts.size} atletas.`);
    for (const [pid, count] of motmCounts.entries()) {
      console.log(`  Atleta ID: ${pid} -> ${count} prêmio(s) de Craque`);
    }

    // 2. Atualizar player_stats dos atletas correspondentes
    const writes = [];
    for await (const pDoc of listDocs(`championships/${season}/player_stats`)) {
      const pid = pDoc.name.split('/').pop();
      const f = pDoc.fields || {};
      const currentAwards = Number(f.man_of_the_match_awards?.integerValue || 0);
      const expectedAwards = motmCounts.get(pid) || 0;

      if (currentAwards !== expectedAwards) {
        const name = f.name?.stringValue || pid;
        console.log(`  Atualizando ${name} (${pid}): de ${currentAwards} para ${expectedAwards}`);
        writes.push({
          update: {
            name: pDoc.name,
            fields: {
              ...f,
              man_of_the_match_awards: { integerValue: String(expectedAwards) },
            },
          },
          updateMask: {
            fieldPaths: ['man_of_the_match_awards'],
          },
        });
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

  console.log('\n🎉 Sincronização de Craques do Jogo concluída com sucesso!');
}

run().catch((e) => {
  console.error('❌ Erro na execução:', e);
  process.exit(1);
});
