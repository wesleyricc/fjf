const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const DEFAULT_CONFIG = {
  ptsGoal: 8.0,
  ptsAssist: 5.0,
  ptsYellowCard: -1.0,
  ptsRedCard: -3.0,
  ptsPenaltySaved: 5.0,
  ptsPenaltyMissed: -3.0,
  ptsShotOnPost: 3.0,
  ptsCleanSheet: 5.0,
  ptsOwnGoal: -3.0,
  ptsDirectFreeKickMissed: -3.0,
  ptsManOfTheMatch: 5.0,
  ptsDifficultSave: 1.0,

  factorExpectation: 0.30,
  factorVariation: 0.18,
  capLimitPercent: 0.25,
  minPrice: 1.0,
};

function normalizeConfig(rawConfig) {
  const cfg = { ...DEFAULT_CONFIG, ...(rawConfig || {}) };
  const warnings = [];

  if (rawConfig) {
    if (rawConfig.ptsMotm !== undefined && rawConfig.ptsManOfTheMatch === undefined) {
      warnings.push("Configuração salva no app usa chave 'ptsMotm' (valor: " + rawConfig.ptsMotm + "). Normalizado para 'ptsManOfTheMatch'.");
      cfg.ptsManOfTheMatch = Number(rawConfig.ptsMotm);
    }
    if (rawConfig.ptsMissedFreeKick !== undefined && rawConfig.ptsDirectFreeKickMissed === undefined) {
      warnings.push("Configuração salva no app usa chave 'ptsMissedFreeKick' (valor: " + rawConfig.ptsMissedFreeKick + "). Normalizado para 'ptsDirectFreeKickMissed'.");
      cfg.ptsDirectFreeKickMissed = Number(rawConfig.ptsMissedFreeKick);
    }
  }

  return { config: cfg, warnings };
}

function calculateExpectedPrice(currentPrice, score, config) {
  const expectation = currentPrice * config.factorExpectation;
  const performance = score - expectation;
  let rawVariation = performance * config.factorVariation;
  let limit = currentPrice * config.capLimitPercent;
  if (limit < 2.0) limit = 2.0;
  if (limit > 5.0) limit = 5.0;

  if (rawVariation > limit) rawVariation = limit;
  if (rawVariation < -limit) rawVariation = -limit;

  let newPrice = currentPrice + rawVariation;
  if (newPrice < config.minPrice) newPrice = config.minPrice;

  return {
    variation: Number(rawVariation.toFixed(1)),
    newPrice: Number(newPrice.toFixed(1)),
    expectation: Number(expectation.toFixed(2)),
    limit: Number(limit.toFixed(2))
  };
}

class AuditBatchWriter {
  constructor(db) {
    this.db = db;
    this.batch = db.batch();
    this.count = 0;
  }

  set(ref, data, options = {}) {
    this.batch.set(ref, data, options);
    this.count++;
    if (this.count >= 400) {
      return this.commit();
    }
    return Promise.resolve();
  }

  async commit() {
    if (this.count > 0) {
      await this.batch.commit();
      this.batch = this.db.batch();
      this.count = 0;
    }
  }
}

exports.auditFantasyRound = onCall({ cors: true, enforceAppCheck: false }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Acesso negado. O usuário precisa estar autenticado.');
  }

  const db = admin.firestore();
  const adminDoc = await db.collection('admin_users').doc(request.auth.uid).get();
  if (!adminDoc.exists) {
    throw new HttpsError('permission-denied', 'Acesso negado. Apenas administradores oficiais podem executar a auditoria.');
  }

  const { seasonId, round, includeTeams = true } = request.data || {};
  if (!seasonId || !round) {
    throw new HttpsError('invalid-argument', 'seasonId e round são parâmetros obrigatórios.');
  }

  const roundNum = Number(round);
  console.log(`🔍 [AUDIT] Iniciando auditoria independente: Temporada ${seasonId}, Rodada ${roundNum} por ${request.auth.uid}`);

  return executeAuditLogic(db, seasonId, roundNum, includeTeams, request.auth.uid, false);
});

