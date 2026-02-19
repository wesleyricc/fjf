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
  ptsGoal: 8.0,
  ptsAssist: 4.0,
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
  
  // 1. Verificação de Segurança (Apenas Admin pode chamar)
  // No seu app, o AdminService chama isso. Garanta que as Regras do Firestore
  // protejam a coleção 'admin_users' para que apenas admins reais tenham conta.
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Acesso negado. Faça login.');
  }

  const { seasonId, round } = request.data;
  if (!seasonId || !round) {
    throw new HttpsError('invalid-argument', 'SeasonId e Round são obrigatórios.');
  }

  try {
    // A. CONFIGURAÇÃO
    let config = DEFAULT_CONFIG;
    const configSnap = await db.collection('fantasy_config').doc('rules').get();
    if (configSnap.exists) {
      config = configSnap.data();
    }

    // B. SCOUTS: Busca partidas da rodada para calcular pontos
    const matchesSnap = await db.collection('championships')
        .doc(seasonId)
        .collection('matches')
        .where('round', '==', round)
        .get();

    const scoresMap = {}; // Map: PlayerID -> Pontos

    matchesSnap.forEach(doc => {
      const matchData = doc.data();
      const stats = matchData.stats_applied?.player_stats || {};
      
      const processStat = (map, multiplier) => {
        if (!map) return;
        Object.keys(map).forEach(pid => {
          const qtd = map[pid] || 0;
          scoresMap[pid] = (scoresMap[pid] || 0) + (qtd * multiplier);
        });
      };

      processStat(stats.goals, config.ptsGoal);
      processStat(stats.assists, config.ptsAssist);
      processStat(stats.yellows, config.ptsYellowCard);
      processStat(stats.reds, config.ptsRedCard);
      processStat(stats.goals_conceded, config.ptsGoalConceded);
    });

    // C. TÉCNICOS: Calcula média do time e atribui ao técnico
    const allPlayersSnap = await db.collection('fantasy_market_players').get();
    const teamScores = {};
    const coachMap = {}; // TeamID -> CoachID

    allPlayersSnap.forEach(doc => {
      const p = doc.data();
      // Mapeia técnicos
      if (p.position === 'Técnico' && p.team_id) {
        coachMap[p.team_id] = doc.id;
      } 
      // Agrupa pontuações por time
      else if (p.team_id && scoresMap[doc.id] !== undefined) {
        if (!teamScores[p.team_id]) teamScores[p.team_id] = [];
        teamScores[p.team_id].push(scoresMap[doc.id]);
      }
    });

    // Atribui média aos técnicos
    Object.keys(coachMap).forEach(teamId => {
      const scores = teamScores[teamId] || [];
      if (scores.length > 0) {
        const total = scores.reduce((a, b) => a + b, 0);
        const avg = total / scores.length;
        scoresMap[coachMap[teamId]] = Number(avg.toFixed(2));
      } else {
        scoresMap[coachMap[teamId]] = 0.0;
      }
    });

    // D. MERCADO: Atualiza preços e histórico dos jogadores
    const batchHandler = new BatchHandler(db);

    allPlayersSnap.forEach(doc => {
      const p = doc.data();
      const pid = doc.id;
      const score = scoresMap[pid] || 0.0;
      const currentPrice = Number(p.current_price || 0);

      // Algoritmo de Valorização
      const expectation = currentPrice * config.factorExpectation;
      const performance = score - expectation;
      let variation = performance * config.factorVariation;
      const limit = currentPrice * config.capLimitPercent;

      // Travas de variação
      if (variation > limit) variation = limit;
      if (variation < -limit) variation = -limit;

      let newPrice = currentPrice + variation;
      if (newPrice < config.minPrice) newPrice = config.minPrice;

      variation = Number(variation.toFixed(2));
      newPrice = Number(newPrice.toFixed(2));

      // Objeto de Histórico
      const historyEntry = {
        round: round,
        score: score,
        price_before: currentPrice,
        price_after: newPrice,
        variation: variation,
        played: (score !== 0), // Simplificação: se pontuou, jogou
        processed_at: admin.firestore.Timestamp.now()
      };

      // Update Player
      batchHandler.update(doc.ref, {
        current_price: newPrice,
        last_price_change: variation,
        last_score: score,
        history: admin.firestore.FieldValue.arrayUnion(historyEntry)
      });
    });

    // E. TIMES DOS USUÁRIOS: Calcula pontuação e atualiza patrimônio
    const userTeamsSnap = await db.collection('fantasy_teams').get();
    
    // Precisamos de um mapa rápido de preços NOVOS para atualizar o patrimônio
    // (Poderíamos ter salvo no passo D, mas recalculamos aqui ou buscamos novamente. 
    //  Para eficiência, assumimos o cálculo feito no passo D).
    // NOTA: Em produção, o ideal é salvar os novos preços em um Map<ID, Price> na memória durante o passo D.
    
    // Vamos fazer um "re-scan" rápido ou otimizar em memória se possível. 
    // Como Cloud Functions tem memória, vamos refazer o loop simples dos preços:
    const newPriceMap = {};
    allPlayersSnap.docs.forEach(doc => {
       const p = doc.data();
       const pid = doc.id;
       const score = scoresMap[pid] || 0.0;
       const currentPrice = Number(p.current_price || 0);
       
       const expectation = currentPrice * config.factorExpectation;
       const performance = score - expectation;
       let variation = performance * config.factorVariation;
       const limit = currentPrice * config.capLimitPercent;
       if (variation > limit) variation = limit;
       if (variation < -limit) variation = -limit;
       let newPrice = currentPrice + variation;
       if (newPrice < config.minPrice) newPrice = config.minPrice;
       
       newPriceMap[pid] = Number(newPrice.toFixed(2));
    });

    userTeamsSnap.forEach(doc => {
      const team = doc.data();
      let roundPoints = 0.0;
      let squadValue = 0.0;
      const lineup = team.lineup_player_ids || [];

      lineup.forEach(pid => {
        // Pontos
        let pScore = scoresMap[pid] || 0.0;
        if (team.captain_id === pid) pScore *= 2;
        roundPoints += pScore;

        // Valor do Time (soma dos novos preços dos jogadores)
        squadValue += (newPriceMap[pid] || 0.0);
      });

      // Patrimônio Total = Saldo em Caixa + Valor do Elenco
      const totalPatrimony = (team.current_balance || 0) + squadValue;

      // Update Time
      batchHandler.update(doc.ref, {
        total_points: (team.total_points || 0) + roundPoints,
        last_score: roundPoints,
        team_value: Number(totalPatrimony.toFixed(2))
      });
      
      // Salva Histórico da Rodada
      const histRef = doc.ref.collection('history').doc(String(round));
      batchHandler.set(histRef, {
        round: round,
        points: roundPoints,
        patrimony: Number(totalPatrimony.toFixed(2)),
        processed_at: admin.firestore.Timestamp.now(),
        captain_id: team.captain_id,
        lineup_snapshot: lineup
      });
    });

    await batchHandler.commit(); // Finaliza escritas pendentes

    return { 
      success: true, 
      message: `Rodada ${round} processada com sucesso.\nJogadores: ${allPlayersSnap.size}\nTimes: ${userTeamsSnap.size}` 
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