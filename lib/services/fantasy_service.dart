import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/fantasy_models.dart';

class FantasyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _fantasyTeamsRef => _firestore.collection('fantasy_teams');
  CollectionReference get _fantasyMarketRef => _firestore.collection('fantasy_market_players');
  
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

      return snapshot.docs
          .map((doc) => FantasyPlayer.fromFirestore(doc))
          .toList();
    } catch (e) {
      print("Erro ao buscar todos os jogadores: $e");
      return [];
    }
  }

  Future<List<FantasyPlayer>> getPlayersByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final snapshot = await _fantasyMarketRef
          .where(FieldPath.documentId, whereIn: ids)
          .get();
      return snapshot.docs.map((doc) => FantasyPlayer.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint("Erro ao buscar jogadores: $e");
      return [];
    }
  }

  Stream<List<FantasyTeam>> streamRanking({bool isGlobal = true}) {
    String orderByField = isGlobal ? 'total_points' : 'last_score';
    
    return _fantasyTeamsRef
        .orderBy(orderByField, descending: true)
        .limit(50) 
        .snapshots()
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
        list = list.where((p) => p.name.toLowerCase().contains(term) || 
                                 p.position.toLowerCase().contains(term)).toList();
      }
      return list;
    });
  }

  // --- OPERAÇÕES DO USUÁRIO ---

  Future<String> updateTeamProfile({
    required String userId,
    required String teamName,
    required String ownerName,
    required String shieldType,
    String? customLogoUrl, // <-- NOVO PARAMETRO
  }) async {
    try {
      await _fantasyTeamsRef.doc(userId).update({
        'team_name': teamName,
        'owner_name': ownerName,
        'shield_type': shieldType,
        'custom_logo_url': customLogoUrl, // <-- SALVA NO BANCO
      });
      return "Sucesso";
    } catch (e) {
      return "Erro ao atualizar perfil: $e";
    }
  }

  Future<void> createUserTeam({required String userId, required String userName, required String teamName}) async {
    final docSnap = await _fantasyTeamsRef.doc(userId).get();
    
    if (!docSnap.exists) {
      final newTeam = FantasyTeam(
        id: userId,
        ownerId: userId,
        userId: userId,
        shieldType: '1',
        ownerName: userName,
        teamName: teamName,
        totalPoints: 0,
        teamValue: 50,      
        currentBalance: 50, 
        lastScore: 0,
        lineupPlayerIds: [],
        captainId: null,
        customLogoUrl: null, // <-- INICIALIZA NULL
      );
      
      await _fantasyTeamsRef.doc(userId).set(newTeam.toMap());
    }
  }

  Future<String> saveLineup({
    required String userId,
    required List<String> playerIds,
    required String? captainId,
    required double totalCost,      
    required double currentBalance, 
  }) async {
    try {
      final double safeBalance = double.parse(currentBalance.toStringAsFixed(2));

      await _fantasyTeamsRef.doc(userId).update({
        'lineup_player_ids': playerIds, 
        'captain_id': captainId,
        'current_balance': safeBalance,
        'lineup': FieldValue.delete(), 
      });
      return "Sucesso";
    } catch (e) {
      return "Erro ao salvar: $e";
    }
  }

  // --- STATUS E RANKING ---

  Stream<Map<String, dynamic>> streamMarketStatus() {
    return _firestore.collection('fantasy_config').doc('status').snapshots().map((doc) {
      if (!doc.exists) return {'is_open': true, 'current_round': 1};
      return doc.data() as Map<String, dynamic>;
    });
  }

  Future<void> setMarketStatus({required bool isOpen, int? newRound}) async {
    final Map<String, dynamic> data = {'is_open': isOpen};
    if (newRound != null) data['current_round'] = newRound;
    await _firestore.collection('fantasy_config').doc('status').set(data, SetOptions(merge: true));
  }

  // --- ADMINISTRAÇÃO ---

  Future<String> populateMarketFromSeason(String seasonId) async {
    try {
      final WriteBatch batch = _firestore.batch();
      int count = 0;

      final playersSnap = await _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('player_stats')
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in playersSnap.docs) {
        final data = doc.data();
        
        final String staffRole = data['staff_role'] ?? '';
        final bool isTechnician = staffRole == 'Técnico';
        final String position = isTechnician ? 'Técnico' : (data['position'] ?? 'Desconhecido');
        
        final double initialPrice = 10.0;

        await _addToBatchIfNew(batch, doc.id, data, position, initialPrice);
        count++;
      }

      await batch.commit();
      return "Sucesso! $count registros verificados/adicionados.";
    } catch (e) {
      return "Erro ao popular mercado: $e";
    }
  }

  Future<void> _addToBatchIfNew(
      WriteBatch batch, String id, Map<String, dynamic> data, String position, double price) async {
    
    final marketDocRef = _fantasyMarketRef.doc(id);
    final marketDocSnap = await marketDocRef.get();

    if (!marketDocSnap.exists) {
      final Map<String, dynamic> playerData = {
        'name': data['name'] ?? 'Sem Nome',
        'position': position,
        'team_id': data['team_id'] ?? '',
        'team_shield_url': data['team_shield_url'] ?? '',
        'photo_url': data['photo_url'] ?? '',
        'current_price': price, 
        'last_price_change': 0.0,
        'last_score': 0.0,
        'average_score': 0.0,
        'matches_played': 0,
        'status': 'probable',
      };
      batch.set(marketDocRef, playerData);
    } else {
      batch.update(marketDocRef, {
        'name': data['name'],
        'photo_url': data['photo_url'],
        'team_id': data['team_id'],
        'team_shield_url': data['team_shield_url'],
      });
    }
  }
}