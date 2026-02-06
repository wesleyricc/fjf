import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/fantasy_models.dart';

class FantasyAdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- TABELA DE PONTUAÇÃO ---
  static const double PTS_GOAL = 5.0;
  static const double PTS_ASSIST = 3.0;
  static const double PTS_YELLOW_CARD = -1.0;
  static const double PTS_RED_CARD = -3.0;
  static const double PTS_GOAL_CONCEDED = -1.0; 

  // --- CONSTANTES DA ECONOMIA ---
  static const double FACTOR_EXPECTATION = 0.35; 
  static const double FACTOR_VARIATION = 0.25;   
  static const double CAP_LIMIT_PERCENT = 0.25;  
  static const double MIN_PRICE = 1.0;           

  // --- 0. LEITURA DOS SCOUTS ---
  Future<Map<String, double>> _fetchSeasonScores(String seasonId, int round) async {
    final Map<String, double> scoresMap = {};
    debugPrint("--- LENDO SCOUTS R$round (Temporada $seasonId) ---");

    try {
      final matchesRef = _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('matches')
          .where('round', isEqualTo: round); 
      
      final matchesSnap = await matchesRef.get();

      for (var matchDoc in matchesSnap.docs) {
        final data = matchDoc.data();
        if (data['stats_applied'] == null) continue;

        final statsApplied = data['stats_applied'] as Map<String, dynamic>;
        final playerStats = statsApplied['player_stats'] as Map<String, dynamic>? ?? {};

        Map<String, int> getStatMap(String key) => _safeCastMap(playerStats[key]);

        final goalsMap = getStatMap('goals');
        final assistsMap = getStatMap('assists');
        final yellowsMap = getStatMap('yellows');
        final redsMap = getStatMap('reds');
        final concededMap = getStatMap('goals_conceded'); 

        final Set<String> allPlayerIds = {
          ...goalsMap.keys, ...assistsMap.keys, ...yellowsMap.keys, 
          ...redsMap.keys, ...concededMap.keys
        };

        for (String pid in allPlayerIds) {
          double points = 0.0;
          points += (goalsMap[pid] ?? 0) * PTS_GOAL;
          points += (assistsMap[pid] ?? 0) * PTS_ASSIST;
          points += (yellowsMap[pid] ?? 0) * PTS_YELLOW_CARD;
          points += (redsMap[pid] ?? 0) * PTS_RED_CARD;
          points += (concededMap[pid] ?? 0) * PTS_GOAL_CONCEDED;
          
          scoresMap[pid] = (scoresMap[pid] ?? 0.0) + points;
        }
      }
    } catch (e) {
      debugPrint("Erro scouts: $e");
    }
    return scoresMap;
  }

  Map<String, int> _safeCastMap(dynamic rawMap) {
    if (rawMap == null || rawMap is! Map) return {};
    return rawMap.map((key, value) => MapEntry(key.toString(), (value is num) ? value.toInt() : 0));
  }

  // --- 1. LÓGICA DE CÁLCULO DE PREÇO E HISTÓRICO ---
  
  Map<String, dynamic> _calculateNewPriceState(
    double currentPrice, 
    double score, 
    bool played, 
    int round
  ) {
    // 1. VALORIZAÇÃO
    double expectation = currentPrice * FACTOR_EXPECTATION;
    double performance = score - expectation;
    double rawVariation = performance * FACTOR_VARIATION;
    double limit = currentPrice * CAP_LIMIT_PERCENT;

    double finalVariation = rawVariation;
    if (finalVariation > limit) finalVariation = limit;   
    if (finalVariation < -limit) finalVariation = -limit; 

    double newPrice = currentPrice + finalVariation;
    if (newPrice < MIN_PRICE) newPrice = MIN_PRICE;

    finalVariation = double.parse(finalVariation.toStringAsFixed(1));
    newPrice = double.parse(newPrice.toStringAsFixed(1));

    // 2. CRIAÇÃO DO ITEM DE HISTÓRICO
    return {
      'new_price': newPrice,
      'variation': finalVariation,
      'history_entry': {
        'round': round,
        'score': score,
        'price_before': currentPrice,
        'price_after': newPrice,
        'variation': finalVariation,
        'played': played,
        'processed_at': Timestamp.now(),
      }
    };
  }

  // --- 2. PROCESSAMENTO DE JOGADORES (MERCADO) ---

  Future<Map<String, double>> processMarketValuation(String seasonId, Map<String, double> actualScores, {int? roundForHistory}) async {
    final Map<String, double> newPricesMap = {};
    final WriteBatch batch = _firestore.batch();
    
    final marketSnap = await _firestore.collection('fantasy_market_players').get();

    for (var doc in marketSnap.docs) {
      final player = FantasyPlayer.fromFirestore(doc);
      
      double score = actualScores[player.playerId] ?? 0.0;
      double currentPrice = player.currentPrice;

      // --- ALTERAÇÃO SOLICITADA: played é sempre TRUE ---
      bool played = true; 
      // --------------------------------------------------

      // Chama a lógica centralizada de cálculo
      final result = _calculateNewPriceState(currentPrice, score, played, roundForHistory ?? 0);
      
      double newPrice = result['new_price'];
      newPricesMap[player.playerId] = newPrice;

      // ATUALIZAÇÃO DO HISTÓRICO
      List<Map<String, dynamic>> updatedHistory = List.from(player.history);
      
      if (roundForHistory != null) {
        updatedHistory.removeWhere((h) => h['round'] == roundForHistory);
        updatedHistory.add(result['history_entry']);
      }

      // --- CÁLCULO DA MÉDIA ---
      // Agora, como played=true sempre, a média será (Total Pontos / Total Rodadas)
      double sumScores = 0.0;
      int countMatches = 0;

      for (var entry in updatedHistory) {
        if (entry['played'] == true) {
          sumScores += (entry['score'] as num).toDouble();
          countMatches++;
        }
      }

      double newAverage = countMatches > 0 ? sumScores / countMatches : 0.0;

      batch.update(doc.reference, {
        'current_price': newPrice,
        'last_price_change': result['variation'],
        'last_score': score, // Score é 0.0 se não tiver scout
        'average_score': double.parse(newAverage.toStringAsFixed(2)),
        'matches_played': countMatches, 
        'history': updatedHistory,
      });
    }

    await batch.commit();
    return newPricesMap;
  }

  // --- 3. PROCESSAMENTO DE TIMES (Mantido) ---

  Future<String> processUserTeams(Map<String, double> newPricesMap, Map<String, double> actualScores, int round) async {
    try {
      final teamsSnap = await _firestore.collection('fantasy_teams').get();
      final WriteBatch batch = _firestore.batch();
      int count = 0;

      for (var doc in teamsSnap.docs) {
        final team = FantasyTeam.fromFirestore(doc);
        
        double roundPoints = 0.0;
        double newTeamValueFromPlayers = 0.0;

        for (String playerId in team.lineupPlayerIds) {
          double pScore = actualScores[playerId] ?? 0.0;
          if (team.captainId == playerId) pScore *= 2;
          roundPoints += pScore;

          double updatedPrice = newPricesMap[playerId] ?? 1.0; 
          newTeamValueFromPlayers += updatedPrice;
        }

        double newTotalPatrimony = team.currentBalance + newTeamValueFromPlayers;
        newTotalPatrimony = double.parse(newTotalPatrimony.toStringAsFixed(2));

        final historyRef = _firestore.collection('fantasy_teams').doc(doc.id).collection('history').doc(round.toString()); 

        batch.set(historyRef, {
          'round': round,
          'points': roundPoints,
          'patrimony': newTotalPatrimony, 
          'processed_at': FieldValue.serverTimestamp(),
          'lineup_snapshot': team.lineupPlayerIds,
          'captain_id': team.captainId,
        });

        batch.update(doc.reference, {
          'total_points': team.totalPoints + roundPoints,
          'last_score': roundPoints, 
          'team_value': newTotalPatrimony,
        });
        count++;
      }

      await batch.commit();
      return "Sucesso! $count times processados.";
    } catch (e) {
      return "Erro ao processar times: $e";
    }
  }

  // --- 4. ROTINA DE FECHAMENTO (ORQUESTRADOR) ---

  Future<String> closeRoundFullRoutine(String seasonId, int round) async {
    try {
      final Map<String, double> scores = await _fetchSeasonScores(seasonId, round);
      if (scores.isEmpty) return "AVISO: Nenhum scout encontrado na Rodada $round.";

      final newPrices = await processMarketValuation(seasonId, scores, roundForHistory: round);
      final resultTeams = await processUserTeams(newPrices, scores, round);
      
      return "Rodada $round fechada.\nJogadores: ${scores.length}\nTimes: $resultTeams";
    } catch (e) {
      return "Erro crítico: $e";
    }
  }

  // --- 5. REPROCESSAMENTO COMPLETO ---
  
  Future<String> reprocessFullHistory(String seasonId, int maxRound) async {
    try {
      debugPrint("=== INICIANDO RECONSTRUÇÃO DA TEMPORADA (1 a $maxRound) ===");
      
      final playersSnap = await _firestore.collection('fantasy_market_players').get();
      
      Map<String, dynamic> playerSimulationState = {};

      for (var doc in playersSnap.docs) {
        final p = FantasyPlayer.fromFirestore(doc);
        double startPrice = p.currentPrice;
        
        // Tenta achar o preço inicial (antes da R1) no histórico existente
        if (p.history.isNotEmpty) {
           var r1 = p.history.where((h) => h['round'] == 1);
           if (r1.isNotEmpty) startPrice = (r1.first['price_before'] as num).toDouble();
        }

        playerSimulationState[p.playerId] = {
          'current_price': startPrice,
          'history': <Map<String, dynamic>>[], 
          'last_score': 0.0,
          'last_price_change': 0.0,
          'matches_played': 0,
          'total_score_sum': 0.0,
        };
      }

      final teamsSnap = await _firestore.collection('fantasy_teams').get();
      Map<String, double> teamTotalPointsMap = { for (var d in teamsSnap.docs) d.id : 0.0 };

      // LOOP RODADA A RODADA
      for (int r = 1; r <= maxRound; r++) {
        debugPrint("> Processando Rodada $r...");

        final Map<String, double> roundScores = await _fetchSeasonScores(seasonId, r);

        // Atualizar Mercado (Simulação)
        playerSimulationState.forEach((pid, state) {
          double priceBefore = state['current_price'];
          
          double score = roundScores[pid] ?? 0.0;
          
          // --- ALTERAÇÃO: played sempre true ---
          bool played = true; 
          // -------------------------------------

          final result = _calculateNewPriceState(priceBefore, score, played, r);

          state['current_price'] = result['new_price'];
          state['last_score'] = score;
          state['last_price_change'] = result['variation'];
          (state['history'] as List).add(result['history_entry']);
          
          if (played) {
            state['matches_played'] = (state['matches_played'] as int) + 1;
            state['total_score_sum'] = (state['total_score_sum'] as double) + score;
          }
        });

        // Atualizar Times
        final WriteBatch roundBatch = _firestore.batch();
        
        for (var teamDoc in teamsSnap.docs) {
          final historyDocRef = teamDoc.reference.collection('history').doc(r.toString());
          final historySnap = await historyDocRef.get();

          if (!historySnap.exists) continue; 

          final historyData = historySnap.data()!;
          final List<String> lineup = List<String>.from(historyData['lineup_snapshot'] ?? []);
          
          String? captainId = historyData['captain_id'] as String?;
          if (captainId == null) {
            final currentTeamData = teamDoc.data();
            captainId = currentTeamData['captain_id'] as String?;
          }

          double roundPoints = 0.0;

          for (var pid in lineup) {
            double pScore = roundScores[pid] ?? 0.0;
            if (captainId != null && captainId == pid) {
              pScore *= 2;
            }
            roundPoints += pScore;
          }

          teamTotalPointsMap[teamDoc.id] = (teamTotalPointsMap[teamDoc.id] ?? 0.0) + roundPoints;

          roundBatch.update(historyDocRef, {
            'points': roundPoints,
            'captain_id': captainId,
            'reprocessed_at': FieldValue.serverTimestamp(),
          });
        }
        await roundBatch.commit();
      }

      // SALVAMENTO FINAL
      debugPrint("Salvando estado final...");
      
      List<QueryDocumentSnapshot> allPlayerDocs = playersSnap.docs;
      int chunkSize = 400;
      for (int i = 0; i < allPlayerDocs.length; i += chunkSize) {
        final batch = _firestore.batch();
        final end = (i + chunkSize < allPlayerDocs.length) ? i + chunkSize : allPlayerDocs.length;
        
        for (var j = i; j < end; j++) {
          final doc = allPlayerDocs[j];
          final pid = doc.id;
          final state = playerSimulationState[pid];

          if (state == null) continue;

          // Cálculo da média final
          double avg = (state['matches_played'] > 0) 
             ? state['total_score_sum'] / state['matches_played'] 
             : 0.0;

          batch.update(doc.reference, {
            'current_price': state['current_price'],
            'last_price_change': state['last_price_change'],
            'last_score': state['last_score'],
            'average_score': double.parse(avg.toStringAsFixed(2)), // Salva a média calculada
            'matches_played': state['matches_played'],
            'history': state['history'], 
          });
        }
        await batch.commit();
      }

      final batchTeams = _firestore.batch();
      for (var teamDoc in teamsSnap.docs) {
        final team = FantasyTeam.fromFirestore(teamDoc);
        final newTotalPoints = teamTotalPointsMap[teamDoc.id] ?? 0.0;
        
        double currentPlayersValue = 0.0;
        double currentLastScore = 0.0; 
        
        for (var pid in team.lineupPlayerIds) {
          final pState = playerSimulationState[pid];
          if (pState != null) {
            currentPlayersValue += (pState['current_price'] as num).toDouble();
            
             final historyList = pState['history'] as List<Map<String, dynamic>>;
             if (historyList.isNotEmpty && historyList.last['round'] == maxRound) {
                double pScore = (historyList.last['score'] as num).toDouble();
                if (team.captainId == pid) pScore *= 2;
                currentLastScore += pScore;
             }
          }
        }

        double newTeamValue = team.currentBalance + currentPlayersValue;

        batchTeams.update(teamDoc.reference, {
          'total_points': newTotalPoints,
          'team_value': double.parse(newTeamValue.toStringAsFixed(2)),
          'last_score': currentLastScore, 
        });
      }
      await batchTeams.commit();

      return "Reprocessamento COMPLETO concluído!\nRodadas: 1 a $maxRound\nMédias corrigidas (Todos jogaram).";

    } catch (e, stack) {
      debugPrint(stack.toString());
      return "Erro fatal no reprocessamento: $e";
    }
  }
}