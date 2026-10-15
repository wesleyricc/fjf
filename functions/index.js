const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const axios = require("axios");
const https = require("https");
const fs = require("fs");
const path = require("path");

admin.initializeApp();
const db = admin.firestore();

// ==================================================================
// CONFIGURAÇÕES GERAIS E SCOUTS (PADRÃO CARTOLA FC)
// ==================================================================

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

const SLOT_POSITIONS = {
  '1': 'Goleiro',
  '2': 'Fixo',
  '3': 'Ala',
  '4': 'Ala',
  '5': 'Pivô',
  '6': 'Técnico',
};

const BENCH_POSITIONS = {
  '11': 'Goleiro',
  '12': 'Fixo',
  '13': 'Ala',
  '15': 'Pivô',
  '16': 'Técnico',
};

// ==================================================================
// 🔐 CONFIGURAÇÃO mTLS E AUTENTICAÇÃO SICOOB (PRODUÇÃO)
// ==================================================================

const SICOOB_CLIENT_ID = "7b0b3a94-9783-4129-bef6-166eb52370a0";
const SICOOB_AUTH_URL = "https://auth.sicoob.com.br/auth/realms/cooperado/protocol/openid-connect/token";
const SICOOB_API_URL = "https://api.sicoob.com.br/pix/api/v2";

const CHAVE_PIX = "04441635000185";

const httpsAgent = new https.Agent({
  cert: fs.readFileSync(path.join(__dirname, 'certificado.pem')),
  key: fs.readFileSync(path.join(__dirname, 'chave.key')),
});

async function getSicoobToken(scope) {
  const params = new URLSearchParams();
  params.append('grant_type', 'client_credentials');
  params.append('client_id', SICOOB_CLIENT_ID);
  params.append('scope', scope);

  try {
    const response = await axios.post(SICOOB_AUTH_URL, params.toString(), {
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      httpsAgent: httpsAgent
    });
    return response.data.access_token;
  } catch (error) {
    console.error("Erro ao gerar Token OAuth2 Sicoob:", error.response?.data || error.message);
    throw new HttpsError('internal', 'Falha na autenticação com o Banco (Sicoob).');
  }
}

// ==================================================================
// 🛒 MÓDULO DE PAGAMENTOS (PIX SICOOB)
// ==================================================================

exports.createPixPayment = onCall({ cors: true, enforceAppCheck: false }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Usuário não autenticado no aplicativo.');
  }

  const { type, userId, customerContact, photoIds, miniBolaoId, customDescription } = request.data;
  let valorInscricao = "0.00";
  let itemsToSave = [];
  let description = customDescription || "";

  if (type === 'bolao') {
    valorInscricao = "20.00";
    if (!description) description = `Inscrição Bolão Copa 2026 - ${userId}`;
  }
  else if (type === 'mini_bolao') {
    if (!miniBolaoId) throw new HttpsError('invalid-argument', 'ID do Mini Bolão não informado.');

    const mbSnap = await db.collection('bolao_mini_leagues').doc(miniBolaoId).get();
    if (!mbSnap.exists) throw new HttpsError('not-found', 'Mini Bolão não encontrado.');

    const mbData = mbSnap.data();

    if (mbData.deadline) {
      const deadlineTime = mbData.deadline.toDate();
      if (new Date() > deadlineTime) {
        throw new HttpsError('permission-denied', 'O prazo de inscrição para este Mini Bolão já encerrou!');
      }
    }

    const entryFee = parseFloat(mbData.entry_fee || 0);
    if (entryFee <= 0) throw new HttpsError('invalid-argument', 'Valor do Mini Bolão é inválido.');

    valorInscricao = entryFee.toFixed(2);
    if (!description) description = `Mini Bolão: ${mbData.title}`.substring(0, 140);
  }
  else if (type === 'portal') {
    const dueId = request.data.dueId;
    if (!dueId) throw new HttpsError('invalid-argument', 'ID do débito não informado.');
    const dueSnap = await db.collection('portal_financial_dues').doc(dueId).get();
    if (!dueSnap.exists) throw new HttpsError('not-found', 'Débito não encontrado.');

    const dueData = dueSnap.data();
    if (dueData.status === 'paid') throw new HttpsError('failed-precondition', 'Este débito já está pago.');

    valorInscricao = parseFloat(dueData.amount).toFixed(2);
    if (!description) description = dueData.title.substring(0, 140);
  }
  else {
    if (!photoIds || !Array.isArray(photoIds) || photoIds.length === 0) {
      throw new HttpsError('invalid-argument', 'Nenhum item no carrinho.');
    }
    let total = 0.0;
    for (const id of photoIds) {
      const snap = await db.collection('photo_sales').doc(id).get();
      if (snap.exists) {
        total += parseFloat(snap.data().price);
        itemsToSave.push({ photo_id: snap.id, original_url: snap.data().original_url });
      }
    }
    valorInscricao = total.toFixed(2);
    if (!description) description = `Pack de ${itemsToSave.length} Fotos FJF - ${customerContact}`;
  }

  try {
    const accessToken = await getSicoobToken('cob.write cob.read');

    const payloadCobranca = {
      calendario: { expiracao: 3600 },
      valor: { original: valorInscricao },
      chave: CHAVE_PIX,
      solicitacaoPagador: description.substring(0, 140),
    };

    const responseCob = await axios.post(`${SICOOB_API_URL}/cob`, payloadCobranca, {
      headers: {
        "client_id": SICOOB_CLIENT_ID,
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json"
      },
      httpsAgent: httpsAgent
    });

    const cobranca = responseCob.data;
    let pixCodeCopiaECola = cobranca.pixCopiaECola || cobranca.brcode;

    if (!pixCodeCopiaECola && cobranca.loc && cobranca.loc.id) {
      const responseQr = await axios.get(`${SICOOB_API_URL}/loc/${cobranca.loc.id}/qrcode`, {
        headers: { "client_id": SICOOB_CLIENT_ID, "Authorization": `Bearer ${accessToken}` },
        httpsAgent: httpsAgent
      });
      pixCodeCopiaECola = responseQr.data.qrcode || responseQr.data.pixCopiaECola;
    }

    await db.collection('orders').doc(cobranca.txid).set({
      user_id: userId || 'anonymous',
      type: type || 'photo',
      customer_contact: customerContact || '',
      status: 'pending',
      amount: valorInscricao,
      txid: cobranca.txid,
      items: itemsToSave,
      mini_bolao_id: miniBolaoId || null,
      due_id: type === 'portal' ? request.data.dueId : null,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, pix_code: pixCodeCopiaECola, payment_id: cobranca.txid };

  } catch (error) {
    console.error("Erro na criação do PIX:", error.response?.data || error.message);
    throw new HttpsError('internal', 'Erro ao processar integração bancária.');
  }
});

exports.checkPixStatus = onCall({ cors: true, enforceAppCheck: false }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Usuário não autenticado.');

  const { txid, userId, type } = request.data;

  try {
    const accessToken = await getSicoobToken('cob.read');

    const response = await axios.get(`${SICOOB_API_URL}/cob/${txid}`, {
      headers: { "client_id": SICOOB_CLIENT_ID, "Authorization": `Bearer ${accessToken}` },
      httpsAgent: httpsAgent
    });

    const cobranca = response.data;
    const isPaid = cobranca.status === 'CONCLUIDA';

    if (isPaid) {
      const orderRef = db.collection('orders').doc(txid);
      const orderSnap = await orderRef.get();

      if (orderSnap.exists && orderSnap.data().status !== 'approved') {
        await processOrderApproval(txid, orderSnap.data(), cobranca.pix ? cobranca.pix[0].valor : null);
      }
    }

    return { status: cobranca.status, is_paid: isPaid };

  } catch (error) {
    console.error("Erro consulta PIX:", error.response?.data || error.message);
    throw new HttpsError('internal', 'Erro ao verificar o pagamento.');
  }
});

