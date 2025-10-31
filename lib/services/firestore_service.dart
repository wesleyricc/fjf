// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart'; // Para debugPrint
import 'admin_service.dart'; // Para acessar regras globais
import '../utils/standings_sorter.dart'; // Para ordenação complexa
import 'package:firebase_storage/firebase_storage.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(bucket: "fjfapp.appspot.com");

  // --- Função Auxiliar: Calcular Delta entre Mapas ---
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

  // --- FUNÇÕES CRUD DE MÍDIAS (NOVAS) ---

  Future<int> getNextMediaOrder() async {
    try {
      final snapshot = await _firestore
          .collection('media_feed')
          .orderBy('order', descending: true)
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) {
        return 1; // É o primeiro item
      }
      
      final lastOrder = (snapshot.docs.first.data()['order'] as num?) ?? 0;
      return lastOrder.toInt() + 1;
    } catch (e) {
      debugPrint("Erro ao buscar próxima ordem: $e");
      return 1; // Retorna 1 em caso de erro
    }
  }

  Future<String> createMediaItem({
    required String title,
    required String targetUrl,
    required String imageUrl,
    required int order,
  }) async {
    try {
      await _firestore.collection('media_feed').add({
        'title': title,
        'targetUrl': targetUrl,
        'imageUrl': imageUrl,
        'order': order,
        'isActive': true, // Sempre ativo ao criar
      });
      return "Sucesso: Mídia criada.";
    } catch (e) {
      return "Erro ao criar mídia: ${e.toString()}";
    }
  }

  Future<String> updateMediaItem({
    required String docId,
    required String title,
    required String targetUrl,
    required String imageUrl,
    required int order,
  }) async {
    try {
      await _firestore.collection('media_feed').doc(docId).update({
        'title': title,
        'targetUrl': targetUrl,
        'imageUrl': imageUrl,
        'order': order,
      });
      return "Sucesso: Mídia atualizada.";
    } catch (e) {
      return "Erro ao atualizar mídia: ${e.toString()}";
    }
  }

  Future<String> deleteMediaItem(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final String imageUrl = data['imageUrl'] ?? '';

    try {
      // 1. Tenta deletar a imagem do Storage (se houver)
      if (imageUrl.isNotEmpty && imageUrl.contains('firebasestorage')) {
        try {
          // Usa o bucket correto
          final ref = _storage.refFromURL(imageUrl); 
          await ref.delete();
          debugPrint("Imagem da mídia deletada do Storage: $imageUrl");
        } catch (e) {
          debugPrint("Aviso: Falha ao deletar imagem do Storage (pode já ter sido removida): $e");
        }
      }
      
      // 2. Deleta o documento do Firestore
      await doc.reference.delete();
      return "Sucesso: Mídia deletada.";
    } catch (e) {
      return "Erro ao deletar mídia: ${e.toString()}";
    }
  }
  // --- FIM DAS FUNÇÕES DE MÍDIA ---

  // --- Função _recalculateTeamStats (MOVIDA PARA CIMA) ---
  // (Esta função permanece a mesma, calculando apenas stats da 1ª Fase)
  Future<void> _recalculateTeamStats(String teamId) async {
    debugPrint("[SERVICE_RECALC] Recalculando Time (1ª Fase): $teamId");
    // 1. Inicializa totais
    int totalMatchPoints = 0;
    int totalGames = 0;
    int totalWins = 0;
    int totalDraws = 0;
    int totalLosses = 0;
    int totalGoalsFor = 0;
    int totalGoalsAgainst = 0;

    // 2. Busca jogos em casa DA PRIMEIRA FASE
    final homeMatches = await _firestore
        .collection('matches')
        .where('team_home_id', isEqualTo: teamId)
        .where('status', whereIn: ['finished', 'in_progress'])
        .where('phase', isEqualTo: 'first')
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

    // 3. Busca jogos fora DA PRIMEIRA FASE
    final awayMatches = await _firestore
        .collection('matches')
        .where('team_away_id', isEqualTo: teamId)
        .where('status', whereIn: ['finished', 'in_progress'])
        .where('phase', isEqualTo: 'first')
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

    // 4. LER PONTOS EXTRAS ATUAIS E ATUALIZAR O TIME
    try {
      final teamRef = _firestore.collection('teams').doc(teamId);
      final teamSnap = await teamRef.get();
      final currentExtraPoints = (teamSnap.data()?['extra_points'] ?? 0) as int;
      final int finalTotalPoints = totalMatchPoints + currentExtraPoints;
      final int finalGoalDifference = totalGoalsFor - totalGoalsAgainst;

      debugPrint(
        "[SERVICE_RECALC] Update Final Time $teamId (1ªF): P=$finalTotalPoints (MP=$totalMatchPoints + EP=$currentExtraPoints), J=$totalGames, V=$totalWins, E=$totalDraws, D=$totalLosses, GP=$totalGoalsFor, GC=$totalGoalsAgainst, SG=$finalGoalDifference ...",
      ); // Log reduzido

      await teamRef.update({
        'match_points': totalMatchPoints, 'points': finalTotalPoints,
        'games_played': totalGames,
        'wins': totalWins,
        'draws': totalDraws,
        'losses': totalLosses,
        'goals_for': totalGoalsFor, 'goals_against': totalGoalsAgainst,
        'goal_difference': finalGoalDifference,
        // NÃO atualiza 'extra_points', 'disciplinary_points', 'total_*_cards', 'phase1_rank' aqui
      });
      debugPrint("[SERVICE_RECALC] Update Time $teamId Concluído.");
    } catch (e) {
      debugPrint("[SERVICE_RECALC] ERRO ao atualizar time $teamId: $e");
    }
  }
  // --- FIM _recalculateTeamStats ---

  // --- NOVAS FUNÇÕES CRUD DE JOGADOR ---

  Future<String> createPlayer({
    required String name,
    required bool isGoalkeeper,
    required String teamId,
    required String teamName,
    required String teamShieldUrl,
    required int? jerseyNumber,
    required bool isStaff,
    required String? staffRole,
  }) async {
    try {
      await _firestore.collection('players').add({
        'name': name,
        'is_goalkeeper': isGoalkeeper,
        'team_id': teamId,
        'team_name': teamName,
        'team_shield_url': teamShieldUrl,
        'jersey_number': jerseyNumber,
        // Inicializa todas as estatísticas
        'goals': 0, 'assists': 0,
        'yellow_cards': 0, 'red_cards': 0,
        'total_yellow_cards': 0, 'total_red_cards': 0,
        'goals_conceded': 0,
        'man_of_the_match_awards': 0,
        'is_suspended': false,
        'is_staff': isStaff,
        'staff_role': isStaff ? staffRole : null,
        'isActive': true, // <-- Define como ativo
      });
      return "Sucesso: Membro '$name' criado.";
    } catch (e) {
      debugPrint("Erro ao criar membro: $e");
      return "Erro ao criar membro: ${e.toString()}";
    }
  }

  Future<String> updatePlayer({
    required DocumentSnapshot playerDoc,
    required String name,
    required bool isGoalkeeper,
    required int? jerseyNumber,
    required bool isStaff,
    required String? staffRole,
  }) async {
    try {
      await playerDoc.reference.update({
        'name': name,
        'is_goalkeeper': isGoalkeeper,
        'jersey_number': jerseyNumber,
        'is_staff': isStaff,
        'staff_role': isStaff ? staffRole : null,
      });
      return "Sucesso: Jogador '$name' atualizado.";
    } catch (e) {
      debugPrint("Erro ao atualizar jogador: $e");
      return "Erro ao atualizar jogador: ${e.toString()}";
    }
  }

  // Soft Delete: Apenas marca o jogador como inativo
  Future<String> deletePlayer(DocumentSnapshot playerDoc) async {
    try {
      await playerDoc.reference.update({'isActive': false});
      // Nota: Isso NÃO recalcula estatísticas. As estatísticas dele
      // permanecem nos totais (Time e Jogador Total), mas ele
      // desaparecerá das listas de jogadores ativos.
      return "Sucesso: Jogador excluído (inativado).";
    } catch (e) {
      debugPrint("Erro ao excluir jogador: $e");
      return "Erro ao excluir jogador: ${e.toString()}";
    }
  }
  // --- FIM CRUD JOGADOR ---

  // --- NOVA FUNÇÃO: CRIAR EQUIPE ---
  Future<String> createTeam({
    required String name,
    required String shortName,
    required String shieldUrl,
  }) async {
    try {
      final newTeamRef = _firestore.collection('teams').doc(); // ID automático

      // Define todos os campos de estatísticas como 0
      await newTeamRef.set({
        'name': name,
        'short_name': shortName,
        'shield_url': shieldUrl,
        // Stats de Classificação (1ª Fase)
        'points': 0,
        'match_points': 0,
        'extra_points': 0,
        'games_played': 0,
        'wins': 0,
        'draws': 0,
        'losses': 0,
        'goals_for': 0,
        'goals_against': 0,
        'goal_difference': 0,
        'phase1_rank': null,
        // Stats Disciplinares
        'disciplinary_points': 0,
        'total_yellow_cards': 0,
        'total_red_cards': 0,
      });
      return "Sucesso: Equipe '$name' criada.";
    } catch (e) {
      debugPrint("Erro ao criar equipe: $e");
      return "Erro ao criar equipe: ${e.toString()}";
    }
  }
  // --- FIM ---

  // --- NOVA FUNÇÃO: ATUALIZAR EQUIPE ---
  Future<String> updateTeam({
    required DocumentSnapshot teamDoc,
    required String name,
    required String shortName,
    required String shieldUrl,
  }) async {
    try {
      await teamDoc.reference.update({
        'name': name,
        'short_name': shortName,
        'shield_url': shieldUrl,
      });

      // ATENÇÃO: Se o nome ou escudo mudou, idealmente deveríamos
      // atualizar 'team_home_name', 'team_away_name', etc.
      // em TODOS os 'matches' e 'players'.
      // Isso é uma operação MUITO CUSTOSA (Cloud Function seria melhor).
      // Por enquanto, vamos assumir que o admin sabe que precisa
      // recriar os jogos ou que os nomes antigos persistirão.
      debugPrint(
        "Aviso: Nome/Escudo da equipe alterado. Jogos e jogadores antigos não serão atualizados automaticamente.",
      );

      return "Sucesso: Equipe '$name' atualizada.";
    } catch (e) {
      debugPrint("Erro ao atualizar equipe: $e");
      return "Erro ao atualizar equipe: ${e.toString()}";
    }
  }
  // --- FIM ---

  // --- NOVA FUNÇÃO DE MIGRAÇÃO ---
  Future<String> migratePlayersV1() async {
    debugPrint("[MIGRAÇÃO] Iniciando migração de jogadores...");
    // Configura um WriteBatch. Limite de 500 operações por batch.
    WriteBatch batch = _firestore.batch();
    int documentsInBatch = 0;
    int totalUpdated = 0;

    try {
      // 1. Pega TODOS os jogadores
      final playersSnapshot = await _firestore.collection('players').get();
      debugPrint(
        "[MIGRAÇÃO] ${playersSnapshot.docs.length} jogadores encontrados.",
      );

      // 2. Itera por cada jogador
      for (final doc in playersSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};

        bool needsUpdate = false;
        Map<String, dynamic> updateData = {};

        // 3. Verifica se o campo 'is_staff' está faltando
        if (!data.containsKey('is_staff')) {
          updateData['is_staff'] = false; // Define o valor padrão
          needsUpdate = true;
          debugPrint(
            "[MIGRAÇÃO] Jogador ${doc.id}: 'is_staff' faltando. Adicionando 'false'.",
          );
        }

        // 4. Verifica se o campo 'jersey_number' está faltando
        if (!data.containsKey('jersey_number')) {
          updateData['jersey_number'] = null; // Define o valor padrão
          needsUpdate = true;
          debugPrint(
            "[MIGRAÇÃO] Jogador ${doc.id}: 'jersey_number' faltando. Adicionando 'null'.",
          );
        }

        // 5. Adiciona a atualização ao batch
        if (needsUpdate) {
          batch.update(doc.reference, updateData);
          documentsInBatch++;
          totalUpdated++;
        }

        // 6. Envia o batch se atingir o limite de 500 e começa um novo
        if (documentsInBatch == 499) {
          debugPrint("[MIGRAÇÃO] Enviando batch de 500...");
          await batch.commit();
          batch = _firestore.batch(); // Reinicia o batch
          documentsInBatch = 0;
        }
      }

      // 7. Envia o último batch (o que sobrou)
      if (documentsInBatch > 0) {
        debugPrint("[MIGRAÇÃO] Enviando batch final de $documentsInBatch...");
        await batch.commit();
      }

      debugPrint("[MIGRAÇÃO] Concluída. $totalUpdated jogadores atualizados.");
      return "Sucesso: $totalUpdated jogadores foram atualizados com os novos campos.";
    } catch (e) {
      debugPrint("[MIGRAÇÃO] ERRO: $e");
      return "Erro durante a migração: ${e.toString()}";
    }
  }
  // --- FIM DA MIGRAÇÃO ---

  // --- NOVA FUNÇÃO: EXCLUIR EQUIPE (CASCATA) ---
  Future<String> deleteTeam(DocumentSnapshot teamDoc) async {
    debugPrint("INICIANDO EXCLUSÃO EM CASCATA PARA: ${teamDoc.id}");
    final teamId = teamDoc.id;
    final WriteBatch batch = _firestore.batch();
    Set<String> opponentsToRecalculate = {}; // Para recalcular classificação

    try {
      // 1. Encontrar e deletar JOGADORES do time
      final playersSnapshot = await _firestore
          .collection('players')
          .where('team_id', isEqualTo: teamId)
          .get();
      for (final player in playersSnapshot.docs) {
        batch.delete(player.reference);
      }
      debugPrint(
        "Exclusão: ${playersSnapshot.docs.length} jogadores marcados para deleção.",
      );

      // 2. Encontrar e deletar PARTIDAS onde o time era CASA
      final homeMatches = await _firestore
          .collection('matches')
          .where('team_home_id', isEqualTo: teamId)
          .get();
      for (final match in homeMatches.docs) {
        final data = match.data() as Map<String, dynamic>? ?? {};
        // Se a partida era da 1ª Fase e finalizada, marca o Oponente para recalcular
        if (data['status'] == 'finished' &&
            data['phase'] == 'first' &&
            data['team_away_id'] != null) {
          opponentsToRecalculate.add(data['team_away_id']);
        }
        batch.delete(match.reference);
      }
      debugPrint(
        "Exclusão: ${homeMatches.docs.length} jogos (casa) marcados para deleção.",
      );

      // 3. Encontrar e deletar PARTIDAS onde o time era VISITANTE
      final awayMatches = await _firestore
          .collection('matches')
          .where('team_away_id', isEqualTo: teamId)
          .get();
      for (final match in awayMatches.docs) {
        final data = match.data() as Map<String, dynamic>? ?? {};
        // Se a partida era da 1ª Fase e finalizada, marca o Oponente para recalcular
        if (data['status'] == 'finished' &&
            data['phase'] == 'first' &&
            data['team_home_id'] != null) {
          opponentsToRecalculate.add(data['team_home_id']);
        }
        batch.delete(match.reference);
      }
      debugPrint(
        "Exclusão: ${awayMatches.docs.length} jogos (visitante) marcados para deleção.",
      );

      // 4. Deletar a própria EQUIPE
      batch.delete(teamDoc.reference);
      debugPrint("Exclusão: Equipe ${teamDoc.id} marcada para deleção.");

      // 5. Executar o Batch (Todas as deleções)
      await batch.commit();
      debugPrint("Batch de exclusão concluído.");

      // 6. Recalcular classificação dos oponentes afetados (PÓS-BATCH)
      if (opponentsToRecalculate.isNotEmpty) {
        debugPrint(
          "Recalculando classificação para ${opponentsToRecalculate.length} oponentes afetados...",
        );
        for (String opponentId in opponentsToRecalculate) {
          await _recalculateTeamStats(
            opponentId,
          ); // Chama a função que já temos
        }
        debugPrint("Recálculo de oponentes concluído.");
      }

      return "Sucesso: Equipe e todos os seus dados associados (jogadores, partidas) foram excluídos.";
    } catch (e) {
      debugPrint("Erro ao excluir equipe: $e");
      return "Erro ao excluir equipe: ${e.toString()}";
    }
  }
  // --- FIM ---

  // --- NOVA FUNÇÃO: CRIAR PARTIDA ---
  Future<String> createMatch({
    required DocumentSnapshot homeTeam, // Doc completo do time
    required DocumentSnapshot awayTeam, // Doc completo do time
    required String location,
    required int round,
    required DateTime dateTime,
  }) async {
    try {
      final homeTeamData = homeTeam.data() as Map<String, dynamic>;
      final awayTeamData = awayTeam.data() as Map<String, dynamic>;

      await _firestore.collection('matches').add({
        'phase': 'first', // Só permite criar jogos da 1ª fase
        'round': round,
        'datetime': Timestamp.fromDate(dateTime),
        'location': location,
        'status': 'pending',
        'score_home': null,
        'score_away': null,
        'penalty_score_home': null,
        'penalty_score_away': null,
        'winner_team_id': null,
        'stats_applied': null,
        'team_home_id': homeTeam.id,
        'team_home_name': homeTeamData['name'] ?? '?',
        'team_home_shield': homeTeamData['shield_url'] ?? '',
        'team_away_id': awayTeam.id,
        'team_away_name': awayTeamData['name'] ?? '?',
        'team_away_shield': awayTeamData['shield_url'] ?? '',
      });
      return "Sucesso: Partida criada.";
    } catch (e) {
      debugPrint("Erro ao criar partida: $e");
      return "Erro ao criar partida: ${e.toString()}";
    }
  }
  // --- FIM ---

  // --- NOVA FUNÇÃO: ATUALIZAR DETALHES DA PARTIDA ---
  Future<String> updateMatchDetails({
    required DocumentSnapshot match,
    required DocumentSnapshot homeTeam,
    required DocumentSnapshot awayTeam,
    required String location,
    required int round,
    required DateTime dateTime,
    required String phase, // Fase (para editar 2ª fase)
  }) async {
    try {
      final homeTeamData = homeTeam.data() as Map<String, dynamic>;
      final awayTeamData = awayTeam.data() as Map<String, dynamic>;

      await match.reference.update({
        'phase': phase,
        'round': round,
        'datetime': Timestamp.fromDate(dateTime),
        'location': location,
        'team_home_id': homeTeam.id,
        'team_home_name': homeTeamData['name'] ?? '?',
        'team_home_shield': homeTeamData['shield_url'] ?? '',
        'team_away_id': awayTeam.id,
        'team_away_name': awayTeamData['name'] ?? '?',
        'team_away_shield': awayTeamData['shield_url'] ?? '',
      });
      return "Sucesso: Detalhes da partida atualizados.";
    } catch (e) {
      debugPrint("Erro ao atualizar detalhes: $e");
      return "Erro ao atualizar detalhes: ${e.toString()}";
    }
  }
  // --- FIM ---

  // --- NOVA FUNÇÃO: EXCLUIR PARTIDA ---
  Future<String> deleteMatch(DocumentSnapshot match) async {
    try {
      final data = match.data() as Map<String, dynamic>? ?? {};
      final status = data['status'] ?? 'pending';
      final phase = data['phase'] ?? 'first';
      final homeTeamId = data['team_home_id'];
      final awayTeamId = data['team_away_id'];

      // 1. Deleta o documento da partida
      await match.reference.delete();

      // 2. Se a partida era da 1ª Fase e estava 'finished',
      // precisamos recalcular a classificação dos times envolvidos.
      if (status == 'finished' && phase == 'first') {
        debugPrint(
          "Partida finalizada da 1ª Fase excluída. Recalculando times...",
        );
        if (homeTeamId != null) await _recalculateTeamStats(homeTeamId);
        if (awayTeamId != null) await _recalculateTeamStats(awayTeamId);
      }

      return "Sucesso: Partida excluída.";
    } catch (e) {
      debugPrint("Erro ao excluir partida: $e");
      return "Erro ao excluir partida: ${e.toString()}";
    }
  }
  // --- FIM ---

  // --- Função Principal: Atualizar Estatísticas de uma Partida ---
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
    required int? penaltyScoreHome,
    required int? penaltyScoreAway,
    required String? winnerTeamId,
    required String? newSumulaUrl,
    required List<Map<String, dynamic>> newMediaLinks,
  }) async {
    final String matchId = matchSnapshot.id;
    final matchDataBefore = matchSnapshot.data() as Map<String, dynamic>? ?? {};
    // --- CORREÇÃO: Validação de Nulidade ---
    final String? homeTeamId = matchDataBefore['team_home_id'];
    final String? awayTeamId = matchDataBefore['team_away_id'];
    
    if (homeTeamId == null || awayTeamId == null) {
      return "Erro: A partida não possui IDs de time válidos.";
    }
    // --- FIM DA CORREÇÃO ---

    debugPrint("[SERVICE_UPDATE] Iniciando update para Jogo $matchId");

    try {
      await _firestore.runTransaction((transaction) async {
        // --- 1. LER DADOS ANTIGOS E JOGADORES (LEITURA) ---
        final DocumentSnapshot freshMatchSnap = await transaction.get(
          _firestore.collection('matches').doc(matchId),
        );
        final currentMatchData =
            freshMatchSnap.data() as Map<String, dynamic>? ?? {};

        Map<String, dynamic> oldStats =
            (currentMatchData.containsKey('stats_applied') &&
                currentMatchData['stats_applied'] != null)
            ? (currentMatchData['stats_applied'] ?? {})
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
        playersToReadIds.removeWhere((id) => id.isEmpty);

        Map<String, DocumentSnapshot> playerSnaps = {};
        for (String playerId in playersToReadIds) {
          var playerRef = _firestore.collection('players').doc(playerId);
          var snap = await transaction.get(playerRef);
          if (snap.exists) {
            playerSnaps[playerId] = snap;
          }
        }

        // --- CORREÇÃO: Lê os dados dos times AGORA ---
        final homeTeamRef = _firestore.collection('teams').doc(homeTeamId);
        final awayTeamRef = _firestore.collection('teams').doc(awayTeamId);
        final DocumentSnapshot homeTeamSnap = await transaction.get(homeTeamRef);
        final DocumentSnapshot awayTeamSnap = await transaction.get(awayTeamRef);
        
        final homeLogoUrl = (homeTeamSnap.data() as Map<String, dynamic>?)?['shield_url'] ?? '';
        final awayLogoUrl = (awayTeamSnap.data() as Map<String, dynamic>?)?['shield_url'] ?? '';
        // --- FIM DA CORREÇÃO (LEITURA) ---

        debugPrint(
          "[SERVICE_UPDATE] Leitura concluída. ${playerSnaps.length} jogadores encontrados.",
        );

        // --- 2. SALVAR O ESTADO ATUALIZADO DO JOGO (ESCRITA) ---
        final Map<String, dynamic> newPlayerStatsToSave = {
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
          'penalty_score_home': penaltyScoreHome,
          'penalty_score_away': penaltyScoreAway,
          'winner_team_id': winnerTeamId,
          'sumula_url': newSumulaUrl,
          'stats_applied': {
            'player_stats': newPlayerStatsToSave,
            'man_of_the_match': newManOfTheMatchId,
            'media_links': newMediaLinks,
          },
        });
        debugPrint(
          "[SERVICE_UPDATE] Documento do jogo $matchId atualizado na transação.",
        );

        // --- 3. APLICAR DELTAS NOS JOGADORES E CALCULAR DELTAS PARA TIMES (ESCRITA) ---
        int disciplinaryHomeDelta = 0;
        int disciplinaryAwayDelta = 0;
        int totalYellowHomeDelta = 0;
        int totalYellowAwayDelta = 0;
        int totalRedHomeDelta = 0;
        int totalRedAwayDelta = 0;

        // Calcula deltas
        Map<String, int> goalDelta = _calculateDelta(oldGoals, newGoals);
        Map<String, int> assistDelta = _calculateDelta(oldAssists, newAssists);
        Map<String, int> goalsConcededDelta = _calculateDelta(
          oldGoalsConceded,
          newGoalsConceded,
        );
        Map<String, int> yellowDelta = _calculateDelta(oldYellows, newYellows);
        Map<String, int> redDelta = _calculateDelta(oldReds, newReds);

        // Zera os acumuladores de delta ANTES do loop
        disciplinaryHomeDelta = 0;
        disciplinaryAwayDelta = 0;
        totalYellowHomeDelta = 0;
        totalYellowAwayDelta = 0;
        totalRedHomeDelta = 0;
        totalRedAwayDelta = 0;

        // Aplica deltas simples (Gols, Assists, Gols Sofridos) aos jogadores
        goalDelta.forEach((playerId, delta) {
          if (delta != 0 && playerSnaps.containsKey(playerId))
            transaction.update(playerSnaps[playerId]!.reference, {
              'goals': FieldValue.increment(delta),
            });
        });
        assistDelta.forEach((playerId, delta) {
          if (delta != 0 && playerSnaps.containsKey(playerId))
            transaction.update(playerSnaps[playerId]!.reference, {
              'assists': FieldValue.increment(delta),
            });
        });
        goalsConcededDelta.forEach((playerId, delta) {
          if (delta != 0 && playerSnaps.containsKey(playerId))
            transaction.update(playerSnaps[playerId]!.reference, {
              'goals_conceded': FieldValue.increment(delta),
            });
        });

        // Aplica delta do Craque do Jogo
        if (oldManOfTheMatchId != newManOfTheMatchId) {
          if (oldManOfTheMatchId != null &&
              playerSnaps.containsKey(oldManOfTheMatchId))
            transaction.update(playerSnaps[oldManOfTheMatchId]!.reference, {
              'man_of_the_match_awards': FieldValue.increment(-1),
            });
          if (newManOfTheMatchId != null &&
              playerSnaps.containsKey(newManOfTheMatchId))
            transaction.update(playerSnaps[newManOfTheMatchId]!.reference, {
              'man_of_the_match_awards': FieldValue.increment(1),
            });
        }

        // --- LÓGICA COMPLEXA PARA CARTÕES (CORRIGIDA) ---
        
        Set<String> affectedCardPlayerIds = {...yellowDelta.keys, ...redDelta.keys};
        debugPrint("[DISCIPLINA] Iniciando cálculo de delta. Jogadores afetados: ${affectedCardPlayerIds.length}");

        for (String playerId in affectedCardPlayerIds) {
          debugPrint("[DISCIPLINA] Processando jogador: $playerId");
          if (!playerSnaps.containsKey(playerId)) {
            debugPrint(
              "[DISCIPLINA] Jogador $playerId não encontrado. Pulando.",
            );
            continue;
          }

          final playerSnap = playerSnaps[playerId]!;
          final playerData = playerSnap.data() as Map<String, dynamic>? ?? {};

          int yDelta = yellowDelta[playerId] ?? 0; // Ex: +2 (Adicionando) ou -2 (Removendo)
          int rDelta = redDelta[playerId] ?? 0;   // Ex: +1 (Adicionando) ou -1 (Removendo)
          debugPrint("[DISCIPLINA] Deltas do Jogo para $playerId: yDelta=$yDelta, rDelta=$rDelta");


          int currentYellows = playerData['yellow_cards'] ?? 0;
          int currentReds = playerData['red_cards'] ?? 0;
          bool currentlySuspended = playerData['is_suspended'] ?? false;
          int currentTotalYellows = playerData['total_yellow_cards'] ?? 0;
          int currentTotalReds = playerData['total_red_cards'] ?? 0;

          // --- 1. Calcula incrementos para JOGADOR e TIME (REGRAS NOVAS) ---
           
           // REGRA JOGADOR: `total_yellow_cards` soma TODOS os cartões.
           int playerTotalYellowIncrement = yDelta; // Ex: +2 (ou -2 se removendo)
           int playerTotalRedIncrement = rDelta;   // Ex: +1 (ou -1 se removendo)
           
           // REGRA JOGADOR: `yellow_cards` (corrente) soma apenas 1 por jogo
           int yellowIncrementForCurrent = 0;
           if (yDelta > 0) yellowIncrementForCurrent = 1; // Se levou 1, 2, ou mais CA, só conta +1
           else if (yDelta < 0) yellowIncrementForCurrent = -1; // Se removeu 1, 2, ou mais CA, só remove 1
           
           // REGRA TIME: `total_yellow_cards` e PD seguem regra especial
           int teamYellowTotalIncrement = yDelta; // Padrão: +2
           int teamRedTotalIncrement = rDelta;     // Padrão: +1
           int teamDisciplinaryPointsIncrement = (yDelta * 10) + (rDelta * 21); // Padrão: 41

           // Cenário Especial: 2 CA + 1 CV (Adição)
          bool isSecondYellowRedScenario_Add = (rDelta > 0 && yDelta == 2);
          // Cenário Especial: Remoção de 2 CA + 1 CV
          bool isSecondYellowRedScenario_Remove = (rDelta < 0 && yDelta == -2);

          if (isSecondYellowRedScenario_Add) {
             // Time: Só +1 CA no total, 31 PD
             teamYellowTotalIncrement = 1; // Regra Time: Só +1 CA no total
             teamDisciplinaryPointsIncrement = (1 * 10) + (1 * 21); // 31
             debugPrint("Jogador $playerId: Cenário 2CA+CV (Adição). Inc Time CA: $teamYellowTotalIncrement, Inc PD: $teamDisciplinaryPointsIncrement");
           } else if (isSecondYellowRedScenario_Remove) {
             // Time: Só -1 CA no total, -31 PD
             teamYellowTotalIncrement = -1; // Regra Time: Só -1 CA do total
             teamDisciplinaryPointsIncrement = -((1 * 10) + (1 * 21)); // -31
             debugPrint("Jogador $playerId: Cenário 2CA+CV (Remoção). Inc Time CA: $teamYellowTotalIncrement, Inc PD: $teamDisciplinaryPointsIncrement");
           }

          // --- 2. Lógica do Jogador (Corrente e Suspensão) ---
          int theoreticalNewYellows = currentYellows + yellowIncrementForCurrent;
          int theoreticalNewReds = currentReds + rDelta; // Vermelho corrente usa delta normal
           
          if (theoreticalNewYellows < 0) theoreticalNewYellows = 0;
          if (theoreticalNewReds < 0) theoreticalNewReds = 0;

          int finalYellows = theoreticalNewYellows;
          int finalReds = theoreticalNewReds;
          bool finalSuspension = currentlySuspended;

          // Verifica suspensão/reset por Amarelos
          if (yellowIncrementForCurrent > 0 &&
              theoreticalNewYellows >= AdminService.suspensionYellowCards &&
              currentYellows < AdminService.suspensionYellowCards) {
            finalSuspension = true;
            if (AdminService.resetYellowsOnSuspension) finalYellows = 0;
            debugPrint(
              "Jogador $playerId: Suspenso por CA. CA Corrente final: $finalYellows",
            );
          }

          // Verifica suspensão/reset por Vermelho
          if (rDelta > 0 && AdminService.suspensionOnRed) {
            finalSuspension = true;
            // A regra 'reset_yellows_on_red_while_pending' foi removida (ID 496)
            if (AdminService.resetYellowsOnRed) {
              finalYellows = 0;
              debugPrint(
                "Jogador $playerId: Zerando amarelos CORRENTES por CV (Regra ResetRed=true).",
              );
            }
          }

          // --- LÓGICA DE CRIAÇÃO DE LOG (ATUALIZADA) ---
           String suspensionReason = ""; 

           // Verifica suspensão/reset por Amarelos
           if (yellowIncrementForCurrent > 0 && 
               theoreticalNewYellows >= AdminService.suspensionYellowCards && 
               currentYellows < AdminService.suspensionYellowCards) 
           {
              if (!currentlySuspended) {
                finalSuspension = true;
                suspensionReason = "${AdminService.suspensionYellowCards} CA";
              }
              if (AdminService.resetYellowsOnSuspension) finalYellows = 0;
           }
           
           // Verifica suspensão/reset por Vermelho
           if (rDelta > 0 && AdminService.suspensionOnRed) {
              if (!currentlySuspended) {
                finalSuspension = true;
                suspensionReason = (suspensionReason.isNotEmpty) ? "$suspensionReason e CV" : "CV";
              }
              if (AdminService.resetYellowsOnRed) finalYellows = 0;
           }

           // Se uma nova suspensão foi detectada...
           if (suspensionReason.isNotEmpty) {
             debugPrint("[SUSPENSION LOG] Registrando nova suspensão para $playerId. Motivo: $suspensionReason");
             final logRef = _firestore.collection('suspension_log').doc();
             
             // --- LÓGICA DAS DATAS (NOVA) ---
             // Pega a data da partida do documento do jogo
             DateTime matchDate = DateTime.now(); // Fallback
             if (currentMatchData['datetime'] != null && currentMatchData['datetime'] is Timestamp) {
                matchDate = (currentMatchData['datetime'] as Timestamp).toDate();
             }
             // Calcula a data de retorno (Data da Partida + 10 dias)
             final DateTime returnDate = matchDate.add(const Duration(days: 10));

             // --- NOVO: BUSCAR E SALVAR A LOGO DA EQUIPE ---
            // --- Usa os dados do time pré-buscados (SEM transaction.get) ---
             String teamLogoUrl = ''; 
             final teamId = playerData['team_id'];
             if (teamId == homeTeamId) {
               teamLogoUrl = homeLogoUrl;
             } else if (teamId == awayTeamId) {
               teamLogoUrl = awayLogoUrl;
             }
             // --- Fim da correção ---
             // --- FIM NOVO ---
             // --- FIM ---
             
             transaction.set(logRef, {
               'playerId': playerId,
               'playerName': playerData['name'] ?? '?',
               'teamId': playerData['team_id'] ?? '?',
               'teamName': playerData['team_name'] ?? '?',
               'teamLogoUrl': teamLogoUrl, // <-- NOVO CAMPO
               'timestamp': Timestamp.fromDate(matchDate), // <-- USA A DATA DA PARTIDA
               'return_date': Timestamp.fromDate(returnDate), // <-- SALVA A DATA DE RETORNO
               'reason': suspensionReason,
               'matchId_occurred': matchId,
               'match_description': "Rodada ${currentMatchData['round']}: ${currentMatchData['team_home_name']} vs ${currentMatchData['team_away_name']}",
               // 'status': 'pending', // Não precisamos mais de 'status'
             });
           }
           // --- FIM DA LÓGICA DE LOG ---
           
          // Verifica remoção de suspensão
          if (rDelta < 0 && finalYellows < AdminService.suspensionYellowCards)
            finalSuspension = false;
          if (yellowIncrementForCurrent < 0 &&
              theoreticalNewYellows < AdminService.suspensionYellowCards &&
              currentYellows >= AdminService.suspensionYellowCards &&
              finalReds == 0)
            finalSuspension = false;

          // --- 3. Prepara update do jogador ---
          int finalTotalYellows = currentTotalYellows + playerTotalYellowIncrement; // Usa o delta real (yDelta)
          int finalTotalReds = currentTotalReds + playerTotalRedIncrement;     // Usa o delta real (rDelta)
          if (finalTotalYellows < 0) finalTotalYellows = 0;
          if (finalTotalReds < 0) finalTotalReds = 0;

          Map<String, dynamic> playerUpdateData = {
            'yellow_cards': finalYellows,
            'red_cards': finalReds,
            'total_yellow_cards': finalTotalYellows,
            'total_red_cards': finalTotalReds,
            'is_suspended': finalSuspension,
          };
          transaction.update(playerSnap.reference, playerUpdateData);
          debugPrint(
            "[DISCIPLINA] Atualizando Jogador $playerId: $playerUpdateData",
          );

          // --- 5. Acumula Deltas para Times (Totais e Disciplinares) ---
          final String? playerTeamId = playerData['team_id'];
           if (playerTeamId == homeTeamId) {
             disciplinaryHomeDelta += teamDisciplinaryPointsIncrement; // Ex: +31 ou -31
             totalYellowHomeDelta += teamYellowTotalIncrement;       // Ex: +1 ou -1
             totalRedHomeDelta += teamRedTotalIncrement;         // Ex: +1 ou -1
           } else if (playerTeamId == awayTeamId) {
             disciplinaryAwayDelta += teamDisciplinaryPointsIncrement;
             totalYellowAwayDelta += teamYellowTotalIncrement;
             totalRedAwayDelta += teamRedTotalIncrement;
           }
        } // Fim do loop for playerId // Fim loop for playerId
        debugPrint(
          "[PONTOS] Antes Update Disc.: TimeCasa=$homeTeamId, DeltaPD=$disciplinaryHomeDelta | TimeFora=$awayTeamId, DeltaPD=$disciplinaryAwayDelta",
        );

        // --- Aplica deltas acumulados aos TIMES ---
        //final homeTeamRef = _firestore.collection('teams').doc(homeTeamId);
        //final awayTeamRef = _firestore.collection('teams').doc(awayTeamId);

        // Cria mapas de update apenas se houver o que mudar
        Map<String, dynamic> homeUpdateData = {};
        if (disciplinaryHomeDelta != 0)
          homeUpdateData['disciplinary_points'] = FieldValue.increment(
            disciplinaryHomeDelta,
          );
        if (totalYellowHomeDelta != 0)
          homeUpdateData['total_yellow_cards'] = FieldValue.increment(
            totalYellowHomeDelta,
          );
        if (totalRedHomeDelta != 0)
          homeUpdateData['total_red_cards'] = FieldValue.increment(
            totalRedHomeDelta,
          );

        Map<String, dynamic> awayUpdateData = {};
        if (disciplinaryAwayDelta != 0)
          awayUpdateData['disciplinary_points'] = FieldValue.increment(
            disciplinaryAwayDelta,
          );
        if (totalYellowAwayDelta != 0)
          awayUpdateData['total_yellow_cards'] = FieldValue.increment(
            totalYellowAwayDelta,
          );
        if (totalRedAwayDelta != 0)
          awayUpdateData['total_red_cards'] = FieldValue.increment(
            totalRedAwayDelta,
          );

        if (homeUpdateData.isNotEmpty) {
          debugPrint(
            "[SERVICE_UPDATE] Aplicando Delta Time Casa ($homeTeamId): ${homeUpdateData.keys}",
          );
          transaction.update(homeTeamRef, homeUpdateData);
        }
        if (awayUpdateData.isNotEmpty) {
          debugPrint(
            "[SERVICE_UPDATE] Aplicando Delta Time Visitante ($awayTeamId): ${awayUpdateData.keys}",
          );
          transaction.update(awayTeamRef, awayUpdateData);
        }
      }); // Fim da Transação

      // --- PÓS-TRANSAÇÃO: RECALCULAR ESTATÍSTICAS DE CLASSIFICAÇÃO (1ª FASE) ---
      // Só recalcula se o jogo afetado for da primeira fase ou se status mudou
      final String phaseBeforeUpdate = matchDataBefore['phase'] ?? 'first';
      final String statusBeforeUpdate = matchDataBefore['status'] ?? 'pending';

      bool isFirstPhaseGame = (phaseBeforeUpdate == 'first');
      bool wasFinished = (statusBeforeUpdate == 'finished');
      bool isNowNotFinished = (newStatus != 'finished');
      bool didGameUnfinish = (wasFinished && isNowNotFinished);

      // Recalcula se for um jogo da 1ª fase OU se um jogo (de qualquer fase) deixou de ser 'finished'
      bool shouldRecalculate = isFirstPhaseGame || didGameUnfinish;

      if (shouldRecalculate) {
        debugPrint(
          "[SERVICE_UPDATE] Recalculando stats 1ª Fase para $homeTeamId e $awayTeamId...",
        );
        await _recalculateTeamStats(homeTeamId); // Chamada correta
        await _recalculateTeamStats(awayTeamId); // Chamada correta
      } else {
        debugPrint("[SERVICE_UPDATE] Recálculo stats 1ª Fase não necessário.");
      }

      return "Sucesso";
    } catch (e) {
      debugPrint('[SERVICE_UPDATE] Erro na transação updateMatchStats: $e');
      return "Erro: ${e.toString()}";
    }
  }

  // --- Função para Calcular e Salvar Ranks da 1ª Fase ---
  Future<String> calculateAndStorePhase1Ranks() async {
    debugPrint("[SERVICE_RANK] Iniciando cálculo Ranks 1ª Fase...");
    try {
      // ... (Busca times e jogos finalizados da 1a fase) ...
      final teamsSnapshot = await _firestore.collection('teams').get();
      final matchesSnapshot = await _firestore
          .collection('matches')
          .where('status', isEqualTo: 'finished')
          .where('phase', isEqualTo: 'first')
          .get();
      if (teamsSnapshot.docs.isEmpty) return "Erro: Nenhuma equipe encontrada.";
      debugPrint(
        "[SERVICE_RANK] Times (${teamsSnapshot.docs.length}) e Jogos (${matchesSnapshot.docs.length}) buscados.",
      );

      // Ordena usando StandingsSorter
      List<TeamStanding> standings = teamsSnapshot.docs
          .map((doc) => TeamStanding(doc))
          .toList();
      final sorter = StandingsSorter(finishedMatches: matchesSnapshot.docs);
      List<TeamStanding> sortedStandings = sorter.sort(standings);
      debugPrint("[SERVICE_RANK] Classificação ordenada.");

      // Salva ranks no batch
      final WriteBatch batch = _firestore.batch();
      for (int i = 0; i < sortedStandings.length; i++) {
        final teamRef = _firestore
            .collection('teams')
            .doc(sortedStandings[i].id);
        batch.update(teamRef, {'phase1_rank': i + 1});
      }
      await batch.commit();
      debugPrint("[SERVICE_RANK] Batch commit Ranks concluído.");
      return "Sucesso! Classificação final da 1ª Fase salva.";
    } catch (e) {
      debugPrint("[SERVICE_RANK] Erro: $e");
      return "Erro: ${e.toString()}";
    }
  }
  // --- FIM calculateAndStorePhase1Ranks ---

  // --- Função para Gerar Semifinais ---
  Future<String> generateSemifinals() async {
    debugPrint("[SERVICE_SEMI] Iniciando geração Semifinais...");
    try {
      final teamsSnapshot = await _firestore.collection('teams').get();
      final matchesSnapshot = await _firestore
          .collection('matches')
          .where('status', isEqualTo: 'finished')
          .where('phase', isEqualTo: 'first')
          .get();
      if (teamsSnapshot.docs.isEmpty) return "Erro: Nenhuma equipe encontrada.";

      List<TeamStanding> standings = teamsSnapshot.docs
          .map((doc) => TeamStanding(doc))
          .toList();
      final sorter = StandingsSorter(finishedMatches: matchesSnapshot.docs);
      List<TeamStanding> sortedStandings = sorter.sort(standings);

      if (sortedStandings.length < 4)
        return "Erro: Menos de 4 times classificados (${sortedStandings.length}).";
      final team1 = sortedStandings[0];
      final team2 = sortedStandings[1];
      final team3 = sortedStandings[2];
      final team4 = sortedStandings[3];
      debugPrint("[SERVICE_SEMI] Classificação Top 4 definida.");

      final existingSemis = await _firestore
          .collection('matches')
          .where('phase', isEqualTo: 'semifinal')
          .limit(1)
          .get();
      if (existingSemis.docs.isNotEmpty) return "Aviso: Semifinais já existem.";

      final WriteBatch batch = _firestore.batch();
      final semiFinalRef1 = _firestore.collection('matches').doc();
      final semiFinalRef2 = _firestore.collection('matches').doc();

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
        'team_home_name': team1.data['name'] ?? '?',
        'team_home_shield': team1.data['shield_url'] ?? '',
        'team_away_id': team4.id,
        'team_away_name': team4.data['name'] ?? '?',
        'team_away_shield': team4.data['shield_url'] ?? '',
      });
      batch.set(semiFinalRef2, {
        'phase': 'semifinal',
        'order': 2,
        'round': null,
        'datetime': null,
        'location': 'A definir',
        'status': 'pending',
        'score_home': null,
        'score_away': null,
        'team_home_id': team2.id,
        'team_home_name': team2.data['name'] ?? '?',
        'team_home_shield': team2.data['shield_url'] ?? '',
        'team_away_id': team3.id,
        'team_away_name': team3.data['name'] ?? '?',
        'team_away_shield': team3.data['shield_url'] ?? '',
      });

      await batch.commit();
      debugPrint("[SERVICE_SEMI] Batch commit Semifinais concluído.");
      return "Sucesso! Jogos da Semifinal gerados (1ºx4º, 2ºx3º).";
    } catch (e) {
      debugPrint("[SERVICE_SEMI] Erro: $e");
      return "Erro: ${e.toString()}";
    }
  }
  // --- FIM generateSemifinals ---

  // --- Função para Gerar Final e 3º Lugar ---
  Future<String> generateFinals() async {
    debugPrint("[SERVICE_FINAL] Iniciando geração Final/3º Lugar...");
    try {
      // ... (Busca semifinais, valida se são 2) ...
      final semisSnapshot = await _firestore
          .collection('matches')
          .where('phase', isEqualTo: 'semifinal')
          .get();
      if (semisSnapshot.docs.length != 2)
        return "Erro: Esperava 2 semifinais, encontrou ${semisSnapshot.docs.length}.";

      // ... (Lê times envolvidos para pegar Rank) ...
      debugPrint(
        "[SERVICE_FINAL] Semifinais encontradas: ${semisSnapshot.docs.length}",
      );

      // 2. Coletar IDs dos times envolvidos
      Set<String> teamIdsInSemis = {};
      for (var semi in semisSnapshot.docs) {
        // Adiciona try/catch ou acesso seguro se 'data' puder ser nulo
        final data = semi.data() as Map<String, dynamic>?;
        if (data != null) {
          if (data['team_home_id'] != null)
            teamIdsInSemis.add(data['team_home_id']);
          if (data['team_away_id'] != null)
            teamIdsInSemis.add(data['team_away_id']);
        }
      }

      // --- TRECHO PREENCHIDO: Buscar dados dos times (para Ranks) ---
      Map<String, DocumentSnapshot> teamDataMap = {};

      if (teamIdsInSemis.isNotEmpty) {
        // Busca os documentos dos 4 times envolvidos nas semis
        final teamDocs = await _firestore
            .collection('teams')
            .where(FieldPath.documentId, whereIn: teamIdsInSemis.toList())
            .get();
        // Mapeia os resultados por ID para fácil acesso
        for (var doc in teamDocs.docs) {
          teamDataMap[doc.id] = doc;
        }
      }
      // --- FIM DO TRECHO PREENCHIDO ---
      debugPrint(
        "[SERVICE_FINAL] Dados dos times das semis carregados: ${teamDataMap.length} times encontrados.",
      );

      // Determina Vencedores/Perdedores (com lógica de desempate atualizada)
      String? winner1Id, loser1Id, winner2Id, loser2Id;
      String? winner1Name, loser1Name, winner2Name, loser2Name;
      String? winner1Shield, loser1Shield, winner2Shield, loser2Shield;
      List<DocumentSnapshot> semis = semisSnapshot.docs;

      for (int i = 0; i < semis.length; i++) {
        final matchDoc = semis[i];
        final data = matchDoc.data() as Map<String, dynamic>?;
        // ... (Validações status finished, placar não nulo) ...
        if (data == null ||
            data['status'] != 'finished' ||
            data['score_home'] == null ||
            data['score_away'] == null) {
          // Exemplo de como pegar nomes para a mensagem de erro
          String homeName = data?['team_home_name'] ?? 'Jogo ${i + 1}';
          String awayName = data?['team_away_name'] ?? '';
          return "Erro: Semifinal $homeName vs $awayName não está finalizada ou não tem placar.";
        }

        String currentWinnerId, currentLoserId;
        String currentWinnerName, currentLoserName;
        String currentWinnerShield, currentLoserShield;

        final int scoreHome = data['score_home'];
        final int scoreAway = data['score_away'];
        final String homeId = data['team_home_id'];
        final String homeName = data['team_home_name'];
        final String homeShield = data['team_home_shield'];
        final String awayId = data['team_away_id'];
        final String awayName = data['team_away_name'];
        final String awayShield = data['team_away_shield'];

        if (scoreHome > scoreAway) {
          /* Casa Venceu */
          currentWinnerId = homeId;
          currentWinnerName = homeName;
          currentWinnerShield = homeShield;
          currentLoserId = awayId;
          currentLoserName = awayName;
          currentLoserShield = awayShield;
        } else if (scoreAway > scoreHome) {
          /* Visitante Venceu */
          currentWinnerId = awayId;
          currentWinnerName = awayName;
          currentWinnerShield = awayShield;
          currentLoserId = homeId;
          currentLoserName = homeName;
          currentLoserShield = homeShield;
        } else {
          // Empate
          debugPrint(
            "[SERVICE_FINAL] Empate em ${matchDoc.id}. Verificando critério...",
          );
          String tiebreakerRule =
              AdminService.semifinalTiebreaker; // Assume semi

          // Tenta Pênaltis
          final int? penaltyHome = data['penalty_score_home'];
          final int? penaltyAway = data['penalty_score_away'];
          if (tiebreakerRule.contains('penalties') &&
              penaltyHome != null &&
              penaltyAway != null &&
              penaltyHome != penaltyAway) {
            debugPrint("... Resolvido por pênaltis.");
            if (penaltyHome > penaltyAway) {
              currentWinnerId = homeId;
              currentWinnerName = homeName;
              currentWinnerShield = homeShield;
              currentLoserId = awayId;
              currentLoserName = awayName;
              currentLoserShield = awayShield;
            } else {
              currentWinnerId = awayId;
              currentWinnerName = awayName;
              currentWinnerShield = awayShield;
              currentLoserId = homeId;
              currentLoserName = homeName;
              currentLoserShield = homeShield;
            }
          }
          // Tenta Classificação
          else if (tiebreakerRule == 'extra_time_standing') {
            debugPrint("... Resolvendo por rank 1ª Fase...");
            final teamHomeDoc = teamDataMap[homeId];
            final teamAwayDoc = teamDataMap[awayId];
            final int? rankHome =
                (teamHomeDoc?.data() as Map<String, dynamic>?)?['phase1_rank'];
            final int? rankAway =
                (teamAwayDoc?.data() as Map<String, dynamic>?)?['phase1_rank'];

            if (rankHome == null || rankAway == null)
              return "Erro: Rank 1ª Fase não encontrado...";
            if (rankHome < rankAway) {
              currentWinnerId = homeId;
              currentWinnerName = homeName;
              currentWinnerShield = homeShield;
              currentLoserId = awayId;
              currentLoserName = awayName;
              currentLoserShield = awayShield;
            } else if (rankAway < rankHome) {
              currentWinnerId = awayId;
              currentWinnerName = awayName;
              currentWinnerShield = awayShield;
              currentLoserId = homeId;
              currentLoserName = homeName;
              currentLoserShield = homeShield;
            } else
              return "Erro: Ranks iguais...";
          }
          // Erro se não resolveu
          else {
            return "Erro: Empate não resolvido...";
          }
        }
        // Atribui a winner1/loser1 ou winner2/loser2
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
          "[SERVICE_FINAL] Semi ${i + 1}: Vencedor=$currentWinnerName, Perdedor=$currentLoserName",
        );
      } // Fim loop for

      if (winner1Id == null ||
          winner2Id == null ||
          loser1Id == null ||
          loser2Id == null)
        return "Erro: Não foi possível determinar participantes.";

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
      if (existingFinal.docs.isNotEmpty || existingThird.docs.isNotEmpty)
        return "Aviso: Final/3º Lugar já existem.";

      // Criar documentos
      final WriteBatch batch = _firestore.batch();
      final finalRef = _firestore.collection('matches').doc();
      final thirdPlaceRef = _firestore.collection('matches').doc();

      // Jogo da Final: Vencedor 1 vs Vencedor 2
      batch.set(finalRef, {
        'phase': 'final',
        'order': 1, // Ordem 1 para a final
        'round': null,
        'datetime': null,
        'location': 'Ginásio de Esportes Jorge Silva',
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
        'location': 'Ginásio de Esportes Jorge Silva',
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

      // Commit
      await batch.commit();
      debugPrint("[SERVICE_FINAL] Batch commit Final/3º Lugar concluído.");
      return "Sucesso! Jogos da Final e 3º Lugar gerados.";
    } catch (e) {
      debugPrint("[SERVICE_FINAL] Erro: $e");
      return "Erro: ${e.toString()}";
    }
  }

  // --- FIM generateFinals ---
} // Fim Classe FirestoreService
