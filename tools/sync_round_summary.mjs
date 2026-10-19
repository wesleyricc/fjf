import { execSync } from 'node:child_process';
import { PROJECT, listDocs, val } from './shield_migration/lib.mjs';

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

async function getDoc(path) {
  const url = `${BASE}/${path}`;
  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${getToken()}`,
      'x-goog-user-project': PROJECT,
    },
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Falha getDoc ${path}: HTTP ${res.status}`);
  return res.json();
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

function toFirestoreValue(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === 'boolean') return { booleanValue: val };
  if (typeof val === 'number') {
    if (Number.isInteger(val)) return { integerValue: val.toString() };
    return { doubleValue: val };
  }
  if (typeof val === 'string') return { stringValue: val };
  if (val instanceof Date) return { timestampValue: val.toISOString() };
  if (Array.isArray(val)) return { arrayValue: { values: val.map(toFirestoreValue) } };
  if (typeof val === 'object') {
    const fields = {};
    for (const [k, v] of Object.entries(val)) {
      if (v !== undefined) fields[k] = toFirestoreValue(v);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(val) };
}

async function run() {
  const targetRound = parseInt(process.argv[2] || '1', 10);
  console.log(`\n==================================================================`);
  console.log(`🚀 Sincronizando Resumo da Rodada ${targetRound} (FinOps & Ranking Cartoletas)...`);
  console.log(`==================================================================\n`);

  // 1. Listar todos os times
  console.log('1. Carregando equipes do fantasy_teams...');
  const teams = [];
  for await (const doc of listDocs('fantasy_teams')) {
    const teamId = doc.name.split('/').pop();
    const data = val({ mapValue: { fields: doc.fields || {} } });
    teams.push({ id: teamId, ...data });
  }
  console.log(`   Total de equipes encontradas: ${teams.length}`);

  // 2. Carregar históricos da rodada
  console.log(`2. Carregando históricos da Rodada ${targetRound}...`);
  const auditedTeams = [];

  for (const team of teams) {
    const histPath = `fantasy_teams/${team.id}/history/${targetRound}`;
    const histDoc = await getDoc(histPath);
    const histData = histDoc ? val({ mapValue: { fields: histDoc.fields || {} } }) : null;

    let prevPatrimony = 50.0;
    if (targetRound > 1) {
      const prevPath = `fantasy_teams/${team.id}/history/${targetRound - 1}`;
      const prevDoc = await getDoc(prevPath);
      if (prevDoc) {
        const prevData = val({ mapValue: { fields: prevDoc.fields || {} } });
        prevPatrimony = Number(prevData.patrimony || 50.0);
      }
    }

    const currentPatrimony = histData && histData.patrimony !== undefined
      ? Number(histData.patrimony)
      : Number(team.team_value || 50.0);

    const roundScore = histData && histData.points !== undefined
      ? Number(histData.points)
      : Number(team.last_score || 0.0);

    const priceVariation = Number((currentPatrimony - prevPatrimony).toFixed(2));

    const originalStarters = histData
      ? (histData.lineup_snapshot || histData.final_lineup || team.lineup_player_ids || [])
      : (team.lineup_player_ids || []);

    auditedTeams.push({
      teamId: team.id,
      userId: team.user_id || team.id,
      teamName: team.team_name || 'Time sem nome',
      ownerName: team.owner_name || 'Cartoleiro',
      customLogoUrl: team.custom_logo_url || null,
      shieldType: team.shield_type || '1',
      roundScore,
      priceVariation,
      currentPatrimony,
      originalStarters,
      hasStarters: Array.isArray(originalStarters) && originalStarters.length > 0,
    });
  }

  // 3. Processar métricas e destaques
  const activeTeams = auditedTeams.filter(t => t.hasStarters);
  const totalCount = auditedTeams.length;
  const activeCount = activeTeams.length;
  const avgScore = activeCount > 0
    ? Number((activeTeams.reduce((acc, t) => acc + t.roundScore, 0) / activeCount).toFixed(2))
    : 0.0;

  let mito = null;
  let lanterna = null;
  let maiorVal = null;
  let maiorDesv = null;

  for (const t of auditedTeams) {
    if (!mito || t.roundScore > mito.roundScore) mito = t;
    if (!maiorVal || t.priceVariation > maiorVal.priceVariation) maiorVal = t;
  }

  for (const t of activeTeams) {
    if (!lanterna || t.roundScore < lanterna.roundScore) lanterna = t;
    if (!maiorDesv || t.priceVariation < maiorDesv.priceVariation) maiorDesv = t;
  }

  console.log(`\n📊 Destaques Computados para a Rodada ${targetRound}:`);
  console.log(`   - Equipes Totais: ${totalCount} | Ativas (escaladas): ${activeCount}`);
  console.log(`   - Média da Liga (escaladas): ${avgScore.toFixed(2)} pts`);
  if (mito) console.log(`   🏆 Mito da Rodada: ${mito.teamName} (${mito.ownerName}) - ${mito.roundScore.toFixed(2)} pts`);
  if (maiorVal) console.log(`   💰 Maior Valorização: ${maiorVal.teamName} (+C$ ${maiorVal.priceVariation.toFixed(2)})`);
  if (lanterna) console.log(`   📉 Menor Pontuação (escalado): ${lanterna.teamName} (${lanterna.roundScore.toFixed(2)} pts)`);
  if (maiorDesv) console.log(`   💸 Maior Desvalorização (escalado): ${maiorDesv.teamName} (${maiorDesv.priceVariation.toFixed(2)})`);

  const summaryPayload = {
    round: targetRound,
    total_teams: totalCount,
    active_teams: activeCount,
    average_score: avgScore,
    highest_score_team: mito ? {
      team_id: mito.teamId,
      user_id: mito.userId,
      team_name: mito.teamName,
      owner_name: mito.ownerName,
      custom_logo_url: mito.customLogoUrl,
      shield_type: mito.shieldType,
      score: mito.roundScore,
      variation: mito.priceVariation,
      patrimony: mito.currentPatrimony,
    } : null,
    lowest_score_team: lanterna ? {
      team_id: lanterna.teamId,
      user_id: lanterna.userId,
      team_name: lanterna.teamName,
      owner_name: lanterna.ownerName,
      custom_logo_url: lanterna.customLogoUrl,
      shield_type: lanterna.shieldType,
      score: lanterna.roundScore,
      variation: lanterna.priceVariation,
      patrimony: lanterna.currentPatrimony,
    } : null,
    highest_appreciation_team: maiorVal ? {
      team_id: maiorVal.teamId,
      user_id: maiorVal.userId,
      team_name: maiorVal.teamName,
      owner_name: maiorVal.ownerName,
      custom_logo_url: maiorVal.customLogoUrl,
      shield_type: maiorVal.shieldType,
      score: maiorVal.roundScore,
      variation: maiorVal.priceVariation,
      patrimony: maiorVal.currentPatrimony,
    } : null,
    lowest_appreciation_team: maiorDesv ? {
      team_id: maiorDesv.teamId,
      user_id: maiorDesv.userId,
      team_name: maiorDesv.teamName,
      owner_name: maiorDesv.ownerName,
      custom_logo_url: maiorDesv.customLogoUrl,
      shield_type: maiorDesv.shieldType,
      score: maiorDesv.roundScore,
      variation: maiorDesv.priceVariation,
      patrimony: maiorDesv.currentPatrimony,
    } : null,
    updated_at: new Date(),
  };

  // 4. Gravar resumos
  console.log(`\n3. Gravando documentos consolidados em fantasy_stats...`);
  const writes = [];

  const roundDocName = `projects/${PROJECT}/databases/(default)/documents/fantasy_stats/round_${targetRound}_summary`;
  writes.push({
    update: {
      name: roundDocName,
      fields: toFirestoreValue(summaryPayload).mapValue.fields,
    },
  });

  const lastDocName = `projects/${PROJECT}/databases/(default)/documents/fantasy_stats/last_round_summary`;
  writes.push({
    update: {
      name: lastDocName,
      fields: toFirestoreValue(summaryPayload).mapValue.fields,
    },
  });

  // 5. Atualizar last_variation e last_score nas equipes e no histórico
  console.log(`4. Preparando atualização de last_variation para ${auditedTeams.length} equipes...`);
  for (const t of auditedTeams) {
    const teamDocName = `projects/${PROJECT}/databases/(default)/documents/fantasy_teams/${t.teamId}`;
    writes.push({
      update: {
        name: teamDocName,
        fields: {
          last_variation: { doubleValue: t.priceVariation },
          last_score: { doubleValue: t.roundScore },
        },
      },
      updateMask: {
        fieldPaths: ['last_variation', 'last_score'],
      },
    });

    const histDocName = `projects/${PROJECT}/databases/(default)/documents/fantasy_teams/${t.teamId}/history/${targetRound}`;
    writes.push({
      update: {
        name: histDocName,
        fields: {
          variation: { doubleValue: t.priceVariation },
        },
      },
      updateMask: {
        fieldPaths: ['variation'],
      },
    });
  }

  // Comitar em chunks de 300 operações
  const CHUNK_SIZE = 300;
  for (let i = 0; i < writes.length; i += CHUNK_SIZE) {
    const chunk = writes.slice(i, i + CHUNK_SIZE);
    await commitBatch(chunk);
    console.log(`   Commited ${Math.min(i + CHUNK_SIZE, writes.length)} / ${writes.length} operações...`);
  }

  console.log(`\n✅ Sucesso! Resumo da Rodada ${targetRound} gravado e todas as equipes sincronizadas com sucesso.`);
  console.log(`   Os dados já podem ser conferidos no app (tela inicial e ranking)!`);
}

run().catch((e) => {
  console.error('\n❌ Erro durante a sincronização:', e);
  process.exit(1);
});
