const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { MercadoPagoConfig, Payment } = require("mercadopago");

admin.initializeApp();

// ==================================================================
// CONFIGURAÇÕES GERAIS
// ==================================================================

// MERCADO PAGO
// Em produção, use: firebase functions:config:set mercadopago.token="SEU_TOKEN"
const MP_ACCESS_TOKEN = "APP_USR-3797379599804379-013016-48576b74ed518f25f9190c9c29996f12-146749346"; 
const client = new MercadoPagoConfig({ accessToken: MP_ACCESS_TOKEN });

// FANTASY GAME (Padrões de Pontuação e Economia)
const DEFAULT_CONFIG = {
  ptsGoal: 5.0,
  ptsAssist: 3.0,
  ptsYellowCard: -1.0,
  ptsRedCard: -3.0,
  ptsGoalConceded: -1.0,
  factorExpectation: 0.35, // Fator para cálculo de valorização
  factorVariation: 0.25,
  capLimitPercent: 0.25,   // Limite máximo de variação de preço (25%)
  minPrice: 1.0,
};

const db = admin.firestore();

// ==================================================================
// 🛒 MÓDULO DE PAGAMENTOS (PIX)
// ==================================================================

exports.createPixPayment = onCall({ cors: true }, async (request) => {
  const { photoIds, customerContact } = request.data; 

  if (!photoIds || !Array.isArray(photoIds) || photoIds.length === 0) {
    throw new HttpsError('invalid-argument', 'O carrinho está vazio.');
  }

  const contactInfo = customerContact || "Não informado";
  const payerEmail = contactInfo.includes('@') ? contactInfo : "cliente.anonimo@fjf.app";

  try {
    let totalPrice = 0.0;
    const itemsToSave = [];
    
    // Busca preços reais no banco para evitar fraude
    const promises = photoIds.map(id => db.collection('photo_sales').doc(id).get());
    const snapshots = await Promise.all(promises);

    for (const snap of snapshots) {
      if (!snap.exists) continue;
      const data = snap.data();
      totalPrice += parseFloat(data.price);
      itemsToSave.push({
        photo_id: snap.id,
        original_url: data.original_url,
        event_name: data.event_name || 'Evento'
      });
    }

    if (totalPrice <= 0) {
      throw new HttpsError('failed-precondition', 'Erro ao calcular total.');
    }

    // Criação no Mercado Pago
    const payment = new Payment(client);
    const paymentData = {
      transaction_amount: totalPrice,
      description: `Pack ${itemsToSave.length} Fotos FJF`,
      payment_method_id: 'pix',
      payer: { email: payerEmail, first_name: "Cliente FJF" },
      metadata: { customer_contact: contactInfo, item_count: itemsToSave.length },
      date_of_expiration: new Date(Date.now() + 30 * 60 * 1000).toISOString() 
    };

    const response = await payment.create({ body: paymentData });
    
    if (!response || !response.point_of_interaction) {
      throw new HttpsError('internal', 'Erro ao comunicar com Mercado Pago.');
    }

    const ticketUrl = response.point_of_interaction.transaction_data.ticket_url;
    const qrCodeCopyPaste = response.point_of_interaction.transaction_data.qr_code;
    const mpPaymentId = response.id;

    // Salva Pedido
    await db.collection('orders').doc(mpPaymentId.toString()).set({
      mp_payment_id: mpPaymentId,
      status: 'pending',
      amount: totalPrice,
      customer_contact: contactInfo,
      items: itemsToSave,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      qr_code_copy_paste: qrCodeCopyPaste,
      ticket_url: ticketUrl
    });

    return { success: true, pix_code: qrCodeCopyPaste, payment_id: mpPaymentId };

  } catch (error) {
    console.error("Erro Cart Pix:", error);
    throw new HttpsError('internal', error.message);
  }
});

exports.handleMpWebhook = onRequest(async (req, res) => {
  try {
    let paymentId = req.body.data?.id || req.body.data?.id;
    if (!paymentId && req.query.id) paymentId = req.query.id;
    if (!paymentId && req.body.type === 'payment' && req.body.id) paymentId = req.body.id;

    if (!paymentId) return res.status(200).send("No ID found");

    const payment = await new Payment(client).get({ id: paymentId });

    if (payment.status === 'approved') {
      const orderRef = db.collection('orders').doc(paymentId.toString());
      const orderSnap = await orderRef.get();

      if (orderSnap.exists) {
        const orderData = orderSnap.data();
        
        // Evita processar duplicado
        if (orderData.status !== 'approved') {
          await orderRef.update({
            status: 'approved',
            approved_at: admin.firestore.FieldValue.serverTimestamp(),
          });

          // Disparo de E-mail (Garante entrega mesmo se app fechado)
          const itemsListHtml = (orderData.items || []).map(item => 
              `<li><a href="${item.original_url}">Baixar Foto (${item.event_name})</a></li>`
          ).join('');

          await db.collection('mail').add({
            to: [orderData.customer_contact],
            message: {
              subject: 'Sua Compra FJF foi Aprovada! 📸',
              html: `
                <div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">
                  <h2 style="color: #4CAF50;">Pagamento Confirmado!</h2>
                  <p>Obrigado por sua compra. Seguem os links para download:</p>
                  <ul>${itemsListHtml}</ul>
                  <hr><p>Equipe FJF</p>
                </div>
              `,
            }
          });
          console.log("✅ Pedido aprovado e e-mail disparado.");
        }
      }
    }
    res.status(200).send("OK");
  } catch (error) {
    console.error("🔥 Erro Webhook:", error);
    res.status(500).send("Internal Server Error");
  }
});

