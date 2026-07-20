import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/player_model.dart';

class PlayerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference getPlayerStatsRef(String seasonId) {
    return _firestore.collection('championships').doc(seasonId).collection('player_stats');
  }

  // --- LEITURA ---

  Stream<List<Player>> streamPlayers(String seasonId, {String? teamId}) {
    Query query = getPlayerStatsRef(seasonId).where('isActive', isEqualTo: true);
    if (teamId != null) query = query.where('team_id', isEqualTo: teamId);
    return query.snapshots().map((snapshot) {
      final players = snapshot.docs.map((doc) => Player.fromFirestore(doc)).toList();
      players.sort((a, b) => (a.name).compareTo(b.name));
      return players;
    });
  }

  Future<Player?> getPlayer(String playerId, String seasonId) async {
    final doc = await getPlayerStatsRef(seasonId).doc(playerId).get();
    if (!doc.exists) return null;
    return Player.fromFirestore(doc);
  }

  // --- ESCRITA ---

  Future<String> createPlayer({required String seasonId, required Map<String, dynamic> data}) async {
    try {
      // Cria na coleção global (opcional) e na temporada
      final globalRef = await _firestore.collection('players').add({
        ...data,
        'isActive': true,
        'goals': 0, 'assists': 0, 'yellow_cards': 0, 'red_cards': 0,
        'total_yellow_cards': 0, 'total_red_cards': 0
      });
      
      await getPlayerStatsRef(seasonId).doc(globalRef.id).set({
        ...data,
        'isActive': true,
        'goals': 0, 'assists': 0, 'yellow_cards': 0, 'red_cards': 0,
        'total_yellow_cards': 0, 'total_red_cards': 0,
        'man_of_the_match_awards': 0, 'goals_conceded': 0,
        'is_suspended': false
      });
      return globalRef.id;
    } catch (e) {
      throw "Erro ao criar jogador: $e";
    }
  }

  Future<String> updatePlayer({required String seasonId, required String playerId, required Map<String, dynamic> data}) async {
    try {
      // Atualiza global
      await _firestore.collection('players').doc(playerId).update(data);
      // Atualiza temporada (com merge para não perder stats)
      await getPlayerStatsRef(seasonId).doc(playerId).set(data, SetOptions(merge: true));
      return "Sucesso: Jogador atualizado.";
    } catch (e) {
      return "Erro ao atualizar jogador: $e";
    }
  }

  Future<String> deletePlayer(DocumentSnapshot doc, String seasonId) async {
    try {
      await _firestore.collection('players').doc(doc.id).update({'isActive': false});
      try {
        await getPlayerStatsRef(seasonId).doc(doc.id).update({'isActive': false});
      } catch (_) {}
      
      // Inativar acesso ao portal (Deletando o documento em portal_users bloqueia o acesso via Rules)
      try {
        final portalUserQuery = await _firestore.collection('portal_users').where('playerId', isEqualTo: doc.id).get();
        for (var portalDoc in portalUserQuery.docs) {
          await portalDoc.reference.delete();
        }
      } catch (e) {
        debugPrint("Aviso: Falha ao remover acesso do portal: $e");
      }
      
      return "Sucesso: Jogador inativado.";
    } catch (e) {
      return "Erro: $e";
    }
  }

  // --- CÁLCULO ---

  Future<void> recalculatePlayerStats(String playerId, String seasonId) async {
    final matchesRef = _firestore.collection('championships').doc(seasonId).collection('matches');
    
    final query = await matchesRef.where('status', whereIn: ['finished', 'in_progress']).get();
    
    int goals = 0;
    int assists = 0;
    int totalYellows = 0;
    int totalReds = 0;
    int conceded = 0;
    int motm = 0;

    for (var doc in query.docs) {
      final data = doc.data();
      final stats = data['stats_applied']?['player_stats'];
      final matchMotm = data['stats_applied']?['man_of_the_match'];

      if (stats != null) {
         goals += (stats['goals']?[playerId] as int?) ?? 0;
         assists += (stats['assists']?[playerId] as int?) ?? 0;
         totalYellows += (stats['yellows']?[playerId] as int?) ?? 0;
         totalReds += (stats['reds']?[playerId] as int?) ?? 0;
         conceded += (stats['goals_conceded']?[playerId] as int?) ?? 0;
      }
      if (matchMotm == playerId) motm++;
    }

    await getPlayerStatsRef(seasonId).doc(playerId).update({
      'goals': goals,
      'assists': assists,
      'total_yellow_cards': totalYellows, 
      'total_red_cards': totalReds,
      'red_cards': totalReds, // Simplificação
      'goals_conceded': conceded,
      'man_of_the_match_awards': motm,
    });
  }
}