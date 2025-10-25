// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'admin_service.dart';
import '../utils/standings_sorter.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Função auxiliar para criar deltas de JOGADOR (continua igual)
  Map<String, int> _calculateDelta(
    Map<String, int> oldMap,
    Map<String, int> newMap,
  ) {
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
        final DocumentSnapshot freshMatchSnap = await transaction.get(
          _firestore.collection('matches').doc(matchId),
        );
        final matchData = freshMatchSnap.data() as Map<String, dynamic>;

        Map<String, dynamic> oldStats =
            (matchData.containsKey('stats_applied') &&
                matchData['stats_applied'] != null)
            ? (matchData['stats_applied'] ?? {})
            : {};
        Map<String, dynamic> oldPlayerStats = oldStats['player_stats'] ?? {};
        String? oldManOfTheMatchId = oldStats['man_of_the_match'];
        Map<String, int> oldGoals = Map<String, int>.from(
          oldPlayerStats['goals'] ?? {},
        );
        Map<String, int> oldAssists = Map<String, int>.from(
          oldPlayerStats['assists'] ?? {},
        );
        Map<String, int> oldYellows = Map<String, int>.from(
          oldPlayerStats['yellows'] ?? {},
        );
        Map<String, int> oldReds = Map<String, int>.from(
          oldPlayerStats['reds'] ?? {},
        );
        Map<String, int> oldGoalsConceded = Map<String, int>.from(
          oldPlayerStats['goals_conceded'] ?? {},
        );

        // Pega todos os IDs de jogadores relevantes
        Set<String> playersToReadIds = {
          ...newGoals.keys,
          ...oldGoals.keys,
          ...newAssists.keys,
          ...oldAssists.keys,
          ...newYellows.keys,
          ...oldYellows.keys,
          ...newReds.keys,
          ...oldReds.keys,
          ...newGoalsConceded.keys,
          ...oldGoalsConceded.keys,
          if (newManOfTheMatchId != null) newManOfTheMatchId,
          if (oldManOfTheMatchId != null) oldManOfTheMatchId,
        };
        playersToReadIds.removeWhere((id) => id == null || id.isEmpty);

        Map<String, DocumentSnapshot> playerSnaps = {};
        for (String playerId in playersToReadIds) {
          playerSnaps[playerId] = await transaction.get(
            _firestore.collection('players').doc(playerId),
          );
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
          },
        });

        Map<String, int> goalDelta = _calculateDelta(oldGoals, newGoals);
        Map<String, int> assistDelta = _calculateDelta(oldAssists, newAssists);
        Map<String, int> goalsConcededDelta = _calculateDelta(
          oldGoalsConceded,
          newGoalsConceded,
        );
        // (Lógica do MotM delta como antes)

        // --- 3. APLICAR DELTA NOS JOGADORES (ESCRITA) ---
        int disciplinaryHomeDelta = 0;
        int disciplinaryAwayDelta = 0;

        // Delta de Gols (sem mudança)
        goalDelta.forEach((playerId, delta) {
          if (delta != 0 && playerSnaps.containsKey(playerId)) {
            transaction.update(_firestore.collection('players').doc(playerId), {
              'goals': FieldValue.increment(delta),
            });
          }
        });
        // Delta de Assistências (sem mudança)

        assistDelta.forEach((playerId, delta) {
          if (delta != 0 && playerSnaps.containsKey(playerId)) {
            transaction.update(_firestore.collection('players').doc(playerId), {
              'assists': FieldValue.increment(delta),
            });
          }
        });

        // --- LÓGICA REFEITA PARA CARTÕES (COM AJUSTE PARA TOTAIS E DEBUG) ---
        Map<String, int> yellowDelta = _calculateDelta(oldYellows, newYellows);
        Map<String, int> redDelta = _calculateDelta(oldReds, newReds);
        Set<String> affectedPlayerIds = {...yellowDelta.keys, ...redDelta.keys};

        // Zera os acumuladores de delta ANTES do loop
        disciplinaryHomeDelta = 0; // Garante que começa zerado nesta transação
        disciplinaryAwayDelta = 0; // Garante que começa zerado nesta transação
        debugPrint(
          "[DISCIPLINA] Iniciando cálculo de delta disciplinar. Jogadores afetados: ${affectedPlayerIds.length}",
        );

        for (String playerId in affectedPlayerIds) {
          debugPrint("[DISCIPLINA] Processando jogador: $playerId");
          if (!playerSnaps.containsKey(playerId)) {
            debugPrint(
              "[DISCIPLINA] Jogador $playerId não encontrado no cache. Pulando.",
            );
            continue;
          }

          final playerSnap = playerSnaps[playerId]!;
          final playerData = playerSnap.data() as Map<String, dynamic>? ?? {};

          // Pega os deltas para este jogador
          int yDelta = yellowDelta[playerId] ?? 0;
          int rDelta = redDelta[playerId] ?? 0;
          debugPrint(
            "[DISCIPLINA] Deltas para $playerId: yDelta=$yDelta, rDelta=$rDelta",
          );

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
          int redIncrementForTotal = rDelta; // Começa com o delta normal

          // Verifica o cenário: expulsão por 2º amarelo NESTE JOGO
          bool isSecondYellowRedScenario = (rDelta > 0 && yDelta == 2);
          if (isSecondYellowRedScenario) {
            yellowIncrementForTotal = 1; // Só incrementa 1 no total de amarelos
            // redIncrementForTotal já é 1 (pois rDelta é 1)
            debugPrint(
              "Jogador $playerId: Cenário 2º Amarelo + Vermelho detectado. Incremento Total CA: $yellowIncrementForTotal, CV: $redIncrementForTotal",
            );
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
          int finalReds = theoreticalNewReds; // Contagem corrente final
          bool finalSuspension = currentlySuspended;

          // 1. Verifica suspensão/reset por AMARELOS (usa theoreticalNewYellows)
          if (yDelta > 0 &&
              theoreticalNewYellows >= AdminService.suspensionYellowCards &&
              currentYellows < AdminService.suspensionYellowCards) {
            finalSuspension = true;
            if (AdminService.resetYellowsOnSuspension) {
              finalYellows = 0; // ZERA O CORRENTE
              debugPrint(
                "Jogador $playerId: Zerando amarelos CORRENTES por suspensão CA",
              );
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
              debugPrint(
                "Jogador $playerId: NÃO zerando amarelos CORRENTES por CV (Regra RedWhilePending)",
              );
            }

            if (shouldResetYellows) {
              finalYellows = 0; // ZERA O CORRENTE
              debugPrint(
                "Jogador $playerId: Zerando amarelos CORRENTES por CV (Regra ResetRed)",
              );
            }
          }

          // 3. Verifica REMOÇÃO de suspensão (usa finalYellows, finalReds)
          if (rDelta < 0 && finalYellows < AdminService.suspensionYellowCards) {
            // Se removeu vermelho E corrente de amarelos está abaixo do limite
            finalSuspension = false;
          }

          if (yDelta < 0 &&
              theoreticalNewYellows < AdminService.suspensionYellowCards &&
              currentYellows >= AdminService.suspensionYellowCards &&
              finalReds == 0) {
            // Se removeu amarelo caindo abaixo do limite E não tem vermelho corrente
            finalSuspension = false;
          }

          // --- Prepara o update para este jogador ---
          Map<String, dynamic> playerUpdateData = {
            'yellow_cards': finalYellows, // Salva contagem CORRENTE final
            'red_cards': finalReds, // Salva contagem CORRENTE final
            'total_yellow_cards':
                finalTotalYellows, // Salva contagem TOTAL final
            'total_red_cards': finalTotalReds, // Salva contagem TOTAL final
            'is_suspended': finalSuspension,
          };

          // Atualiza no batch (usando SET, não increment)
          transaction.update(
            _firestore.collection('players').doc(playerId),
            playerUpdateData,
          );

          // Calcula delta de pontos disciplinares (baseado nos DELTAS yDelta/rDelta)
          int pointsDelta = 0;
          if (isSecondYellowRedScenario) {
            // Usa a flag que calculamos antes
            pointsDelta =
                (1 * 10) +
                (1 * 21); // Conta SÓ o 1º amarelo (10) + o vermelho (21) = 31
            debugPrint(
              "[DISCIPLINA] Jogador $playerId: Cenário 2º CA+CV. pointsDelta = $pointsDelta",
            );
          } else {
            pointsDelta = (yDelta * 10) + (rDelta * 21);
            debugPrint(
              "[DISCIPLINA] Jogador $playerId: Caso padrão. pointsDelta = ($yDelta * 10) + ($rDelta * 21) = $pointsDelta",
            );
          }
          // --- FIM DA LÓGICA ATUALIZADA ---

          final String? playerTeamId = playerSnap.get(
            'team_id',
          ); // Pega o ID do time

          if (playerTeamId == homeTeamId) {
            disciplinaryHomeDelta += pointsDelta;
            debugPrint(
              "[DISCIPLINA] Acumulado Casa: $disciplinaryHomeDelta (adicionado $pointsDelta de $playerId)",
            );
          } else if (playerTeamId == awayTeamId) {
            disciplinaryAwayDelta += pointsDelta;
            debugPrint(
              "[DISCIPLINA] Acumulado Visitante: $disciplinaryAwayDelta (adicionado $pointsDelta de $playerId)",
            );
          } else {
            debugPrint(
              "[DISCIPLINA] ERRO: Jogador $playerId não pertence a nenhum dos times da partida ($homeTeamId vs $awayTeamId). TeamID: $playerTeamId",
            );
          }
        } // Fim do loop for playerId

        debugPrint(
          "[PONTOS] Antes Update Disc.: TimeCasa=$homeTeamId, Delta=$disciplinaryHomeDelta | TimeFora=$awayTeamId, Delta=$disciplinaryAwayDelta",
        );

        // Aplica o DELTA de pontos disciplinares
        final homeTeamRef = _firestore.collection('teams').doc(homeTeamId);
        final awayTeamRef = _firestore.collection('teams').doc(awayTeamId);

        // Só aplica se o delta for diferente de zero para evitar escritas desnecessárias
        if (disciplinaryHomeDelta != 0) {
          transaction.update(homeTeamRef, {
            'disciplinary_points': FieldValue.increment(disciplinaryHomeDelta),
          });
          debugPrint(
            "[DISCIPLINA] Aplicando Delta Casa: $disciplinaryHomeDelta",
          );
        }
        if (disciplinaryAwayDelta != 0) {
          transaction.update(awayTeamRef, {
            'disciplinary_points': FieldValue.increment(disciplinaryAwayDelta),
          });
          debugPrint(
            "[DISCIPLINA] Aplicando Delta Visitante: $disciplinaryAwayDelta",
          );
        }

        // --- NOVO: Delta de Gols Sofridos ---
        //Map<String, int> goalsConcededDelta = _calculateDelta(oldGoalsConceded, newGoalsConceded);
        goalsConcededDelta.forEach((playerId, delta) {
          if (delta != 0 && playerSnaps.containsKey(playerId)) {
            // Atualiza o campo 'goals_conceded' no documento do jogador
            transaction.update(_firestore.collection('players').doc(playerId), {
              'goals_conceded': FieldValue.increment(delta),
            });
          }
        });
        // --- FIM DO DELTA ---

        // --- NOVO: Delta de Craque do Jogo ---
        if (oldManOfTheMatchId != newManOfTheMatchId) {
          // Remove do antigo
          if (oldManOfTheMatchId != null &&
              playerSnaps.containsKey(oldManOfTheMatchId)) {
            transaction.update(
              _firestore.collection('players').doc(oldManOfTheMatchId),
              {'man_of_the_match_awards': FieldValue.increment(-1)},
            );
          }
          // Adiciona ao novo
          if (newManOfTheMatchId != null &&
              playerSnaps.containsKey(newManOfTheMatchId)) {
            transaction.update(
              _firestore.collection('players').doc(newManOfTheMatchId),
              {'man_of_the_match_awards': FieldValue.increment(1)},
            );
          }
        }
        // --- FIM DO DELTA ---
      }); // Fim da Transação

      // --- PÓS-TRANSAÇÃO: RECALCULAR OS DOIS TIMES ---
      debugPrint(
        "[PONTOS] Transação concluída. Iniciando recálculo para $homeTeamId e $awayTeamId...",
      );
      // (Esta parte continua igual)
      await _recalculateTeamStats(homeTeamId);
      await _recalculateTeamStats(awayTeamId);

      return "Sucesso";
    } catch (e) {
      debugPrint('Erro na transação: $e');
      return "Erro: ${e.toString()}";
    }
  }

  // --- NOVA FUNÇÃO PARA GERAR SEMIFINAIS ---
  Future<String> generateSemifinals() async {
    debugPrint("Iniciando geração de semifinais...");
    try {
      // 1. Verificar se a primeira fase terminou (opcional, mas recomendado)
      //    Você pode querer adicionar uma flag 'is_phase1_complete' no config/app_settings
      //    ou verificar se todos os jogos 'phase: first' estão 'finished'.
      //    Por simplicidade, pularemos essa verificação agora.

      // 2. Buscar a classificação FINAL da primeira fase (Top 4)
      //    IMPORTANTE: Esta query assume que os dados em 'teams' estão 100% atualizados
      //    pela função _recalculateTeamStats. A lógica de confronto direto
      //    NÃO é aplicada aqui, apenas os critérios do Firestore.
      final teamsSnapshot = await _firestore.collection('teams').get();
      final matchesSnapshot = await _firestore
          .collection('matches')
          .where('status', isEqualTo: 'finished')
          // Adiciona filtro de fase para garantir que só conta jogos da 1a fase (IMPORTANTE!)
          .where('phase', isEqualTo: 'first')
          .get();

      if (teamsSnapshot.docs.isEmpty) {
        return "Erro: Nenhuma equipe encontrada para gerar classificação.";
      }
      debugPrint(
        "Times (${teamsSnapshot.docs.length}) e Jogos Finalizados 1ª Fase (${matchesSnapshot.docs.length}) buscados.",
      );

      // 2. Converter times e Ordenar usando StandingsSorter
      List<TeamStanding> standings = teamsSnapshot.docs
          .map((doc) => TeamStanding(doc)) // Usa classe do utilitário
          .toList();

      final sorter = StandingsSorter(finishedMatches: matchesSnapshot.docs);
      List<TeamStanding> sortedStandings = sorter.sort(
        standings,
      ); // Ordena com a lógica completa

      // 3. Pegar os Top 4 da lista ordenada
      if (sortedStandings.length < 4) {
        return "Erro: Menos de 4 times classificados (${sortedStandings.length}). Não é possível gerar semifinais.";
      }
      final team1 = sortedStandings[0]; // 1º Colocado
      final team2 = sortedStandings[1]; // 2º Colocado
      final team3 = sortedStandings[2]; // 3º Colocado
      final team4 = sortedStandings[3]; // 4º Colocado
      debugPrint(
        "Classificação final (Top 4): 1º-${team1.id}, 2º-${team2.id}, 3º-${team3.id}, 4º-${team4.id}",
      );

      // 3. Verificar se semifinais já existem
      final existingSemis = await _firestore
          .collection('matches')
          .where('phase', isEqualTo: 'semifinal')
          .limit(1)
          .get();

      if (existingSemis.docs.isNotEmpty) {
        debugPrint(
          "Semifinais existentes encontradas. Elas serão sobrescritas.",
        );
        return "Aviso: Jogos da Semifinal já parecem existir.";
      }

      // 4. Criar os documentos das semifinais
      final WriteBatch batch = _firestore.batch();
      final semiFinalRef1 = _firestore.collection('matches').doc();
      final semiFinalRef2 = _firestore.collection('matches').doc();

      // Jogo 1: 1º vs 4º
      batch.set(semiFinalRef1, {
        'phase': 'semifinal',
        'order': 1,
        'round': null,
        'datetime': null,
        'location': 'A definir',
        'status': 'pending',
        'score_home': null,
        'score_away': null,
        'team_home_id': team1.id,
        'team_home_name': team1.data['name'] ?? 'Time 1',
        'team_home_shield': team1.data['shield_url'] ?? '',
        'team_away_id': team4.id,
        'team_away_name': team4.data['name'] ?? 'Time 4',
        'team_away_shield': team4.data['shield_url'] ?? '',
      });

      debugPrint("Jogo Semifinal 1 criado: ${team1.id} vs ${team4.id}");

      // Jogo 2: 2º vs 3º
      batch.set(semiFinalRef2, {
        'phase': 'semifinal',
        'order': 2, // <-- ADICIONA ORDEM 2
        'round': null,
        'datetime': null,
        'location': 'A definir',
        'status': 'pending',
        'score_home': null,
        'score_away': null,
        'team_home_id': team2.id,
        'team_home_name': team2.data['name'] ?? 'Time 2',
        'team_home_shield': team2.data['shield_url'] ?? '',
        'team_away_id': team3.id,
        'team_away_name': team3.data['name'] ?? 'Time 3',
        'team_away_shield': team3.data['shield_url'] ?? '',
      });
      debugPrint("Jogo Semifinal 2 criado: ${team2.id} vs ${team3.id}");

      // 6. Commit
      await batch.commit();
      debugPrint("Batch commit para semifinais concluído.");
      return "Sucesso! Jogos da Semifinal gerados (1ºx4º, 2ºx3º).";
    } catch (e) {
      debugPrint("Erro ao gerar semifinais: $e");
      return "Erro ao gerar semifinais: ${e.toString()}";
    }
  }
  // --- FIM DA FUNÇÃO ---

  // --- FUNÇÃO generateFinal SUBSTITUÍDA POR generateFinals ---
  Future<String> generateFinals() async {
    // Nome mudou
    debugPrint("Iniciando geração da Final e 3º Lugar...");
    try {
      // 1. Buscar os jogos da semifinal
      final semisSnapshot = await _firestore
          .collection('matches')
          .where('phase', isEqualTo: 'semifinal')
          .get();

      if (semisSnapshot.docs.length != 2) {
        return "Erro: Esperava 2 jogos de semifinal, encontrou ${semisSnapshot.docs.length}.";
      }
      debugPrint(
        "Jogos da semifinal encontrados: ${semisSnapshot.docs.length}",
      );

      // 2. Validar status, placares e determinar VENCEDORES e PERDEDORES
      String? winner1Id, winner1Name, winner1Shield;
      String? loser1Id, loser1Name, loser1Shield;
      String? winner2Id, winner2Name, winner2Shield;
      String? loser2Id, loser2Name, loser2Shield;

      List<DocumentSnapshot> semis = semisSnapshot.docs;

      for (int i = 0; i < semis.length; i++) {
        final matchDoc = semis[i];
        final data = matchDoc.data() as Map<String, dynamic>?;

        if (data == null)
          return "Erro: Dados inválidos na semifinal ${matchDoc.id}.";
        if (data['status'] != 'finished')
          return "Erro: Semifinal ${data['team_home_name']} x ${data['team_away_name']} não finalizada.";
        if (data['score_home'] == null || data['score_away'] == null)
          return "Erro: Placar não definido na semifinal ${matchDoc.id}.";
        if (data['score_home'] == data['score_away'])
          return "Erro: Empate na semifinal ${matchDoc.id}. Resolva antes de gerar a final.";

        // Determina vencedor e perdedor da partida atual
        String currentWinnerId, currentWinnerName, currentWinnerShield;
        String currentLoserId, currentLoserName, currentLoserShield;

        if (data['score_home'] > data['score_away']) {
          // Casa Venceu
          currentWinnerId = data['team_home_id'];
          currentWinnerName = data['team_home_name'];
          currentWinnerShield = data['team_home_shield'];
          currentLoserId = data['team_away_id'];
          currentLoserName = data['team_away_name'];
          currentLoserShield = data['team_away_shield'];
        } else {
          // Visitante Venceu
          currentWinnerId = data['team_away_id'];
          currentWinnerName = data['team_away_name'];
          currentWinnerShield = data['team_away_shield'];
          currentLoserId = data['team_home_id'];
          currentLoserName = data['team_home_name'];
          currentLoserShield = data['team_home_shield'];
        }

        // Atribui aos Vencedores/Perdedores 1 ou 2
        if (i == 0) {
          winner1Id = currentWinnerId;
          winner1Name = currentWinnerName;
          winner1Shield = currentWinnerShield;
          loser1Id = currentLoserId;
          loser1Name = currentLoserName;
          loser1Shield = currentLoserShield;
        } else {
          winner2Id = currentWinnerId;
          winner2Name = currentWinnerName;
          winner2Shield = currentWinnerShield;
          loser2Id = currentLoserId;
          loser2Name = currentLoserName;
          loser2Shield = currentLoserShield;
        }
        debugPrint(
          "Semi ${i + 1}: Vencedor=$currentWinnerName, Perdedor=$currentLoserName",
        );
      }

      // Garante que todos foram encontrados
      if (winner1Id == null ||
          winner2Id == null ||
          loser1Id == null ||
          loser2Id == null) {
        return "Erro: Não foi possível determinar todos os participantes das finais.";
      }

      // 3. Verificar se final OU terceiro lugar já existem
      final existingFinal = await _firestore
          .collection('matches')
          .where('phase', isEqualTo: 'final')
          .limit(1)
          .get();
      final existingThird = await _firestore
          .collection('matches')
          .where('phase', isEqualTo: 'third_place')
          .limit(1)
          .get();

      if (existingFinal.docs.isNotEmpty || existingThird.docs.isNotEmpty) {
        debugPrint(
          "Aviso: Jogo da Final ou 3º Lugar já existe. Nenhuma ação realizada.",
        );
        return "Aviso: Jogo da Final e/ou 3º Lugar já parecem existir.";
      }

      // 4. Criar os documentos da final e terceiro lugar
      final WriteBatch batch = _firestore.batch();
      final finalRef = _firestore.collection('matches').doc();
      final thirdPlaceRef = _firestore.collection('matches').doc();

      // Jogo da Final: Vencedor 1 vs Vencedor 2
      batch.set(finalRef, {
        'phase': 'final',
        'order': 1, // Ordem 1 para a final
        'round': null,
        'datetime': null,
        'location': 'A definir',
        'status': 'pending',
        'score_home': null, 'score_away': null,
        'team_home_id': winner1Id,
        'team_home_name': winner1Name ?? 'Vencedor Semi 1',
        'team_home_shield': winner1Shield ?? '',
        'team_away_id': winner2Id,
        'team_away_name': winner2Name ?? 'Vencedor Semi 2',
        'team_away_shield': winner2Shield ?? '',
      });
      debugPrint("Jogo da Final criado: $winner1Name vs $winner2Name");

      // Jogo do Terceiro Lugar: Perdedor 1 vs Perdedor 2
      batch.set(thirdPlaceRef, {
        'phase': 'third_place',
        'order': 1, // Ordem 1 (só tem um jogo nessa fase)
        'round': null,
        'datetime': null,
        'location': 'A definir',
        'status': 'pending',
        'score_home': null, 'score_away': null,
        'team_home_id': loser1Id,
        'team_home_name': loser1Name ?? 'Perdedor Semi 1',
        'team_home_shield': loser1Shield ?? '',
        'team_away_id': loser2Id,
        'team_away_name': loser2Name ?? 'Perdedor Semi 2',
        'team_away_shield': loser2Shield ?? '',
      });
      debugPrint("Jogo de 3º Lugar criado: $loser1Name vs $loser2Name");

      // 5. Commit
      await batch.commit();
      debugPrint("Batch commit para final e 3º lugar concluído.");
      return "Sucesso! Jogos da Final e 3º Lugar gerados.";
    } catch (e) {
      debugPrint("Erro ao gerar finais: $e");
      return "Erro ao gerar finais: ${e.toString()}";
    }
  }
  // --- FIM DA FUNÇÃO ---

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

    debugPrint(
      "[PONTOS] Recalculo $teamId - Após jogos Casa: MP=$totalMatchPoints, J=$totalGames, V=$totalWins, E=$totalDraws, D=$totalLosses, GP=$totalGoalsFor, GC=$totalGoalsAgainst",
    );

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

    debugPrint(
      "[PONTOS] Recalculo $teamId - Após jogos Fora: MP=$totalMatchPoints, J=$totalGames, V=$totalWins, E=$totalDraws, D=$totalLosses, GP=$totalGoalsFor, GC=$totalGoalsAgainst",
    );

    // --- 4. LER PONTOS EXTRAS ATUAIS E ATUALIZAR O TIME ---
    try {
      final teamRef = _firestore.collection('teams').doc(teamId);
      final teamSnap = await teamRef.get(); // Lê o estado atual do time
      final currentExtraPoints =
          (teamSnap.data()?['extra_points'] ?? 0) as int; // Pega extra_points

      debugPrint(
        "[PONTOS] Recalculo $teamId - Extra Points atuais lidos: $currentExtraPoints",
      );

      // Calcula o total final
      final int finalTotalPoints = totalMatchPoints + currentExtraPoints;
      final int finalGoalDifference = totalGoalsFor - totalGoalsAgainst;

      debugPrint(
        "[PONTOS] Recalculo $teamId - Update Final: MP=$totalMatchPoints, EP=$currentExtraPoints, P=$finalTotalPoints, J=$totalGames, V=$totalWins, E=$totalDraws, D=$totalLosses, GP=$totalGoalsFor, GC=$totalGoalsAgainst, SG=$finalGoalDifference",
      );

      // ATUALIZA o documento do time com valores absolutos
      await teamRef.update({
        'match_points': totalMatchPoints, // Define os pontos SÓ de jogos
        'points': finalTotalPoints, // Define o TOTAL (jogos + extras)
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