// ==================================================================
// ⚽ MÓDULO FANTASY (Fechamento de Rodada Seguro)
// ==================================================================

exports.closeRound = onCall({ 
  cors: true, 
  timeoutSeconds: 540, // 9 minutos (máximo) para processar muitos times
  memory: '1GB'        // Mais memória para cálculos em lote
}, async (request) => {
  const { seasonId, round } = request.data;

  if (!seasonId || !round) {
    throw new HttpsError('invalid-argument', 'seasonId e round são obrigatórios.');
  }

  const db = admin.firestore();

  try {
    const configSnap = await db.collection('fantasy_config').doc('settings').get();
    const config = configSnap.exists ? { ...DEFAULT_CONFIG, ...configSnap.data() } : DEFAULT_CONFIG;

    const matchesSnap = await db.collection('championships').doc(seasonId)
      .collection('matches').where('round', '==', round).get();

    const scoresMap = {};

    matchesSnap.forEach(doc => {
      const data = doc.data();
      if (!data.stats_applied || !data.stats_applied.player_stats) return;

      const stats = data.stats_applied.player_stats;
      const ptsRules = {
        goals: config.ptsGoal,
        assists: config.ptsAssist,
        yellows: config.ptsYellowCard,
        reds: config.ptsRedCard,
        goals_conceded: config.ptsGoalConceded
      };

      ['goals', 'assists', 'yellows', 'reds', 'goals_conceded'].forEach(cat => {
        if (stats[cat]) {
          Object.entries(stats[cat]).forEach(([pid, val]) => {
            const points = (Number(val) || 0) * (ptsRules[cat] || 0);
            scoresMap[pid] = (scoresMap[pid] || 0) + points;
          });
        }
      });
    });

    console.log(`--- 🔍 CALCULANDO MÉDIA DOS TÉCNICOS (R${round}) ---`);
    const allPlayersSnap = await db.collection('fantasy_market_players').get();
    
    const teamScores = {};    
    const teamLogDetails = {}; 
    const teamCoaches = {};   

    allPlayersSnap.forEach(doc => {
      const p = doc.data();
      const pid = doc.id;
      const teamId = p.team_id; // Ajustado para snake_case

      if (!teamId) return;

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
        console.log(`[MÉDIA TÉCNICO] Time: ${tId} | Scores: ${scores} | Quantidade: ${scores.length} | Total: ${total} | Participantes: ${teamLogDetails[tId].join(' | ')} | Média: ${scoresMap[coachPid]}`);
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
      const currentPrice = p.current_price || config.minPrice; // Ajustado: current_price

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

    // --- ATUALIZAÇÃO DOS TIMES USANDO SNAKE_CASE ---
    const userTeamsSnap = await db.collection('fantasy_teams').get();
    userTeamsSnap.forEach(doc => {
      const team = doc.data();
      const lineup = team.lineup_player_ids || []; // Ajustado: lineup_player_ids
      const captainId = team.captain_id || null;    // Ajustado: captain_id (Garante null se vazio)

      let roundPoints = 0;
      let playersCurrentValue = 0;

      lineup.forEach(pid => {
        let pScore = scoresMap[pid] || 0;
        if (pid === captainId) pScore *= 2;
        roundPoints += pScore;
        playersCurrentValue += (newPricesMap[pid] || config.minPrice);
      });

      const currentBalance = team.current_balance || 0; // Ajustado: current_balance
      const totalPatrimony = Number((currentBalance + playersCurrentValue).toFixed(2));

      const teamHistoryRef = doc.ref.collection('history').doc(round.toString());
      
      batchHandler.set(teamHistoryRef, {
        round: round,
        points: roundPoints,
        patrimony: totalPatrimony,
        processed_at: admin.firestore.Timestamp.now(),
        captain_id: captainId, 
        lineup_snapshot: lineup // Ajustado: lineup_snapshot
      });

      batchHandler.update(doc.ref, {
        total_points: Number(((team.total_points || 0) + roundPoints).toFixed(2)), // Ajustado: total_points
        last_score: roundPoints,                                                   // Ajustado: last_score
        team_value: totalPatrimony,                                                // Ajustado: team_value
        updated_at: admin.firestore.Timestamp.now()                                 // Ajustado: updated_at
      });
    });

    await batchHandler.commit();

    return { 
      success: true, 
      message: `Rodada ${round} finalizada com sucesso (snake_case padrão).` 
    };

  } catch (error) {
    console.error("Erro closeRound:", error);
    throw new HttpsError('internal', error.message);
  }
});


// ==================================================================
// UTILS: Batch Handler (Para lidar com limite de 500 writes)
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
    if (this.count >= 490) { // Margem de segurança para o limite de 500
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