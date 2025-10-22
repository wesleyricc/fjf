// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Função auxiliar para criar deltas de JOGADOR (ainda precisamos dela)
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

  // --- FUNÇÃO DE REBUILD TOTAL ---
  Future<String> updateMatchStats({
    required DocumentSnapshot matchSnapshot,
    required int newScoreHome,
    required int newScoreAway,
    required Map<String, int> newGoals,
    required Map<String, int> newAssists,
    required Map<String, int> newYellows,
    required Map<String, int> newReds,
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
        
        // Pega as estatísticas antigas dos jogadores (para calcular o delta)
        Map<String, dynamic> oldPlayerStats = (matchData.containsKey('stats_applied') && matchData['stats_applied'] != null)
            ? (matchData['stats_applied']['player_stats'] ?? {})
            : {};
        
        // Pega todos os jogadores que podem ser afetados
        Set<String> playersToReadIds = {
          ...newGoals.keys, ...oldPlayerStats['goals']?.keys ?? [],
          ...newAssists.keys, ...oldPlayerStats['assists']?.keys ?? [],
          ...newYellows.keys, ...oldPlayerStats['yellows']?.keys ?? [],
          ...newReds.keys, ...oldPlayerStats['reds']?.keys ?? [],
        };
        Map<String, DocumentSnapshot> playerSnaps = {};
        for (String playerId in playersToReadIds) {
          if (playerId.isNotEmpty) {
             playerSnaps[playerId] = await transaction.get(_firestore.collection('players').doc(playerId));
          }
        }

        // --- 2. SALVAR O JOGO ATUAL (ESCRITA) ---
        // Salva as novas estatísticas de JOGADOR neste jogo
        final Map<String, dynamic> newPlayerStats = {
          'goals': newGoals,
          'assists': newAssists,
          'yellows': newYellows,
          'reds': newReds,
        };
        // Salva o placar, status e as estatísticas dos jogadores
        transaction.update(_firestore.collection('matches').doc(matchId), {
          'score_home': newScoreHome,
          'score_away': newScoreAway,
          'status': 'finished',
          'stats_applied': { 'player_stats': newPlayerStats } // Não salvamos mais team_stats
        });


        // --- 3. APLICAR DELTA NOS JOGADORES (ESCRITA) ---
        // (Esta lógica está correta e não causa o bug da classificação)
        
        int disciplinaryHomeDelta = 0;
        int disciplinaryAwayDelta = 0;

        // Delta de Gols
        Map<String, int> goalDelta = _calculateDelta(Map<String, int>.from(oldPlayerStats['goals'] ?? {}), newGoals);
        goalDelta.forEach((playerId, delta) {
          if(delta != 0 && playerSnaps.containsKey(playerId)) {
            transaction.update(_firestore.collection('players').doc(playerId), {'goals': FieldValue.increment(delta)});
          }
        });
        // Delta de Assistências
        Map<String, int> assistDelta = _calculateDelta(Map<String, int>.from(oldPlayerStats['assists'] ?? {}), newAssists);
        assistDelta.forEach((playerId, delta) {
          if(delta != 0 && playerSnaps.containsKey(playerId)) {
            transaction.update(_firestore.collection('players').doc(playerId), {'assists': FieldValue.increment(delta)});
          }
        });
        // Delta de Cartões Amarelos
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
            disciplinaryHomeDelta += (delta * 21);
          }
        });

        // Aplica o DELTA de pontos disciplinares (Esta parte está correta)
        final homeTeamRef = _firestore.collection('teams').doc(homeTeamId);
        final awayTeamRef = _firestore.collection('teams').doc(awayTeamId);
        transaction.update(homeTeamRef, {'disciplinary_points': FieldValue.increment(disciplinaryHomeDelta)});
        transaction.update(awayTeamRef, {'disciplinary_points': FieldValue.increment(disciplinaryAwayDelta)});

        // --- 4. RECALCULAR ESTATÍSTICAS DOS TIMES (A GRANDE MUDANÇA) ---
        // Esta parte agora acontece FORA da transação principal, pois
        // ler muitos documentos dentro de uma transação pode falhar.
        // Chamaremos uma função separada.

      });

      // --- PÓS-TRANSAÇÃO: RECALCULAR OS DOIS TIMES ---
      // Como a transação foi bem-sucedida, agora disparamos o recálculo.
      // Isso é "eventualmente consistente", mas muito mais seguro.
      await _recalculateTeamStats(homeTeamId);
      await _recalculateTeamStats(awayTeamId);
      
      return "Sucesso";
    } catch (e) {
      debugPrint('Erro na transação: $e');
      return "Erro: ${e.toString()}";
    }
  }

  // --- NOVA FUNÇÃO DE RECALCULO TOTAL (POR TIME) ---
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
    
    // --- 4. ATUALIZA O DOCUMENTO DO TIME (CORRIGIDO) ---
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