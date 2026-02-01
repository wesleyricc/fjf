const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { MercadoPagoConfig, Payment } = require("mercadopago");

admin.initializeApp();

const MP_ACCESS_TOKEN = "APP_USR-3797379599804379-013016-48576b74ed518f25f9190c9c29996f12-146749346"; 
const client = new MercadoPagoConfig({ accessToken: MP_ACCESS_TOKEN });

// ==================================================================
// 🛒 GERAÇÃO DE PIX PARA CARRINHO (Múltiplos Itens)
// ==================================================================
exports.createPixPayment = onCall({ cors: true }, async (request) => {
  // Recebe LISTA de IDs e o contato
  const { photoIds, customerContact } = request.data; 

  if (!photoIds || !Array.isArray(photoIds) || photoIds.length === 0) {
    throw new HttpsError('invalid-argument', 'O carrinho está vazio.');
  }

  const contactInfo = customerContact || "Não informado";
  // E-mail para o Mercado Pago (obrigatório)
  const payerEmail = contactInfo.includes('@') ? contactInfo : "cliente.anonimo@fjf.app";

  try {
    let totalPrice = 0.0;
    const itemsToSave = []; // Array que guardaremos no pedido final
    const descriptionItems = [];

    // 1. BUSCAR PREÇOS REAIS NO BANCO (Segurança crítica)
    // Usamos Promise.all para buscar tudo em paralelo (rápido)
    const promises = photoIds.map(id => admin.firestore().collection('photo_sales').doc(id).get());
    const snapshots = await Promise.all(promises);

    for (const snap of snapshots) {
      if (!snap.exists) continue; // Pula se alguma foto foi deletada
      
      const data = snap.data();
      const price = parseFloat(data.price);
      
      totalPrice += price;
      
      // Monta o objeto de entrega
      itemsToSave.push({
        photo_id: snap.id,
        original_url: data.original_url,
        event_name: data.event_name || 'Evento'
      });
      
      descriptionItems.push(snap.id.substring(0, 5)); // Apenas para log curto
    }

    if (totalPrice <= 0) {
      throw new HttpsError('failed-precondition', 'Erro ao calcular total. Tente novamente.');
    }

    // 2. GERAR PIX NO MERCADO PAGO
    const payment = new Payment(client);

    const paymentData = {
      transaction_amount: totalPrice,
      description: `Pack ${itemsToSave.length} Fotos FJF`, // Descrição resumida
      payment_method_id: 'pix',
      payer: {
        email: payerEmail,
        first_name: "Cliente FJF", 
      },
      metadata: {
        customer_contact: contactInfo,
        item_count: itemsToSave.length
      },
      date_of_expiration: new Date(Date.now() + 30 * 60 * 1000).toISOString() 
    };

    const response = await payment.create({ body: paymentData });
    
    if (!response || !response.point_of_interaction) {
      throw new HttpsError('internal', 'Erro ao comunicar com Mercado Pago.');
    }

    const ticketUrl = response.point_of_interaction.transaction_data.ticket_url;
    const qrCodeCopyPaste = response.point_of_interaction.transaction_data.qr_code;
    const mpPaymentId = response.id;

    // 3. SALVAR PEDIDO (Agora com array de 'items')
    await admin.firestore().collection('orders').doc(mpPaymentId.toString()).set({
      mp_payment_id: mpPaymentId,
      status: 'pending',
      amount: totalPrice,
      customer_contact: contactInfo,
      items: itemsToSave, // <--- AQUI ESTÁ O OURO: Lista com todos os links
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      qr_code_copy_paste: qrCodeCopyPaste,
      ticket_url: ticketUrl
    });

    return {
      success: true,
      pix_code: qrCodeCopyPaste,
      payment_id: mpPaymentId,
    };

  } catch (error) {
    console.error("Erro Cart Pix:", error);
    throw new HttpsError('internal', error.message);
  }
});


exports.handleMpWebhook = onRequest(async (req, res) => {
  try {
    // LOG DE DEBUG: Vamos ver exatamente o que o MP está mandando
    console.log("🔔 WEBHOOK RECEBIDO:", JSON.stringify(req.body));
    console.log("QUERY PARAMS:", JSON.stringify(req.query));

    // 1. Tenta extrair o ID de vários lugares possíveis
    let paymentId = req.body.data?.id || req.body.data?.id; // Formato Webhook Padrão
    
    // Se não achou, tenta formato antigo (IPN)
    if (!paymentId && req.query.id) {
       paymentId = req.query.id;
    }
    // Se ainda não achou, verifica se é uma notificação de tópico
    if (!paymentId && req.body.type === 'payment' && req.body.id) {
        paymentId = req.body.id;
    }

    if (!paymentId) {
      console.log("⚠️ Nenhuma ID de pagamento encontrada na requisição.");
      // Retorna 200 para o MP parar de chamar, pois não é um pagamento útil
      return res.status(200).send("No ID found");
    }

    console.log(`🔎 Verificando Pagamento ID: ${paymentId}`);

    // 2. Consulta a API do Mercado Pago para ter a verdade absoluta
    const payment = await new Payment(client).get({ id: paymentId });
    
    console.log(`💳 Status no MP: ${payment.status}`);

    if (payment.status === 'approved') {
      // 3. Atualiza no Firestore
      const orderRef = admin.firestore().collection('orders').doc(paymentId.toString());
      const orderSnap = await orderRef.get();

      if (!orderSnap.exists) {
        console.error(`❌ Pedido ${paymentId} não existe no Firestore.`);
        // Talvez o ID salvo no createPixPayment tenha sido diferente?
        return res.status(200).send("Order not found locally");
      }

      await orderRef.update({
        status: 'approved',
        approved_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log("✅ PEDIDO ATUALIZADO PARA APPROVED NO FIRESTORE!");
    }

    res.status(200).send("OK");

  } catch (error) {
    console.error("🔥 Erro CRÍTICO no Webhook:", error);
    // Retorna 500 para o Mercado Pago tentar de novo mais tarde se for erro de rede
    res.status(500).send("Internal Server Error");
  }
});