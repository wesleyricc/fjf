import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart'; 
import '../models/bolao_models.dart';

class BolaoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  List<BolaoMatch>? _cachedMatches;
  DateTime? _lastMatchesFetch;

  List<BolaoPrediction>? _cachedPredictions;
  DateTime? _lastPredictionsFetch;

  // ===========================================================================
  // 🚀 ARQUITETURA "IDLE / EXIT" (Baseada no Fantasy)
  // ===========================================================================
  
  // O "Caderninho" que guarda tudo sem tentar enviar imediatamente
  static final Map<String, Map<String, dynamic>> _pendingSaves = {};
  static Timer? _idleTimer;
  static bool _isCommitting = false;

  Future<void> savePrediction(String userId, String matchId, int scoreHome, int scoreAway) async {
    // 1. Atualiza a UI imediatamente
    updateLocalPredictionCache(matchId, scoreHome, scoreAway);

    // 2. Anota no caderninho (sobrescreve se o utilizador mudar de ideias na mesma partida)
    _pendingSaves[matchId] = {
      'scoreHome': scoreHome,
      'scoreAway': scoreAway,
    };

    debugPrint("📝 Anotado no caderninho: $matchId | Total pendente: ${_pendingSaves.length}");

    // 3. Cancela o timer de inatividade se o utilizador continuar a digitar
    _idleTimer?.cancel();

    // 4. Se ele parar de mexer no telemóvel/rato durante 3 SEGUNDOS, nós guardamos tudo silenciosamente
    _idleTimer = Timer(const Duration(seconds: 3), () {
      commitPendingPredictions();
    });
  }

  // 🚨 FUNÇÃO PÚBLICA: Para ser chamada pelo Timer de inatividade OU quando o utilizador sai do ecrã
  static Future<void> commitPendingPredictions() async {
    if (_pendingSaves.isEmpty || _isCommitting) return;
    
    _isCommitting = true;
    
    // Copia o caderninho e rasga as folhas originais para recebermos novos dados
    final batch = Map<String, Map<String, dynamic>>.from(_pendingSaves);
    _pendingSaves.clear();

    debugPrint("🚀 [IDLE/EXIT] A enviar ${batch.length} palpites para o banco de dados...");

    // Dispara todas as Cloud Functions (Sem usar await no loop para enviar super rápido)
    final List<Future<void>> futures = [];

    for (var entry in batch.entries) {
      final matchId = entry.key;
      final data = entry.value;

      final callable = FirebaseFunctions.instance.httpsCallable('submitBolaoPrediction');
      futures.add(
        callable.call({
          'matchId': matchId,
          'scoreHome': data['scoreHome'],
          'scoreAway': data['scoreAway'],
        }).then((_) {
          debugPrint("✅ $matchId guardado com sucesso!");
        }).catchError((e) {
          debugPrint("❌ Erro em $matchId: $e");
        })
      );
    }

    // Aguarda que todas as requisições paralelas terminem
    await Future.wait(futures);
    _isCommitting = false;
  }

  // ===========================================================================
  // 🔄 BUSCA DADOS DO USUÁRIO E RESTANTE CÓDIGO
  // ===========================================================================
  Stream<BolaoUser?> streamBolaoUser(String userId) {
    final docRef = _firestore.collection('bolao_users').doc(userId);
    final privateRef = docRef.collection('private').doc('info'); 

    return docRef.snapshots().asyncMap((publicSnap) async {
      if (!publicSnap.exists) return null;

      final Map<String, dynamic> mergedData = Map<String, dynamic>.from(publicSnap.data() as Map<String, dynamic>);
      
      try {
        final privateSnap = await privateRef.get();
        if (privateSnap.exists && privateSnap.data() != null) {
          mergedData.addAll(privateSnap.data() as Map<String, dynamic>);
        }
      } catch (e) {
        debugPrint("LGPD: Leitura privada restrita.");
      }

      try {
        return BolaoUser.fromMap(userId, mergedData); 
      } catch (e) {
        return BolaoUser.fromFirestore(publicSnap, 'Utilizador');
      }
    });
  }

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
      throw Exception("Erro ao gerar PIX: $e");
    }
  }

  Future<List<BolaoMatch>> getMatches({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedMatches != null && _lastMatchesFetch != null) {
      if (DateTime.now().difference(_lastMatchesFetch!).inMinutes < 15) return _cachedMatches!;
    }
    final snap = await _firestore.collection('bolao_matches').orderBy('date').get();
    _cachedMatches = snap.docs.map((d) => BolaoMatch.fromFirestore(d)).toList();
    _lastMatchesFetch = DateTime.now();
    return _cachedMatches!;
  }

  Future<List<BolaoPrediction>> getMyPredictions(String userId, {bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedPredictions != null && _lastPredictionsFetch != null) {
      if (DateTime.now().difference(_lastPredictionsFetch!).inMinutes < 15) return _cachedPredictions!;
    }
    final snap = await _firestore.collection('bolao_users').doc(userId).collection('predictions').get();
    _cachedPredictions = snap.docs.map((d) => BolaoPrediction.fromMap(d.id, d.data())).toList();
    _lastPredictionsFetch = DateTime.now();
    return _cachedPredictions!;
  }

  void updateLocalPredictionCache(String matchId, int scoreHome, int scoreAway) {
    if (_cachedPredictions == null) return;
    final index = _cachedPredictions!.indexWhere((p) => p.matchId == matchId);
    if (index != -1) {
      _cachedPredictions![index] = BolaoPrediction(matchId: matchId, scoreHome: scoreHome, scoreAway: scoreAway, pointsEarned: _cachedPredictions![index].pointsEarned);
    } else {
      _cachedPredictions!.add(BolaoPrediction(matchId: matchId, scoreHome: scoreHome, scoreAway: scoreAway));
    }
  }

  Future<void> saveFullUserProfile(String userId, String name, String cpf, String phone, String? photoUrl) async {
    final Map<String, dynamic> publicData = {'name': name, 'updated_at': FieldValue.serverTimestamp()};
    if (photoUrl != null) publicData['photo_url'] = photoUrl;
    final Map<String, dynamic> privateData = {'cpf': cpf, 'phone': phone, 'updated_at': FieldValue.serverTimestamp()};

    final WriteBatch batch = _firestore.batch();
    final DocumentReference publicDocRef = _firestore.collection('bolao_users').doc(userId);
    final DocumentReference privateDocRef = publicDocRef.collection('private').doc('info');

    batch.set(publicDocRef, publicData, SetOptions(merge: true));
    batch.set(privateDocRef, privateData, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> saveBonusPrediction(String userId, String field, String value) async {
    await _firestore.collection('bolao_users').doc(userId).update({field: value});
  }

  Stream<List<BolaoUser>> streamLeaderboard() {
    return _firestore.collection('bolao_users').snapshots().map((snap) {
      final users = snap.docs.map((d) => BolaoUser.fromFirestore(d, d.data()['name'] ?? 'Participante')).toList();
      users.sort((a, b) {
        int cmp = b.totalPoints.compareTo(a.totalPoints);
        if (cmp != 0) return cmp;
        cmp = b.exactHits.compareTo(a.exactHits);
        if (cmp != 0) return cmp;
        cmp = b.goalDifferenceHits.compareTo(a.goalDifferenceHits);
        if (cmp != 0) return cmp;
        cmp = b.winnerHits.compareTo(a.winnerHits);
        if (cmp != 0) return cmp;
        return b.bonusPoints.compareTo(a.bonusPoints);
      });
      return users;
    });
  }

  Future<void> saveUserName(String userId, String name) async {
    await _firestore.collection('bolao_users').doc(userId).set({'name': name, 'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }
}