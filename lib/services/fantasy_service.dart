import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'; 
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; 
import '../models/fantasy_models.dart';
import 'firestore_cache_service.dart';

class FantasyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance; 

  CollectionReference get _fantasyTeamsRef => _firestore.collection('fantasy_teams');
  CollectionReference get _fantasyMarketRef => _firestore.collection('fantasy_market_players');
  
  Future<bool> _isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<FantasyGameConfig> getGameConfig() async {
    try {
      final doc = await _firestore.collection('fantasy_config').doc('rules').get();
      if (doc.exists && doc.data() != null) {
        return FantasyGameConfig.fromMap(doc.data() as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint("Erro ao buscar config do fantasy (usando default): $e");
    }
    return FantasyGameConfig.defaults();
  }

  Future<void> saveGameConfig(FantasyGameConfig config) async {
    await _firestore.collection('fantasy_config').doc('rules').set(config.toMap());
  }

  // ---> OTIMIZAÇÃO DE CUSTO AQUI <---
  // Antes estava a buscar a coleção global inteira de 'players' (milhares de leituras)
  // Agora busca apenas os jogadores instanciados no mercado do Fantasy!
  Future<List<FantasyPlayer>> getAllPlayers({bool forceRefresh = false}) async {
    try {
      final snapshot = await FirestoreCacheService.getWithCache(
        query: _fantasyMarketRef,
        cacheKey: 'fantasy_market_players',
        ttl: const Duration(minutes: 5), // TTL morno (5 minutos)
        forceRefresh: forceRefresh,
      );
      if (snapshot.docs.isEmpty) return [];
      return snapshot.docs.map((doc) => FantasyPlayer.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint("Erro ao buscar todos os jogadores do mercado: $e");
      return [];
    }
  }

  Future<List<FantasyPlayer>> getPlayersByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final List<Future<QuerySnapshot>> futures = [];
      for (var i = 0; i < ids.length; i += 10) {
        final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
        futures.add(_fantasyMarketRef.where(FieldPath.documentId, whereIn: chunk).get());
      }
      
      final snapshots = await Future.wait(futures);
      final List<FantasyPlayer> allPlayers = [];
      for (var snap in snapshots) {
        allPlayers.addAll(snap.docs.map((doc) => FantasyPlayer.fromFirestore(doc)));
      }
      return allPlayers;
    } catch (e) {
      debugPrint("Erro ao buscar jogadores por IDs: $e");
      return [];
    }
  }

  Stream<List<FantasyTeam>> streamRanking({bool isGlobal = true, int limit = 20}) {
    String orderByField = isGlobal ? 'total_points' : 'last_score';
    return _fantasyTeamsRef.orderBy(orderByField, descending: true).limit(limit).snapshots()
        .map((snap) => snap.docs.map((doc) => FantasyTeam.fromFirestore(doc)).toList());
  }

  Stream<FantasyTeam?> streamMyTeam(String userId) {
    return _fantasyTeamsRef.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return FantasyTeam.fromFirestore(doc);
    });
  }

  Stream<List<FantasyPlayer>> streamMarket() {
    return _fantasyMarketRef
        .orderBy('current_price', descending: true)
        .limit(100) // Re-adicionado o limite para evitar excesso de reads do Firebase
        .snapshots()
        .map((snap) => snap.docs.map((doc) => FantasyPlayer.fromFirestore(doc)).toList());
  }

  Future<String> updateTeamProfile({
    required String userId, required String teamName, required String ownerName,
    required String shieldType, String? customLogoUrl,
  }) async {
    if (!await _isOnline()) return "Erro: Sem conexão com a internet."; 
    try {
      return await _firestore.runTransaction((transaction) async {
        final docRef = _fantasyTeamsRef.doc(userId);
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return "Erro: Time não encontrado.";

        transaction.update(docRef, {
          'team_name': teamName, 'owner_name': ownerName, 'shield_type': shieldType, 'custom_logo_url': customLogoUrl,
        });
        return "Sucesso";
      });
    } catch (e) { return "Erro ao atualizar perfil: $e"; }
  }

  Future<void> createUserTeam({required String userId, required String userName, required String teamName}) async {
    if (!await _isOnline()) return; 
    final docSnap = await _fantasyTeamsRef.doc(userId).get();
    
    if (!docSnap.exists) {
      final newTeam = FantasyTeam(
        id: userId, ownerId: userId, userId: userId, shieldType: '1',
        ownerName: userName, teamName: teamName, totalPoints: 0,
        teamValue: 50, currentBalance: 50, lastScore: 0,
        lineupPlayerIds: [], captainId: null, customLogoUrl: null,
      );
      await _fantasyTeamsRef.doc(userId).set(newTeam.toMap());
    }
  }

  Future<String> saveLineup({
    required String userId, required List<String> playerIds, required List<String> benchIds, 
    required String? captainId, required String? luxuryReserveId,
    required double expectedOldTeamCost, required double newTeamCost,
  }) async {
    if (!await _isOnline()) return "Erro: Sem conexão com a internet. O time não foi salvo."; 
    
    try {
      return await _firestore.runTransaction((transaction) async {
        final statusRef = _firestore.collection('fantasy_config').doc('status');
        final statusSnap = await transaction.get(statusRef);
        
        if (statusSnap.exists) {
          final bool isOpen = statusSnap.data()?['is_open'] ?? true;
          if (!isOpen) return "O Mercado está FECHADO. Não é possível salvar.";
        }

        final teamRef = _fantasyTeamsRef.doc(userId);
        final teamSnap = await transaction.get(teamRef);
        
        if (!teamSnap.exists) return "Erro: Time inexistente.";
        
        final double serverPatrimony = (teamSnap.data() as Map<String, dynamic>)['team_value'] ?? 0.0;
        final double actualNewBalance = serverPatrimony - newTeamCost;
        
        if (actualNewBalance < -0.01) { 
          return "Saldo insuficiente! Patrimônio: C\$${serverPatrimony.toStringAsFixed(2)} | Time: C\$${newTeamCost.toStringAsFixed(2)}";
        }

        final double safeBalance = double.parse(actualNewBalance.toStringAsFixed(2));

        transaction.update(teamRef, {
          'lineup_player_ids': playerIds, 
          'bench_player_ids': benchIds,
          'captain_id': captainId,
          'luxury_reserve_id': luxuryReserveId,
          'current_balance': safeBalance,
          'lineup': FieldValue.delete(), 
        });
        
        return "Sucesso";
      });
    } catch (e) { return "Erro ao salvar transação: $e"; }
  }

  Stream<Map<String, dynamic>> streamMarketStatus() {
    return _firestore.collection('fantasy_config').doc('status').snapshots().map((doc) {
      if (!doc.exists) return {'is_open': true, 'current_round': 1};
      return doc.data() as Map<String, dynamic>;
    });
  }

  Stream<QuerySnapshot> streamHistory(String userId) {
    return _firestore.collection('fantasy_teams').doc(userId).collection('history').orderBy('round', descending: true).snapshots();
  }

  Stream<DocumentSnapshot> streamGlobalScouts() {
    return _firestore.collection('fantasy_stats').doc('global_round_stats').snapshots();
  }

  Future<void> setMarketStatus(bool isOpen, int currentRound) async {
    if (!await _isOnline()) return;
    await _firestore.collection('fantasy_config').doc('status').set({
      'is_open': isOpen, 'current_round': currentRound, 'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> processRoundCloud(String seasonId, int round) async {
    if (!await _isOnline()) return "Erro: Sem internet. Não é possível chamar a Cloud Function."; 
    try {
      final HttpsCallable callable = _functions.httpsCallable('closeRound');
      final result = await callable.call(<String, dynamic>{'seasonId': seasonId, 'round': round});
      final data = result.data as Map<dynamic, dynamic>;
      
      if (data['success'] == true) return "Sucesso: ${data['message']}";
      else return "Erro no retorno da função: ${data['message'] ?? 'Desconhecido'}";
    } catch (e) {
      debugPrint("Erro ao chamar Cloud Function: $e");
      if (e is FirebaseFunctionsException) return "Erro Cloud (${e.code}): ${e.message}";
      return "Erro desconhecido: $e";
    }
  }

  Future<String> populateMarketFromSeason(String seasonId) async {
    if (!await _isOnline()) return "Erro de Conexão.";
    try {
      final WriteBatch batch = _firestore.batch();
      int count = 0;

      final playersSnap = await _firestore.collection('championships').doc(seasonId)
          .collection('player_stats').where('isActive', isEqualTo: true).get();

      // FINOPS: Busca todos os jogadores do mercado de uma vez para evitar loop de .get()
      final marketSnap = await _fantasyMarketRef.get();
      final Set<String> existingMarketIds = marketSnap.docs.map((doc) => doc.id).toSet();

      for (var doc in playersSnap.docs) {
        final data = doc.data();
        final bool isStaff = data['is_staff'] == true;
        final String staffRole = (data['staff_role'] ?? '').toString().trim();
        
        bool isHeadCoach = false;
        if (isStaff) {
          final roleLower = staffRole.toLowerCase();
          if (roleLower == 'técnico' || roleLower == 'tecnico' || roleLower == 'treinador' || roleLower.isEmpty) {
            isHeadCoach = true;
          }
          
          if (!isHeadCoach) {
            continue; // Ignora membros como Auxiliar, Massagista, etc.
          }
        }
        
        final String position = isHeadCoach ? 'Técnico' : (data['position'] ?? 'Desconhecido');
        final double initialPrice = 5.0;

        _addToBatchWithCache(batch, doc.id, data, position, initialPrice, existingMarketIds.contains(doc.id));
        count++;
      }

      await batch.commit();
      return "Sucesso! $count registros verificados/sincronizados.";
    } catch (e) { return "Erro ao popular mercado: $e"; }
  }

  void _addToBatchWithCache(WriteBatch batch, String id, Map<String, dynamic> data, String position, double price, bool exists) {
    final marketDocRef = _fantasyMarketRef.doc(id);

    if (!exists) {
      final Map<String, dynamic> playerData = {
        'name': data['name'] ?? 'Sem Nome', 'position': position, 'team_id': data['team_id'] ?? '',
        'team_shield_url': data['team_shield_url'] ?? '', 'photo_url': data['photo_url'] ?? '',
        'current_price': price, 'last_price_change': 0.0, 'last_score': 0.0, 'average_score': 0.0,
        'matches_played': 0, 'status': 'probable', 'history': [],
      };
      batch.set(marketDocRef, playerData);
    } else {
      batch.update(marketDocRef, {
        'name': data['name'], 'photo_url': data['photo_url'],
        'team_id': data['team_id'], 'team_shield_url': data['team_shield_url'],
        'position': position,
      });
    }
  }
}