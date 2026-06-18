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
  
  factorExpectation: 0.35, 
  factorVariation: 0.25,
  capLimitPercent: 0.25,   
  minPrice: 1.0,
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

  const { type, userId, customerContact, photoIds, miniBolaoId } = request.data;
  let valorInscricao = "0.00";
  let itemsToSave = [];
  let description = "";

  if (type === 'bolao') {
    valorInscricao = "20.00"; 
    description = `Inscrição Bolão Copa 2026 - ${userId}`;
  } 
  else if (type === 'mini_bolao') {
    if (!miniBolaoId) throw new HttpsError('invalid-argument', 'ID do Mini Bolão não informado.');
    
    const mbSnap = await db.collection('bolao_mini_leagues').doc(miniBolaoId).get();
    if (!mbSnap.exists) throw new HttpsError('not-found', 'Mini Bolão não encontrado.');
    
    const mbData = mbSnap.data();

    // 🚨 BLOQUEIO POR DATA LIMITE: Ninguém gera PIX depois que a sala trancou
    if (mbData.deadline) {
      const deadlineTime = mbData.deadline.toDate();
      if (new Date() > deadlineTime) {
        throw new HttpsError('permission-denied', 'O prazo de inscrição para este Mini Bolão já encerrou!');
      }
    }
    
    const entryFee = parseFloat(mbData.entry_fee || 0);
    if (entryFee <= 0) throw new HttpsError('invalid-argument', 'Valor do Mini Bolão é inválido.');
    
    valorInscricao = entryFee.toFixed(2);
    description = `Mini Bolão: ${mbData.title}`.substring(0, 140);
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
    description = `Pack de ${itemsToSave.length} Fotos FJF - ${customerContact}`;
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
    const config = configSnap.exists ? { ...DEFAULT_CONFIG, ...configSnap.data() } : DEFAULT_CONFIG;

    const matchesSnap = await db.collection('championships').doc(seasonId)
      .collection('matches').where('round', '==', round).get();

    const scoresMap = {};
    const teamCleanSheets = {}; 

    matchesSnap.forEach(doc => {
      const data = doc.data();
      
      const scoreHome = data.score_home || 0;
      const scoreAway = data.score_away || 0;
      if (scoreAway === 0) teamCleanSheets[data.team_home_id] = true;
      if (scoreHome === 0) teamCleanSheets[data.team_away_id] = true;

      if (!data.stats_applied || !data.stats_applied.player_stats) return;

      const stats = data.stats_applied.player_stats;
      const ptsRules = {
        goals: config.ptsGoal,
        assists: config.ptsAssist,
        yellows: config.ptsYellowCard,
        reds: config.ptsRedCard,
        penalties_saved: config.ptsPenaltySaved,     
        penalties_missed: config.ptsPenaltyMissed,   
        shots_on_post: config.ptsShotOnPost          
      };

      ['goals', 'assists', 'yellows', 'reds', 'penalties_saved', 'penalties_missed', 'shots_on_post'].forEach(cat => {
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

    allPlayersSnap.forEach(doc => {
      const p = doc.data();
      const pid = doc.id;
      const teamId = p.team_id; 

      if (!teamId) return;

      if (teamCleanSheets[teamId] && (p.position === 'Goleiro' || p.position === 'Fixo')) {
        scoresMap[pid] = (scoresMap[pid] || 0) + config.ptsCleanSheet;
      }

      if (p.position === 'Técnico') {
        teamCoaches[teamId] = pid;
      }

      if (scoresMap[pid] !== undefined) {
        const points = scoresMap[pid];
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
      const currentPrice = p.current_price || config.minPrice; 

      const expectation = currentPrice * config.factorExpectation;
      const performance = score - expectation;
      let variation = performance * config.factorVariation;
      const limit = currentPrice * config.capLimitPercent;

      if (variation > limit) variation = limit;
      if (variation < -limit) variation = -limit;

      let newPrice = currentPrice + variation;
      if (newPrice < config.minPrice) newPrice = config.minPrice;

      newPricesMap[pid] = Number(newPrice.toFixed(1));
      variation = Number(variation.toFixed(1));

      const updatedHistory = Array.isArray(p.history) ? p.history.filter(h => h.round !== round) : [];
      updatedHistory.push({
        round: round,
        score: score,
        price_before: currentPrice,
        price_after: newPricesMap[pid],
        variation: variation,
        played: true,
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

    const userTeamsSnap = await db.collection('fantasy_teams').get();
    userTeamsSnap.forEach(doc => {
      const team = doc.data();
      const lineup = team.lineup_player_ids || []; 
      const captainId = team.captain_id || null;    

      let roundPoints = 0;
      let playersCurrentValue = 0;

      lineup.forEach(pid => {
        let pScore = scoresMap[pid] || 0;
        if (pid === captainId) pScore *= 2;
        roundPoints += pScore;
        playersCurrentValue += (newPricesMap[pid] || config.minPrice);
      });

      const currentBalance = team.current_balance || 0; 
      const totalPatrimony = Number((currentBalance + playersCurrentValue).toFixed(2));

      const teamHistoryRef = doc.ref.collection('history').doc(round.toString());
      
      batchHandler.set(teamHistoryRef, {
        round: round,
        points: roundPoints,
        patrimony: totalPatrimony,
        processed_at: admin.firestore.Timestamp.now(),
        captain_id: captainId, 
        lineup_snapshot: lineup 
      });

      batchHandler.update(doc.ref, {
        total_points: Number(((team.total_points || 0) + roundPoints).toFixed(2)), 
        last_score: roundPoints,                                                   
        team_value: totalPatrimony,                                                
        updated_at: admin.firestore.Timestamp.now()                                 
      });
    });

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
    
    if (oldStats === newStats && oldHome === newHome && oldAway === newAway) {
      return; 
    }
  }

  try {
    const liveDocRef = db.collection('championships').doc(seasonId).collection('fantasy_live').doc(`round_${round}`);
    const liveDocSnap = await liveDocRef.get();
    
    let scoresMap = liveDocSnap.exists ? (liveDocSnap.data().scores || {}) : {};

    const configSnap = await db.collection('fantasy_config').doc('rules').get();
    const config = configSnap.exists ? { ...DEFAULT_CONFIG, ...configSnap.data() } : DEFAULT_CONFIG;

    const matchesSnap = await db.collection('championships').doc(seasonId)
      .collection('matches').where('round', '==', round).get();

    const teamCleanSheets = {}; 

    matchesSnap.forEach(doc => {
      const data = doc.data();
      
      const scoreHome = data.score_home || 0;
      const scoreAway = data.score_away || 0;
      if (scoreAway === 0) teamCleanSheets[data.team_home_id] = true;
      if (scoreHome === 0) teamCleanSheets[data.team_away_id] = true;

      if (!data.stats_applied || !data.stats_applied.player_stats) return;

      const stats = data.stats_applied.player_stats;
      const ptsRules = {
        goals: config.ptsGoal,
        assists: config.ptsAssist,
        yellows: config.ptsYellowCard,
        reds: config.ptsRedCard,
        penalties_saved: config.ptsPenaltySaved,     
        penalties_missed: config.ptsPenaltyMissed,   
        shots_on_post: config.ptsShotOnPost          
      };

      ['goals', 'assists', 'yellows', 'reds', 'penalties_saved', 'penalties_missed', 'shots_on_post'].forEach(cat => {
        if (stats[cat]) {
          Object.entries(stats[cat]).forEach(([pid, val]) => {
            if (!scoresMap[pid]) {
              scoresMap[pid] = { totalScore: 0, goals: 0, assists: 0, yellows: 0, reds: 0, goals_conceded: 0, penalties_saved: 0, penalties_missed: 0, shots_on_post: 0, clean_sheets: 0 };
            } else {
              scoresMap[pid][cat] = 0;
              scoresMap[pid].totalScore = 0; 
            }
            
            const count = Number(val) || 0;
            scoresMap[pid][cat] = count;
          });
        }
      });
    });

    Object.keys(scoresMap).forEach(pid => {
       let total = 0;
       total += (scoresMap[pid].goals || 0) * config.ptsGoal;
       total += (scoresMap[pid].assists || 0) * config.ptsAssist;
       total += (scoresMap[pid].yellows || 0) * config.ptsYellowCard;
       total += (scoresMap[pid].reds || 0) * config.ptsRedCard;
       total += (scoresMap[pid].penalties_saved || 0) * config.ptsPenaltySaved;
       total += (scoresMap[pid].penalties_missed || 0) * config.ptsPenaltyMissed;
       total += (scoresMap[pid].shots_on_post || 0) * config.ptsShotOnPost;
       
       scoresMap[pid].totalScore = total;
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
  schedule: "every 10 minutes",
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
    
    const diffMinutes = (matchTimeMs - nowMs) / (1000 * 60);

    if (diffMinutes <= 20) {
      await statusRef.update({
        is_open: false,
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`🛑 PILOTO AUTOMÁTICO: Mercado FECHADO para a rodada ${currentRound}.`);
    }

  } catch (error) {
    console.error("🔥 Erro no autoCloseMarket:", error);
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

// 🚨 NOVA FUNÇÃO PROTEGIDA: PALPITES DO MINI BOLÃO VIP 🚨
exports.submitMiniBolaoPrediction = onCall({ cors: true }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Login obrigatório.');
  
  const { miniBolaoId, scoreHome, scoreAway, goalScorers, lastGoalTeam } = request.data;
  const userId = request.auth.uid;

  if (!miniBolaoId || scoreHome === undefined || scoreAway === undefined || !lastGoalTeam) {
    throw new HttpsError('invalid-argument', 'Dados incompletos para o palpite VIP.');
  }

  try {
    const mbSnap = await db.collection('bolao_mini_leagues').doc(miniBolaoId).get();
    if (!mbSnap.exists) throw new HttpsError('not-found', 'Mini Bolão não encontrado.');
    
    const mbData = mbSnap.data();
    
    if (mbData.status === 'finished') {
      throw new HttpsError('permission-denied', 'Esta sala VIP já foi encerrada.');
    }

    // 🚨 VALIDAÇÃO IMUTÁVEL DE HORA DO SERVIDOR DO GOOGLE
    if (mbData.deadline) {
      const deadlineTime = mbData.deadline.toDate();
      const serverNow = new Date();
      if (serverNow > deadlineTime) {
        throw new HttpsError('permission-denied', 'O prazo para salvar palpites nesta sala VIP já encerrou!');
      }
    }

    const participantRef = db.collection('bolao_mini_leagues').doc(miniBolaoId).collection('participants').doc(userId);
    
    // Confirma que o usuário pagou o PIX antes de deixar ele salvar um palpite
    const pSnap = await participantRef.get();
    if (!pSnap.exists) {
      throw new HttpsError('permission-denied', 'Você não está participando desta sala VIP.');
    }

    await participantRef.set({
      pred_score_home: parseInt(scoreHome),
      pred_score_away: parseInt(scoreAway),
      pred_goal_scorers: goalScorers || [],
      pred_last_goal_team: lastGoalTeam,
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

    for (const userDoc of usersSnap.docs) {
      const userData = userDoc.data();
      let extraPoints = 0;

      if (userData.bonus_champion === officialChampion) extraPoints += 20;
      if (userData.bonus_runner_up === officialRunnerUp) extraPoints += 10;
      if (userData.bonus_best_offense === officialBestOffense) extraPoints += 10;
      if (userData.bonus_worst_defense === officialWorstDefense) extraPoints += 10;
      if (userData.bonus_disappointment === officialDisappointment) extraPoints += 10;

      if (extraPoints > 0) {
        batchHandler.update(userDoc.ref, {
          total_points: admin.firestore.FieldValue.increment(extraPoints),
          bonus_points: admin.firestore.FieldValue.increment(extraPoints),
          updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
      }
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
// 🏆 ENCERRAMENTO E CÁLCULO DE MINI BOLÕES VIP
// ==================================================================
exports.calculateMiniBolaoPoints = onCall({ cors: true, timeoutSeconds: 540 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Acesso negado.');
  
  const adminDoc = await db.collection('admin_users').doc(request.auth.uid).get();
  if (!adminDoc.exists) throw new HttpsError('permission-denied', 'Apenas administradores podem calcular resultados.');

  const { miniBolaoId, realHomeScore, realAwayScore, realScorers, realLastGoalTeam } = request.data;
  
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
    const participantsSnap = await db.collection('bolao_mini_leagues').doc(miniBolaoId).collection('participants').get();

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
          points += 5; // Na Mosca
        } else if (pOutcome === realOutcome) {
          if (pDiff === realDiff) points += 3; // Saldo
          else points += 2; // Vencedor
        }
      }

      // 2. Cálculo de Artilheiros (Com checagem de frequência)
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

      // 3. Cálculo de Último Gol
      let lastGoalPoints = 0;
      if (pData.pred_last_goal_team && pData.pred_last_goal_team === realLastGoalTeam) {
        lastGoalPoints = 2;
        points += lastGoalPoints;
      }

      // Atualiza o participante
      batchHandler.update(partDoc.ref, {
        points: points,
        breakdown_scorers: scorersPoints,
        breakdown_last_goal: lastGoalPoints,
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      });
    });

    // Atualiza o status da Sala VIP
    const mbRef = db.collection('bolao_mini_leagues').doc(miniBolaoId);
    batchHandler.update(mbRef, {
      status: 'finished',
      is_active: false,
      real_score_home: realHome,
      real_score_away: realAway,
      real_scorers: realScorers || [],
      real_last_goal_team: realLastGoalTeam || '',
      finished_at: admin.firestore.FieldValue.serverTimestamp()
    });

    await batchHandler.commit();
    return { success: true, message: 'Ranking do Mini Bolão calculado com sucesso!' };

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