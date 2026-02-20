import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'; 
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // <-- NOVO
import '../models/fantasy_models.dart';

class FantasyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance; 

  CollectionReference get _fantasyTeamsRef => _firestore.collection('fantasy_teams');
  CollectionReference get _fantasyMarketRef => _firestore.collection('fantasy_market_players');
  
  // --- HELPERS DE CONECTIVIDADE ---
  Future<bool> _isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  // --- CONFIGURAÇÃO DO JOGO ---

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

  // --- LEITURA DE DADOS ---
  
  Future<List<FantasyPlayer>> getAllPlayers() async {
    try {
      final snapshot = await _firestore.collection('players').get();
      if (snapshot.docs.isEmpty) return [];
      return snapshot.docs.map((doc) => FantasyPlayer.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint("Erro ao buscar todos os jogadores: $e");
      return [];
    }
  }

  Future<List<FantasyPlayer>> getPlayersByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      if (ids.length > 10) {
        final futures = ids.map((id) => _fantasyMarketRef.doc(id).get());
        final snapshots = await Future.wait(futures);
        return snapshots.where((doc) => doc.exists).map((doc) => FantasyPlayer.fromFirestore(doc)).toList();
      }

      final snapshot = await _fantasyMarketRef.where(FieldPath.documentId, whereIn: ids).get();
      return snapshot.docs.map((doc) => FantasyPlayer.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint("Erro ao buscar jogadores por IDs: $e");
      return [];
    }
  }

  Stream<List<FantasyTeam>> streamRanking({bool isGlobal = true}) {
    String orderByField = isGlobal ? 'total_points' : 'last_score';
    return _fantasyTeamsRef.orderBy(orderByField, descending: true).limit(50).snapshots()
        .map((snap) => snap.docs.map((doc) => FantasyTeam.fromFirestore(doc)).toList());
  }

  Stream<FantasyTeam?> streamMyTeam(String userId) {
    return _fantasyTeamsRef.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return FantasyTeam.fromFirestore(doc);
    });
  }

  // --- MERCADO OTIMIZADO ---
  Stream<List<FantasyPlayer>> streamMarket({String? positionFilter, String? searchTerm}) {
    Query query = _fantasyMarketRef.orderBy('current_price', descending: true);
    if (positionFilter != null && positionFilter != 'Todos') {
      query = query.where('position', isEqualTo: positionFilter);
    }
    query = query.limit(100);

    return query.snapshots().map((snap) {
      var list = snap.docs.map((doc) => FantasyPlayer.fromFirestore(doc)).toList();
      if (searchTerm != null && searchTerm.isNotEmpty) {
        final term = searchTerm.toLowerCase();
        list = list.where((p) => p.name.toLowerCase().contains(term) || p.position.toLowerCase().contains(term)).toList();
      }
      return list;
    });
  }

  // --- OPERAÇÕES DO USUÁRIO ---

  Future<String> updateTeamProfile({
    required String userId, required String teamName, required String ownerName,
    required String shieldType, String? customLogoUrl,
  }) async {
    if (!await _isOnline()) return "Erro: Sem conexão com a internet."; // <-- NOVO
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
    if (!await _isOnline()) return; // <-- NOVO
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

  // Lógica de Salvar Time com Transação Segura
  Future<String> saveLineup({
    required String userId, required List<String> playerIds, required String? captainId,
    required double expectedOldTeamCost, required double newTeamCost,
  }) async {
    if (!await _isOnline()) return "Erro: Sem conexão com a internet. O time não foi salvo."; // <-- NOVO
    
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
          'captain_id': captainId,
          'current_balance': safeBalance,
          'lineup': FieldValue.delete(), 
        });
        
        return "Sucesso";
      });
    } catch (e) { return "Erro ao salvar transação: $e"; }
  }

  // --- STATUS E ADMINISTRAÇÃO (COM CLOUD FUNCTIONS) ---

  Stream<Map<String, dynamic>> streamMarketStatus() {
    return _firestore.collection('fantasy_config').doc('status').snapshots().map((doc) {
      if (!doc.exists) return {'is_open': true, 'current_round': 1};
      return doc.data() as Map<String, dynamic>;
    });
  }

  Future<void> setMarketStatus(bool isOpen, int currentRound) async {
    if (!await _isOnline()) return;
    await _firestore.collection('fantasy_config').doc('status').set({
      'is_open': isOpen, 'current_round': currentRound, 'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> processRoundCloud(String seasonId, int round) async {
    if (!await _isOnline()) return "Erro: Sem internet. Não é possível chamar a Cloud Function."; // <-- NOVO
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

  // --- SINCRONIZAÇÃO DE MERCADO ---

  Future<String> populateMarketFromSeason(String seasonId) async {
    if (!await _isOnline()) return "Erro de Conexão.";
    try {
      final WriteBatch batch = _firestore.batch();
      int count = 0;

      final playersSnap = await _firestore.collection('championships').doc(seasonId)
          .collection('player_stats').where('isActive', isEqualTo: true).get();

      for (var doc in playersSnap.docs) {
        final data = doc.data();
        final String staffRole = data['staff_role'] ?? '';
        final bool isTechnician = staffRole == 'Técnico';
        final String position = isTechnician ? 'Técnico' : (data['position'] ?? 'Desconhecido');
        final double initialPrice = 5.0; 

        await _addToBatchIfNew(batch, doc.id, data, position, initialPrice);
        count++;
      }

      await batch.commit();
      return "Sucesso! $count registros verificados/sincronizados.";
    } catch (e) { return "Erro ao popular mercado: $e"; }
  }

  Future<void> _addToBatchIfNew(WriteBatch batch, String id, Map<String, dynamic> data, String position, double price) async {
    final marketDocRef = _fantasyMarketRef.doc(id);
    final marketDocSnap = await marketDocRef.get();

    if (!marketDocSnap.exists) {
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
      });
    }
  }
}