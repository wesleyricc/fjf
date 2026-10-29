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

    if (matchesSnap.empty) {
      throw new HttpsError('failed-precondition', `Nenhuma partida encontrada para a rodada ${round}.`);
    }

    // Regra Oficial: Considerar apenas partidas com status = finished no fechamento da rodada
    const finishedMatches = matchesSnap.docs.filter(doc => doc.data().status === 'finished');

    if (finishedMatches.length === 0) {
      throw new HttpsError('failed-precondition', `A rodada ${round} não possui partidas encerradas (status = finished).`);
    }

    const hasAnyScouts = finishedMatches.some(doc => {
      const d = doc.data();
      return (d.lineup_played && Array.isArray(d.lineup_played) && d.lineup_played.length > 0) ||
             (d.stats_applied && d.stats_applied.player_stats);
    });

    if (!hasAnyScouts) {
      throw new HttpsError('failed-precondition', `A rodada ${round} não possui partidas encerradas com súmula ou atletas confirmados.`);
    }

    const scoresMap = {};
    const teamCleanSheets = {};
    const teamPlayedMatch = {};
    const teamGoalsAgainst = {};
    const playersPlayedSet = new Set();

    finishedMatches.forEach(doc => {
      const data = doc.data();

      // Mapeamento de Presença (quem jogou)
      if (data.lineup_played && Array.isArray(data.lineup_played)) {
        data.lineup_played.forEach(pid => playersPlayedSet.add(pid.toString()));
      }

      const scoreHome = Number(data.score_home) || 0;
      const scoreAway = Number(data.score_away) || 0;
      if (data.team_home_id) {
        teamPlayedMatch[data.team_home_id] = true;
        teamGoalsAgainst[data.team_home_id] = (teamGoalsAgainst[data.team_home_id] || 0) + scoreAway;
      }
      if (data.team_away_id) {
        teamPlayedMatch[data.team_away_id] = true;
        teamGoalsAgainst[data.team_away_id] = (teamGoalsAgainst[data.team_away_id] || 0) + scoreHome;
      }

      // Craque do Jogo (MOTM) pontua independentemente de stats_applied.player_stats
      const motmPid = data.stats_applied?.man_of_the_match || data.man_of_the_match;
      if (motmPid) {
        const strMotm = motmPid.toString();
        scoresMap[strMotm] = (scoresMap[strMotm] || 0) + ptsMotm;
        playersPlayedSet.add(strMotm);
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

      if (stats.goals_conceded) {
        Object.keys(stats.goals_conceded).forEach(pid => playersPlayedSet.add(pid.toString()));
      }

      ['goals', 'assists', 'yellows', 'reds', 'penalties_saved', 'penalties_missed', 'shots_on_post', 'own_goals', 'direct_free_kicks_missed', 'difficult_saves'].forEach(cat => {
        if (stats[cat]) {
          Object.entries(stats[cat]).forEach(([pid, val]) => {
            const count = Number(val) || 0;
            const points = count * (ptsRules[cat] || 0);
            scoresMap[pid] = (scoresMap[pid] || 0) + points;
            if (count > 0) {
              playersPlayedSet.add(pid.toString());
            }
          });
        }
      });
    });

    Object.keys(teamPlayedMatch).forEach(tId => {
      if (teamGoalsAgainst[tId] === 0) {
        teamCleanSheets[tId] = true;
      }
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
    const pricesBeforeMap = {};

    allPlayersSnap.forEach(doc => {
      const p = doc.data();
      const pid = doc.id;
      const score = scoresMap[pid] || 0;

      // Busca o histórico caso seja um reprocessamento da rodada
      const existingHistory = Array.isArray(p.history) ? p.history.find(h => h.round === round) : null;
      // Se já existir, usamos o price_before original para não acumular variações de preço
      const currentPrice = existingHistory ? (existingHistory.price_before || config.minPrice) : (p.current_price || config.minPrice);
      pricesBeforeMap[pid] = currentPrice;

      const hasPlayed = playersPlayedSet.has(pid.toString()) || (p.position === 'Técnico' && (teamScores[p.team_id] && teamScores[p.team_id].length > 0));

      let variation = 0.0;
      let newPrice = currentPrice;

      if (hasPlayed) {
        const expectation = currentPrice * config.factorExpectation;
        const performance = score - expectation;
        variation = performance * config.factorVariation;
        let limit = currentPrice * config.capLimitPercent;

        // Clamp garante que o limite nunca seja menor que 2.0 nem maior que 5.0
        if (limit < 2.0) limit = 2.0;
        if (limit > 5.0) limit = 5.0;

        if (variation > limit) variation = limit;
        if (variation < -limit) variation = -limit;

        variation = Number(variation.toFixed(2));
        newPrice = Number((currentPrice + variation).toFixed(2));
        if (newPrice < config.minPrice) {
          newPrice = config.minPrice;
          variation = Number((newPrice - currentPrice).toFixed(2));
        }

        newPricesMap[pid] = newPrice;
      } else {
        newPricesMap[pid] = Number(currentPrice.toFixed(2));
        variation = 0.0;
      }

      const updatedHistory = Array.isArray(p.history) ? p.history.filter(h => h.round !== round) : [];
      updatedHistory.push({
        round: round,
        score: hasPlayed ? score : 0,
        price_before: currentPrice,
        price_after: newPricesMap[pid],
        variation: variation,
        played: hasPlayed,
        processed_at: admin.firestore.Timestamp.now()
      });

      const playedMatches = updatedHistory.filter(h => h.played);
      const avgScore = playedMatches.length > 0 ? (playedMatches.reduce((acc, h) => acc + h.score, 0) / playedMatches.length) : 0;
      const lastPlayedMatch = playedMatches.length > 0 ? playedMatches[playedMatches.length - 1] : null;

      batchHandler.update(doc.ref, {
        current_price: newPricesMap[pid],
        last_price_change: hasPlayed ? variation : (lastPlayedMatch ? (lastPlayedMatch.variation || 0) : 0),
        last_score: hasPlayed ? score : (lastPlayedMatch ? (lastPlayedMatch.score || 0) : 0),
        average_score: Number(avgScore.toFixed(2)),
        matches_played: playedMatches.length,
        history: updatedHistory
      });
    });

    const oldTeamHistoriesSnap = await db.collectionGroup('history').where('round', '==', round).get();
    const oldTeamPointsMap = {};
    const oldTeamHistoriesMap = {};
    oldTeamHistoriesSnap.forEach(doc => {
      // O caminho é fantasy_teams/{teamId}/history/{round}
      const teamId = doc.ref.parent.parent.id;
      const hData = doc.data();
      oldTeamPointsMap[teamId] = hData.points || 0;
      oldTeamHistoriesMap[teamId] = hData;
    });

    // 🏆 FinOps: Busca o patrimônio da rodada anterior para cálculo exato da valorização da rodada
    const prevRoundHistoriesMap = {};
    if (round > 1) {
      const prevRoundHistoriesSnap = await db.collectionGroup('history').where('round', '==', round - 1).get();
      prevRoundHistoriesSnap.forEach(doc => {
        const teamId = doc.ref.parent.parent.id;
        prevRoundHistoriesMap[teamId] = doc.data().patrimony || 50.0;
      });
    }

    const userTeamsSnap = await db.collection('fantasy_teams').get();

    const playerPickedCount = {};
    const teamRoundScores = {};
    const teamPatrimony = {};
    const teamTotalPointsMap = {};
    const teamVariations = {};

    // 📊 FinOps: Métricas consolidadas da rodada para tela inicial (Média, Mito, Menor pontuação, Maior/Menor valorização)
    let totalTeamsCount = 0;
    let activeTeamsCount = 0;
    let activeTeamsPointsSum = 0;
    let highestScoreTeam = null;       // Mito da rodada (maior pontuação)
    let lowestScoreTeam = null;        // Lanterna da rodada (apenas times que escalaram)
    let highestAppreciationTeam = null;// Maior valorização da rodada (+C$)
    let lowestAppreciationTeam = null; // Maior desvalorização da rodada (-C$, apenas times que escalaram)

    userTeamsSnap.forEach(doc => {
      const team = doc.data();
      const oldHistory = oldTeamHistoriesMap[doc.id] || null;

      // No reprocessamento de rodada já encerrada, preserva o snapshot da escalação daquela rodada
      const originalLineup = (oldHistory && Array.isArray(oldHistory.lineup_snapshot))
        ? oldHistory.lineup_snapshot
        : (team.lineup_player_ids || []);
      const benchIds = (oldHistory && Array.isArray(oldHistory.bench_snapshot))
        ? oldHistory.bench_snapshot
        : (team.bench_player_ids || []);
      const captainId = (oldHistory && oldHistory.original_captain_id !== undefined)
        ? oldHistory.original_captain_id
        : (team.captain_id || null);
      const luxuryReserveId = (oldHistory && oldHistory.luxury_reserve_snapshot !== undefined)
        ? oldHistory.luxury_reserve_snapshot
        : (team.luxury_reserve_id || null);

      // Conta para Mais Escalados
      originalLineup.forEach(pid => {
        playerPickedCount[pid] = (playerPickedCount[pid] || 0) + 1;
      });

      let finalLineup = [...originalLineup];
      let substitutedList = [];
      let activeCaptainId = captainId;

      const lineupSlots = (oldHistory && oldHistory.lineup_slots_snapshot)
        ? oldHistory.lineup_slots_snapshot
        : (team.lineup_slots || {});
      const benchSlots = (oldHistory && oldHistory.bench_slots_snapshot)
        ? oldHistory.bench_slots_snapshot
        : (team.bench_slots || {});

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

      let playersInitialCost = 0;
      originalLineup.forEach(pid => {
        playersCurrentValue += (newPricesMap[pid] || config.minPrice);
        playersInitialCost += (pricesBeforeMap[pid] || config.minPrice);
      });

      // Arredonda pra 2 casas decimais
      roundPoints = Number(roundPoints.toFixed(2));
      teamRoundScores[doc.id] = roundPoints; // Guarda pra usar no mata-mata

      const rawBalance = team.current_balance !== undefined ? team.current_balance : (team.balance || 0);
      const teamValue = team.team_value || 50.0;
      // No reprocessamento, recupera o saldo livre que o time tinha na rodada para não somar valorização em dobro
      const safeBalance = (oldHistory && oldHistory.balance !== undefined)
        ? Number(oldHistory.balance)
        : Math.min(rawBalance, Math.max(0, Number((teamValue - playersInitialCost).toFixed(2))));

      const totalPatrimony = Number((safeBalance + playersCurrentValue).toFixed(2));
      teamPatrimony[doc.id] = totalPatrimony;

      // 💰 Cálculo da variação de patrimônio da rodada (Cartoletas)
      const prevPatrimony = round === 1
        ? 50.0
        : (prevRoundHistoriesMap[doc.id] !== undefined
          ? prevRoundHistoriesMap[doc.id]
          : (oldHistory && oldHistory.patrimony !== undefined && oldHistory.variation !== undefined
            ? Number((oldHistory.patrimony - oldHistory.variation).toFixed(2))
            : (team.team_value || 50.0)));
      const roundVariation = Number((totalPatrimony - prevPatrimony).toFixed(2));
      teamVariations[doc.id] = roundVariation;

      const teamHistoryRef = doc.ref.collection('history').doc(round.toString());

      batchHandler.set(teamHistoryRef, {
        round: round,
        points: roundPoints,
        patrimony: totalPatrimony,
        variation: roundVariation,
        balance: safeBalance,
        processed_at: admin.firestore.Timestamp.now(),
        captain_id: activeCaptainId,
        original_captain_id: captainId,
        luxury_reserve_snapshot: luxuryReserveId,
        lineup_snapshot: originalLineup,
        bench_snapshot: benchIds,
        lineup_slots_snapshot: lineupSlots,
        bench_slots_snapshot: benchSlots,
        final_lineup: finalLineup,
        substitutions: substitutedList
      });

      let baseTotalPoints = team.total_points || 0;
      if (oldTeamPointsMap[doc.id] !== undefined) {
        baseTotalPoints -= oldTeamPointsMap[doc.id]; // Subtrai a pontuação anterior para não duplicar no reprocessamento
      }
      const newTotalPoints = Number((baseTotalPoints + roundPoints).toFixed(2));
      teamTotalPointsMap[doc.id] = newTotalPoints;

      // Se for reprocessamento e o usuário já tiver alterado o time para a rodada seguinte, ajusta apenas o delta de patrimônio
      const currentLineupIds = team.lineup_player_ids || [];
      const lineupUnchanged = JSON.stringify(currentLineupIds) === JSON.stringify(originalLineup);
      let updatedTeamValue = totalPatrimony;
      let updatedBalance = safeBalance;
      if (oldHistory && !lineupUnchanged && oldHistory.patrimony !== undefined) {
        const patrimonyDelta = Number((totalPatrimony - oldHistory.patrimony).toFixed(2));
        updatedTeamValue = Math.max(config.minPrice, Number((teamValue + patrimonyDelta).toFixed(2)));
        updatedBalance = Math.max(0, Number((rawBalance + patrimonyDelta).toFixed(2)));
      }

      batchHandler.update(doc.ref, {
        total_points: newTotalPoints,
        last_score: roundPoints,
        team_value: updatedTeamValue,
        last_variation: roundVariation,
        current_balance: updatedBalance,
        balance: admin.firestore.FieldValue.delete(), // Limpa campo legado
        updated_at: admin.firestore.Timestamp.now()
      });

      // 📊 Agrupamento de métricas para resumo consolidado (FinOps)
      totalTeamsCount++;
      const hasPlayersFielded = originalLineup && originalLineup.length > 0;
      if (hasPlayersFielded) {
        activeTeamsCount++;
        activeTeamsPointsSum += roundPoints;
      }

      const teamSummaryItem = {
        team_id: doc.id,
        user_id: team.user_id || doc.id,
        team_name: team.team_name || 'Time sem nome',
        owner_name: team.owner_name || 'Cartoleiro',
        shield_type: team.shield_type || '1',
        custom_logo_url: team.custom_logo_url || null,
        score: roundPoints,
        variation: roundVariation,
        patrimony: totalPatrimony
      };

      // 1. Mito da Rodada (Maior pontuação geral)
      if (!highestScoreTeam || roundPoints > highestScoreTeam.score) {
        highestScoreTeam = teamSummaryItem;
      }

      // 2. Menor pontuação da rodada (APENAS times com jogadores escalados)
      if (hasPlayersFielded) {
        if (!lowestScoreTeam || roundPoints < lowestScoreTeam.score) {
          lowestScoreTeam = teamSummaryItem;
        }
      }

      // 3. Maior valorização (+C$)
      if (!highestAppreciationTeam || roundVariation > highestAppreciationTeam.variation) {
        highestAppreciationTeam = teamSummaryItem;
      }

      // 4. Maior desvalorização (-C$, APENAS times com jogadores escalados)
      if (hasPlayersFielded) {
        if (!lowestAppreciationTeam || roundVariation < lowestAppreciationTeam.variation) {
          lowestAppreciationTeam = teamSummaryItem;
        }
      }
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

    // 🏆 FinOps: Grava documento consolidado do resumo da rodada para acesso em 1 leitura
    const avgScoreRound = activeTeamsCount > 0 ? Number((activeTeamsPointsSum / activeTeamsCount).toFixed(2)) : 0.0;
    const roundSummaryPayload = {
      round: round,
      total_teams: totalTeamsCount,
      active_teams: activeTeamsCount,
      average_score: avgScoreRound,
      highest_score_team: highestScoreTeam,
      lowest_score_team: lowestScoreTeam,
      highest_appreciation_team: highestAppreciationTeam,
      lowest_appreciation_team: lowestAppreciationTeam,
      updated_at: admin.firestore.Timestamp.now()
    };

    const roundSummaryRef = db.collection('fantasy_stats').doc(`round_${round}_summary`);
    batchHandler.set(roundSummaryRef, roundSummaryPayload, { merge: true });

    const lastRoundSummaryRef = db.collection('fantasy_stats').doc('last_round_summary');
    batchHandler.set(lastRoundSummaryRef, roundSummaryPayload, { merge: true });


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
        const teamAId = kMatch.team_a_id || kMatch.teamAId || null;
        const teamBId = kMatch.team_b_id || kMatch.teamBId || null;
        const matchIndex = kMatch.match_index !== undefined
          ? Number(kMatch.match_index)
          : (kMatch.matchIndex !== undefined ? Number(kMatch.matchIndex) : 0);

        const scoreA = teamAId ? (teamRoundScores[teamAId] || 0) : 0;
        const scoreB = teamBId ? (teamRoundScores[teamBId] || 0) : 0;

        let winnerId = null;

        if (!teamAId && teamBId) {
          winnerId = teamBId;
        } else if (teamAId && !teamBId) {
          winnerId = teamAId;
        } else if (scoreA > scoreB) {
          winnerId = teamAId;
        } else if (scoreB > scoreA) {
          winnerId = teamBId;
        } else {
          // 1º Desempate: Pontuação geral do campeonato (total_points)
          const totalA = teamTotalPointsMap[teamAId] || 0;
          const totalB = teamTotalPointsMap[teamBId] || 0;
          if (totalA !== totalB) {
            winnerId = totalA > totalB ? teamAId : teamBId;
          } else {
            // 2º Desempate: Patrimônio
            const patA = teamPatrimony[teamAId] || 0;
            const patB = teamPatrimony[teamBId] || 0;
            if (patA !== patB) {
              winnerId = patA > patB ? teamAId : teamBId;
            } else {
              // 3º Desempate determinístico (evita inversão em reprocessamento)
              winnerId = String(teamAId || '').localeCompare(String(teamBId || '')) <= 0 ? teamAId : teamBId;
            }
          }
        }

        batchHandler.update(kMatchDoc.ref, {
          team_a_score: scoreA,
          team_b_score: scoreB,
          winner_id: winnerId,
          scoreA: scoreA,
          scoreB: scoreB,
          winnerId: winnerId
        });

        // Promove o vencedor
        if (totalMatchesInRound > 1) {
          const nextMatchIndex = Math.floor(matchIndex / 2);
          const isTeamAForNext = matchIndex % 2 === 0;

          const nextPhase = totalMatchesInRound === 2 ? 'Final' :
            totalMatchesInRound === 4 ? 'Semi' :
              totalMatchesInRound === 8 ? 'Quartas' : 'Oitavas';

          const nextMatchId = `match_${round + 1}_${nextMatchIndex}`;
          const nextMatchRef = db.collection('fantasy_leagues').doc(leagueId).collection('matches').doc(nextMatchId);

          const nextTeamField = isTeamAForNext ? 'team_a_id' : 'team_b_id';
          const nextTeamLegacyField = isTeamAForNext ? 'teamAId' : 'teamBId';

          batchHandler.set(nextMatchRef, {
            phase: nextPhase,
            round: round + 1,
            match_index: nextMatchIndex,
            matchIndex: nextMatchIndex,
            [nextTeamField]: winnerId,
            [nextTeamLegacyField]: winnerId
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

    // 🏆 FinOps: Atualiza o Leaderboard Consolidado com status finalizado
    try {
      await updateLiveLeaderboard(seasonId, round, liveScoresObj, playersPlayedSet, playersInfo, true);
    } catch (e) {
      console.error("Aviso ao atualizar Leaderboard final:", e);
    }

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
    // 🔒 Se uma partida da rodada atual entrou em andamento (ou finalizou) e o mercado ainda estava aberto, fecha imediatamente
    if (matchData.status === 'in_progress' || matchData.status === 'finished') {
      const statusRef = db.collection('fantasy_config').doc('status');
      const statusSnap = await statusRef.get();
      if (statusSnap.exists) {
        const sData = statusSnap.data();
        if (sData.is_open === true && Number(sData.current_round || 1) === Number(round)) {
          await statusRef.update({
            is_open: false,
            updated_at: admin.firestore.FieldValue.serverTimestamp()
          });
          console.log(`🔒 Mercado fechado automaticamente ao iniciar partida da rodada ${round}.`);
        }
      }
    }

    const liveDocRef = db.collection('championships').doc(seasonId).collection('fantasy_live').doc(`round_${round}`);
    const liveDocSnap = await liveDocRef.get();
    const wasAlreadyFinal = liveDocSnap.exists && liveDocSnap.data().is_final === true;

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
    const teamPlayedMatch = {};
    const teamGoalsAgainst = {};
    const playersPlayedSet = new Set();

    matchesSnap.forEach(doc => {
      const data = doc.data();

      // Apenas partidas iniciadas ou encerradas contabilizam presença, SG e scouts ao vivo
      const isMatchStarted = data.status === 'in_progress' || data.status === 'finished';
      if (!isMatchStarted) return;

      const scoreHome = Number(data.score_home) || 0;
      const scoreAway = Number(data.score_away) || 0;
      if (data.team_home_id) {
        teamPlayedMatch[data.team_home_id] = true;
        teamGoalsAgainst[data.team_home_id] = (teamGoalsAgainst[data.team_home_id] || 0) + scoreAway;
      }
      if (data.team_away_id) {
        teamPlayedMatch[data.team_away_id] = true;
        teamGoalsAgainst[data.team_away_id] = (teamGoalsAgainst[data.team_away_id] || 0) + scoreHome;
      }

      const lineups = Array.isArray(data.lineup_played) ? data.lineup_played : [];
      lineups.forEach(pid => {
        const strPid = pid.toString();
        playersPlayedSet.add(strPid);
        if (!scoresMap[strPid]) {
          scoresMap[strPid] = { totalScore: 0, goals: 0, assists: 0, yellows: 0, reds: 0, goals_conceded: 0, penalties_saved: 0, penalties_missed: 0, shots_on_post: 0, clean_sheets: 0, own_goals: 0, direct_free_kicks_missed: 0, motm: 0, difficult_saves: 0 };
        }
      });

      const motmPid = data.stats_applied?.man_of_the_match || data.man_of_the_match;
      if (motmPid) {
        const strMotm = motmPid.toString();
        if (!scoresMap[strMotm]) {
          scoresMap[strMotm] = { totalScore: 0, goals: 0, assists: 0, yellows: 0, reds: 0, goals_conceded: 0, penalties_saved: 0, penalties_missed: 0, shots_on_post: 0, clean_sheets: 0, own_goals: 0, direct_free_kicks_missed: 0, motm: 0, difficult_saves: 0 };
        }
        scoresMap[strMotm].motm += 1;
        playersPlayedSet.add(strMotm);
      }

      if (!data.stats_applied || !data.stats_applied.player_stats) return;

      const stats = data.stats_applied.player_stats;

      ['goals', 'assists', 'yellows', 'reds', 'goals_conceded', 'penalties_saved', 'penalties_missed', 'shots_on_post', 'own_goals', 'direct_free_kicks_missed', 'difficult_saves'].forEach(cat => {
        if (stats[cat]) {
          Object.entries(stats[cat]).forEach(([pid, val]) => {
            if (!scoresMap[pid]) {
              scoresMap[pid] = { totalScore: 0, goals: 0, assists: 0, yellows: 0, reds: 0, goals_conceded: 0, penalties_saved: 0, penalties_missed: 0, shots_on_post: 0, clean_sheets: 0, own_goals: 0, direct_free_kicks_missed: 0, motm: 0, difficult_saves: 0 };
            }

            const count = Number(val) || 0;
            scoresMap[pid][cat] += count;
            if (count > 0 || cat === 'goals_conceded') {
              playersPlayedSet.add(pid.toString());
            }
          });
        }
      });
    });

    Object.keys(teamPlayedMatch).forEach(tId => {
      if (teamGoalsAgainst[tId] === 0) {
        teamCleanSheets[tId] = true;
      }
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
      scores: scoresMap,
      players_played: Array.from(playersPlayedSet)
    }, { merge: true });

    // 🏆 FinOps: Atualiza o Leaderboard Consolidado em tempo real (preservando is_final caso a rodada já tenha sido fechada)
    await updateLiveLeaderboard(seasonId, round, scoresMap, playersPlayedSet, playersInfo, wasAlreadyFinal);

  } catch (error) {
    console.error("🔥 Erro ao atualizar Live Scouts:", error);
  }
});

// ==================================================================
// 🏆 FINOPS: AGREGADOR DE RANKINGS AO VIVO (LEADERBOARD CONSOLIDADO)
// ==================================================================

function getScoreFromMap(scoresMap, pid) {
  if (!scoresMap || !pid) return 0;
  const val = scoresMap[pid];
  if (val === undefined || val === null) return 0;
  if (typeof val === 'object') {
    return Number(val.totalScore) || 0;
  }
  return Number(val) || 0;
}

async function updateLiveLeaderboard(seasonId, round, scoresMap, playersPlayedSet, playersInfo, isFinal = false) {
  try {
    const userTeamsSnap = await db.collection('fantasy_teams').get();
    if (userTeamsSnap.empty) return;

    const oldTeamHistoriesMap = {};
    if (isFinal) {
      const oldHistSnap = await db.collectionGroup('history').where('round', '==', Number(round)).get();
      oldHistSnap.forEach(hDoc => {
        const teamId = hDoc.ref.parent.parent.id;
        oldTeamHistoriesMap[teamId] = hDoc.data();
      });
    }

    const leaderboard = [];

    userTeamsSnap.forEach(doc => {
      const team = doc.data();
      const oldHistory = oldTeamHistoriesMap[doc.id] || null;

      const originalLineup = (oldHistory && Array.isArray(oldHistory.lineup_snapshot))
        ? oldHistory.lineup_snapshot
        : (team.lineup_player_ids || []);
      const benchIds = (oldHistory && Array.isArray(oldHistory.bench_snapshot))
        ? oldHistory.bench_snapshot
        : (team.bench_player_ids || []);
      const captainId = (oldHistory && oldHistory.original_captain_id !== undefined)
        ? oldHistory.original_captain_id
        : (team.captain_id || null);
      const luxuryReserveId = (oldHistory && oldHistory.luxury_reserve_snapshot !== undefined)
        ? oldHistory.luxury_reserve_snapshot
        : (team.luxury_reserve_id || null);
      const lineupSlots = (oldHistory && oldHistory.lineup_slots_snapshot)
        ? oldHistory.lineup_slots_snapshot
        : (team.lineup_slots || {});
      const benchSlots = (oldHistory && oldHistory.bench_slots_snapshot)
        ? oldHistory.bench_slots_snapshot
        : (team.bench_slots || {});

      let finalLineup = [...originalLineup];
      let activeCaptainId = captainId;
      const substitutedList = [];

      // Agrupa titulares por posição baseando-se no slot escalado
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

      // Fallback para times legados
      originalLineup.forEach(pid => {
        if (!slottedStarters.has(pid) && playersInfo[pid]) {
          const pos = playersInfo[pid].position;
          if (startersByPos[pos]) {
            startersByPos[pos].push(pid);
          }
        }
      });

      // Agrupa reservas por posição baseando-se no slot do banco
      const benchByPos = {};
      const slottedBench = new Set();
      Object.entries(benchSlots).forEach(([slot, bId]) => {
        const pos = BENCH_POSITIONS[slot];
        if (pos && bId && benchIds.includes(bId)) {
          benchByPos[pos] = bId;
          slottedBench.add(bId);
        }
      });

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

        if (startersOfPos.length && benchId && playersPlayedSet && playersPlayedSet.has(benchId)) {
          const allPlayed = startersOfPos.every(pid => playersPlayedSet.has(pid));
          if (!allPlayed) {
            const missedStarters = startersOfPos.filter(pid => !playersPlayedSet.has(pid));
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
              substitutedList.push({
                out: missedStarter,
                in: benchId,
                type: 'normal',
                slot_position: pos
              });
              if (missedStarter === activeCaptainId) {
                activeCaptainId = benchId;
              }
            }
          } else {
            if (luxuryReserveId === benchId) {
              const benchScore = getScoreFromMap(scoresMap, benchId);
              let worstStarter = startersOfPos[0];
              let worstScore = getScoreFromMap(scoresMap, worstStarter);

              startersOfPos.forEach(pid => {
                const s = getScoreFromMap(scoresMap, pid);
                if (s < worstScore) {
                  worstScore = s;
                  worstStarter = pid;
                } else if (s === worstScore) {
                  if (worstStarter === activeCaptainId && pid !== activeCaptainId) {
                    worstStarter = pid;
                  }
                }
              });

              if (benchScore > worstScore) {
                finalLineup = finalLineup.filter(p => p !== worstStarter);
                finalLineup.push(benchId);
                substitutedList.push({
                  out: worstStarter,
                  in: benchId,
                  type: 'luxury',
                  slot_position: pos
                });
                if (worstStarter === activeCaptainId) {
                  activeCaptainId = benchId;
                }
              }
            }
          }
        }
      });

      let roundPoints = 0;
      let playersPlayed = 0;

      finalLineup.forEach(pid => {
        let pScore = getScoreFromMap(scoresMap, pid);
        if (pid === activeCaptainId) pScore *= 2;
        roundPoints += pScore;
        if (playersPlayedSet && playersPlayedSet.has(pid.toString())) {
          playersPlayed++;
        }
      });

      roundPoints = Number(roundPoints.toFixed(2));

      const alreadyCreditedPoints = oldHistory && oldHistory.points !== undefined
        ? Number(oldHistory.points)
        : (team.last_score !== undefined ? Number(team.last_score) : roundPoints);

      const baseTotalPoints = isFinal
        ? ((team.total_points || 0) - alreadyCreditedPoints)
        : (team.total_points || 0);
      const liveTotalPoints = Number((baseTotalPoints + roundPoints).toFixed(2));

      leaderboard.push({
        team_id: doc.id,
        user_id: team.user_id || doc.id,
        team_name: team.team_name || 'Time sem nome',
        owner_name: team.owner_name || 'Cartoleiro',
        shield_type: team.shield_type || 'shield_1',
        custom_logo_url: team.custom_logo_url || null,
        round_score: roundPoints,
        total_points: liveTotalPoints,
        team_value: (team.team_value !== undefined ? team.team_value : 50.0),
        last_variation: (team.last_variation !== undefined ? team.last_variation : 0.0),
        players_played: playersPlayed,
        players_total: finalLineup.length,
        captain_id: activeCaptainId,
        substitutions: substitutedList,
        final_lineup: finalLineup,
      });
    });

    // Ordena primariamente por pontuação da rodada desc
    leaderboard.sort((a, b) => b.round_score - a.round_score);

    const leaderboardRef = db.collection('championships').doc(seasonId)
      .collection('fantasy_live_leaderboard').doc(`round_${round}`);

    await leaderboardRef.set({
      round: Number(round),
      season_id: seasonId,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      is_final: isFinal,
      teams_count: leaderboard.length,
      teams: leaderboard
    }, { merge: true });

    console.log(`🏆 Live Leaderboard atualizado para a rodada ${round}: ${leaderboard.length} times consolidados.`);
  } catch (error) {
    console.error("🔥 Erro ao atualizar Live Leaderboard:", error);
  }
}

// Cloud Function onCall para recalcular o Leaderboard ao vivo sob demanda por Admin
exports.recalculateLiveLeaderboard = onCall({
  cors: true,
  timeoutSeconds: 300,
  memory: '512MB'
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Acesso negado. Usuário não autenticado.');
  }
  const adminDoc = await db.collection('admin_users').doc(request.auth.uid).get();
  if (!adminDoc.exists) {
    throw new HttpsError('permission-denied', 'Apenas administradores podem recalcular o leaderboard ao vivo.');
  }

  const { seasonId, round } = request.data;
  if (!seasonId || !round) {
    throw new HttpsError('invalid-argument', 'seasonId e round são obrigatórios.');
  }

  const liveDocSnap = await db.collection('championships').doc(seasonId)
    .collection('fantasy_live').doc(`round_${round}`).get();

  if (!liveDocSnap.exists) {
    throw new HttpsError('not-found', `Documento fantasy_live para a rodada ${round} não encontrado.`);
  }

  const liveData = liveDocSnap.data();
  const liveScores = liveData.scores || {};
  const isFinal = liveData.is_final || false;

  const matchesSnap = await db.collection('championships').doc(seasonId)
    .collection('matches').where('round', '==', Number(round)).get();

  const playersPlayedSet = new Set();
  matchesSnap.forEach(doc => {
    const data = doc.data();
    const isValidStatus = isFinal
      ? data.status === 'finished'
      : (data.status === 'in_progress' || data.status === 'finished');
    if (!isValidStatus) return;

    if (data.lineup_played && Array.isArray(data.lineup_played)) {
      data.lineup_played.forEach(pid => playersPlayedSet.add(pid.toString()));
    }
    const motmPid = data.stats_applied?.man_of_the_match || data.man_of_the_match;
    if (motmPid) playersPlayedSet.add(motmPid.toString());
  });

  const allPlayersSnap = await db.collection('fantasy_market_players').get();
  const playersInfo = {};
  allPlayersSnap.forEach(doc => {
    playersInfo[doc.id] = doc.data();
  });

  await updateLiveLeaderboard(seasonId, round, liveScores, playersPlayedSet, playersInfo, isFinal);

  return { success: true, message: `Leaderboard da rodada ${round} recalculado com sucesso.` };
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
    const nowEarlyMs = Date.now();
    const cachedClosingMs = statusData.closing_time ? statusData.closing_time.toMillis() : null;

    // ⚡ FinOps: Se closing_time já foi calculado e atingido, fecha imediatamente sem consultar championships/matches
    if (cachedClosingMs !== null && nowEarlyMs >= cachedClosingMs) {
      await statusRef.update({
        is_open: false,
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`🛑 PILOTO AUTOMÁTICO: Mercado FECHADO (via closing_time em cache) para a rodada ${currentRound}.`);
      return;
    }

    // ⚡ FinOps: Se ainda falta mais de 30 minutos para o fechamento já agendado,
    // só revalida a agenda de jogos a cada 30 minutos (economiza ~93% das leituras de championships e matches)
    if (cachedClosingMs !== null && (cachedClosingMs - nowEarlyMs) > 30 * 60 * 1000) {
      const currentMinute = new Date(nowEarlyMs).getMinutes();
      if (currentMinute % 30 >= 2) {
        return;
      }
    }

    const seasonsSnap = await db.collection('championships')
      .where('is_active', '==', true)
      .limit(1)
      .get();

    if (seasonsSnap.empty) return;
    const seasonId = seasonsSnap.docs[0].id;

    // Busca todas as partidas da rodada atual (evita ignorar 1º jogo que já tenha mudado de status para in_progress)
    const roundMatchesSnap = await db.collection('championships').doc(seasonId)
      .collection('matches')
      .where('round', '==', currentRound)
      .get();

    if (roundMatchesSnap.empty) return;

    const roundMatches = roundMatchesSnap.docs.map(d => d.data());

    // Se qualquer partida da rodada já estiver em andamento ou finalizada, fecha o mercado imediatamente
    const anyMatchAlreadyStarted = roundMatches.some(m => m.status === 'in_progress' || m.status === 'finished');
    if (anyMatchAlreadyStarted) {
      await statusRef.update({
        is_open: false,
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`🛑 PILOTO AUTOMÁTICO: Mercado FECHADO imediatamente (partida da R${currentRound} já iniciada).`);
      return;
    }

    // Filtra partidas com datetime definido e pega a mais próxima (1º jogo da rodada)
    const matchesWithDate = roundMatches.filter(m => m.datetime && typeof m.datetime.toDate === 'function');
    if (matchesWithDate.length === 0) return;

    matchesWithDate.sort((a, b) => a.datetime.toDate().getTime() - b.datetime.toDate().getTime());
    const firstMatch = matchesWithDate[0];

    const matchTimeMs = firstMatch.datetime.toDate().getTime();
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
      if (!batchHandler.predByUserId) {
        const predRefs = usersSnap.docs.map(u => db.collection('bolao_users').doc(u.id).collection('predictions').doc(matchId));
        const predSnaps = predRefs.length > 0 ? await db.getAll(...predRefs) : [];
        batchHandler.predByUserId = {};
        predSnaps.forEach((snap, idx) => { batchHandler.predByUserId[usersSnap.docs[idx].id] = snap; });
      }
      const predDoc = batchHandler.predByUserId[userId];

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
  const beforeMatchData = event.data.before ? event.data.before.data() : null;
  const triggeringMatchData = event.data.after ? event.data.after.data() : null;

  if (!triggeringMatchData || triggeringMatchData.status !== 'in_progress') {
    return;
  }

  // ⚡ FinOps: Evita recalcular todo o ranking se o placar e o status da partida não mudaram
  if (beforeMatchData &&
      beforeMatchData.status === triggeringMatchData.status &&
      beforeMatchData.real_score_home === triggeringMatchData.real_score_home &&
      beforeMatchData.real_score_away === triggeringMatchData.real_score_away) {
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
// UTILS: Batch Handler (Auto-chunking seguro para Firestore WriteBatch)
// ==================================================================
class BatchHandler {
  constructor(dbInstance) {
    this.db = dbInstance;
    this.operations = [];
  }

  update(ref, data) {
    this.operations.push({ type: 'update', ref, data });
  }

  set(ref, data, options = null) {
    this.operations.push({ type: 'set', ref, data, options });
  }

  delete(ref) {
    this.operations.push({ type: 'delete', ref });
  }

  async commit() {
    if (this.operations.length === 0) return;

    const CHUNK_SIZE = 450;
    let currentBatch = this.db.batch();
    const currentPaths = new Set();
    let currentCount = 0;

    for (const op of this.operations) {
      const docPath = op.ref ? op.ref.path : null;

      // Se atingir o limite de 450 operações ou se o mesmo documento já foi
      // referenciado no batch atual (Firestore proíbe múltiplos writes no mesmo doc num único batch),
      // commita o batch corrente e abre um novo de forma estritamente sequencial.
      if (currentCount >= CHUNK_SIZE || (docPath && currentPaths.has(docPath))) {
        await currentBatch.commit();
        currentBatch = this.db.batch();
        currentPaths.clear();
        currentCount = 0;
      }

      if (op.type === 'update') {
        currentBatch.update(op.ref, op.data);
      } else if (op.type === 'set') {
        if (op.options) {
          currentBatch.set(op.ref, op.data, op.options);
        } else {
          currentBatch.set(op.ref, op.data);
        }
      } else if (op.type === 'delete') {
        currentBatch.delete(op.ref);
      }

      if (docPath) currentPaths.add(docPath);
      currentCount++;
    }

    if (currentCount > 0) {
      await currentBatch.commit();
    }

    this.operations = [];
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