exports.sicoobWebhook = onRequest(async (req, res) => {
  try {
    const pixList = req.body.pix;

    if (!pixList || !Array.isArray(pixList)) {
      console.warn(`Webhook Sicoob ignorado (Path: ${req.path}): Payload sem array 'pix'.`);
      return res.status(400).send("Bad Request");
    }

    const batchHandler = new BatchHandler(db);

    for (const pix of pixList) {
      const txid = pix.txid;
      if (!txid) continue;

      const orderRef = db.collection('orders').doc(txid);
      const orderSnap = await orderRef.get();

      if (orderSnap.exists) {
        const orderData = orderSnap.data();

        if (orderData.status !== 'approved') {
          batchHandler.update(orderRef, {
            status: 'approved',
            valor_pago: pix.valor,
            approved_at: admin.firestore.FieldValue.serverTimestamp(),
          });

          if (orderData.type === 'bolao' && orderData.user_id) {
            const userBolaoRef = db.collection('bolao_users').doc(orderData.user_id);
            batchHandler.set(userBolaoRef, {
              has_paid: true,
              total_points: 0,
              payment_id: txid,
              approved_at: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
          }
          else if (orderData.type === 'mini_bolao' && orderData.user_id && orderData.mini_bolao_id) {
            const miniBolaoRef = db.collection('bolao_mini_leagues').doc(orderData.mini_bolao_id);
            const participantRef = miniBolaoRef.collection('participants').doc(orderData.user_id);

            batchHandler.set(participantRef, {
              joined_at: admin.firestore.FieldValue.serverTimestamp(),
              points: 0
            });

            batchHandler.update(miniBolaoRef, {
              prize_pool: admin.firestore.FieldValue.increment(parseFloat(orderData.amount || 0)),
              participants_count: admin.firestore.FieldValue.increment(1)
            });

            console.log(`✅ [WEBHOOK SICOOB] Mini Bolão liberado automaticamente. TXID: ${txid}`);
          }
          else if (orderData.type === 'portal' && orderData.due_id) {
            const dueRef = db.collection('portal_financial_dues').doc(orderData.due_id);
            batchHandler.update(dueRef, {
              status: 'paid',
              payment_date: admin.firestore.FieldValue.serverTimestamp()
            });
            console.log(`✅ [WEBHOOK SICOOB] Débito do Portal pago. TXID: ${txid}`);
          }
        }
      }
    }

    await batchHandler.commit();
    res.status(200).send("OK");

  } catch (error) {
    console.error("🔥 Erro Webhook Sicoob:", error);
    res.status(500).send("Internal Server Error");
  }
});

async function processOrderApproval(txid, orderData, valorPago = null) {
  const batchHandler = new BatchHandler(db);
  const orderRef = db.collection('orders').doc(txid);

  const updateData = {
    status: 'approved',
    approved_at: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (valorPago) updateData.valor_pago = valorPago;

  batchHandler.update(orderRef, updateData);

  if (orderData.type === 'bolao' && orderData.user_id) {
    const userBolaoRef = db.collection('bolao_users').doc(orderData.user_id);
    batchHandler.set(userBolaoRef, {
      has_paid: true,
      total_points: 0,
      payment_id: txid,
      approved_at: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
  }
  else if (orderData.type === 'mini_bolao' && orderData.user_id && orderData.mini_bolao_id) {
    const miniBolaoRef = db.collection('bolao_mini_leagues').doc(orderData.mini_bolao_id);
    const participantRef = miniBolaoRef.collection('participants').doc(orderData.user_id);

    batchHandler.set(participantRef, {
      joined_at: admin.firestore.FieldValue.serverTimestamp(),
      points: 0
    });

    batchHandler.update(miniBolaoRef, {
      prize_pool: admin.firestore.FieldValue.increment(parseFloat(orderData.amount || 0)),
      participants_count: admin.firestore.FieldValue.increment(1)
    });

    console.log(`✅ [POLLING MANUAL] Mini Bolão liberado. TXID: ${txid}`);
  }
  else if (orderData.type === 'portal' && orderData.due_id) {
    const dueRef = db.collection('portal_financial_dues').doc(orderData.due_id);
    batchHandler.update(dueRef, {
      status: 'paid',
      payment_date: admin.firestore.FieldValue.serverTimestamp()
    });
    console.log(`✅ [POLLING MANUAL] Débito do Portal pago. TXID: ${txid}`);
  }
  else if (orderData.type === 'photo') {
    console.log(`✅ [POLLING MANUAL] Fotos liberadas. TXID: ${txid}`);
  }

  await batchHandler.commit();
}

exports.registerWebhookSicoob = onRequest(async (req, res) => {
  try {
    const accessToken = await getSicoobToken('webhook.write');
    const myWebhookBaseUrl = "https://us-central1-acefjf.cloudfunctions.net/sicoobWebhook";

    const response = await axios.put(`${SICOOB_API_URL}/webhook/${CHAVE_PIX}`,
      { webhookUrl: myWebhookBaseUrl },
      {
        headers: {
          "client_id": SICOOB_CLIENT_ID,
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json"
        },
        httpsAgent: httpsAgent
      }
    );

    res.status(200).send(`Webhook atrelado à chave ${CHAVE_PIX} com sucesso! Resposta: ${JSON.stringify(response.data)}`);
  } catch (error) {
    res.status(500).send(`Erro ao cadastrar Webhook: ${error.response?.data ? JSON.stringify(error.response.data) : error.message}`);
  }
});

// ==================================================================
// ⚽ MÓDULO FANTASY (Fechamento de Rodada)
// ==================================================================

exports.closeRound = onCall({
  cors: true,
  timeoutSeconds: 540,
  memory: '1GB'
}, async (request) => {

  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Acesso negado. O usuário precisa estar logado.');
  }

  const adminDoc = await db.collection('admin_users').doc(request.auth.uid).get();
  if (!adminDoc.exists) {
    console.error(`🚨 TENTATIVA DE INVASÃO DETECTADA! UID: ${request.auth.uid} tentou executar closeRound.`);
    throw new HttpsError('permission-denied', 'Acesso negado. Apenas administradores podem fechar a rodada.');
  }

  const { seasonId, round } = request.data;

  if (!seasonId || !round) {
    throw new HttpsError('invalid-argument', 'seasonId e round são obrigatórios.');
  }

  try {
    const configSnap = await db.collection('fantasy_config').doc('rules').get();
    const rawConfig = configSnap.exists ? configSnap.data() : {};
    const config = { ...DEFAULT_CONFIG, ...rawConfig };
    if (rawConfig.ptsMotm !== undefined && rawConfig.ptsManOfTheMatch === undefined) {
      config.ptsManOfTheMatch = Number(rawConfig.ptsMotm);
    }
    if (rawConfig.ptsMissedFreeKick !== undefined && rawConfig.ptsDirectFreeKickMissed === undefined) {
      config.ptsDirectFreeKickMissed = Number(rawConfig.ptsMissedFreeKick);
    }
    const ptsMotm = config.ptsManOfTheMatch !== undefined ? Number(config.ptsManOfTheMatch) : (config.ptsMotm !== undefined ? Number(config.ptsMotm) : 5.0);

    const matchesSnap = await db.collection('championships').doc(seasonId)
      .collection('matches').where('round', '==', round).get();

    const scoresMap = {};
    const teamCleanSheets = {};
    const playersPlayedSet = new Set();

    matchesSnap.forEach(doc => {
      const data = doc.data();

      // Mapeamento de Presença (quem jogou)
      if (data.lineup_played && Array.isArray(data.lineup_played)) {
        data.lineup_played.forEach(pid => playersPlayedSet.add(pid.toString()));
      }

      const scoreHome = data.score_home || 0;
      const scoreAway = data.score_away || 0;
      if (scoreAway === 0) teamCleanSheets[data.team_home_id] = true;
      if (scoreHome === 0) teamCleanSheets[data.team_away_id] = true;

      // Craque do Jogo (MOTM) pontua independentemente de stats_applied.player_stats
      const motmPid = data.stats_applied?.man_of_the_match || data.man_of_the_match;
      if (motmPid) {
        const strMotm = motmPid.toString();
        scoresMap[strMotm] = (scoresMap[strMotm] || 0) + ptsMotm;
      }

      if (!data.stats_applied || !data.stats_applied.player_stats) return;

      const stats = data.stats_applied.player_stats;
      const ptsRules = {
        goals: config.ptsGoal,
        assists: config.ptsAssist,
        yellows: config.ptsYellowCard,
        reds: config.ptsRedCard,
        penalties_saved: config.ptsPenaltySaved,
        penalties_missed: config.ptsPenaltyMissed,
        shots_on_post: config.ptsShotOnPost,
        own_goals: config.ptsOwnGoal,
        direct_free_kicks_missed: config.ptsDirectFreeKickMissed,
        difficult_saves: config.ptsDifficultSave
      };

      ['goals', 'assists', 'yellows', 'reds', 'penalties_saved', 'penalties_missed', 'shots_on_post', 'own_goals', 'direct_free_kicks_missed', 'difficult_saves'].forEach(cat => {
        if (stats[cat]) {
          Object.entries(stats[cat]).forEach(([pid, val]) => {
            const points = (Number(val) || 0) * (ptsRules[cat] || 0);
            scoresMap[pid] = (scoresMap[pid] || 0) + points;
          });
        }
      });
    });

    const allPlayersSnap = await db.collection('fantasy_market_players').get();

    const teamScores = {};
    const teamLogDetails = {};
    const teamCoaches = {};
    const playersInfo = {};

    allPlayersSnap.forEach(doc => {
      const p = doc.data();
      const pid = doc.id;
      const teamId = p.team_id;

      playersInfo[pid] = p;

      if (!teamId) return;

      const hasPlayed = playersPlayedSet.has(pid.toString());

      // Regra Oficial: SG só conta para atletas da posição Goleiro e Fixo confirmados na súmula (lineup_played)
      if (hasPlayed && teamCleanSheets[teamId] && (p.position === 'Goleiro' || p.position === 'Fixo')) {
        scoresMap[pid] = (scoresMap[pid] || 0) + config.ptsCleanSheet;
      }

      if (p.position === 'Técnico') {
        teamCoaches[teamId] = pid;
      }

      // Regra Oficial: Média do técnico considera a pontuação total do time dividido pelo total de atletas confirmados que jogaram em súmula (lineup_played)
      if (hasPlayed && p.position !== 'Técnico') {
        const points = (scoresMap[pid] !== undefined) ? scoresMap[pid] : 0.0;
        if (!teamScores[teamId]) {
          teamScores[teamId] = [];
          teamLogDetails[teamId] = [];
        }
        teamScores[teamId].push(points);
        teamLogDetails[teamId].push(`${p.name} (${p.position}): ${points}pts`);
      }
    });

    Object.entries(teamCoaches).forEach(([tId, coachPid]) => {
      const scores = teamScores[tId] || [];
      if (scores.length > 0) {
        const total = scores.reduce((a, b) => a + b, 0);
        const avg = total / scores.length;
        scoresMap[coachPid] = Number(avg.toFixed(2));
      } else {
        scoresMap[coachPid] = 0;
      }
    });

    const batchHandler = new BatchHandler(db);
    const newPricesMap = {};

    allPlayersSnap.forEach(doc => {
      const p = doc.data();
      const pid = doc.id;
      const score = scoresMap[pid] || 0;

      // Busca o histórico caso seja um reprocessamento da rodada
      const existingHistory = Array.isArray(p.history) ? p.history.find(h => h.round === round) : null;
      // Se já existir, usamos o price_before original para não acumular variações de preço
      const currentPrice = existingHistory ? (existingHistory.price_before || config.minPrice) : (p.current_price || config.minPrice);

      const expectation = currentPrice * config.factorExpectation;
      const performance = score - expectation;
      let variation = performance * config.factorVariation;
      let limit = currentPrice * config.capLimitPercent;

      // Clamp garante que o limite nunca seja menor que 2.0 nem maior que 5.0
      if (limit < 2.0) limit = 2.0;
      if (limit > 5.0) limit = 5.0;

      if (variation > limit) variation = limit;
      if (variation < -limit) variation = -limit;

      let newPrice = currentPrice + variation;
      if (newPrice < config.minPrice) newPrice = config.minPrice;

      newPricesMap[pid] = Number(newPrice.toFixed(1));
      variation = Number(variation.toFixed(1));

      const hasPlayed = playersPlayedSet.has(pid.toString()) || (p.position === 'Técnico' && (teamScores[p.team_id] && teamScores[p.team_id].length > 0));

      const updatedHistory = Array.isArray(p.history) ? p.history.filter(h => h.round !== round) : [];
      updatedHistory.push({
        round: round,
        score: score,
        price_before: currentPrice,
        price_after: newPricesMap[pid],
        variation: variation,
        played: hasPlayed,
        processed_at: admin.firestore.Timestamp.now()
      });

      const playedMatches = updatedHistory.filter(h => h.played);
      const avgScore = playedMatches.length > 0 ? (playedMatches.reduce((acc, h) => acc + h.score, 0) / playedMatches.length) : 0;

      batchHandler.update(doc.ref, {
        current_price: newPricesMap[pid],
        last_price_change: variation,
        last_score: score,
        average_score: Number(avgScore.toFixed(2)),
        matches_played: playedMatches.length,
        history: updatedHistory
      });
    });

    const oldTeamHistoriesSnap = await db.collectionGroup('history').where('round', '==', round).get();
    const oldTeamPointsMap = {};
    oldTeamHistoriesSnap.forEach(doc => {
      // O caminho é fantasy_teams/{teamId}/history/{round}
      const teamId = doc.ref.parent.parent.id;
      oldTeamPointsMap[teamId] = doc.data().points || 0;
    });

    const userTeamsSnap = await db.collection('fantasy_teams').get();

    const playerPickedCount = {};
    const teamRoundScores = {};
    const teamPatrimony = {}; // NOVO

    userTeamsSnap.forEach(doc => {
      const team = doc.data();
      const originalLineup = team.lineup_player_ids || [];
      const benchIds = team.bench_player_ids || [];
      const captainId = team.captain_id || null;
      const luxuryReserveId = team.luxury_reserve_id || null;

      // Conta para Mais Escalados
      originalLineup.forEach(pid => {
        playerPickedCount[pid] = (playerPickedCount[pid] || 0) + 1;
      });

      let finalLineup = [...originalLineup];
      let substitutedList = [];
      let activeCaptainId = captainId;

      const lineupSlots = team.lineup_slots || {};
      const benchSlots = team.bench_slots || {};

      // Mapeia os titulares para as posições com base estritamente no SLOT onde foram escalados
      const startersByPos = {
        'Goleiro': [],
        'Fixo': [],
        'Ala': [],
        'Pivô': [],
        'Técnico': []
      };

      const slottedStarters = new Set();
      Object.entries(lineupSlots).forEach(([slot, pid]) => {
        const pos = SLOT_POSITIONS[slot];
        if (pos && pid && originalLineup.includes(pid)) {
          startersByPos[pos].push(pid);
          slottedStarters.add(pid);
        }
      });

      // Fallback para times legados que não possuem lineup_slots gravado
      originalLineup.forEach(pid => {
        if (!slottedStarters.has(pid) && playersInfo[pid]) {
          const pos = playersInfo[pid].position;
          if (startersByPos[pos]) {
            startersByPos[pos].push(pid);
          }
        }
      });

      // Mapeia os reservas para as posições com base estritamente no SLOT do banco onde foram colocados
      const benchByPos = {};
      const slottedBench = new Set();
      Object.entries(benchSlots).forEach(([slot, bId]) => {
        const pos = BENCH_POSITIONS[slot];
        if (pos && bId && benchIds.includes(bId)) {
          benchByPos[pos] = bId;
          slottedBench.add(bId);
        }
      });

      // Fallback para banco de times legados que não possuem bench_slots
      benchIds.forEach(bId => {
        if (!slottedBench.has(bId) && playersInfo[bId]) {
          const pos = playersInfo[bId].position;
          if (!benchByPos[pos]) {
            benchByPos[pos] = bId;
          }
        }
      });

      const positions = ['Goleiro', 'Fixo', 'Ala', 'Pivô', 'Técnico'];

      positions.forEach(pos => {
        const startersOfPos = startersByPos[pos] || [];
        const benchId = benchByPos[pos];

        if (startersOfPos.length && benchId && playersPlayedSet.has(benchId)) {
          const allPlayed = startersOfPos.every(pid => playersPlayedSet.has(pid));

          if (!allPlayed) {
            // Um ou mais titulares da posição não jogaram
            const missedStarters = startersOfPos.filter(pid => !playersPlayedSet.has(pid));

            // Se houver mais de um que não jogou (ex: duas alas), prioriza:
            // 1) Se for o capitão, substitui o capitão primeiro para passar a braçadeira pro reserva que jogou
            // 2) Maior preço de mercado
            // 3) Ordem alfabética
            missedStarters.sort((a, b) => {
              if (a === activeCaptainId) return -1;
              if (b === activeCaptainId) return 1;
              const priceA = playersInfo[a]?.current_price || 0;
              const priceB = playersInfo[b]?.current_price || 0;
              return priceB - priceA;
            });

            const missedStarter = missedStarters[0];
            if (missedStarter) {
              finalLineup = finalLineup.filter(p => p !== missedStarter);
              finalLineup.push(benchId);
              substitutedList.push({ out: missedStarter, in: benchId, type: 'normal', slot_position: pos });

              // Repassa faixa de capitão se o titular ausente era o capitão
              if (missedStarter === activeCaptainId) {
                activeCaptainId = benchId;
              }
            }
          } else {
            // Todos jogaram. Avalia Reserva de Luxo.
            if (luxuryReserveId === benchId) {
              const benchScore = scoresMap[benchId] || 0;

              // Reserva de luxo só entra se tiver pontuação estritamente superior ao pior titular daquela posição
              let worstStarter = startersOfPos[0];
              let worstScore = scoresMap[worstStarter] || 0;

              startersOfPos.forEach(pid => {
                const s = scoresMap[pid] || 0;
                if (s < worstScore) {
                  worstScore = s;
                  worstStarter = pid;
                } else if (s === worstScore) {
                  // Em empate de pior pontuação, prioriza substituir quem NÃO é capitão
                  if (worstStarter === activeCaptainId && pid !== activeCaptainId) {
                    worstStarter = pid;
                  }
                }
              });

              if (benchScore > worstScore) {
                finalLineup = finalLineup.filter(p => p !== worstStarter);
                finalLineup.push(benchId);
                substitutedList.push({ out: worstStarter, in: benchId, type: 'luxury', slot_position: pos });

                if (worstStarter === activeCaptainId) {
                  activeCaptainId = benchId;
                }
              }
            }
          }
        }
      });

      let roundPoints = 0;
      let playersCurrentValue = 0;

      finalLineup.forEach(pid => {
        let pScore = scoresMap[pid] || 0;
        if (pid === activeCaptainId) pScore *= 2;
        roundPoints += pScore;
      });

      originalLineup.forEach(pid => {
        playersCurrentValue += (newPricesMap[pid] || config.minPrice);
      });

      // Arredonda pra 2 casas decimais
      roundPoints = Number(roundPoints.toFixed(2));
      teamRoundScores[doc.id] = roundPoints; // Guarda pra usar no mata-mata

      const currentBalance = team.current_balance || 0;
      const totalPatrimony = Number((currentBalance + playersCurrentValue).toFixed(2));
      teamPatrimony[doc.id] = totalPatrimony; // NOVO

      const teamHistoryRef = doc.ref.collection('history').doc(round.toString());

      batchHandler.set(teamHistoryRef, {
        round: round,
        points: roundPoints,
        patrimony: totalPatrimony,
        processed_at: admin.firestore.Timestamp.now(),
        captain_id: activeCaptainId,
        original_captain_id: captainId,
        lineup_snapshot: originalLineup,
        final_lineup: finalLineup,
        substitutions: substitutedList
      });

      let baseTotalPoints = team.total_points || 0;
      if (oldTeamPointsMap[doc.id] !== undefined) {
        baseTotalPoints -= oldTeamPointsMap[doc.id]; // Subtrai a pontuação anterior para não duplicar no reprocessamento
      }
      const newTotalPoints = Number((baseTotalPoints + roundPoints).toFixed(2));

      batchHandler.update(doc.ref, {
        total_points: newTotalPoints,
        last_score: roundPoints,
        team_value: totalPatrimony,
        updated_at: admin.firestore.Timestamp.now()
      });
    });

    // ==========================================
    // 3. SCOUTS GLOBAIS (Seleção e Mais Escalados)
    // ==========================================
    const mostPickedArr = Object.keys(playerPickedCount).map(pid => {
      return { pid, count: playerPickedCount[pid], ...playersInfo[pid] };
    });
    mostPickedArr.sort((a, b) => b.count - a.count);
    const topPickedFormatted = mostPickedArr.slice(0, 30).map(p => ({
      player_id: p.pid,
      name: p.name || 'Sem nome',
      position: p.position || 'Desconhecido',
      team_name: p.team_name || '',
      team_shield_url: p.team_shield_url || '',
      photo_url: p.photo_url || '',
      current_price: p.current_price || 0,
      selections: p.count,
      count: p.count,
      score: scoresMap[p.pid] || 0,
      round_score: scoresMap[p.pid] || 0
    }));

    const playersByPos = { 'Goleiro': [], 'Fixo': [], 'Ala': [], 'Pivô': [], 'Técnico': [] };
    Object.keys(scoresMap).forEach(pid => {
      const pInfo = playersInfo[pid];
      if (pInfo && playersByPos[pInfo.position]) {
        playersByPos[pInfo.position].push({ pid, score: scoresMap[pid], info: pInfo });
      }
    });

    const dreamTeam = [];
    const pushTop = (pos, limit) => {
      if (playersByPos[pos]) {
        playersByPos[pos].sort((a, b) => b.score - a.score);
        playersByPos[pos].slice(0, limit).forEach(p => {
          dreamTeam.push({
            player_id: p.pid,
            name: p.info.name || 'Sem nome',
            position: pos,
            photo_url: p.info.photo_url || '',
            team_shield_url: p.info.team_shield_url || '',
            score: p.score,
            round_score: p.score
          });
        });
      }
    };
    pushTop('Goleiro', 1);
    pushTop('Fixo', 1);
    pushTop('Ala', 2);
    pushTop('Pivô', 1);
    pushTop('Técnico', 1);

    const roundStatsPayload = {
      round: round,
      most_selected: topPickedFormatted,
      most_picked: topPickedFormatted,
      dream_team: dreamTeam,
      updated_at: admin.firestore.Timestamp.now()
    };

    const roundStatsRef = db.collection('fantasy_stats').doc(`round_${round}`);
    batchHandler.set(roundStatsRef, roundStatsPayload, { merge: true });

    const globalStatsRef = db.collection('fantasy_stats').doc('global_round_stats');
    batchHandler.set(globalStatsRef, roundStatsPayload, { merge: true });


    // ==========================================
    // 4. LIGAS MATA-MATA (Knockout Processing)
    // ==========================================
    const knockoutLeaguesSnap = await db.collection('fantasy_leagues')
      .where('type', '==', 'knockout')
      .where('status', '==', 'active')
      .get();

    for (let leagueDoc of knockoutLeaguesSnap.docs) {
      const leagueId = leagueDoc.id;

      const kMatchesSnap = await db.collection('fantasy_leagues').doc(leagueId)
        .collection('matches')
        .where('round', '==', round)
        .get();

      if (kMatchesSnap.empty) continue;

      let totalMatchesInRound = kMatchesSnap.size;

      for (let kMatchDoc of kMatchesSnap.docs) {
        const kMatch = kMatchDoc.data();
        const scoreA = teamRoundScores[kMatch.teamAId] || 0;
        const scoreB = teamRoundScores[kMatch.teamBId] || 0;

        let winnerId = null;
        let loserId = null;

        if (scoreA > scoreB) {
          winnerId = kMatch.teamAId; loserId = kMatch.teamBId;
        } else if (scoreB > scoreA) {
          winnerId = kMatch.teamBId; loserId = kMatch.teamAId;
        } else {
          // Desempate por patrimônio
          const patA = teamPatrimony[kMatch.teamAId] || 0;
          const patB = teamPatrimony[kMatch.teamBId] || 0;
          if (patA !== patB) {
            winnerId = patA > patB ? kMatch.teamAId : kMatch.teamBId;
            loserId = patA > patB ? kMatch.teamBId : kMatch.teamAId;
          } else {
            // Sorteio em caso de empate total
            winnerId = Math.random() > 0.5 ? kMatch.teamAId : kMatch.teamBId;
            loserId = winnerId === kMatch.teamAId ? kMatch.teamBId : kMatch.teamAId;
          }
        }

        batchHandler.update(kMatchDoc.ref, {
          scoreA: scoreA,
          scoreB: scoreB,
          winnerId: winnerId
        });

        // Promove o vencedor
        if (totalMatchesInRound > 1) {
          const nextMatchIndex = Math.floor(kMatch.matchIndex / 2);
          const isTeamAForNext = kMatch.matchIndex % 2 === 0;

          const nextPhase = totalMatchesInRound === 2 ? 'Final' :
            totalMatchesInRound === 4 ? 'Semi' :
              totalMatchesInRound === 8 ? 'Quartas' : 'Oitavas';

          const nextMatchId = `match_${round + 1}_${nextMatchIndex}`;
          const nextMatchRef = db.collection('fantasy_leagues').doc(leagueId).collection('matches').doc(nextMatchId);

          batchHandler.set(nextMatchRef, {
            phase: nextPhase,
            round: round + 1,
            matchIndex: nextMatchIndex,
            [`team${isTeamAForNext ? 'A' : 'B'}Id`]: winnerId
          }, { merge: true });
        } else {
          // É a Final, temos um Campeão!
          batchHandler.update(leagueDoc.ref, {
            status: 'finished',
            champion_id: winnerId
          });
        }
      }
    }

    // ==========================================
    // 5. ATUALIZAR LIVE SCOUT COM PONTUAÇÃO FINAL
    // ==========================================
    const liveDocRef = db.collection('championships').doc(seasonId).collection('fantasy_live').doc(`round_${round}`);
    const liveDocSnap = await liveDocRef.get();
    let liveScoresObj = liveDocSnap.exists ? (liveDocSnap.data().scores || {}) : {};

    Object.keys(scoresMap).forEach(pid => {
      if (!liveScoresObj[pid]) liveScoresObj[pid] = {};
      liveScoresObj[pid].totalScore = scoresMap[pid]; // Pontuação FINAL (já consolidada com técnicos, MOTM, etc)
    });

    batchHandler.set(liveDocRef, {
      scores: liveScoresObj,
      is_final: true,
      updated_at: admin.firestore.Timestamp.now()
    }, { merge: true });

    await batchHandler.commit();

    return {
      success: true,
      message: `Rodada ${round} finalizada com sucesso.`
    };

  } catch (error) {
    console.error("Erro closeRound:", error);
    throw new HttpsError('internal', error.message);
  }
});

// ==================================================================
// 📡 MÓDULO FANTASY (Parciais Ao Vivo) - ULTRA OTIMIZADO
// ==================================================================

exports.updateLiveScouts = onDocumentWritten({
  document: "championships/{seasonId}/matches/{matchId}",
}, async (event) => {
  const seasonId = event.params.seasonId;
  const matchData = event.data.after.data();
  const previousData = event.data.before?.data();

  if (!matchData || !matchData.round) return;
  const round = matchData.round;

  if (previousData) {
    const oldStats = JSON.stringify(previousData.stats_applied?.player_stats || {});
    const newStats = JSON.stringify(matchData.stats_applied?.player_stats || {});
    const oldHome = previousData.score_home;
    const oldAway = previousData.score_away;
    const newHome = matchData.score_home;
    const newAway = matchData.score_away;
    const oldMotm = (previousData.stats_applied?.man_of_the_match || previousData.man_of_the_match || '').toString();
    const newMotm = (matchData.stats_applied?.man_of_the_match || matchData.man_of_the_match || '').toString();
    const oldStatus = previousData.status || '';
    const newStatus = matchData.status || '';
    const oldLineup = JSON.stringify(previousData.lineup_played || []);
    const newLineup = JSON.stringify(matchData.lineup_played || []);

    if (oldStats === newStats &&
        oldHome === newHome &&
        oldAway === newAway &&
        oldMotm === newMotm &&
        oldStatus === newStatus &&
        oldLineup === newLineup) {
      return;
    }
  }

  try {
    const liveDocRef = db.collection('championships').doc(seasonId).collection('fantasy_live').doc(`round_${round}`);
    const liveDocSnap = await liveDocRef.get();

    let scoresMap = liveDocSnap.exists ? (liveDocSnap.data().scores || {}) : {};

    const configSnap = await db.collection('fantasy_config').doc('rules').get();
    const rawConfig = configSnap.exists ? configSnap.data() : {};
    const config = { ...DEFAULT_CONFIG, ...rawConfig };
    if (rawConfig.ptsMotm !== undefined && rawConfig.ptsManOfTheMatch === undefined) {
      config.ptsManOfTheMatch = Number(rawConfig.ptsMotm);
    }
    if (rawConfig.ptsMissedFreeKick !== undefined && rawConfig.ptsDirectFreeKickMissed === undefined) {
      config.ptsDirectFreeKickMissed = Number(rawConfig.ptsMissedFreeKick);
    }
    const ptsMotm = config.ptsManOfTheMatch !== undefined ? Number(config.ptsManOfTheMatch) : (config.ptsMotm !== undefined ? Number(config.ptsMotm) : 5.0);

    const allPlayersSnap = await db.collection('fantasy_market_players').get();
    const playersInfo = {};
    const teamCoaches = {};
    allPlayersSnap.forEach(doc => {
      const p = doc.data();
      playersInfo[doc.id] = p;
      if (p.team_id && p.position === 'Técnico') {
        teamCoaches[p.team_id] = doc.id;
      }
    });

    const matchesSnap = await db.collection('championships').doc(seasonId)
      .collection('matches').where('round', '==', round).get();

    // Reset scores to rebuild fresh from matches
    Object.keys(scoresMap).forEach(pid => {
      scoresMap[pid] = { totalScore: 0, goals: 0, assists: 0, yellows: 0, reds: 0, goals_conceded: 0, penalties_saved: 0, penalties_missed: 0, shots_on_post: 0, clean_sheets: 0, own_goals: 0, direct_free_kicks_missed: 0, motm: 0, difficult_saves: 0 };
    });

    const teamCleanSheets = {};
    const playersPlayedSet = new Set();

    matchesSnap.forEach(doc => {
      const data = doc.data();

      if (data.status === 'in_progress' || data.status === 'finished') {
        const scoreHome = data.score_home || 0;
        const scoreAway = data.score_away || 0;
        if (scoreAway === 0) teamCleanSheets[data.team_home_id] = true;
        if (scoreHome === 0) teamCleanSheets[data.team_away_id] = true;

        const lineups = data.lineup_played || [];
        lineups.forEach(pid => {
          const strPid = pid.toString();
          playersPlayedSet.add(strPid);
          if (!scoresMap[strPid]) {
            scoresMap[strPid] = { totalScore: 0, goals: 0, assists: 0, yellows: 0, reds: 0, goals_conceded: 0, penalties_saved: 0, penalties_missed: 0, shots_on_post: 0, clean_sheets: 0, own_goals: 0, direct_free_kicks_missed: 0, motm: 0, difficult_saves: 0 };
          }
        });
      }

      const motmPid = data.stats_applied?.man_of_the_match || data.man_of_the_match;
      if (motmPid) {
        const strMotm = motmPid.toString();
        if (!scoresMap[strMotm]) {
          scoresMap[strMotm] = { totalScore: 0, goals: 0, assists: 0, yellows: 0, reds: 0, goals_conceded: 0, penalties_saved: 0, penalties_missed: 0, shots_on_post: 0, clean_sheets: 0, own_goals: 0, direct_free_kicks_missed: 0, motm: 0, difficult_saves: 0 };
        }
        scoresMap[strMotm].motm += 1;
      }

      if (!data.stats_applied || !data.stats_applied.player_stats) return;

      const stats = data.stats_applied.player_stats;
      const ptsRules = {
        goals: config.ptsGoal,
        assists: config.ptsAssist,
        yellows: config.ptsYellowCard,
        reds: config.ptsRedCard,
        penalties_saved: config.ptsPenaltySaved,
        penalties_missed: config.ptsPenaltyMissed,
        shots_on_post: config.ptsShotOnPost,
        own_goals: config.ptsOwnGoal,
        direct_free_kicks_missed: config.ptsDirectFreeKickMissed,
        difficult_saves: config.ptsDifficultSave
      };

      ['goals', 'assists', 'yellows', 'reds', 'goals_conceded', 'penalties_saved', 'penalties_missed', 'shots_on_post', 'own_goals', 'direct_free_kicks_missed', 'difficult_saves'].forEach(cat => {
        if (stats[cat]) {
          Object.entries(stats[cat]).forEach(([pid, val]) => {
            if (!scoresMap[pid]) {
              scoresMap[pid] = { totalScore: 0, goals: 0, assists: 0, yellows: 0, reds: 0, goals_conceded: 0, penalties_saved: 0, penalties_missed: 0, shots_on_post: 0, clean_sheets: 0, own_goals: 0, direct_free_kicks_missed: 0, motm: 0, difficult_saves: 0 };
            }

            const count = Number(val) || 0;
            scoresMap[pid][cat] += count;
          });
        }
      });
    });

    const teamScores = {};
    Object.keys(scoresMap).forEach(pid => {
      let total = 0;
      total += (scoresMap[pid].goals || 0) * config.ptsGoal;
      total += (scoresMap[pid].assists || 0) * config.ptsAssist;
      total += (scoresMap[pid].yellows || 0) * config.ptsYellowCard;
      total += (scoresMap[pid].reds || 0) * config.ptsRedCard;
      total += (scoresMap[pid].penalties_saved || 0) * config.ptsPenaltySaved;
      total += (scoresMap[pid].penalties_missed || 0) * config.ptsPenaltyMissed;
      total += (scoresMap[pid].shots_on_post || 0) * config.ptsShotOnPost;
      total += (scoresMap[pid].own_goals || 0) * config.ptsOwnGoal;
      total += (scoresMap[pid].direct_free_kicks_missed || 0) * config.ptsDirectFreeKickMissed;
      total += (scoresMap[pid].difficult_saves || 0) * config.ptsDifficultSave;
      total += (scoresMap[pid].motm || 0) * ptsMotm;

      const p = playersInfo[pid];
      const hasPlayed = playersPlayedSet.has(pid.toString());

      if (p && p.team_id) {
        // Regra Oficial: SG só conta para atletas da posição Goleiro e Fixo confirmados na súmula (lineup_played)
        if (hasPlayed && teamCleanSheets[p.team_id] && (p.position === 'Goleiro' || p.position === 'Fixo')) {
          scoresMap[pid].clean_sheets = 1;
          total += config.ptsCleanSheet;
        } else {
          scoresMap[pid].clean_sheets = 0;
        }

        // Regra Oficial: Média do técnico considera apenas atletas confirmados que jogaram em súmula (lineup_played)
        if (hasPlayed && p.position !== 'Técnico') {
          if (!teamScores[p.team_id]) teamScores[p.team_id] = [];
          teamScores[p.team_id].push(total);
        }
      }

      scoresMap[pid].totalScore = total;
    });

    Object.entries(teamCoaches).forEach(([tId, coachPid]) => {
      const scores = teamScores[tId] || [];
      if (!scoresMap[coachPid]) {
        scoresMap[coachPid] = { totalScore: 0, goals: 0, assists: 0, yellows: 0, reds: 0, goals_conceded: 0, penalties_saved: 0, penalties_missed: 0, shots_on_post: 0, clean_sheets: 0, own_goals: 0, direct_free_kicks_missed: 0, motm: 0, difficult_saves: 0 };
      }
      if (scores.length > 0) {
        const total = scores.reduce((a, b) => a + b, 0);
        const avg = total / scores.length;
        scoresMap[coachPid].totalScore = Number(avg.toFixed(2));
      } else {
        scoresMap[coachPid].totalScore = 0;
      }
    });

    await liveDocRef.set({
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      scores: scoresMap
    }, { merge: true });

  } catch (error) {
    console.error("🔥 Erro ao atualizar Live Scouts:", error);
  }
});

// ==================================================================
// ⏰ PILOTO AUTOMÁTICO (Fechar Mercado Sozinho - CRON)
// ==================================================================

exports.autoCloseMarket = onSchedule({
  schedule: "every 2 minutes",
  timeZone: "America/Sao_Paulo",
}, async (event) => {
  try {
    const statusRef = db.collection('fantasy_config').doc('status');
    const statusSnap = await statusRef.get();

    if (!statusSnap.exists) return;

    const statusData = statusSnap.data();
    if (statusData.is_open === false) {
      return;
    }

    const currentRound = statusData.current_round || 1;

    const seasonsSnap = await db.collection('championships')
      .where('is_active', '==', true)
      .limit(1)
      .get();

    if (seasonsSnap.empty) return;
    const seasonId = seasonsSnap.docs[0].id;

    const nextMatchSnap = await db.collection('championships').doc(seasonId)
      .collection('matches')
      .where('round', '==', currentRound)
      .where('status', '==', 'pending')
      .orderBy('datetime', 'asc')
      .limit(1)
      .get();

    if (nextMatchSnap.empty) return;

    const nextMatch = nextMatchSnap.docs[0].data();
    if (!nextMatch.datetime) return;

    const matchTimeMs = nextMatch.datetime.toDate().getTime();
    const nowMs = Date.now();

    // Fechamento exato: 20 minutos antes do início do primeiro jogo da rodada
    const closingTimeMs = matchTimeMs - (20 * 60 * 1000);
    const closingTimestamp = admin.firestore.Timestamp.fromMillis(closingTimeMs);

    if (nowMs >= closingTimeMs) {
      await statusRef.update({
        is_open: false,
        closing_time: closingTimestamp,
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`🛑 PILOTO AUTOMÁTICO: Mercado FECHADO para a rodada ${currentRound}.`);
    } else {
      // Sincroniza closing_time com antecedência para Security Rules e app
      const currentClosingMs = statusData.closing_time ? statusData.closing_time.toMillis() : null;
      if (currentClosingMs !== closingTimeMs) {
        await statusRef.update({
          closing_time: closingTimestamp
        });
        console.log(`⏰ PILOTO AUTOMÁTICO: Prazo do mercado atualizado para R${currentRound}: ${new Date(closingTimeMs).toISOString()}`);
      }
    }

  } catch (error) {
    console.error("🔥 Erro no autoCloseMarket:", error);
  }
});

// ==================================================================
// 📊 ESTATÍSTICAS DA RODADA (FinOps - Mercado Fechado / Mais Escalados)
// ==================================================================

async function generateMarketStatsInternal(targetRound = null) {
  let round = targetRound;
  if (!round) {
    const statusSnap = await db.collection('fantasy_config').doc('status').get();
    round = statusSnap.data()?.current_round || 1;
  }

  const teamsSnap = await db.collection('fantasy_teams').get();

  const playerCounts = {};
  const captainCounts = {};
  let totalTeamsWithLineup = 0;

  teamsSnap.forEach(doc => {
    const team = doc.data();
    const lineup = team.lineup_player_ids || [];
    const captainId = team.captain_id;

    if (lineup.length > 0) totalTeamsWithLineup++;

    lineup.forEach(pid => {
      if (pid) {
        playerCounts[pid] = (playerCounts[pid] || 0) + 1;
      }
    });

    if (captainId) {
      captainCounts[captainId] = (captainCounts[captainId] || 0) + 1;
    }
  });

  const playersInfo = {};
  const marketSnap = await db.collection('fantasy_market_players').get();
  marketSnap.forEach(doc => {
    playersInfo[doc.id] = doc.data();
  });

  const mostSelected = Object.keys(playerCounts).map(pid => {
    const pInfo = playersInfo[pid] || {};
    return {
      player_id: pid,
      name: pInfo.name || 'Desconhecido',
      position: pInfo.position || 'Desconhecido',
      team_name: pInfo.team_name || '',
      team_shield_url: pInfo.team_shield_url || '',
      photo_url: pInfo.photo_url || '',
      current_price: pInfo.current_price || 0,
      selections: playerCounts[pid] || 0,
      count: playerCounts[pid] || 0,
      captain_selections: captainCounts[pid] || 0
    };
  });

  mostSelected.sort((a, b) => b.selections - a.selections);

  let mostSelectedCaptain = null;
  let mostSelectedCaptainCount = 0;

  Object.entries(captainCounts).forEach(([pid, count]) => {
    if (count > mostSelectedCaptainCount) {
      mostSelectedCaptain = pid;
      mostSelectedCaptainCount = count;
    }
  });

  const top30 = mostSelected.slice(0, 30);

  const payload = {
    round: round,
    most_selected: top30,
    most_picked: top30,
    most_selected_player_id: top30[0]?.player_id || null,
    most_selected_player_count: top30[0]?.selections || 0,
    most_selected_captain_id: mostSelectedCaptain,
    most_selected_captain_count: mostSelectedCaptainCount,
    total_teams: totalTeamsWithLineup,
    updated_at: admin.firestore.FieldValue.serverTimestamp()
  };

  // 1. Atualiza documento global consumido diretamente pela Central de Scouts (streamGlobalScouts)
  await db.collection('fantasy_stats').doc('global_round_stats').set(payload, { merge: true });

  // 2. Grava histórico na coleção da rodada
  await db.collection('fantasy_stats').doc(`round_${round}`).set(payload, { merge: true });

  // 3. Grava documento para compatibilidade com Home
  await db.collection('fantasy_config').doc('market_stats').set({
    round: round,
    most_selected_player_id: payload.most_selected_player_id,
    most_selected_player_count: payload.most_selected_player_count,
    most_selected_captain_id: payload.most_selected_captain_id,
    most_selected_captain_count: payload.most_selected_captain_count,
    total_teams: totalTeamsWithLineup,
    updated_at: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`✅ generateMarketStatsInternal: Geradas estatísticas para R${round} (${top30.length} atletas, ${totalTeamsWithLineup} times).`);
  return payload;
}

exports.processMarketClosed = onDocumentWritten({
  document: "fantasy_config/status",
}, async (event) => {
  const before = event.data.before?.data();
  const after = event.data.after?.data();

  if (!before || !after) return;
  if (before.is_open === true && after.is_open === false) {
    console.log("🔒 Mercado fechou! Processando estatísticas de escalação...");
    const currentRound = after.current_round || 1;

    try {
      await generateMarketStatsInternal(currentRound);
      console.log(`✅ Estatísticas da rodada ${currentRound} geradas com sucesso!`);
    } catch (error) {
      console.error("🔥 Erro ao processar estatísticas do mercado:", error);
    }
  }
});

exports.generateGlobalMarketStats = onCall({ cors: true, enforceAppCheck: false }, async (request) => {
  try {
    const payload = await generateMarketStatsInternal();
    return {
      success: true,
      message: "Estatísticas geradas com sucesso!",
      count: payload.most_selected.length,
      round: payload.round
    };
  } catch (error) {
    console.error("🔥 Erro ao gerar estatísticas sob demanda:", error);
    throw new HttpsError('internal', `Falha ao gerar estatísticas: ${error.message}`);
  }
});

// ==================================================================
// 🏆 MÓDULO BOLÃO DA COPA (Cálculo de Pontos e Ranking)
// ==================================================================

exports.calculateBolaoMatchPoints = onCall({ cors: true, timeoutSeconds: 540 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Acesso negado. O utilizador precisa de estar logado.');

  const adminDoc = await db.collection('admin_users').doc(request.auth.uid).get();
  if (!adminDoc.exists) throw new HttpsError('permission-denied', 'Apenas administradores podem calcular os resultados do bolão.');

  const { matchId, realHomeScore, realAwayScore } = request.data;
  if (!matchId || realHomeScore === undefined || realAwayScore === undefined) {
    throw new HttpsError('invalid-argument', 'Faltam os dados do jogo (matchId, realHomeScore, realAwayScore).');
  }

  try {
    const realHome = parseInt(realHomeScore);
    const realAway = parseInt(realAwayScore);
    const realDiff = realHome - realAway;

    let realOutcome = 'draw';
    if (realHome > realAway) realOutcome = 'home_win';
    if (realHome < realAway) realOutcome = 'away_win';

    const usersSnap = await db.collection('bolao_users').get();
    const batchHandler = new BatchHandler(db);

    for (const userDoc of usersSnap.docs) {
      const userId = userDoc.id;
      const predDoc = await db.collection('bolao_users').doc(userId).collection('predictions').doc(matchId).get();

      if (predDoc.exists) {
        const predData = predDoc.data();
        const predHome = parseInt(predData.score_home);
        const predAway = parseInt(predData.score_away);
        const predDiff = predHome - predAway;

        let predOutcome = 'draw';
        if (predHome > predAway) predOutcome = 'home_win';
        if (predHome < predAway) predOutcome = 'away_win';

        let pointsEarned = 0;
        let isExact = 0;
        let isGoalDiff = 0;
        let isWinner = 0;

        if (predHome === realHome && predAway === realAway) {
          pointsEarned = 5; isExact = 1;
        }
        else if (predOutcome === realOutcome) {
          if (predDiff === realDiff) {
            pointsEarned = 3; isGoalDiff = 1;
          } else {
            pointsEarned = 2; isWinner = 1;
          }
        }

        const oldPoints = predData.points_earned || 0;
        let oldExact = 0; let oldGoalDiff = 0; let oldWinner = 0;

        if (oldPoints === 5) oldExact = 1;
        else if (oldPoints === 3) oldGoalDiff = 1;
        else if (oldPoints === 2) oldWinner = 1;

        const diffPoints = pointsEarned - oldPoints;
        const diffExact = isExact - oldExact;
        const diffGoalDiff = isGoalDiff - oldGoalDiff;
        const diffWinner = isWinner - oldWinner;

        if (diffPoints !== 0 || diffExact !== 0 || diffGoalDiff !== 0 || diffWinner !== 0) {
          batchHandler.update(userDoc.ref, {
            total_points: admin.firestore.FieldValue.increment(diffPoints),
            exact_hits: admin.firestore.FieldValue.increment(diffExact),
            goal_difference_hits: admin.firestore.FieldValue.increment(diffGoalDiff),
            winner_hits: admin.firestore.FieldValue.increment(diffWinner),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
          });

          batchHandler.update(predDoc.ref, { points_earned: pointsEarned });
        }
      }
    }

    const matchRef = db.collection('bolao_matches').doc(matchId);
    batchHandler.update(matchRef, {
      real_score_home: realHome,
      real_score_away: realAway,
      status: 'finished',
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    });

    await batchHandler.commit();

    try {
      await admin.database().ref(`live_ranking/${matchId}`).remove();

      const liveMatchesSnap = await db.collection('bolao_matches')
        .where('status', '==', 'in_progress')
        .get();

      if (!liveMatchesSnap.empty) {
        const touchBatch = db.batch();
        liveMatchesSnap.forEach(liveDoc => {
          if (liveDoc.id !== matchId) {
            touchBatch.update(liveDoc.ref, { updated_at: admin.firestore.FieldValue.serverTimestamp() });
          }
        });
        await touchBatch.commit();
      }
    } catch (e) {
      console.error("Erro ao limpar RTDB:", e);
    }

    return { success: true, message: `Jogo ${matchId} processado e corrigido com sucesso!` };

  } catch (error) {
    throw new HttpsError('internal', error.message);
  }
});

// ==================================================================
// 🔒 GRAVAÇÃO SEGURA DE PALPITES (Com validação temporal do Servidor)
// ==================================================================

exports.submitBolaoPrediction = onCall({ cors: true }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Precisa de fazer login.');

  const { matchId, scoreHome, scoreAway } = request.data;
  const userId = request.auth.uid;

  if (!matchId || scoreHome === undefined || scoreAway === undefined) {
    throw new HttpsError('invalid-argument', 'Dados incompletos.');
  }

  try {
    const configDoc = await db.collection('bolao_config').doc('settings').get();
    const settings = configDoc.data();

    if (settings && settings.is_predictions_open === false) {
      throw new HttpsError('permission-denied', 'Mercado Geral encerrado pelo Administrador!');
    }

    const matchDoc = await db.collection('bolao_matches').doc(matchId).get();
    if (!matchDoc.exists) throw new HttpsError('not-found', 'Jogo não encontrado.');

    const matchData = matchDoc.data();
    if (matchData.status !== 'pending') throw new HttpsError('permission-denied', 'Este jogo já terminou ou está a decorrer.');

    const matchDate = matchData.date.toDate();
    const serverNow = new Date();
    const deadlineTime = new Date(matchDate.getTime() - (30 * 60000));

    if (serverNow > deadlineTime) {
      throw new HttpsError('permission-denied', 'Mercado encerrado! O prazo de 30 min antes do jogo expirou.');
    }

    const predRef = db.collection('bolao_users').doc(userId).collection('predictions').doc(matchId);

    await predRef.set({
      score_home: parseInt(scoreHome),
      score_away: parseInt(scoreAway),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    return { success: true, message: 'Palpite gravado em segurança.' };

  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', 'Erro interno no servidor.');
  }
});

// 🚨 PALPITES DO MINI BOLÃO VIP (ATUALIZADO COM MINUTO DO 1º GOL) 🚨
exports.submitMiniBolaoPrediction = onCall({ cors: true }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Login obrigatório.');

  const { miniBolaoId, scoreHome, scoreAway, goalScorers, firstGoalTeam, firstGoalMinute, halfTimeDraw, highestScoringHalf } = request.data;
  const userId = request.auth.uid;

  if (!miniBolaoId || scoreHome === undefined || scoreAway === undefined || !firstGoalTeam || firstGoalMinute === undefined || halfTimeDraw === undefined || !highestScoringHalf) {
    throw new HttpsError('invalid-argument', 'Dados incompletos para o palpite VIP.');
  }

  try {
    const mbSnap = await db.collection('bolao_mini_leagues').doc(miniBolaoId).get();
    if (!mbSnap.exists) throw new HttpsError('not-found', 'Mini Bolão não encontrado.');

    const mbData = mbSnap.data();

    if (mbData.status === 'finished') {
      throw new HttpsError('permission-denied', 'Esta sala VIP já foi encerrada.');
    }

    if (mbData.deadline) {
      const deadlineTime = mbData.deadline.toDate();
      const serverNow = new Date();
      if (serverNow > deadlineTime) {
        throw new HttpsError('permission-denied', 'O prazo para salvar palpites nesta sala VIP já encerrou!');
      }
    }

    const participantRef = db.collection('bolao_mini_leagues').doc(miniBolaoId).collection('participants').doc(userId);

    const pSnap = await participantRef.get();
    if (!pSnap.exists) {
      throw new HttpsError('permission-denied', 'Você não está participando desta sala VIP.');
    }

    await participantRef.set({
      pred_score_home: parseInt(scoreHome),
      pred_score_away: parseInt(scoreAway),
      pred_goal_scorers: goalScorers || [],
      pred_first_goal_team: firstGoalTeam,
      pred_first_goal_minute: parseInt(firstGoalMinute), // 🚨 NOVO CAMPO
      pred_half_time_draw: halfTimeDraw,
      pred_highest_scoring_half: highestScoringHalf,
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    return { success: true, message: 'Palpites VIP salvos com segurança.' };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', 'Erro interno no servidor ao salvar palpite VIP.');
  }
});

// ==================================================================
// 🏆 GRAVAÇÃO SEGURA DOS BÔNUS EXTRAS (Com Prazo de Validade)
// ==================================================================
exports.submitBolaoBonus = onCall({ cors: true }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Login obrigatório.');

  const { field, teamName } = request.data;
  const userId = request.auth.uid;

  const deadline = new Date('2026-06-18T02:59:59Z');
  const serverNow = new Date();

  if (serverNow > deadline) {
    throw new HttpsError('permission-denied', 'O prazo para salvar Bônus encerrou no dia 17/06/2026 às 23h59!');
  }

  try {
    const userRef = db.collection('bolao_users').doc(userId);
    await userRef.set({
      [field]: teamName,
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    return { success: true };
  } catch (error) {
    throw new HttpsError('internal', 'Erro ao salvar o bônus.');
  }
});

// ==================================================================
// 🏆 CÁLCULO FINAL DOS BÔNUS (Disparado pelo Admin no fim da Copa)
// ==================================================================
exports.calculateBonusPoints = onCall({ cors: true, timeoutSeconds: 540 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Login obrigatório.');

  const adminDoc = await db.collection('admin_users').doc(request.auth.uid).get();
  if (!adminDoc.exists) throw new HttpsError('permission-denied', 'Apenas admins.');

  const { officialChampion, officialRunnerUp, officialBestOffense, officialWorstDefense, officialDisappointment } = request.data;

  try {
    const usersSnap = await db.collection('bolao_users').get();
    const batchHandler = new BatchHandler(db);

    // Garantir que as variáveis sejam tratadas como arrays (mesmo que venham vazias ou como string legada)
    const bestOffenseArray = Array.isArray(officialBestOffense) ? officialBestOffense : (officialBestOffense ? [officialBestOffense] : []);
    const worstDefenseArray = Array.isArray(officialWorstDefense) ? officialWorstDefense : (officialWorstDefense ? [officialWorstDefense] : []);

    for (const userDoc of usersSnap.docs) {
      const userData = userDoc.data();
      let championPts = (userData.bonus_champion === officialChampion) ? 20 : 0;
      let runnerUpPts = (userData.bonus_runner_up === officialRunnerUp) ? 10 : 0;

      // 🚨 VALIDAÇÃO EM LISTA (Array) PARA EMPATES
      let offensePts = (userData.bonus_best_offense && bestOffenseArray.includes(userData.bonus_best_offense)) ? 10 : 0;
      let defensePts = (userData.bonus_worst_defense && worstDefenseArray.includes(userData.bonus_worst_defense)) ? 10 : 0;

      let disappointmentPts = (userData.bonus_disappointment === officialDisappointment) ? 10 : 0;

      let extraPoints = championPts + runnerUpPts + offensePts + defensePts + disappointmentPts;

      // Recupera TODO o bônus que já foi somado no total_points (pode estar duplicado pelo bug anterior)
      let oldBonusPoints = userData.bonus_points || 0;
      let pointsDiff = extraPoints - oldBonusPoints;

      batchHandler.update(userDoc.ref, {
        total_points: admin.firestore.FieldValue.increment(pointsDiff),
        bonus_points: extraPoints,
        bonus_champion_points: championPts,
        bonus_runner_up_points: runnerUpPts,
        bonus_best_offense_points: offensePts,
        bonus_worst_defense_points: defensePts,
        bonus_disappointment_points: disappointmentPts,
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      });
    }

    await batchHandler.commit();
    return { success: true, message: 'Bônus processados e Ranking Final atualizado!' };

  } catch (error) {
    throw new HttpsError('internal', error.message);
  }
});

// ==================================================================
// 🔴 MOTOR DO RANKING AO VIVO MULTI-PARTIDA (RTDB) - OTIMIZADO C/ DESEMPATES
// ==================================================================

exports.updateLiveBolaoRanking = onDocumentWritten({
  document: "bolao_matches/{matchId}",
}, async (event) => {
  const triggeringMatchData = event.data.after.data();

  if (!triggeringMatchData || triggeringMatchData.status !== 'in_progress') {
    return;
  }

  try {
    const liveMatchesSnap = await db.collection('bolao_matches')
      .where('status', '==', 'in_progress')
      .get();

    if (liveMatchesSnap.empty) return;

    const liveMatchesData = {};
    const liveMatchIds = [];
    liveMatchesSnap.forEach(doc => {
      liveMatchesData[doc.id] = doc.data();
      liveMatchIds.push(doc.id);
    });

    const usersSnap = await db.collection('bolao_users').get();

    const predMap = {};
    const predictionPromises = [];

    usersSnap.forEach(userDoc => {
      const uid = userDoc.id;
      predMap[uid] = {};

      liveMatchIds.forEach(mId => {
        const p = db.collection('bolao_users').doc(uid).collection('predictions').doc(mId).get()
          .then(snap => {
            if (snap.exists) {
              predMap[uid][mId] = {
                home: parseInt(snap.data().score_home),
                away: parseInt(snap.data().score_away)
              };
            }
          });
        predictionPromises.push(p);
      });
    });

    await Promise.all(predictionPromises);

    const usersLiveState = {};

    usersSnap.forEach(userDoc => {
      const uid = userDoc.id;
      const userData = userDoc.data();

      const basePoints = userData.total_points || 0;
      const baseExactHits = userData.exact_hits || 0;
      const baseGoalDiffHits = userData.goal_difference_hits || 0;
      const baseWinnerHits = userData.winner_hits || 0;
      const bonusPoints = userData.bonus_points || 0;

      const userMatchesPoints = {};
      let totalLivePoints = 0;

      let liveExactHits = 0;
      let liveGoalDiffHits = 0;
      let liveWinnerHits = 0;

      liveMatchIds.forEach(mId => {
        const mData = liveMatchesData[mId];
        const liveHome = parseInt(mData.real_score_home) || 0;
        const liveAway = parseInt(mData.real_score_away) || 0;
        const liveDiff = liveHome - liveAway;
        let liveOutcome = 'draw';
        if (liveHome > liveAway) liveOutcome = 'home_win';
        if (liveHome < liveAway) liveOutcome = 'away_win';

        let points = 0;
        if (predMap[uid] && predMap[uid][mId]) {
          const pHome = predMap[uid][mId].home;
          const pAway = predMap[uid][mId].away;
          const pDiff = pHome - pAway;
          let pOutcome = 'draw';
          if (pHome > pAway) pOutcome = 'home_win';
          if (pHome < pAway) pOutcome = 'away_win';

          if (pHome === liveHome && pAway === liveAway) {
            points = 5;
            liveExactHits++;
          } else if (pOutcome === liveOutcome) {
            if (pDiff === liveDiff) {
              points = 3;
              liveGoalDiffHits++;
            } else {
              points = 2;
              liveWinnerHits++;
            }
          }
        }

        userMatchesPoints[mId] = points;
        totalLivePoints += points;
      });

      usersLiveState[uid] = {
        name: userData.name || 'Treinador',
        photoUrl: userData.photo_url || '',
        basePoints: basePoints,
        globalTotalPoints: basePoints + totalLivePoints,
        globalExactHits: baseExactHits + liveExactHits,
        globalGoalDiffHits: baseGoalDiffHits + liveGoalDiffHits,
        globalWinnerHits: baseWinnerHits + liveWinnerHits,
        bonusPoints: bonusPoints,
        userMatchesPoints: userMatchesPoints,
        predictions: predMap[uid] || {}
      };
    });

    const rtdbUpdates = {};

    liveMatchIds.forEach(mId => {
      const mData = liveMatchesData[mId];
      let rankingList = [];

      Object.keys(usersLiveState).forEach(uid => {
        const state = usersLiveState[uid];
        const pHome = state.predictions[mId]?.home;
        const pAway = state.predictions[mId]?.away;
        const predText = (pHome !== undefined && pAway !== undefined) ? `${pHome}x${pAway}` : "Sem palpite";

        rankingList.push({
          userId: uid,
          name: state.name,
          photoUrl: state.photoUrl,
          basePoints: state.basePoints,
          matchPoints: state.userMatchesPoints[mId],
          totalPoints: state.globalTotalPoints,
          exactHits: state.globalExactHits,
          goalDiffHits: state.globalGoalDiffHits,
          winnerHits: state.globalWinnerHits,
          bonusPoints: state.bonusPoints,
          prediction: predText
        });
      });

      rankingList.sort((a, b) =>
        (b.totalPoints - a.totalPoints) ||
        (b.exactHits - a.exactHits) ||
        (b.goalDiffHits - a.goalDiffHits) ||
        (b.winnerHits - a.winnerHits) ||
        (b.bonusPoints - a.bonusPoints) ||
        a.name.localeCompare(b.name)
      );

      rankingList.forEach((u, index) => u.rank = index + 1);

      rtdbUpdates[`live_ranking/${mId}`] = {
        matchId: mId,
        homeTeam: mData.home_team,
        awayTeam: mData.away_team,
        scoreHome: parseInt(mData.real_score_home) || 0,
        scoreAway: parseInt(mData.real_score_away) || 0,
        timestamp: admin.database.ServerValue.TIMESTAMP,
        ranking: rankingList
      };
    });

    await admin.database().ref().update(rtdbUpdates);

  } catch (error) {
    console.error("🔥 Erro Crítico no Motor Multi-Partida do Live Ranking:", error);
  }
});

// ==================================================================
// 🏆 ENCERRAMENTO E CÁLCULO DE MINI BOLÕES VIP (COM ATUALIZAÇÃO PARCIAL E DESEMPATE)
// ==================================================================
exports.calculateMiniBolaoPoints = onCall({ cors: true, timeoutSeconds: 540 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Acesso negado.');

  const adminDoc = await db.collection('admin_users').doc(request.auth.uid).get();
  if (!adminDoc.exists) throw new HttpsError('permission-denied', 'Apenas administradores podem calcular resultados.');

  const { miniBolaoId, realHomeScore, realAwayScore, realScorers, realFirstGoalTeam, realFirstGoalMinute, realHalfTimeDraw, realHighestScoringHalf, isPartial } = request.data;

  if (!miniBolaoId || realHomeScore === undefined || realAwayScore === undefined) {
    throw new HttpsError('invalid-argument', 'Faltam dados da partida real.');
  }

  try {
    const realHome = parseInt(realHomeScore);
    const realAway = parseInt(realAwayScore);
    const realDiff = realHome - realAway;

    let realOutcome = 'draw';
    if (realHome > realAway) realOutcome = 'home_win';
    if (realHome < realAway) realOutcome = 'away_win';

    const batchHandler = new BatchHandler(db);
    const mbRef = db.collection('bolao_mini_leagues').doc(miniBolaoId);
    const participantsSnap = await mbRef.collection('participants').get();

    participantsSnap.forEach(partDoc => {
      const pData = partDoc.data();
      let points = 0;

      // 1. Cálculo de Placar 
      if (pData.pred_score_home !== undefined && pData.pred_score_away !== undefined) {
        const pHome = parseInt(pData.pred_score_home);
        const pAway = parseInt(pData.pred_score_away);
        const pDiff = pHome - pAway;
        let pOutcome = 'draw';
        if (pHome > pAway) pOutcome = 'home_win';
        if (pHome < pAway) pOutcome = 'away_win';

        if (pHome === realHome && pAway === realAway) {
          points += 50;
        } else if (pOutcome === realOutcome) {
          if (pDiff === realDiff) points += 30;
          else points += 15;
        }
      }

      // 2. Cálculo de Artilheiros
      let scorersPoints = 0;
      if (pData.pred_goal_scorers && Array.isArray(pData.pred_goal_scorers)) {
        let realList = [...(realScorers || [])];
        let predList = [...pData.pred_goal_scorers];

        for (const pred of predList) {
          const idx = realList.indexOf(pred);
          if (idx !== -1) {
            scorersPoints += 2;
            realList.splice(idx, 1);
          }
        }
      }
      points += scorersPoints;

      // 3. Cálculo de Primeiro Gol
      let firstGoalPoints = 0;
      if (pData.pred_first_goal_team && pData.pred_first_goal_team === realFirstGoalTeam) {
        firstGoalPoints = 2;
        points += firstGoalPoints;
      }

      // 🚨 3.1. CÁLCULO DE DESEMPATE DO MINUTO (Aproximação) 🚨
      let minuteDiff = 999;
      if (pData.pred_first_goal_minute !== undefined) {
        minuteDiff = Math.abs(parseInt(pData.pred_first_goal_minute) - (parseInt(realFirstGoalMinute) || 0));
      }

      // 4. Cálculo de Perguntas Extras
      let extrasPoints = 0;
      if (pData.pred_half_time_draw !== undefined && pData.pred_half_time_draw === realHalfTimeDraw) {
        extrasPoints += 1;
      }
      if (pData.pred_highest_scoring_half && pData.pred_highest_scoring_half === realHighestScoringHalf) {
        extrasPoints += 1;
      }
      points += extrasPoints;

      // Atualiza o participante com o fator de desempate
      batchHandler.update(partDoc.ref, {
        points: points,
        breakdown_scorers: scorersPoints,
        breakdown_first_goal: firstGoalPoints,
        breakdown_extras: extrasPoints,
        first_goal_minute_diff: minuteDiff, // 🚨 GRAVADO NO PARTICIPANTE PARA O APP PODER ORDENAR
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      });
    });

    const mbUpdatePayload = {
      real_score_home: realHome,
      real_score_away: realAway,
      real_scorers: realScorers || [],
      real_first_goal_team: realFirstGoalTeam || '',
      real_first_goal_minute: parseInt(realFirstGoalMinute) || 0, // 🚨 GRAVA NO CABEÇALHO DA SALA
      real_half_time_draw: realHalfTimeDraw,
      real_highest_scoring_half: realHighestScoringHalf || '',
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    };

    if (!isPartial) {
      mbUpdatePayload.status = 'finished';
      mbUpdatePayload.is_active = false;
      mbUpdatePayload.finished_at = admin.firestore.FieldValue.serverTimestamp();
    }

    batchHandler.update(mbRef, mbUpdatePayload);

    await batchHandler.commit();
    return { success: true, message: isPartial ? 'Ranking parcial atualizado!' : 'Ranking do Mini Bolão calculado com sucesso!' };

  } catch (error) {
    throw new HttpsError('internal', error.message);
  }
});

// ==================================================================
// UTILS: Batch Handler
// ==================================================================
class BatchHandler {
  constructor(dbInstance) {
    this.db = dbInstance;
    this.batch = dbInstance.batch();
    this.count = 0;
  }

  update(ref, data) {
    this.batch.update(ref, data);
    this.checkCommit();
  }

  set(ref, data) {
    this.batch.set(ref, data);
    this.checkCommit();
  }

  async checkCommit() {
    this.count++;
    if (this.count >= 490) {
      await this.batch.commit();
      this.batch = this.db.batch();
      this.count = 0;
    }
  }

  async commit() {
    if (this.count > 0) {
      await this.batch.commit();
      this.count = 0;
    }
  }
}

// ==================================================================
// 📈 FINOPS: OTIMIZAÇÃO DE RECÁLCULO DE ESTATÍSTICAS DE TIMES
// ==================================================================

exports.updateTeamStatsOnMatchUpdate = onDocumentWritten({
  document: "championships/{seasonId}/matches/{matchId}",
}, async (event) => {
  const seasonId = event.params.seasonId;
  const before = event.data.before?.data();
  const after = event.data.after?.data();

  // Se não tem time definido, ignora
  if (!after?.team_home_id && !before?.team_home_id) return;

  const hId = after?.team_home_id || before?.team_home_id;
  const aId = after?.team_away_id || before?.team_away_id;

  const calculatePoints = (h, a) => {
    if (h > a) return { pHome: 3, pAway: 0, wH: 1, dH: 0, lH: 0, wA: 0, dA: 0, lA: 1 };
    if (h < a) return { pHome: 0, pAway: 3, wH: 0, dH: 0, lH: 1, wA: 1, dA: 0, lA: 0 };
    return { pHome: 1, pAway: 1, wH: 0, dH: 1, lH: 0, wA: 0, dA: 1, lA: 0 };
  };

  const getStatsContributed = (match) => {
    if (!match || match.status !== 'finished') {
      return { home: null, away: null };
    }
    const hScore = match.score_home || 0;
    const aScore = match.score_away || 0;
    const res = calculatePoints(hScore, aScore);
    const isPhase1 = match.phase === 'first';

    return {
      home: {
        match_points: isPhase1 ? res.pHome : 0,
        points: isPhase1 ? res.pHome : 0,
        games_played: isPhase1 ? 1 : 0,
        wins: isPhase1 ? res.wH : 0,
        draws: isPhase1 ? res.dH : 0,
        losses: isPhase1 ? res.lH : 0,
        goals_for: isPhase1 ? hScore : 0,
        goals_against: isPhase1 ? aScore : 0,
        goal_difference: isPhase1 ? (hScore - aScore) : 0,

        overall_match_points: res.pHome,
        overall_points: res.pHome,
        overall_games_played: 1,
        overall_wins: res.wH,
        overall_draws: res.dH,
        overall_losses: res.lH,
        overall_goals_for: hScore,
        overall_goals_against: aScore,
        overall_goal_difference: hScore - aScore,
      },
      away: {
        match_points: isPhase1 ? res.pAway : 0,
        points: isPhase1 ? res.pAway : 0,
        games_played: isPhase1 ? 1 : 0,
        wins: isPhase1 ? res.wA : 0,
        draws: isPhase1 ? res.dA : 0,
        losses: isPhase1 ? res.lA : 0,
        goals_for: isPhase1 ? aScore : 0,
        goals_against: isPhase1 ? hScore : 0,
        goal_difference: isPhase1 ? (aScore - hScore) : 0,

        overall_match_points: res.pAway,
        overall_points: res.pAway,
        overall_games_played: 1,
        overall_wins: res.wA,
        overall_draws: res.dA,
        overall_losses: res.lA,
        overall_goals_for: aScore,
        overall_goals_against: hScore,
        overall_goal_difference: aScore - hScore,
      }
    };
  };

  const oldStats = getStatsContributed(before);
  const newStats = getStatsContributed(after);

  // Calcular deltas
  const calcDelta = (oldS, newS) => {
    if (!oldS && !newS) return null;
    const result = {};
    let hasChanges = false;
    const keys = [
      'match_points', 'points', 'games_played', 'wins', 'draws', 'losses', 'goals_for', 'goals_against', 'goal_difference',
      'overall_match_points', 'overall_points', 'overall_games_played', 'overall_wins', 'overall_draws', 'overall_losses', 'overall_goals_for', 'overall_goals_against', 'overall_goal_difference'
    ];
    keys.forEach(k => {
      const oldVal = oldS ? (oldS[k] || 0) : 0;
      const newVal = newS ? (newS[k] || 0) : 0;
      const diff = newVal - oldVal;
      if (diff !== 0) {
        result[k] = admin.firestore.FieldValue.increment(diff);
        hasChanges = true;
      }
    });
    return hasChanges ? result : null;
  };

  const homeDelta = calcDelta(oldStats.home, newStats.home);
  const awayDelta = calcDelta(oldStats.away, newStats.away);

  if (!homeDelta && !awayDelta) return;

  const batch = db.batch();

  if (homeDelta && hId) {
    const tHomeRef = db.collection('championships').doc(seasonId).collection('teams_participation').doc(hId);
    batch.update(tHomeRef, homeDelta);
  }

  if (awayDelta && aId) {
    const tAwayRef = db.collection('championships').doc(seasonId).collection('teams_participation').doc(aId);
    batch.update(tAwayRef, awayDelta);
  }

  await batch.commit();
  console.log(`✅ FINOPS: Estatísticas do time atualizadas via Cloud Functions para o jogo ${event.params.matchId}`);
});

// ==================================================================
// 🔍 MÓDULO DE AUDITORIA E VALIDAÇÃO DE SCOUTS (ADMIN ONLY)
// ==================================================================
const { auditFantasyRound, syncAuditToLive } = require("./fantasy_audit");
exports.auditFantasyRound = auditFantasyRound;
exports.syncAuditToLive = syncAuditToLive;