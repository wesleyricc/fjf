import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/fantasy_models.dart';
import 'fantasy_service.dart';
import 'dart:developer' as developer;

class RoundScoutData {
  final Map<String, double> scoresMap;
  final Set<String> playersPlayedSet;

  RoundScoutData({
    required this.scoresMap,
    required this.playersPlayedSet,
  });
}

class FantasyAdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FantasyService _fantasyService = FantasyService();

  // --- 0. LEITURA DOS SCOUTS (ATUALIZADO PARA REGRAS CARTOLA) ---
  Future<RoundScoutData> _fetchSeasonScores(
      String seasonId, int round, FantasyGameConfig config) async {
    final Map<String, double> scoresMap = {};
    final Map<String, bool> teamCleanSheets = {}; // Mapeamento de SG
    final Set<String> playersPlayedSet = {}; // Mapeamento de Presença (lineup_played)

    debugPrint("--- LENDO SCOUTS R$round (Temporada $seasonId) ---");

    if (seasonId.trim().isEmpty) {
      debugPrint("AVISO: seasonId está vazio ao buscar scouts da rodada $round.");
      return RoundScoutData(
        scoresMap: scoresMap,
        playersPlayedSet: playersPlayedSet,
      );
    }

    try {
      final matchesRef = _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('matches')
          .where('round', isEqualTo: round);

      final matchesSnap = await matchesRef.get();

      for (var matchDoc in matchesSnap.docs) {
        final data = matchDoc.data();

        // 🚨 Mapeamento de Presença (quem jogou)
        if (data['lineup_played'] != null && data['lineup_played'] is List) {
          for (var pid in (data['lineup_played'] as List)) {
            playersPlayedSet.add(pid.toString());
          }
        }

        // 🚨 Inteligência do Saldo de Gols (Clean Sheet)
        final int scoreHome = data['score_home'] ?? 0;
        final int scoreAway = data['score_away'] ?? 0;
        final String homeId = data['team_home_id'] ?? '';
        final String awayId = data['team_away_id'] ?? '';

        if (scoreAway == 0 && homeId.isNotEmpty) teamCleanSheets[homeId] = true;
        if (scoreHome == 0 && awayId.isNotEmpty) teamCleanSheets[awayId] = true;

        if (data['stats_applied'] == null) continue;

        final statsApplied = data['stats_applied'] as Map<String, dynamic>;
        final playerStats =
            statsApplied['player_stats'] as Map<String, dynamic>? ?? {};

        Map<String, int> getStatMap(String key) =>
            _safeCastMap(playerStats[key]);

        final goalsMap = getStatMap('goals');
        final assistsMap = getStatMap('assists');
        final yellowsMap = getStatMap('yellows');
        final redsMap = getStatMap('reds');
        final penaltiesSavedMap = getStatMap('penalties_saved');
        final penaltiesMissedMap = getStatMap('penalties_missed');
        final shotsOnPostMap = getStatMap('shots_on_post');
        final ownGoalsMap = getStatMap('own_goals');
        final missedFreeKicksMap = getStatMap('direct_free_kicks_missed').isNotEmpty
            ? getStatMap('direct_free_kicks_missed')
            : getStatMap('missed_free_kicks');
        final difficultSavesMap = getStatMap('difficult_saves');

        // MOTM fica em stats_applied['man_of_the_match'] ou data['man_of_the_match']
        final String? motmPid = (statsApplied['man_of_the_match'] ?? data['man_of_the_match'])?.toString();
        final Map<String, int> motmMap = (motmPid != null && motmPid.isNotEmpty)
            ? {motmPid: 1}
            : getStatMap('motm');

        final Set<String> allPlayerIds = {
          ...goalsMap.keys,
          ...assistsMap.keys,
          ...yellowsMap.keys,
          ...redsMap.keys,
          ...penaltiesSavedMap.keys,
          ...penaltiesMissedMap.keys,
          ...shotsOnPostMap.keys,
          ...ownGoalsMap.keys,
          ...missedFreeKicksMap.keys,
          ...difficultSavesMap.keys,
          ...motmMap.keys
        };

        for (String pid in allPlayerIds) {
          double points = 0.0;
          points += (goalsMap[pid] ?? 0) * config.ptsGoal;
          points += (assistsMap[pid] ?? 0) * config.ptsAssist;
          points += (yellowsMap[pid] ?? 0) * config.ptsYellowCard;
          points += (redsMap[pid] ?? 0) * config.ptsRedCard;
          points += (penaltiesSavedMap[pid] ?? 0) * config.ptsPenaltySaved;
          points += (penaltiesMissedMap[pid] ?? 0) * config.ptsPenaltyMissed;
          points += (shotsOnPostMap[pid] ?? 0) * config.ptsShotOnPost;
          points += (ownGoalsMap[pid] ?? 0) * config.ptsOwnGoal;
          points += (missedFreeKicksMap[pid] ?? 0) * config.ptsMissedFreeKick;
          points += (difficultSavesMap[pid] ?? 0) * config.ptsDifficultSave;
          points += (motmMap[pid] ?? 0) * config.ptsMotm;

          scoresMap[pid] = (scoresMap[pid] ?? 0.0) + points;
        }
      }

      // 🚨 Aplica o Saldo de Gols (SG) APENAS para Goleiros e Fixos confirmados em súmula
      if (teamCleanSheets.isNotEmpty) {
        final marketSnap =
            await _firestore.collection('fantasy_market_players').get();
        for (var doc in marketSnap.docs) {
          final p = doc.data();
          final teamId = p['team_id'];
          final pos = p['position'];
          final pid = doc.id;
          final bool hasPlayed = playersPlayedSet.contains(pid);
          if (hasPlayed &&
              teamId != null &&
              teamCleanSheets.containsKey(teamId) &&
              (pos == 'Goleiro' || pos == 'Fixo')) {
            scoresMap[pid] =
                (scoresMap[pid] ?? 0.0) + config.ptsCleanSheet;
          }
        }
      }
    } catch (e) {
      debugPrint("Erro scouts: $e");
    }
    return RoundScoutData(
      scoresMap: scoresMap,
      playersPlayedSet: playersPlayedSet,
    );
  }

  Map<String, int> _safeCastMap(dynamic rawMap) {
    if (rawMap == null || rawMap is! Map) return {};
    return rawMap.map((key, value) =>
        MapEntry(key.toString(), (value is num) ? value.toInt() : 0));
  }

  // --- CÁLCULO DA MÉDIA DO TÉCNICO ---
  Future<void> _calculateCoachesAverages(
      Map<String, double> scoresMap, Set<String> playersPlayedSet) async {
    try {
      developer.log('--- 🔍 INICIANDO CÁLCULO DE MÉDIA DOS TÉCNICOS ---',
          name: 'FJF.Fantasy');

      final marketSnap =
          await _firestore.collection('fantasy_market_players').get();
      final List<FantasyPlayer> allPlayers =
          marketSnap.docs.map((d) => FantasyPlayer.fromFirestore(d)).toList();

      final Map<String, List<Map<String, dynamic>>> teamScoutDetails = {};
      final Map<String, List<double>> teamScores = {};
      final Map<String, String> teamCoaches = {};

      for (var player in allPlayers) {
        if (player.position == 'Técnico') {
          if (player.teamId.isNotEmpty) {
            teamCoaches[player.teamId] = player.playerId;
          }
          continue;
        }

        // Regra Oficial: Apenas atletas que confirmaram presença em súmula (lineup_played)
        final bool hasPlayed = playersPlayedSet.contains(player.playerId);
        if (hasPlayed) {
          final score = scoresMap[player.playerId] ?? 0.0;
          if (player.teamId.isNotEmpty) {
            teamScores.putIfAbsent(player.teamId, () => []).add(score);

            teamScoutDetails.putIfAbsent(player.teamId, () => []).add({
              'nome': player.name,
              'posicao': player.position,
              'pontos': score
            });
          }
        }
      }

      teamCoaches.forEach((teamId, coachId) {
        final scores = teamScores[teamId] ?? [];
        final details = teamScoutDetails[teamId] ?? [];
        double average = 0.0;

        if (scores.isNotEmpty) {
          final double total = scores.reduce((a, b) => a + b);
          average = total / scores.length;

          String logMembros = details
              .map((m) => "${m['nome']} (${m['pontos']} pts)")
              .join(', ');

          developer.log(
              '📊 TIME: $teamId | TÉCNICO ID: $coachId\n'
              '   Atletas presentes em súmula (${scores.length}): $logMembros\n'
              '   🧮 CONTA: ${total.toStringAsFixed(2)} / ${scores.length} = ${average.toStringAsFixed(2)}',
              name: 'FJF.Fantasy');
        }

        scoresMap[coachId] = double.parse(average.toStringAsFixed(2));
      });
    } catch (e) {
      developer.log('❌ Erro média técnicos', error: e, name: 'FJF.Fantasy');
    }
  }

  // --- 1. LÓGICA DE CÁLCULO DE PREÇO ---

  Map<String, dynamic> _calculateNewPriceState(
    double currentPrice,
    double score,
    bool played,
    int round,
    FantasyGameConfig config,
  ) {
    if (!played) {
      return {
        'new_price': currentPrice,
        'variation': 0.0,
        'history_entry': {
          'round': round,
          'score': 0.0,
          'price_before': currentPrice,
          'price_after': currentPrice,
          'variation': 0.0,
          'played': false,
          'processed_at': Timestamp.now(),
        }
      };
    }

    double expectation = currentPrice * config.factorExpectation;
    double performance = score - expectation;
    double rawVariation = performance * config.factorVariation;
    // Clamp garante que o limite nunca seja menor que 2.0 nem maior que 5.0
    double limit = (currentPrice * config.capLimitPercent).clamp(2.0, 5.0);

    double finalVariation = rawVariation;
    if (finalVariation > limit) finalVariation = limit;
    if (finalVariation < -limit) finalVariation = -limit;

    finalVariation = double.parse(finalVariation.toStringAsFixed(2));
    double newPrice = double.parse((currentPrice + finalVariation).toStringAsFixed(2));
    if (newPrice < config.minPrice) {
      newPrice = config.minPrice;
      finalVariation = double.parse((newPrice - currentPrice).toStringAsFixed(2));
    }

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

  Future<Map<String, double>> processMarketValuation(String seasonId,
      Map<String, double> actualScores, FantasyGameConfig config,
      {int? roundForHistory, Set<String>? playersPlayedSet}) async {
    final Map<String, double> newPricesMap = {};
    final WriteBatch batch = _firestore.batch();

    final marketSnap =
        await _firestore.collection('fantasy_market_players').get();

    for (var doc in marketSnap.docs) {
      final player = FantasyPlayer.fromFirestore(doc);

      double score = actualScores[player.playerId] ?? 0.0;
      double currentPrice = player.currentPrice;
      bool played = playersPlayedSet != null
          ? (playersPlayedSet.contains(player.playerId) ||
              (player.position == 'Técnico' && actualScores.containsKey(player.playerId)))
          : true;

      final result = _calculateNewPriceState(
          currentPrice, score, played, roundForHistory ?? 0, config);

      double newPrice = result['new_price'];
      newPricesMap[player.playerId] = newPrice;

      List<Map<String, dynamic>> updatedHistory = List.from(player.history);

      if (roundForHistory != null) {
        updatedHistory.removeWhere((h) => h['round'] == roundForHistory);
        updatedHistory.add(result['history_entry']);
      }

      double sumScores = 0.0;
      int countMatches = 0;

      for (var entry in updatedHistory) {
        if (entry['played'] == true) {
          sumScores += (entry['score'] as num).toDouble();
          countMatches++;
        }
      }

      double newAverage = countMatches > 0 ? sumScores / countMatches : 0.0;

      final playedMatches =
          updatedHistory.where((h) => h['played'] == true).toList();
      double lastScore = played
          ? score
          : (playedMatches.isNotEmpty
              ? (playedMatches.last['score'] as num).toDouble()
              : 0.0);
      double lastVariation = played
          ? result['variation']
          : (playedMatches.isNotEmpty
              ? (playedMatches.last['variation'] as num).toDouble()
              : 0.0);

      batch.update(doc.reference, {
        'current_price': newPrice,
        'last_price_change': lastVariation,
        'last_score': lastScore,
        'average_score': double.parse(newAverage.toStringAsFixed(2)),
        'matches_played': countMatches,
        'history': updatedHistory,
      });
    }

    await batch.commit();
    return newPricesMap;
  }

  // --- 3. PROCESSAMENTO DE TIMES ---

  Future<String> processUserTeams(Map<String, double> newPricesMap,
      Map<String, double> actualScores, int round) async {
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

        double newTotalPatrimony =
            team.currentBalance + newTeamValueFromPlayers;
        newTotalPatrimony = double.parse(newTotalPatrimony.toStringAsFixed(2));

        final historyRef = _firestore
            .collection('fantasy_teams')
            .doc(doc.id)
            .collection('history')
            .doc(round.toString());

        batch.set(historyRef, {
          'round': round,
          'points': roundPoints,
          'patrimony': newTotalPatrimony,
          'balance': team.currentBalance,
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
      final config = await _fantasyService.getGameConfig();

      final scoutData =
          await _fetchSeasonScores(seasonId, round, config);
      final scores = scoutData.scoresMap;

      await _calculateCoachesAverages(scores, scoutData.playersPlayedSet);

      if (scores.isEmpty) {
        return "AVISO: Nenhum scout encontrado na Rodada $round.";
      }

      final newPrices = await processMarketValuation(seasonId, scores, config,
          roundForHistory: round,
          playersPlayedSet: scoutData.playersPlayedSet);

      final resultTeams = await processUserTeams(newPrices, scores, round);

      return "Rodada $round fechada com Config Dinâmica.\nJogadores + Técnicos: ${scores.length}\nTimes: $resultTeams";
    } catch (e) {
      return "Erro crítico: $e";
    }
  }

  // --- 5. REPROCESSAMENTO COMPLETO ---

  Future<String> reprocessFullHistory(String seasonId, int maxRound) async {
    try {
      debugPrint("=== INICIANDO RECONSTRUÇÃO DA TEMPORADA (1 a $maxRound) ===");

      if (seasonId.trim().isEmpty) {
        debugPrint("Aviso: seasonId veio vazio. Buscando temporada ativa no Firestore...");
        try {
          final activeSnap = await _firestore
              .collection('championships')
              .where('isActive', isEqualTo: true)
              .limit(1)
              .get();
          if (activeSnap.docs.isNotEmpty) {
            seasonId = activeSnap.docs.first.id;
          } else {
            final anySnap =
                await _firestore.collection('championships').limit(1).get();
            if (anySnap.docs.isNotEmpty) {
              seasonId = anySnap.docs.first.id;
            }
          }
        } catch (e) {
          debugPrint("Erro ao buscar temporada fallback: $e");
        }
        debugPrint("Temporada resolvida para reprocessamento: $seasonId");
      }

      if (seasonId.trim().isEmpty) {
        return "Erro: Nenhuma temporada ativa encontrada para reprocessamento.";
      }

      final config = await _fantasyService.getGameConfig();

      final playersSnap =
          await _firestore.collection('fantasy_market_players').get();

      Map<String, dynamic> playerSimulationState = {};

      for (var doc in playersSnap.docs) {
        final p = FantasyPlayer.fromFirestore(doc);
        double startPrice = p.currentPrice;

        if (p.history.isNotEmpty) {
          var r1 = p.history.where((h) => h['round'] == 1);
          if (r1.isNotEmpty) {
            startPrice = (r1.first['price_before'] as num).toDouble();
          }
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
      Map<String, double> teamTotalPointsMap = {
        for (var d in teamsSnap.docs) d.id: 0.0
      };
      Map<String, double> teamLastScoreMap = {
        for (var d in teamsSnap.docs) d.id: 0.0
      };

      // LOOP RODADA A RODADA
      for (int r = 1; r <= maxRound; r++) {
        debugPrint("> Processando Rodada $r...");

        final scoutData =
            await _fetchSeasonScores(seasonId, r, config);
        final roundScores = scoutData.scoresMap;

        // Se a rodada não possui jogadores em súmula nem pontuações (rodada ainda não disputada), ignora
        if (scoutData.playersPlayedSet.isEmpty && roundScores.isEmpty) {
          debugPrint("Rodada $r ignorada no reprocessamento por não possuir partidas finalizadas.");
          continue;
        }

        await _calculateCoachesAverages(roundScores, scoutData.playersPlayedSet);

        playerSimulationState.forEach((pid, state) {
          double priceBefore = state['current_price'];
          double score = roundScores[pid] ?? 0.0;
          bool played = scoutData.playersPlayedSet.contains(pid) ||
              (state['position'] == 'Técnico' && roundScores.containsKey(pid));

          final result =
              _calculateNewPriceState(priceBefore, score, played, r, config);

          state['current_price'] = result['new_price'];
          if (played) {
            state['last_score'] = score;
            state['last_price_change'] = result['variation'];
          }
          (state['history'] as List).add(result['history_entry']);

          if (played) {
            state['matches_played'] = (state['matches_played'] as int) + 1;
            state['total_score_sum'] =
                (state['total_score_sum'] as double) + score;
          }
        });

        final WriteBatch roundBatch = _firestore.batch();
        for (var teamDoc in teamsSnap.docs) {
          final historyDocRef =
              teamDoc.reference.collection('history').doc(r.toString());
          final historySnap = await historyDocRef.get();

          if (!historySnap.exists) continue;

          final historyData = historySnap.data()!;
          final List<String> lineup = (historyData['final_lineup'] != null &&
                  (historyData['final_lineup'] as List).isNotEmpty)
              ? List<String>.from(historyData['final_lineup'])
              : List<String>.from(historyData['lineup_snapshot'] ?? []);

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

          teamTotalPointsMap[teamDoc.id] =
              (teamTotalPointsMap[teamDoc.id] ?? 0.0) + roundPoints;
          teamLastScoreMap[teamDoc.id] = roundPoints;

          final team = FantasyTeam.fromFirestore(teamDoc);
          final startersPids = lineup.isNotEmpty ? lineup : team.lineupPlayerIds;
          double roundPlayersValue = 0.0;
          double startersInitialCost = 0.0;
          for (var pid in startersPids) {
            final pState = playerSimulationState[pid];
            if (pState != null) {
              roundPlayersValue += (pState['current_price'] as num).toDouble();
              final historyList = pState['history'] as List<dynamic>?;
              final hist = historyList?.cast<Map<String, dynamic>?>().firstWhere(
                (h) => h != null && h['round'] == r,
                orElse: () => null,
              );
              startersInitialCost += (hist?['price_before'] as num?)?.toDouble() ?? (pState['current_price'] as num).toDouble();
            } else {
              final pDoc = playersSnap.docs.firstWhere(
                (p) => p.id == pid,
                orElse: () => playersSnap.docs.first,
              );
              final price = (pDoc.data()['current_price'] as num?)?.toDouble() ?? 5.0;
              roundPlayersValue += price;
              startersInitialCost += price;
            }
          }

          final double? existingPatrimony = (historyData['patrimony'] as num?)?.toDouble();
          final double histBalance = (historyData['balance'] as num?)?.toDouble() ?? team.currentBalance;
          final double maxPossibleBalance = ((existingPatrimony ?? team.teamValue) - startersInitialCost) > 0
              ? ((existingPatrimony ?? team.teamValue) - startersInitialCost) : 0.0;
          final double safeBalance = histBalance > maxPossibleBalance ? maxPossibleBalance : histBalance;

          final roundPatrimony = existingPatrimony ??
              double.parse((safeBalance + roundPlayersValue).toStringAsFixed(2));

          roundBatch.update(historyDocRef, {
            'points': roundPoints,
            'captain_id': captainId,
            'patrimony': roundPatrimony,
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
        final end = (i + chunkSize < allPlayerDocs.length)
            ? i + chunkSize
            : allPlayerDocs.length;

        for (var j = i; j < end; j++) {
          final doc = allPlayerDocs[j];
          final pid = doc.id;
          final state = playerSimulationState[pid];
          if (state == null) continue;

          double avg = (state['matches_played'] > 0)
              ? state['total_score_sum'] / state['matches_played']
              : 0.0;

          batch.update(doc.reference, {
            'current_price': state['current_price'],
            'last_price_change': state['last_price_change'],
            'last_score': state['last_score'],
            'average_score': double.parse(avg.toStringAsFixed(2)),
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
        final currentLastScore = teamLastScoreMap[teamDoc.id] ?? 0.0;
        double currentPlayersValue = 0.0;
        double startersInitialCost = 0.0;
        final startersPids = team.lineupPlayerIds;
        for (var pid in startersPids) {
          final pState = playerSimulationState[pid];
          if (pState != null) {
            currentPlayersValue += (pState['current_price'] as num).toDouble();
            final historyList = pState['history'] as List<dynamic>?;
            final hist = historyList?.cast<Map<String, dynamic>?>().firstWhere(
              (h) => h != null && h['round'] == 1,
              orElse: () => null,
            );
            startersInitialCost += (hist?['price_before'] as num?)?.toDouble() ?? (pState['current_price'] as num).toDouble();
          } else {
            final pDoc = playersSnap.docs.firstWhere(
              (p) => p.id == pid,
              orElse: () => playersSnap.docs.first,
            );
            final price = (pDoc.data()['current_price'] as num?)?.toDouble() ?? 5.0;
            currentPlayersValue += price;
            startersInitialCost += price;
          }
        }
        final double maxPossibleBalance = (team.teamValue - startersInitialCost) > 0 ? (team.teamValue - startersInitialCost) : 0.0;
        final double safeBalance = team.currentBalance > maxPossibleBalance ? maxPossibleBalance : team.currentBalance;
        double newTeamValue = safeBalance + currentPlayersValue;
        batchTeams.update(teamDoc.reference, {
          'total_points': newTotalPoints,
          'team_value': double.parse(newTeamValue.toStringAsFixed(2)),
          'current_balance': double.parse(safeBalance.toStringAsFixed(2)),
          'balance': FieldValue.delete(),
          'last_score': currentLastScore,
        });
      }
      await batchTeams.commit();

      return "Reprocessamento COMPLETO com CONFIGURAÇÃO DINÂMICA!\nRodadas: 1 a $maxRound";
    } catch (e, stack) {
      debugPrint(stack.toString());
      return "Erro fatal no reprocessamento: $e";
    }
  }
}
