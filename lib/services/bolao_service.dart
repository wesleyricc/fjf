import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firestore_cache_service.dart';

import '../models/bolao_models.dart';

class BolaoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  List<BolaoMatch>? _cachedMatches;
  DateTime? _lastMatchesFetch;

  List<BolaoPrediction>? _cachedPredictions;
  DateTime? _lastPredictionsFetch;

  // ===========================================================================
  //   ARQUITETURA DE FILA RESILIENTE (OFFLINE / BACKGROUND)
  // ===========================================================================
  
  static final Map<String, Map<String, dynamic>> _pendingSaves = {};
  static Timer? _idleTimer;
  static bool _isCommitting = false;
  static const String _offlineQueueKey = 'bolao_offline_queue';

  /// Carrega palpites que ficaram travados no celular (por falta de internet ou crash)
  /// Deve ser chamado assim que o usuário faz login ou abre a tela do bolão.
  static Future<void> syncPendingPredictionsOnStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedData = prefs.getString(_offlineQueueKey);
      
      if (savedData != null && savedData.isNotEmpty) {
        final Map<String, dynamic> decoded = json.decode(savedData);
        if (decoded.isNotEmpty) {
          debugPrint("🔄 Recuperando ${decoded.length} palpites perdidos do cache local...");
          for (var entry in decoded.entries) {
            _pendingSaves[entry.key] = Map<String, dynamic>.from(entry.value);
          }
          // Dispara a sincronização
          commitPendingPredictions();
        }
      }
    } catch (e) {
      debugPrint("Erro ao recuperar fila offline: $e");
    }
  }

  /// Salva a fila de pendentes no armazenamento físico do aparelho
  static Future<void> _persistQueueLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_pendingSaves.isEmpty) {
        await prefs.remove(_offlineQueueKey);
      } else {
        await prefs.setString(_offlineQueueKey, json.encode(_pendingSaves));
      }
    } catch (e) {
      debugPrint("Erro ao persistir fila localmente: $e");
    }
  }

  Future<void> savePrediction(String userId, String matchId, int scoreHome, int scoreAway) async {
    // 1. Atualiza a UI imediatamente
    updateLocalPredictionCache(matchId, scoreHome, scoreAway);

    // 2. Anota no caderninho em memória
    _pendingSaves[matchId] = {
      'scoreHome': scoreHome,
      'scoreAway': scoreAway,
    };
    
    // 3. Salva no HD do celular IMEDIATAMENTE (Garantia contra Force Close)
    await _persistQueueLocally();
    
    debugPrint("📝 Palpite salvo localmente: $matchId | Total pendente: ${_pendingSaves.length}");

    // 4. Cancela o timer de inatividade se o utilizador continuar a digitar
    _idleTimer?.cancel();

    // 5. Se ele parar de mexer durante 3 SEGUNDOS, tentamos enviar para o servidor
    _idleTimer = Timer(const Duration(seconds: 3), () {
      commitPendingPredictions();
    });
  }

  // FUNÇÃO DE COMMIT BLINDADA (Tenta enviar e gerencia falhas)
  static Future<void> commitPendingPredictions() async {
    if (_pendingSaves.isEmpty || _isCommitting) return;
    
    _isCommitting = true;
    
    // Clonamos a fila para processamento
    final batch = Map<String, Map<String, dynamic>>.from(_pendingSaves);
    
    debugPrint("🚀 Iniciando envio de ${batch.length} palpites para a nuvem...");

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
        }).then((_) async {
          debugPrint("✅ $matchId guardado com sucesso na nuvem!");
          // SUCESSO: Removemos da fila em memória
          _pendingSaves.remove(matchId);
        }).catchError((e) {
          // FALHA: Mantemos na fila em memória para tentar de novo depois
          debugPrint("❌ Erro em $matchId (Será mantido na fila local): $e");
        })
      );
    }

    // Aguarda que todas as requisições paralelas terminem
    await Future.wait(futures);
    
    // Atualiza o HD do celular (apagando os que deram sucesso, mantendo os que falharam)
    await _persistQueueLocally();
    
    _isCommitting = false;
  }

  // ===========================================================================
  //   BUSCA DADOS DO USUÁRIO E RESTANTE CÓDIGO
  // ===========================================================================

  Stream<BolaoUser?> streamBolaoUser(String userId) {
    final docRef = _firestore.collection('bolao_users').doc(userId);
    final privateRef = docRef.collection('private').doc('info');
    
    // Aciona a sincronização residual toda vez que a tela do usuário carregar
    syncPendingPredictionsOnStartup();

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

  Stream<List<BolaoUser>> streamLeaderboard() async* {
    List<BolaoUser> mapUsers(QuerySnapshot snap) {
      final users = snap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>?;
        return BolaoUser.fromFirestore(d, data?['name'] ?? 'Participante');
      }).toList();
      
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
    }

    final query = _firestore.collection('bolao_users');
    const cacheKey = 'bolao_users_leaderboard';
    const ttl = Duration(minutes: 5);

    // 1. Emite o dado imediatamente via Cache (TTL: 5 min)
    final initialSnap = await FirestoreCacheService.getWithCache(
      query: query,
      cacheKey: cacheKey,
      ttl: ttl,
    );
    yield mapUsers(initialSnap);

    // 2. Continua emitindo atualizações a cada 5 minutos
    yield* Stream.periodic(ttl).asyncMap((_) async {
      final snap = await FirestoreCacheService.getWithCache(
        query: query,
        cacheKey: cacheKey,
        ttl: ttl,
        forceRefresh: true, 
      );
      return mapUsers(snap);
    });
  }

  Future<void> saveUserName(String userId, String name) async {
    await _firestore.collection('bolao_users').doc(userId).set({'name': name, 'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  
   // ===========================================================================
  //   CHAT DA RESENHA E PALPITES DA GALERA (RTDB e FIRESTORE)
  // ===========================================================================

  /// Escuta as mensagens de chat para um jogo em tempo real (Realtime Database)
  Stream<DatabaseEvent> streamMatchChat(String matchId) {
    return _rtdb.ref('match_chats/$matchId').orderByChild('timestamp').limitToLast(100).onValue;
  }

  /// Envia mensagem (RTDB) - Com suporte a Respostas (Reply)
  Future<void> sendChatMessage(
    String matchId, String userId, String userName, String photoUrl, String text,
    {String? replyToUserName, String? replyToText} // 🚨 NOVOS PARÂMETROS
  ) async {
    if (text.trim().isEmpty || text.length > 50) return;
    
    final Map<String, dynamic> payload = {
      'userId': userId,
      'userName': userName,
      'photoUrl': photoUrl,
      'text': text.trim(),
      'timestamp': ServerValue.timestamp,
    };

    // Só adiciona os campos de resposta se existirem
    if (replyToUserName != null && replyToText != null) {
      payload['replyToUserName'] = replyToUserName;
      payload['replyToText'] = replyToText;
    }

    await _rtdb.ref('match_chats/$matchId').push().set(payload);
  }

  /// Escuta as reações de emoji para os palpites de um jogo (RTDB)
  Stream<DatabaseEvent> streamMatchReactions(String matchId) {
    return _rtdb.ref('match_reactions/$matchId').onValue;
  }

  /// Liga ou desliga uma reação de emoji (RTDB)
  Future<void> toggleReaction(String matchId, String targetUserId, String reactorUserId, String emoji) async {
    final ref = _rtdb.ref('match_reactions/$matchId/$targetUserId/$reactorUserId');
    final snap = await ref.get();
    if (snap.exists && snap.value == emoji) {
      await ref.remove(); // Desmarca se já tinha clicado
    } else {
      await ref.set(emoji); // Marca
    }
  }

  /// Puxa do Firestore todos os palpites dos usuários para uma partida
  Future<List<Map<String, dynamic>>> getMatchPredictions(String matchId) async {
    try {
      // 1. Busca todos os usuários do Bolão de uma vez
      final usersSnap = await _firestore.collection('bolao_users').get();
      
      List<Map<String, dynamic>> results = [];
      
      // 2. Dispara a busca do palpite específico desse jogo para cada usuário SIMULTANEAMENTE.
      // O Future.wait faz as requisições acontecerem em paralelo, deixando a leitura ultra-rápida.
      await Future.wait(usersSnap.docs.map((userDoc) async {
        final predDoc = await userDoc.reference.collection('predictions').doc(matchId).get();
        
        if (predDoc.exists) {
          final userData = userDoc.data();
          final predData = predDoc.data()!;
          
          results.add({
            'userId': userDoc.id,
            'userName': userData['name'] ?? 'Treinador',
            'photoUrl': userData['photo_url'] ?? '',
            'scoreHome': predData['score_home'],
            'scoreAway': predData['score_away'],
            // 🚨 AQUI ESTÁ A CORREÇÃO! Repassando os pontos para a UI
            'points_earned': predData['points_earned'] ?? 0, 
          });
        }
      }));

      return results;
    } catch (e) {
      debugPrint("Erro ao buscar palpites do jogo: $e");
      return [];
    }
  }

  // ===========================================================================
  //   SISTEMA DE DUELOS PARTICULARES (X1)
  // ===========================================================================

  Future<void> sendDuelChallenge(String challengerId, String challengerName, String challengerPhoto, String challengedId, String challengedName, String challengedPhoto) async {
    // 1. Verifica se já existe duelo entre eles (ida ou volta) para não duplicar
    final query1 = await _firestore.collection('bolao_duels').where('challengerId', isEqualTo: challengerId).where('challengedId', isEqualTo: challengedId).get();
    final query2 = await _firestore.collection('bolao_duels').where('challengerId', isEqualTo: challengedId).where('challengedId', isEqualTo: challengerId).get();
    
    final allDocs = [...query1.docs, ...query2.docs];
    if (allDocs.any((d) => d['status'] != 'declined')) {
      throw Exception("Já existe um duelo ativo ou pendente com este treinador!");
    }

    // 2. Grava o desafio
    await _firestore.collection('bolao_duels').add({
      'challengerId': challengerId,
      'challengerName': challengerName,
      'challengerPhoto': challengerPhoto,
      'challengedId': challengedId,
      'challengedName': challengedName,
      'challengedPhoto': challengedPhoto,
      'status': 'pending', // pending, accepted, declined
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateDuelStatus(String duelId, String status) async {
    await _firestore.collection('bolao_duels').doc(duelId).update({'status': status});
  }

  // Lemos separadamente para garantir compatibilidade com qualquer versão do Flutter
  Stream<List<Map<String, dynamic>>> streamMySentDuels(String userId) {
    return _firestore.collection('bolao_duels').where('challengerId', isEqualTo: userId).snapshots().map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> streamMyReceivedDuels(String userId) {
    return _firestore.collection('bolao_duels').where('challengedId', isEqualTo: userId).snapshots().map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

}