exports.syncAuditToLive = onCall({ cors: true, enforceAppCheck: false }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Acesso negado. O usuário precisa estar autenticado.');
  }

  const db = admin.firestore();
  const adminDoc = await db.collection('admin_users').doc(request.auth.uid).get();
  if (!adminDoc.exists) {
    throw new HttpsError('permission-denied', 'Acesso negado. Apenas administradores oficiais podem sincronizar scouts.');
  }

  const { seasonId, round, includeTeams = true } = request.data || {};
  if (!seasonId || !round) {
    throw new HttpsError('invalid-argument', 'seasonId e round são parâmetros obrigatórios.');
  }

  const roundNum = Number(round);
  console.log(`⚡ [AUDIT_SYNC] Sincronizando scouts ao vivo com base na auditoria: Temporada ${seasonId}, Rodada ${roundNum} por ${request.auth.uid}`);

  return executeAuditLogic(db, seasonId, roundNum, includeTeams, request.auth.uid, true);
});

async function executeAuditLogic(db, seasonId, roundNum, includeTeams, callerUid, syncToLive = false) {
  try {
    // 1. Configurações vigentes
    const configSnap = await db.collection('fantasy_config').doc('rules').get();
    const { config, warnings: configWarnings } = normalizeConfig(configSnap.exists ? configSnap.data() : null);

    // 2. Partidas da Rodada
    const matchesSnap = await db.collection('championships').doc(seasonId)
      .collection('matches').where('round', '==', roundNum).get();

    const matchesList = [];
    const timelineEventsByPlayer = {}; // pid -> [events]
    const timelineEvidenceByPlayer = {}; // pid -> [evidence items]
    const playersPlayedSet = new Set(); // Jogadores confirmados em súmula de presença
    const teamCleanSheets = {}; // teamId -> bool
    const matchAuditList = [];

    for (const matchDoc of matchesSnap.docs) {
      const mData = matchDoc.data();
      const mId = matchDoc.id;
      const status = mData.status || 'pending';
      const homeId = mData.team_home_id || '';
      const awayId = mData.team_away_id || '';
      const homeName = mData.team_home_name || homeId;
      const awayName = mData.team_away_name || awayId;
      const matchLabel = `${homeName} x ${awayName}`;
      const scoreHome = Number(mData.score_home || 0);
      const scoreAway = Number(mData.score_away || 0);
      const lineupPlayed = Array.isArray(mData.lineup_played) ? mData.lineup_played.map(String) : [];

      lineupPlayed.forEach(pid => playersPlayedSet.add(pid));

      // Limpeza de Clean Sheet (apenas para jogos em andamento ou finalizados)
      const isMatchUnderwayOrDone = (status === 'in_progress' || status === 'finished');
      let homeKeptClean = false;
      let awayKeptClean = false;
      if (isMatchUnderwayOrDone) {
        if (scoreAway === 0 && homeId) {
          teamCleanSheets[homeId] = true;
          homeKeptClean = true;
        }
        if (scoreHome === 0 && awayId) {
          teamCleanSheets[awayId] = true;
          awayKeptClean = true;
        }
      }

      // Buscar eventos da Timeline (Fonte da Verdade)
      const timelineSnap = await matchDoc.ref.collection('timeline').get();
      const matchEvents = [];
      let timelineGoalsCount = 0;
      let timelineOwnGoalsCount = 0;

      timelineSnap.docs.forEach(eDoc => {
        const eData = eDoc.data();
        const pid = eData.playerId ? eData.playerId.toString() : '';
        const eventType = eData.type;

        if (eventType === 'goal') timelineGoalsCount++;
        if (eventType === 'ownGoal') timelineOwnGoalsCount++;

        const eventItem = {
          id: eDoc.id,
          matchId: mId,
          matchLabel,
          type: eventType,
          playerId: pid,
          playerName: eData.playerName || 'Desconhecido',
          teamId: eData.teamId || '',
          minute: eData.minute ?? 0,
          period: eData.period || '1T',
          concededByPlayerId: eData.concededByPlayerId || null,
        };

        matchEvents.push(eventItem);

        if (pid) {
          if (!timelineEventsByPlayer[pid]) timelineEventsByPlayer[pid] = [];
          timelineEventsByPlayer[pid].push(eventItem);

          if (!timelineEvidenceByPlayer[pid]) timelineEvidenceByPlayer[pid] = [];
          timelineEvidenceByPlayer[pid].push({
            matchId: mId,
            matchLabel,
            minute: eventItem.minute,
            period: eventItem.period,
            type: eventItem.type,
            details: `Evento de ${eventItem.type} registrado aos ${eventItem.minute}' (${eventItem.period})`
          });
        }
      });

      // Validação de Integridade da Partida
      const matchDiscrepancies = [];
      const totalPlacar = scoreHome + scoreAway;
      const totalGolsTimeline = timelineGoalsCount + timelineOwnGoalsCount;
      if (isMatchUnderwayOrDone && totalPlacar !== totalGolsTimeline) {
        matchDiscrepancies.push(`Placar (${totalPlacar}) diverge do total de gols na timeline (${totalGolsTimeline}).`);
      }
      if (isMatchUnderwayOrDone && lineupPlayed.length === 0) {
        matchDiscrepancies.push("Súmula de presença (lineup_played) está vazia para jogo em andamento/finalizado.");
      }

      const motmId = mData.stats_applied?.man_of_the_match || mData.man_of_the_match || null;
      if (status === 'finished' && !motmId) {
        matchDiscrepancies.push("Partida finalizada sem Craque do Jogo (MOTM) definido.");
      }

      matchAuditList.push({
        matchId: mId,
        matchLabel,
        homeId,
        awayId,
        scoreHome,
        scoreAway,
        status,
        lineupPlayedCount: lineupPlayed.length,
        timelineEventsCount: matchEvents.length,
        motmId,
        cleanSheetHome: homeKeptClean,
        cleanSheetAway: awayKeptClean,
        statsAppliedPresent: !!mData.stats_applied,
        discrepancies: matchDiscrepancies
      });

      matchesList.push({
        id: mId,
        data: mData,
        events: matchEvents,
        motmId
      });
    }

    // 3. Buscar Atletas do Mercado do Fantasy
    const marketSnap = await db.collection('fantasy_market_players').get();
    const allMarketPlayers = {};
    marketSnap.docs.forEach(doc => {
      allMarketPlayers[doc.id] = { id: doc.id, ...doc.data() };
    });

    // 4. Buscar Pontuações Publicadas Ao Vivo
    const liveDocSnap = await db.collection('championships').doc(seasonId)
      .collection('fantasy_live').doc(`round_${roundNum}`).get();
    const liveScoresObj = liveDocSnap.exists ? (liveDocSnap.data().scores || {}) : {};
    const liveIsFinal = liveDocSnap.exists ? (liveDocSnap.data().is_final === true) : false;

    // 5. Motor de Auditoria Independente (Jogador por Jogador)
    const auditedPlayers = {};
    const teamScoresForCoach = {}; // teamId -> [scores dos atletas que JOGARAM]
    const teamCoachAthleteDetails = {}; // teamId -> [detalhes para memória de cálculo]
    const coachesList = [];

    // Primeiro passo: Processar atletas de linha e goleiros (não-técnicos)
    for (const [pid, player] of Object.entries(allMarketPlayers)) {
      const pos = player.position || 'Desconhecido';
      const teamId = player.team_id || '';
      const hasPlayed = playersPlayedSet.has(pid);

      if (pos === 'Técnico') {
        coachesList.push(player);
        continue;
      }

      const playerEvents = timelineEventsByPlayer[pid] || [];
      const counts = {
        goals: 0,
        assists: 0,
        yellows: 0,
        reds: 0,
        penalties_saved: 0,
        penalties_missed: 0,
        shots_on_post: 0,
        own_goals: 0,
        direct_free_kicks_missed: 0,
        difficult_saves: 0,
        clean_sheets: 0,
        motm: 0
      };

      playerEvents.forEach(e => {
        if (e.type === 'goal') counts.goals++;
        else if (e.type === 'assist') counts.assists++;
        else if (e.type === 'yellowCard') counts.yellows++;
        else if (e.type === 'redCard') counts.reds++;
        else if (e.type === 'penaltySaved') counts.penalties_saved++;
        else if (e.type === 'penaltyMissed') counts.penalties_missed++;
        else if (e.type === 'shotOnPost') counts.shots_on_post++;
        else if (e.type === 'ownGoal') counts.own_goals++;
        else if (e.type === 'directFreeKickMissed') counts.direct_free_kicks_missed++;
        else if (e.type === 'difficultSave') counts.difficult_saves++;
      });

      // Checagem de MOTM
      for (const m of matchesList) {
        if (m.motmId === pid) {
          counts.motm++;
        }
      }

      // Regra 1 Decidida: Goleiro/Fixo só ganha SG se confirmou presença na súmula (jogou)
      const isDefensivePos = (pos === 'Goleiro' || pos === 'Fixo');
      const teamHadCleanSheet = teamId ? !!teamCleanSheets[teamId] : false;
      const flags = [];

      if (isDefensivePos && teamHadCleanSheet) {
        if (hasPlayed) {
          counts.clean_sheets = 1;
        } else {
          flags.push("SG_BLOQUEADO_NAO_JOGOU: Time não tomou gol, mas jogador não jogou na rodada.");
        }
      }

      // Cálculo da Pontuação Esperada
      const breakdown = [];
      let expectedScore = 0.0;

      const addStatBreakdown = (label, count, pts) => {
        if (count > 0) {
          const subtotal = Number((count * pts).toFixed(2));
          expectedScore += subtotal;
          breakdown.push({ label, count, ptsPerUnit: pts, subtotal });
        }
      };

      addStatBreakdown('Gols', counts.goals, config.ptsGoal);
      addStatBreakdown('Assistências', counts.assists, config.ptsAssist);
      addStatBreakdown('Cartões Amarelos', counts.yellows, config.ptsYellowCard);
      addStatBreakdown('Cartões Vermelhos', counts.reds, config.ptsRedCard);
      addStatBreakdown('Pênaltis Defendidos', counts.penalties_saved, config.ptsPenaltySaved);
      addStatBreakdown('Pênaltis Perdidos', counts.penalties_missed, config.ptsPenaltyMissed);
      addStatBreakdown('Chutes na Trave', counts.shots_on_post, config.ptsShotOnPost);
      addStatBreakdown('Gols Contra', counts.own_goals, config.ptsOwnGoal);
      addStatBreakdown('Faltas Diretas Desperdiçadas', counts.direct_free_kicks_missed, config.ptsDirectFreeKickMissed);
      addStatBreakdown('Defesas Difíceis', counts.difficult_saves, config.ptsDifficultSave);
      addStatBreakdown('Saldo de Gols (SG)', counts.clean_sheets, config.ptsCleanSheet);
      addStatBreakdown('Craque da Partida (MOTM)', counts.motm, config.ptsManOfTheMatch);

      expectedScore = Number(expectedScore.toFixed(2));

      // Se jogou, alimenta a lista para a média do técnico da equipe (Regra 2 Decidida)
      if (teamId && hasPlayed) {
        if (!teamScoresForCoach[teamId]) {
          teamScoresForCoach[teamId] = [];
          teamCoachAthleteDetails[teamId] = [];
        }
        teamScoresForCoach[teamId].push(expectedScore);
        teamCoachAthleteDetails[teamId].push({
          playerId: pid,
          name: player.name || 'Desconhecido',
          position: pos,
          score: expectedScore
        });
      }

      // Variação de Preço Esperada (Regra 6 Decidida)
      const currentPrice = Number(player.current_price || config.minPrice);
      const priceValuation = calculateExpectedPrice(currentPrice, expectedScore, config);

      // Dados Publicados
      const liveData = liveScoresObj[pid] || {};
      const publishedLiveScore = Number((liveData.totalScore !== undefined ? liveData.totalScore : 0).toFixed(2));
      const liveCleanSheetCount = Number(liveData.clean_sheets || liveData.cleanSheets || 0);

      // Checa se o ao vivo deu SG indevido
      if (!hasPlayed && liveCleanSheetCount > 0 && isDefensivePos) {
        flags.push("ERRO_AO_VIVO: Sistema concedeu SG ao jogador mesmo sem ele ter entrado em campo!");
      }

      // Pontuação Final de Fechamento (se houver histórico)
      const historyEntry = Array.isArray(player.history) ? player.history.find(h => h.round === roundNum) : null;
      const publishedFinalScore = historyEntry ? Number(Number(historyEntry.score || 0).toFixed(2)) : null;
      const publishedPriceChange = historyEntry ? Number(Number(historyEntry.variation || 0).toFixed(1)) : null;

      // Deltas
      const deltaLive = Number((publishedLiveScore - expectedScore).toFixed(2));
      const deltaFinal = publishedFinalScore !== null ? Number((publishedFinalScore - expectedScore).toFixed(2)) : null;
      const deltaPrice = publishedPriceChange !== null ? Number((publishedPriceChange - priceValuation.variation).toFixed(1)) : null;

      if (Math.abs(deltaLive) >= 0.01) {
        flags.push(`DIVERGENCIA_AO_VIVO: Exibido (${publishedLiveScore}) vs Esperado (${expectedScore}) [Δ ${deltaLive}]`);
      }
      if (deltaFinal !== null && Math.abs(deltaFinal) >= 0.01) {
        flags.push(`DIVERGENCIA_FECHAMENTO: Gravado (${publishedFinalScore}) vs Esperado (${expectedScore}) [Δ ${deltaFinal}]`);
      }
      if (deltaPrice !== null && Math.abs(deltaPrice) >= 0.1) {
        flags.push(`DIVERGENCIA_PRECO: Variação gravada (${publishedPriceChange}) vs Calculada (${priceValuation.variation})`);
      }

      auditedPlayers[pid] = {
        playerId: pid,
        name: player.name || 'Desconhecido',
        position: pos,
        teamId,
        teamShieldUrl: player.team_shield_url || '',
        photoUrl: player.photo_url || '',
        played: hasPlayed,
        scouts: counts,
        expectedScore,
        breakdown,
        timelineEvidence: timelineEvidenceByPlayer[pid] || [],
        priceBefore: currentPrice,
        priceExpectedVariation: priceValuation.variation,
        priceExpectedNew: priceValuation.newPrice,
        publishedLiveScore,
        publishedFinalScore,
        publishedPriceChange,
        deltaLive,
        deltaFinal,
        deltaPrice,
        hasDiscrepancy: flags.some(f => f.startsWith('DIVERGENCIA') || f.startsWith('ERRO')),
        flags,
        coachDetails: null
      };
    }

    // Segundo passo: Processar Técnicos (Média dos atletas com presença confirmada)
    for (const coach of coachesList) {
      const pid = coach.playerId || coach.id;
      const teamId = coach.team_id || '';
      const coachScores = teamScoresForCoach[teamId] || [];
      const athleteDetails = teamCoachAthleteDetails[teamId] || [];

      let expectedScore = 0.0;
      let formulaStr = "Sem atletas com presença confirmada na rodada (0.00 pts)";

      if (coachScores.length > 0) {
        const totalSum = coachScores.reduce((acc, v) => acc + v, 0);
        expectedScore = Number((totalSum / coachScores.length).toFixed(2));
        formulaStr = `${totalSum.toFixed(2)} pts somados / ${coachScores.length} atletas confirmados = ${expectedScore.toFixed(2)} pts`;
      }

      const breakdown = [
        {
          label: "Média dos Atletas que Jogaram",
          count: coachScores.length,
          ptsPerUnit: 1.0,
          subtotal: expectedScore
        }
      ];

      const currentPrice = Number(coach.current_price || config.minPrice);
      const priceValuation = calculateExpectedPrice(currentPrice, expectedScore, config);

      const liveData = liveScoresObj[pid] || {};
      const publishedLiveScore = Number((liveData.totalScore !== undefined ? liveData.totalScore : 0).toFixed(2));
      const historyEntry = Array.isArray(coach.history) ? coach.history.find(h => h.round === roundNum) : null;
      const publishedFinalScore = historyEntry ? Number(Number(historyEntry.score || 0).toFixed(2)) : null;
      const publishedPriceChange = historyEntry ? Number(Number(historyEntry.variation || 0).toFixed(1)) : null;

      const deltaLive = Number((publishedLiveScore - expectedScore).toFixed(2));
      const deltaFinal = publishedFinalScore !== null ? Number((publishedFinalScore - expectedScore).toFixed(2)) : null;
      const deltaPrice = publishedPriceChange !== null ? Number((publishedPriceChange - priceValuation.variation).toFixed(1)) : null;

      const flags = [];
      if (Math.abs(deltaLive) >= 0.01) {
        flags.push(`DIVERGENCIA_AO_VIVO: Técnico exibido (${publishedLiveScore}) vs Esperado (${expectedScore}) [Δ ${deltaLive}]`);
      }
      if (deltaFinal !== null && Math.abs(deltaFinal) >= 0.01) {
        flags.push(`DIVERGENCIA_FECHAMENTO: Técnico gravado (${publishedFinalScore}) vs Esperado (${expectedScore}) [Δ ${deltaFinal}]`);
      }
      if (deltaPrice !== null && Math.abs(deltaPrice) >= 0.1) {
        flags.push(`DIVERGENCIA_PRECO: Variação gravada (${publishedPriceChange}) vs Calculada (${priceValuation.variation})`);
      }

      auditedPlayers[pid] = {
        playerId: pid,
        name: coach.name || 'Desconhecido',
        position: 'Técnico',
        teamId,
        teamShieldUrl: coach.team_shield_url || '',
        photoUrl: coach.photo_url || '',
        played: true, // Técnico sempre pontua se a equipe jogou
        scouts: { goals: 0, assists: 0, yellows: 0, reds: 0, penalties_saved: 0, penalties_missed: 0, shots_on_post: 0, clean_sheets: 0, own_goals: 0, direct_free_kicks_missed: 0, motm: 0, difficult_saves: 0 },
        expectedScore,
        breakdown,
        timelineEvidence: [],
        priceBefore: currentPrice,
        priceExpectedVariation: priceValuation.variation,
        priceExpectedNew: priceValuation.newPrice,
        publishedLiveScore,
        publishedFinalScore,
        publishedPriceChange,
        deltaLive,
        deltaFinal,
        deltaPrice,
        hasDiscrepancy: flags.some(f => f.startsWith('DIVERGENCIA') || f.startsWith('ERRO')),
        flags,
        coachDetails: {
          athletesCount: coachScores.length,
          formula: formulaStr,
          athletes: athleteDetails
        }
      };
    }

    // 6. Auditoria de Times dos Usuários
    const teamAuditList = [];
    if (includeTeams) {
      const teamsSnap = await db.collection('fantasy_teams').get();

      for (const tDoc of teamsSnap.docs) {
        const tData = tDoc.data();
        const tid = tDoc.id;
        const ownerName = tData.owner_name || 'Desconhecido';
        const teamName = tData.team_name || 'Sem nome';

        // Busca o documento de histórico da rodada
        const tHistorySnap = await tDoc.ref.collection('history').doc(roundNum.toString()).get();
        if (!tHistorySnap.exists) {
          continue; // Time não tem histórico nesta rodada ainda
        }

        const hData = tHistorySnap.data();
        const publishedRoundPoints = Number(Number(hData.points || 0).toFixed(2));
        const lineupSnapshot = Array.isArray(hData.final_lineup) && hData.final_lineup.length > 0
          ? hData.final_lineup
          : (Array.isArray(hData.lineup_snapshot) ? hData.lineup_snapshot : (tData.lineup_player_ids || []));
        const captainId = hData.captain_id || tData.captain_id || null;

        let expectedTeamPoints = 0.0;
        const playerDetailsList = [];

        lineupSnapshot.forEach(pid => {
          const auditedP = auditedPlayers[pid];
          let basePoints = auditedP ? auditedP.expectedScore : 0.0;
          const isCaptain = (pid === captainId);
          const finalPlayerPoints = isCaptain ? Number((basePoints * 2).toFixed(2)) : basePoints;
          expectedTeamPoints += finalPlayerPoints;

          playerDetailsList.push({
            playerId: pid,
            name: auditedP?.name || 'Desconhecido',
            position: auditedP?.position || '',
            score: basePoints,
            isCaptain,
            finalScore: finalPlayerPoints
          });
        });

        expectedTeamPoints = Number(expectedTeamPoints.toFixed(2));
        const delta = Number((publishedRoundPoints - expectedTeamPoints).toFixed(2));
        const hasDiscrepancy = Math.abs(delta) >= 0.01;

        teamAuditList.push({
          teamId: tid,
          teamName,
          ownerName,
          captainId,
          lineupCount: lineupSnapshot.length,
          expectedPoints: expectedTeamPoints,
          publishedPoints: publishedRoundPoints,
          delta,
          hasDiscrepancy,
          players: playerDetailsList,
          substitutions: hData.substitutions || []
        });
      }
    }

    // 6.5 Sincronização direta com o Ao Vivo (se solicitada pelo Admin)
    if (syncToLive) {
      const liveDocRef = db.collection('championships').doc(seasonId)
        .collection('fantasy_live').doc(`round_${roundNum}`);
      const currentLiveSnap = await liveDocRef.get();
      const currentLiveScores = currentLiveSnap.exists ? (currentLiveSnap.data().scores || {}) : {};

      const syncedScores = {};
      for (const [pid, p] of Object.entries(auditedPlayers)) {
        syncedScores[pid] = {
          totalScore: p.expectedScore,
          goals: p.scouts?.goals || 0,
          assists: p.scouts?.assists || 0,
          yellows: p.scouts?.yellows || 0,
          reds: p.scouts?.reds || 0,
          goals_conceded: currentLiveScores[pid]?.goals_conceded || 0,
          penalties_saved: p.scouts?.penalties_saved || 0,
          penalties_missed: p.scouts?.penalties_missed || 0,
          shots_on_post: p.scouts?.shots_on_post || 0,
          clean_sheets: p.scouts?.clean_sheets || 0,
          own_goals: p.scouts?.own_goals || 0,
          direct_free_kicks_missed: p.scouts?.direct_free_kicks_missed || 0,
          difficult_saves: p.scouts?.difficult_saves || 0,
          motm: p.scouts?.motm || 0
        };

        // Atualiza os dados locais do atleta auditado para refletir a sincronização
        p.publishedLiveScore = p.expectedScore;
        p.deltaLive = 0.0;
        p.flags = p.flags.filter(f => !f.startsWith('DIVERGENCIA_AO_VIVO') && !f.startsWith('ERRO_AO_VIVO'));
        p.hasDiscrepancy = p.flags.some(f => f.startsWith('DIVERGENCIA') || f.startsWith('ERRO'));
      }

      await liveDocRef.set({
        scores: syncedScores,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        synced_from_audit: true
      }, { merge: true });

      console.log(`⚡ [AUDIT_SYNC] ${Object.keys(syncedScores).length} atletas sincronizados com sucesso no Ao Vivo (round_${roundNum}).`);
    }

    // 7. Consolidação de KPIs e Métricas
    const playerArray = Object.values(auditedPlayers);
    const playersWithDiscrepancy = playerArray.filter(p => p.hasDiscrepancy);
    const teamsWithDiscrepancy = teamAuditList.filter(t => t.hasDiscrepancy);
    let maxDelta = 0.0;
    playerArray.forEach(p => {
      const absLive = Math.abs(p.deltaLive || 0);
      const absFinal = p.deltaFinal !== null ? Math.abs(p.deltaFinal) : 0;
      if (absLive > maxDelta) maxDelta = absLive;
      if (absFinal > maxDelta) maxDelta = absFinal;
    });

    const reportId = `${seasonId}_r${roundNum}`;
    const reportRef = db.collection('fantasy_audit').doc(reportId);
    const nowTimestamp = admin.firestore.FieldValue.serverTimestamp();

    const summaryData = {
      season_id: seasonId,
      round: roundNum,
      run_at: nowTimestamp,
      run_by: callerUid,
      total_players_audited: playerArray.length,
      players_with_discrepancies: playersWithDiscrepancy.length,
      total_teams_audited: teamAuditList.length,
      teams_with_discrepancies: teamsWithDiscrepancy.length,
      max_player_delta: Number(maxDelta.toFixed(2)),
      total_matches: matchAuditList.length,
      matches_finished: matchAuditList.filter(m => m.status === 'finished').length,
      live_is_final: liveIsFinal,
      config_effective: config,
      config_warnings: configWarnings,
      status: playersWithDiscrepancy.length === 0 && teamsWithDiscrepancy.length === 0 ? 'CLEAN' : 'DISCREPANCIES_FOUND'
    };

    // 8. Gravação Transacional/Batch em Subcoleções
    const batchWriter = new AuditBatchWriter(db);

    // Salva o resumo raiz
    await reportRef.set(summaryData);

    // Salva subcoleção de jogadores
    for (const p of playerArray) {
      const pRef = reportRef.collection('players').doc(p.playerId);
      await batchWriter.set(pRef, p);
    }

    // Salva subcoleção de partidas
    for (const m of matchAuditList) {
      const mRef = reportRef.collection('matches').doc(m.matchId);
      await batchWriter.set(mRef, m);
    }

    // Salva subcoleção de times
    for (const t of teamAuditList) {
      const tRef = reportRef.collection('teams').doc(t.teamId);
      await batchWriter.set(tRef, t);
    }

    await batchWriter.commit();

    console.log(`✅ [AUDIT] Concluída com sucesso: ${playerArray.length} jogadores, ${playersWithDiscrepancy.length} divergências encontradas.`);

    return {
      success: true,
      reportId,
      summary: {
        ...summaryData,
        run_at: new Date().toISOString()
      }
    };

  } catch (error) {
    console.error("❌ [AUDIT] Erro durante auditoria de scouts:", error);
    throw new HttpsError('internal', `Erro no processamento da auditoria: ${error.message}`);
  }
}
