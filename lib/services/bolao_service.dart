import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/bolao_models.dart';

class BolaoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // 1. Verifica se o utilizador já pagou a taxa
  Stream<BolaoUser?> streamBolaoUser(String userId) {
    return _firestore.collection('bolao_users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return BolaoUser.fromFirestore(doc, 'Utilizador');
    });
  }

  // 2. Gera o PIX para a Inscrição
  Future<Map<String, dynamic>> generatePixForBolao(String userId, String email) async {
    try {
      final callable = _functions.httpsCallable('createPixPayment');
      final response = await callable.call({
        'type': 'bolao',
        'userId': userId,
        'customerContact': email,
      });
      
      return {
        'success': response.data['success'] ?? false,
        'pix_code': response.data['pix_code'],
        'payment_id': response.data['payment_id'],
      };
    } catch (e) {
      throw Exception("Erro ao gerar PIX do Bolão: $e");
    }
  }

  // 3. Buscar os Jogos da Copa (Ex: Primeira Fase)
  Stream<List<BolaoMatch>> streamMatches() {
    return _firestore
        .collection('bolao_matches')
        .orderBy('date')
        .snapshots()
        .map((snap) => snap.docs.map((d) => BolaoMatch.fromFirestore(d)).toList());
  }

  // 4. Buscar os Palpites de um Utilizador
  Stream<List<BolaoPrediction>> streamMyPredictions(String userId) {
    return _firestore
        .collection('bolao_users')
        .doc(userId)
        .collection('predictions')
        .snapshots()
        .map((snap) => snap.docs.map((d) => BolaoPrediction.fromMap(d.id, d.data())).toList());
  }

  // Salva o palpite de forma super segura usando Cloud Functions
  Future<void> savePrediction(String userId, String matchId, int scoreHome, int scoreAway) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('submitBolaoPrediction');
      await callable.call({
        'matchId': matchId,
        'scoreHome': scoreHome,
        'scoreAway': scoreAway,
      });
    } catch (e) {
      // Repassa o erro que vier do servidor (ex: "Mercado Fechado!")
      throw Exception(_parseFunctionError(e.toString()));
    }
  }

  // Salva o Perfil Completo do Treinador do Bolão
  Future<void> saveFullUserProfile(String userId, String name, String cpf, String phone, String? photoUrl) async {
    final Map<String, dynamic> data = {
      'name': name,
      'cpf': cpf,
      'phone': phone,
      'updated_at': FieldValue.serverTimestamp(),
    };
    
    // Só atualiza a foto se houver uma nova
    if (photoUrl != null) {
      data['photo_url'] = photoUrl;
    }

    await _firestore.collection('bolao_users').doc(userId).set(data, SetOptions(merge: true));
  }

  String _parseFunctionError(String error) {
    if (error.contains('deadline-exceeded') || error.contains('Mercado encerrado')) {
      return "Mercado encerrado para este jogo!";
    }
    return "Erro ao salvar palpite.";
  }

  // 6. Salvar um Palpite de Bónus
  Future<void> saveBonusPrediction(String userId, String field, String value) async {
    await _firestore.collection('bolao_users').doc(userId).update({
      field: value,
    });
  }

  // Busca todos os participantes e ordena por Pontos -> Placar Exato -> Saldo -> Vencedor -> Bônus
  Stream<List<BolaoUser>> streamLeaderboard() {
    return _firestore.collection('bolao_users').snapshots().map((snap) {
      final users = snap.docs.map((d) => BolaoUser.fromFirestore(d, d.data()['name'] ?? 'Participante')).toList();
      
      // Aplica os critérios de desempate em cascata solicitados
      users.sort((a, b) {
        // 1. Pontuação Total
        int cmp = b.totalPoints.compareTo(a.totalPoints);
        if (cmp != 0) return cmp;
        
        // 2. Quantidade de acertos exatos
        cmp = b.exactHits.compareTo(a.exactHits);
        if (cmp != 0) return cmp;
        
        // 3. Quantidade de acertos de saldo de gol
        cmp = b.goalDifferenceHits.compareTo(a.goalDifferenceHits);
        if (cmp != 0) return cmp;
        
        // 4. Quantidade de acertos de vencedores
        cmp = b.winnerHits.compareTo(a.winnerHits);
        if (cmp != 0) return cmp;
        
        // 5. Pontos extras
        return b.bonusPoints.compareTo(a.bonusPoints);
      });
      
      return users;
    });
  }

  // Salva ou atualiza o nome de exibição do usuário no Bolão
  Future<void> saveUserName(String userId, String name) async {
    await _firestore.collection('bolao_users').doc(userId).set({
      'name': name,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}