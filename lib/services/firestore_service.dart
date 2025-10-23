// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Função auxiliar para criar deltas de JOGADOR (continua igual)
  Map<String, int> _calculateDelta(Map<String, int> oldMap, Map<String, int> newMap) {
    Map<String, int> delta = {};
    newMap.forEach((key, newValue) {
      int oldValue = oldMap[key] ?? 0;
      if (newValue != oldValue) {
        delta[key] = newValue - oldValue;
      }
    });
    oldMap.forEach((key, oldValue) {
      if (!newMap.containsKey(key) && oldValue > 0) {
        delta[key] = -oldValue;
      }
    });
    return delta;
  }

  // --- FUNÇÃO DE ATUALIZAÇÃO (COM NOVOS CAMPOS) ---
  Future<String> updateMatchStats({
    required DocumentSnapshot matchSnapshot,
    required int newScoreHome,
    required int newScoreAway,
    required String newStatus,
    required Map<String, int> newGoals,
    required Map<String, int> newAssists,
    required Map<String, int> newYellows,
    required Map<String, int> newReds,
    required Map<String, int> newGoalsConceded,
    required String? newManOfTheMatchId,
  }) async {
    final String matchId = matchSnapshot.id;
    final matchData = matchSnapshot.data() as Map<String, dynamic>;
    final String homeTeamId = matchData['team_home_id'];
    final String awayTeamId = matchData['team_away_id'];

    try {
      await _firestore.runTransaction((transaction) async {
        
        // --- 1. LER JOGADORES e O JOGO ATUAL (LEITURA) ---
        final DocumentSnapshot freshMatchSnap = await transaction.get(_firestore.collection('matches').doc(matchId));
        final matchData = freshMatchSnap.data() as Map<String, dynamic>;
        
        Map<String, dynamic> oldStats = (matchData.containsKey('stats_applied') && matchData['stats_applied'] != null)
            ? (matchData['stats_applied'] ?? {})
            : {};
        Map<String, dynamic> oldPlayerStats = oldStats['player_stats'] ?? {};
        String? oldManOfTheMatchId = oldStats['man_of_the_match'];
        Map<String, int> oldGoalsConceded = Map<String, int>.from(oldPlayerStats['goals_conceded'] ?? {});
        
        // Pega todos os jogadores que podem ser afetados
        Set<String> playersToReadIds = {
          ...newGoals.keys, ...oldPlayerStats['goals']?.keys ?? [],
          ...newAssists.keys, ...oldPlayerStats['assists']?.keys ?? [],
          ...newYellows.keys, ...oldPlayerStats['yellows']?.keys ?? [],
          ...newReds.keys, ...oldPlayerStats['reds']?.keys ?? [],
          ...newGoalsConceded.keys, ...oldGoalsConceded.keys,
          if (newManOfTheMatchId != null) newManOfTheMatchId,
          if (oldManOfTheMatchId != null) oldManOfTheMatchId,
        };
        playersToReadIds.removeWhere((id) => id == null || id.isEmpty); // Limpa nulos

        Map<String, DocumentSnapshot> playerSnaps = {};
        for (String playerId in playersToReadIds) {
          if (playerId.isNotEmpty) {
             playerSnaps[playerId] = await transaction.get(_firestore.collection('players').doc(playerId));
          }
        }

        // --- 2. SALVAR O JOGO ATUAL (ESCRITA) ---
        final Map<String, dynamic> newPlayerStats = {
          'goals': newGoals,
          'assists': newAssists,
          'yellows': newYellows,
          'reds': newReds,
          'goals_conceded': newGoalsConceded, // <-- SALVA GOLS SOFRIDOS
        };
        
        transaction.update(_firestore.collection('matches').doc(matchId), {
          'score_home': newScoreHome,
          'score_away': newScoreAway,
          'status': newStatus,
          //'status': 'finished',
          'stats_applied': { 
            'player_stats': newPlayerStats,
            'man_of_the_match': newManOfTheMatchId, // <-- SALVA CRAQUE DO JOGO
          }
        });


        // --- 3. APLICAR DELTA NOS JOGADORES (ESCRITA) ---
        int disciplinaryHomeDelta = 0;
        int disciplinaryAwayDelta = 0;

        // Delta de Gols (sem mudança)
        Map<String, int> goalDelta = _calculateDelta(Map<String, int>.from(oldPlayerStats['goals'] ?? {}), newGoals);
        goalDelta.forEach((playerId, delta) {
          if(delta != 0 && playerSnaps.containsKey(playerId)) {
            transaction.update(_firestore.collection('players').doc(playerId), {'goals': FieldValue.increment(delta)});
          }
        });
        // Delta de Assistências (sem mudança)
        Map<String, int> assistDelta = _calculateDelta(Map<String, int>.from(oldPlayerStats['assists'] ?? {}), newAssists);
        assistDelta.forEach((playerId, delta) {
          if(delta != 0 && playerSnaps.containsKey(playerId)) {
            transaction.update(_firestore.collection('players').doc(playerId), {'assists': FieldValue.increment(delta)});
          }
        });
        // Delta de Cartões Amarelos (sem mudança)
        Map<String, int> yellowDelta = _calculateDelta(Map<String, int>.from(oldPlayerStats['yellows'] ?? {}), newYellows);
        yellowDelta.forEach((playerId, delta) {
          if(delta == 0 || !playerSnaps.containsKey(playerId)) return;
          final playerSnap = playerSnaps[playerId]!;
          final int currentYellows = (playerSnap.data() as Map<String, dynamic>).containsKey('yellow_cards') 
                                      ? playerSnap.get('yellow_cards') : 0;
          final int newTotalYellows = currentYellows + delta;
          bool suspend = (newTotalYellows % 3 == 0) && delta > 0;
          bool unsuspend = (currentYellows % 3 == 0) && delta < 0; 
          transaction.update(_firestore.collection('players').doc(playerId), {
            'yellow_cards': FieldValue.increment(delta),
            if (suspend) 'is_suspended': true,
            if (unsuspend) 'is_suspended': false,
          });
          if (playerSnap.get('team_id') == homeTeamId) {
            disciplinaryHomeDelta += (delta * 10);
          } else if (playerSnap.get('team_id') == awayTeamId) {
            disciplinaryAwayDelta += (delta * 10);
          }
        });
        // Delta de Cartões Vermelhos
        Map<String, int> redDelta = _calculateDelta(Map<String, int>.from(oldPlayerStats['reds'] ?? {}), newReds);
        redDelta.forEach((playerId, delta) {
          if(delta == 0 || !playerSnaps.containsKey(playerId)) return;
          final playerSnap = playerSnaps[playerId]!;
          transaction.update(_firestore.collection('players').doc(playerId), {
            'red_cards': FieldValue.increment(delta),
            'is_suspended': (delta > 0), 
          });
          if (playerSnap.get('team_id') == homeTeamId) {
            disciplinaryHomeDelta += (delta * 21);
          } else if (playerSnap.get('team_id') == awayTeamId) {
            // *** BUG CORRIGIDO AQUI ***
            disciplinaryAwayDelta += (delta * 21); // Antes estava 'disciplinaryHomeDelta'
          }
        });

        // --- NOVO: Delta de Gols Sofridos ---
        Map<String, int> goalsConcededDelta = _calculateDelta(oldGoalsConceded, newGoalsConceded);
        goalsConcededDelta.forEach((playerId, delta) {
          if(delta != 0 && playerSnaps.containsKey(playerId)) {
            // Atualiza o campo 'goals_conceded' no documento do jogador
            transaction.update(_firestore.collection('players').doc(playerId), {'goals_conceded': FieldValue.increment(delta)});
          }
        });
        // --- FIM DO DELTA ---
        
        // --- NOVO: Delta de Craque do Jogo ---
        if (oldManOfTheMatchId != newManOfTheMatchId) {
          // Remove do antigo
          if (oldManOfTheMatchId != null && playerSnaps.containsKey(oldManOfTheMatchId)) {
            transaction.update(
              _firestore.collection('players').doc(oldManOfTheMatchId),
              {'man_of_the_match_awards': FieldValue.increment(-1)}
            );
          }
          // Adiciona ao novo
          if (newManOfTheMatchId != null && playerSnaps.containsKey(newManOfTheMatchId)) {
            transaction.update(
              _firestore.collection('players').doc(newManOfTheMatchId),
              {'man_of_the_match_awards': FieldValue.increment(1)}
            );
          }
        }
        // --- FIM DO DELTA ---

        // Aplica o DELTA de pontos disciplinares (sem mudança)
        final homeTeamRef = _firestore.collection('teams').doc(homeTeamId);
        final awayTeamRef = _firestore.collection('teams').doc(awayTeamId);
        transaction.update(homeTeamRef, {'disciplinary_points': FieldValue.increment(disciplinaryHomeDelta)});
        transaction.update(awayTeamRef, {'disciplinary_points': FieldValue.increment(disciplinaryAwayDelta)});

      }); // Fim da Transação

      // --- PÓS-TRANSAÇÃO: RECALCULAR OS DOIS TIMES ---
      // (Esta parte continua igual)
      await _recalculateTeamStats(homeTeamId);
      await _recalculateTeamStats(awayTeamId);
      
      return "Sucesso";
    } catch (e) {
      debugPrint('Erro na transação: $e');
      return "Erro: ${e.toString()}";
    }
  }

  // --- FUNÇÃO DE RECALCULO TOTAL (POR TIME) ---
  // (Esta função permanece idêntica à que você forneceu, pois está correta)
  Future<void> _recalculateTeamStats(String teamId) async {
    // 1. Inicializa os totais
    int totalPoints = 0;
    int totalGames = 0;
    int totalWins = 0;
    int totalDraws = 0;
    int totalLosses = 0;
    int totalGoalsFor = 0;
    int totalGoalsAgainst = 0;

    // 2. Busca todos os jogos finalizados onde o time foi o TIME DA CASA
    final homeMatches = await _firestore
        .collection('matches')
        .where('team_home_id', isEqualTo: teamId)
        .where('status', isEqualTo: 'finished')
        .get();

    for (final doc in homeMatches.docs) {
      final data = doc.data();
      final scoreHome = (data['score_home'] ?? 0) as int;
      final scoreAway = (data['score_away'] ?? 0) as int;

      totalGames++;
      totalGoalsFor += scoreHome;
      totalGoalsAgainst += scoreAway;

      if (scoreHome > scoreAway) {
        totalPoints += 3;
        totalWins++;
      } else if (scoreHome < scoreAway) {
        totalLosses++;
      } else {
        totalPoints += 1;
        totalDraws++;
      }
    }

    // 3. Busca todos os jogos finalizados onde o time foi o TIME VISITANTE
    final awayMatches = await _firestore
        .collection('matches')
        .where('team_away_id', isEqualTo: teamId)
        .where('status', isEqualTo: 'finished')
        .get();

    for (final doc in awayMatches.docs) {
      final data = doc.data();
      final scoreHome = (data['score_home'] ?? 0) as int;
      final scoreAway = (data['score_away'] ?? 0) as int;

      totalGames++;
      totalGoalsFor += scoreAway;
      totalGoalsAgainst += scoreHome;

      if (scoreAway > scoreHome) {
        totalPoints += 3;
        totalWins++;
      } else if (scoreAway < scoreHome) {
        totalLosses++;
      } else {
        totalPoints += 1;
        totalDraws++;
      }
    }
    
    // 4. ATUALIZA O DOCUMENTO DO TIME
    await _firestore.collection('teams').doc(teamId).update({
      'points': totalPoints,
      'games_played': totalGames,
      'wins': totalWins,
      'draws': totalDraws,
      'losses': totalLosses,
      'goals_for': totalGoalsFor,
      'goals_against': totalGoalsAgainst,
      'goal_difference': totalGoalsFor - totalGoalsAgainst,
    });
  }
}