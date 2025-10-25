// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'admin_service.dart';

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
    required String newStatus,
    required int newScoreHome,
    required int newScoreAway,
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
            ? (matchData['stats_applied'] ?? {}) : {};
        Map<String, dynamic> oldPlayerStats = oldStats['player_stats'] ?? {};
        String? oldManOfTheMatchId = oldStats['man_of_the_match'];
        Map<String, int> oldGoals = Map<String, int>.from(oldPlayerStats['goals'] ?? {});
        Map<String, int> oldAssists = Map<String, int>.from(oldPlayerStats['assists'] ?? {});
        Map<String, int> oldYellows = Map<String, int>.from(oldPlayerStats['yellows'] ?? {});
        Map<String, int> oldReds = Map<String, int>.from(oldPlayerStats['reds'] ?? {});
        Map<String, int> oldGoalsConceded = Map<String, int>.from(oldPlayerStats['goals_conceded'] ?? {});
        
        // Pega todos os IDs de jogadores relevantes
        Set<String> playersToReadIds = {
          ...newGoals.keys, ...oldGoals.keys,
          ...newAssists.keys, ...oldAssists.keys,
          ...newYellows.keys, ...oldYellows.keys,
          ...newReds.keys, ...oldReds.keys,
          ...newGoalsConceded.keys, ...oldGoalsConceded.keys,
          if (newManOfTheMatchId != null) newManOfTheMatchId,
          if (oldManOfTheMatchId != null) oldManOfTheMatchId,
        };
        playersToReadIds.removeWhere((id) => id == null || id.isEmpty);

        Map<String, DocumentSnapshot> playerSnaps = {};
        for (String playerId in playersToReadIds) {
          playerSnaps[playerId] = await transaction.get(_firestore.collection('players').doc(playerId));
        }

        // --- 2. SALVAR O JOGO ATUAL (ESCRITA) ---
        final Map<String, dynamic> newPlayerStats = {
          'goals': newGoals,
          'assists': newAssists,
          'yellows': newYellows,
          'reds': newReds,
          'goals_conceded': newGoalsConceded,
        };
        
        transaction.update(_firestore.collection('matches').doc(matchId), {
          'score_home': newScoreHome,
          'score_away': newScoreAway,
          'status': newStatus,
          'stats_applied': { 
            'player_stats': newPlayerStats,
            'man_of_the_match': newManOfTheMatchId,
          }
        });

        Map<String, int> goalDelta = _calculateDelta(oldGoals, newGoals);
        Map<String, int> assistDelta = _calculateDelta(oldAssists, newAssists);
        Map<String, int> goalsConcededDelta = _calculateDelta(oldGoalsConceded, newGoalsConceded);
        // (Lógica do MotM delta como antes)

        // --- 3. APLICAR DELTA NOS JOGADORES (ESCRITA) ---
        int disciplinaryHomeDelta = 0;
        int disciplinaryAwayDelta = 0;

        // Delta de Gols (sem mudança)
        goalDelta.forEach((playerId, delta) {
          if(delta != 0 && playerSnaps.containsKey(playerId)) {
            transaction.update(_firestore.collection('players').doc(playerId), {'goals': FieldValue.increment(delta)});
          }
        });
        // Delta de Assistências (sem mudança)
      
        assistDelta.forEach((playerId, delta) {
          if(delta != 0 && playerSnaps.containsKey(playerId)) {
            transaction.update(_firestore.collection('players').doc(playerId), {'assists': FieldValue.increment(delta)});
          }
        });

        // --- LÓGICA REFEITA PARA CARTÕES (COM AJUSTE PARA TOTAIS E DEBUG) ---
        Map<String, int> yellowDelta = _calculateDelta(oldYellows, newYellows);
        Map<String, int> redDelta = _calculateDelta(oldReds, newReds);
        Set<String> affectedPlayerIds = {...yellowDelta.keys, ...redDelta.keys};
        
        // Zera os acumuladores de delta ANTES do loop
        disciplinaryHomeDelta = 0; // Garante que começa zerado nesta transação
        disciplinaryAwayDelta = 0; // Garante que começa zerado nesta transação
        debugPrint("[DISCIPLINA] Iniciando cálculo de delta disciplinar. Jogadores afetados: ${affectedPlayerIds.length}");

        for (String playerId in affectedPlayerIds) {
          debugPrint("[DISCIPLINA] Processando jogador: $playerId");
           if (!playerSnaps.containsKey(playerId)) {
               debugPrint("[DISCIPLINA] Jogador $playerId não encontrado no cache. Pulando.");
               continue;
           }

           final playerSnap = playerSnaps[playerId]!;
           final playerData = playerSnap.data() as Map<String, dynamic>? ?? {};
           
           // Pega os deltas para este jogador
           int yDelta = yellowDelta[playerId] ?? 0;
           int rDelta = redDelta[playerId] ?? 0;
           debugPrint("[DISCIPLINA] Deltas para $playerId: yDelta=$yDelta, rDelta=$rDelta");


           // Pega valores atuais do BD
           int currentYellows = playerData['yellow_cards'] ?? 0;
           int currentReds = playerData['red_cards'] ?? 0;
           bool currentlySuspended = playerData['is_suspended'] ?? false;

           // Pega valores TOTAIS do BD
           int currentTotalYellows = playerData['total_yellow_cards'] ?? 0;
           int currentTotalReds = playerData['total_red_cards'] ?? 0;

           // Calcula os novos totais TEÓRICOS (antes de aplicar zeramento)
           int theoreticalNewYellows = currentYellows + yDelta;
           int theoreticalNewReds = currentReds + rDelta;
           // Garante que não fiquem negativos
           if (theoreticalNewYellows < 0) theoreticalNewYellows = 0;
           if (theoreticalNewReds < 0) theoreticalNewReds = 0;

          // --- Calcula incrementos para os TOTAIS (Lógica Especial) ---
           int yellowIncrementForTotal = yDelta; // Começa com o delta normal
           int redIncrementForTotal = rDelta;   // Começa com o delta normal

           // Verifica o cenário: expulsão por 2º amarelo NESTE JOGO
           bool isSecondYellowRedScenario = (rDelta > 0 && yDelta == 2);
           if (isSecondYellowRedScenario) {
             yellowIncrementForTotal = 1; // Só incrementa 1 no total de amarelos
             // redIncrementForTotal já é 1 (pois rDelta é 1)
             debugPrint("Jogador $playerId: Cenário 2º Amarelo + Vermelho detectado. Incremento Total CA: $yellowIncrementForTotal, CV: $redIncrementForTotal");
           }

           // Calcula os novos totais ACUMULADOS FINAIS
           int finalTotalYellows = currentTotalYellows + yellowIncrementForTotal;
           int finalTotalReds = currentTotalReds + redIncrementForTotal;

           if (finalTotalYellows < 0) finalTotalYellows = 0;
           if (finalTotalReds < 0) finalTotalReds = 0;

          // --- Fim do cálculo para totais ---


           // --- Determina o estado final dos cartões CORRENTES e suspensão ---
           // (Esta lógica permanece a mesma, usando theoreticalNewYellows e regras de zeramento)
           int finalYellows = theoreticalNewYellows; // Contagem corrente final
           int finalReds = theoreticalNewReds;       // Contagem corrente final
           bool finalSuspension = currentlySuspended; 

          // 1. Verifica suspensão/reset por AMARELOS (usa theoreticalNewYellows)
           if (yDelta > 0 && theoreticalNewYellows >= AdminService.suspensionYellowCards && currentYellows < AdminService.suspensionYellowCards) {
              finalSuspension = true;
              if (AdminService.resetYellowsOnSuspension) {
                 finalYellows = 0; // ZERA O CORRENTE
                 debugPrint("Jogador $playerId: Zerando amarelos CORRENTES por suspensão CA");
              }
           }

           // 2. Verifica suspensão/reset por VERMELHO (usa currentYellows e regras)
           if (rDelta > 0 && AdminService.suspensionOnRed) {
              finalSuspension = true;
              //suspendedByRedThisTurn = true;
              bool wasPending = currentYellows == AdminService.pendingYellowCards;

              // Verifica se zera amarelos (com a regra especial 'while_pending')
              bool shouldResetYellows = AdminService.resetYellowsOnRed;
              if (wasPending && !AdminService.resetYellowsOnRedWhilePending) {
                 shouldResetYellows = false; 
                 debugPrint("Jogador $playerId: NÃO zerando amarelos CORRENTES por CV (Regra RedWhilePending)");
              }

              if (shouldResetYellows) {
                 finalYellows = 0; // ZERA O CORRENTE
                 debugPrint("Jogador $playerId: Zerando amarelos CORRENTES por CV (Regra ResetRed)");
              }
           }

           // 3. Verifica REMOÇÃO de suspensão (usa finalYellows, finalReds)
           if (rDelta < 0 && finalYellows < AdminService.suspensionYellowCards) { // Se removeu vermelho E corrente de amarelos está abaixo do limite
              finalSuspension = false;
           }
           
           if (yDelta < 0 && theoreticalNewYellows < AdminService.suspensionYellowCards && currentYellows >= AdminService.suspensionYellowCards && finalReds == 0) { // Se removeu amarelo caindo abaixo do limite E não tem vermelho corrente
              finalSuspension = false;
           }

           // --- Prepara o update para este jogador ---
           Map<String, dynamic> playerUpdateData = {
              'yellow_cards': finalYellows,             // Salva contagem CORRENTE final
              'red_cards': finalReds,                 // Salva contagem CORRENTE final
              'total_yellow_cards': finalTotalYellows, // Salva contagem TOTAL final
              'total_red_cards': finalTotalReds,     // Salva contagem TOTAL final
              'is_suspended': finalSuspension,
           };

           // Atualiza no batch (usando SET, não increment)
           transaction.update(_firestore.collection('players').doc(playerId), playerUpdateData);

           // Calcula delta de pontos disciplinares (baseado nos DELTAS yDelta/rDelta)
           int pointsDelta = 0;
           if (isSecondYellowRedScenario) { // Usa a flag que calculamos antes
             pointsDelta = (1 * 10) + (1 * 21); // Conta SÓ o 1º amarelo (10) + o vermelho (21) = 31
             debugPrint("[DISCIPLINA] Jogador $playerId: Cenário 2º CA+CV. pointsDelta = $pointsDelta");
           } else {
             pointsDelta = (yDelta * 10) + (rDelta * 21);
             debugPrint("[DISCIPLINA] Jogador $playerId: Caso padrão. pointsDelta = ($yDelta * 10) + ($rDelta * 21) = $pointsDelta");
           }
           // --- FIM DA LÓGICA ATUALIZADA ---

           final String? playerTeamId = playerSnap.get('team_id'); // Pega o ID do time
         
           if (playerTeamId == homeTeamId) {
            disciplinaryHomeDelta += pointsDelta;
            debugPrint("[DISCIPLINA] Acumulado Casa: $disciplinaryHomeDelta (adicionado $pointsDelta de $playerId)");
           
           } else if (playerTeamId == awayTeamId) {
             disciplinaryAwayDelta += pointsDelta;
             debugPrint("[DISCIPLINA] Acumulado Visitante: $disciplinaryAwayDelta (adicionado $pointsDelta de $playerId)");
           }else {
              debugPrint("[DISCIPLINA] ERRO: Jogador $playerId não pertence a nenhum dos times da partida ($homeTeamId vs $awayTeamId). TeamID: $playerTeamId");
           }
        } // Fim do loop for playerId

        debugPrint("[PONTOS] Antes Update Disc.: TimeCasa=$homeTeamId, Delta=$disciplinaryHomeDelta | TimeFora=$awayTeamId, Delta=$disciplinaryAwayDelta");

        // Aplica o DELTA de pontos disciplinares
        final homeTeamRef = _firestore.collection('teams').doc(homeTeamId);
        final awayTeamRef = _firestore.collection('teams').doc(awayTeamId);
        
        // Só aplica se o delta for diferente de zero para evitar escritas desnecessárias
        if (disciplinaryHomeDelta != 0) {
            transaction.update(homeTeamRef, {'disciplinary_points': FieldValue.increment(disciplinaryHomeDelta)});
            debugPrint("[DISCIPLINA] Aplicando Delta Casa: $disciplinaryHomeDelta");
        }
        if (disciplinaryAwayDelta != 0) {
            transaction.update(awayTeamRef, {'disciplinary_points': FieldValue.increment(disciplinaryAwayDelta)});
            debugPrint("[DISCIPLINA] Aplicando Delta Visitante: $disciplinaryAwayDelta");
        }

        // --- NOVO: Delta de Gols Sofridos ---
        //Map<String, int> goalsConcededDelta = _calculateDelta(oldGoalsConceded, newGoalsConceded);
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

        

      }); // Fim da Transação

      // --- PÓS-TRANSAÇÃO: RECALCULAR OS DOIS TIMES ---
      debugPrint("[PONTOS] Transação concluída. Iniciando recálculo para $homeTeamId e $awayTeamId...");
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
    debugPrint("[PONTOS] Recalculando Time: $teamId");
    // 1. Inicializa os totais
    int totalMatchPoints = 0;
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
        totalMatchPoints += 3;
        totalWins++;
      } else if (scoreHome < scoreAway) {
        totalLosses++;
      } else {
        totalMatchPoints += 1;
        totalDraws++;
      }
    }

    debugPrint("[PONTOS] Recalculo $teamId - Após jogos Casa: MP=$totalMatchPoints, J=$totalGames, V=$totalWins, E=$totalDraws, D=$totalLosses, GP=$totalGoalsFor, GC=$totalGoalsAgainst");

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
        totalMatchPoints += 3;
        totalWins++;
      } else if (scoreAway < scoreHome) {
        totalLosses++;
      } else {
        totalMatchPoints += 1;
        totalDraws++;
      }
    }

    debugPrint("[PONTOS] Recalculo $teamId - Após jogos Fora: MP=$totalMatchPoints, J=$totalGames, V=$totalWins, E=$totalDraws, D=$totalLosses, GP=$totalGoalsFor, GC=$totalGoalsAgainst");
    
   // --- 4. LER PONTOS EXTRAS ATUAIS E ATUALIZAR O TIME ---
    try {
      final teamRef = _firestore.collection('teams').doc(teamId);
      final teamSnap = await teamRef.get(); // Lê o estado atual do time
      final currentExtraPoints = (teamSnap.data()?['extra_points'] ?? 0) as int; // Pega extra_points

      debugPrint("[PONTOS] Recalculo $teamId - Extra Points atuais lidos: $currentExtraPoints");

      // Calcula o total final
      final int finalTotalPoints = totalMatchPoints + currentExtraPoints;
      final int finalGoalDifference = totalGoalsFor - totalGoalsAgainst;

      debugPrint("[PONTOS] Recalculo $teamId - Update Final: MP=$totalMatchPoints, EP=$currentExtraPoints, P=$finalTotalPoints, J=$totalGames, V=$totalWins, E=$totalDraws, D=$totalLosses, GP=$totalGoalsFor, GC=$totalGoalsAgainst, SG=$finalGoalDifference");

      // ATUALIZA o documento do time com valores absolutos
      await teamRef.update({
        'match_points': totalMatchPoints, // Define os pontos SÓ de jogos
        'points': finalTotalPoints,     // Define o TOTAL (jogos + extras)
        'games_played': totalGames,
        'wins': totalWins,
        'draws': totalDraws,
        'losses': totalLosses,
        'goals_for': totalGoalsFor,
        'goals_against': totalGoalsAgainst,
        'goal_difference': finalGoalDifference,
        // 'extra_points' NÃO é modificado aqui
        // 'disciplinary_points' NÃO é modificado aqui
      });
      debugPrint("[PONTOS] Recalculo $teamId - Update Concluído.");
    } catch (e) {
       debugPrint("[PONTOS] ERRO Recalculo $teamId: $e");
       // Considerar como tratar esse erro (talvez tentar de novo?)
    }
  }
}