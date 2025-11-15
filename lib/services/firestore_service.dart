// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart'; // Para debugPrint
import 'admin_service.dart'; // Para acessar regras globais
import '../utils/standings_sorter.dart'; // Para ordenação complexa
import 'package:firebase_storage/firebase_storage.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(bucket: "fjfapp.firebasestorage.app");

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

  // --- FUNÇÕES CRUD DE MÍDIAS (Sem alteração) ---
  Future<int> getNextMediaOrder() async {
    try {
      final snapshot = await _firestore
          .collection('media_feed')
          .orderBy('order', descending: true)
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) {
        return 1;
      }
      
      final lastOrder = (snapshot.docs.first.data()['order'] as num?) ?? 0;
      return lastOrder.toInt() + 1;
    } catch (e) {
      debugPrint("Erro ao buscar próxima ordem: $e");
      return 1;
    }
  }

  Future<String> createMediaItem({
    required String title,
    required String targetUrl,
    required String imageUrl,
    required int order,
    required String author,
  }) async {
    try {
      await _firestore.collection('media_feed').add({
        'title': title,
        'targetUrl': targetUrl,
        'imageUrl': imageUrl,
        'order': order,
        'author': author,
        'isActive': true,
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
    required String author,
  }) async {
    try {
      await _firestore.collection('media_feed').doc(docId).update({
        'title': title,
        'targetUrl': targetUrl,
        'imageUrl': imageUrl,
        'order': order,
        'author': author,
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
      if (imageUrl.isNotEmpty && imageUrl.contains('firebasestorage')) {
        try {
          final ref = _storage.refFromURL(imageUrl); 
          await ref.delete();
          debugPrint("Imagem da mídia deletada do Storage: $imageUrl");
        } catch (e) {
          debugPrint("Aviso: Falha ao deletar imagem do Storage (pode já ter sido removida): $e");
        }
      }
      
      await doc.reference.delete();
      return "Sucesso: Mídia deletada.";
    } catch (e) {
      return "Erro ao deletar mídia: ${e.toString()}";
    }
  }
  // --- FIM MÍDIAS ---

  // --- Função _recalculateTeamStats (Sem alteração) ---
  Future<void> _recalculateTeamStats(String teamId) async {
    debugPrint("[SERVICE_RECALC] Recalculando Time (1ª Fase): $teamId");
    int totalMatchPoints = 0;
    int totalGames = 0;
    int totalWins = 0;
    int totalDraws = 0;
    int totalLosses = 0;
    int totalGoalsFor = 0;
    int totalGoalsAgainst = 0;

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

    try {
      final teamRef = _firestore.collection('teams').doc(teamId);
      final teamSnap = await teamRef.get();
      final currentExtraPoints = (teamSnap.data()?['extra_points'] ?? 0) as int;
      final int finalTotalPoints = totalMatchPoints + currentExtraPoints;
      final int finalGoalDifference = totalGoalsFor - totalGoalsAgainst;

      await teamRef.update({
        'match_points': totalMatchPoints, 'points': finalTotalPoints,
        'games_played': totalGames,
        'wins': totalWins,
        'draws': totalDraws,
        'losses': totalLosses,
        'goals_for': totalGoalsFor, 'goals_against': totalGoalsAgainst,
        'goal_difference': finalGoalDifference,
      });
      debugPrint("[SERVICE_RECALC] Update Time $teamId Concluído.");
    } catch (e) {
      debugPrint("[SERVICE_RECALC] ERRO ao atualizar time $teamId: $e");
    }
  }
  // --- FIM _recalculateTeamStats ---


  // --- CRUD JOGADOR (Sem alteração) ---
  Future<String> createPlayer({
    required String name,
    required bool isGoalkeeper,
    required String teamId,
    required String teamName,
    required int? jerseyNumber,
    required bool isStaff,
    required String? staffRole,
    required String? position,
    required Timestamp? dateOfBirth,
    required int? heightCm,
    required int? weightKg,
    required String? preferredFoot,
    required String? photoUrl,
  }) async {
    try {
      // Busca o shield_url do time
      String teamShieldUrl = '';
      try {
        final teamDoc = await _firestore.collection('teams').doc(teamId).get();
        if(teamDoc.exists) {
           teamShieldUrl = (teamDoc.data() as Map<String, dynamic>)['shield_url'] ?? '';
        }
      } catch (e) {
         debugPrint("Aviso: Não foi possível buscar shield_url para o novo jogador. $e");
      }

      await _firestore.collection('players').add({
        'name': name,
        'is_goalkeeper': isGoalkeeper,
        'team_id': teamId,
        'team_name': teamName,
        'team_shield_url': teamShieldUrl, // <-- Adicionado
        'jersey_number': jerseyNumber,
        'goals': 0, 'assists': 0,
        'yellow_cards': 0, 'red_cards': 0,
        'total_yellow_cards': 0, 'total_red_cards': 0,
        'goals_conceded': 0,
        'man_of_the_match_awards': 0,
        'is_suspended': false,
        'is_staff': isStaff,
        'staff_role': isStaff ? staffRole : null,
        'isActive': true,
        // Novos campos
        'position': isGoalkeeper || isStaff ? null : position,
        'date_of_birth': dateOfBirth,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'preferred_foot': isGoalkeeper || isStaff ? null : preferredFoot,
        'photo_url': photoUrl,
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
    required String? position,
    required Timestamp? dateOfBirth,
    required int? heightCm,
    required int? weightKg,
    required String? preferredFoot,
    required String? photoUrl,
  }) async {
    try {
      await playerDoc.reference.update({
        'name': name,
        'is_goalkeeper': isGoalkeeper,
        'jersey_number': jerseyNumber,
        'is_staff': isStaff,
        'staff_role': isStaff ? staffRole : null,
        // Novos campos
        'position': isGoalkeeper || isStaff ? null : position,
        'date_of_birth': dateOfBirth,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'preferred_foot': isGoalkeeper || isStaff ? null : preferredFoot,
        'photo_url': photoUrl,
      });
      return "Sucesso: Jogador '$name' atualizado.";
    } catch (e) {
      debugPrint("Erro ao atualizar jogador: $e");
      return "Erro ao atualizar jogador: ${e.toString()}";
    }
  }

  Future<String> deletePlayer(DocumentSnapshot playerDoc) async {
    try {
      await playerDoc.reference.update({'isActive': false});
      return "Sucesso: Jogador excluído (inativado).";
    } catch (e) {
      debugPrint("Erro ao excluir jogador: $e");
      return "Erro ao excluir jogador: ${e.toString()}";
    }
  }
  // --- FIM CRUD JOGADOR ---


  // --- CRUD EQUIPE (Sem alteração) ---
  Future<String> createTeam({
    required String name,
    required String shortName,
    required String shieldUrl,
    required List<Map<String, dynamic>> championshipHistory,
  }) async {
    try {
      final newTeamRef = _firestore.collection('teams').doc();

      await newTeamRef.set({
        'name': name,
        'short_name': shortName,
        'shield_url': shieldUrl,
        'championship_history': championshipHistory,
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

  Future<String> updateTeam({
    required DocumentSnapshot teamDoc,
    required String name,
    required String shortName,
    required String shieldUrl,
    required List<Map<String, dynamic>> championshipHistory,
  }) async {
    try {
      await teamDoc.reference.update({
        'name': name,
        'short_name': shortName,
        'shield_url': shieldUrl,
        'championship_history': championshipHistory,
      });

      debugPrint(
        "Aviso: Nome/Escudo da equipe alterado. Jogos e jogadores antigos não serão atualizados automaticamente.",
      );

      return "Sucesso: Equipe '$name' atualizada.";
    } catch (e) {
      debugPrint("Erro ao atualizar equipe: $e");
      return "Erro ao atualizar equipe: ${e.toString()}";
    }
  }
  // --- FIM CRUD EQUIPE ---

  // --- Função de Migração V1 (Sem alteração) ---
  Future<String> migratePlayersV1() async {
    debugPrint("[MIGRAÇÃO] Iniciando migração de jogadores...");
    WriteBatch batch = _firestore.batch();
    int documentsInBatch = 0;
    int totalUpdated = 0;

    try {
      final playersSnapshot = await _firestore.collection('players').get();
      debugPrint(
        "[MIGRAÇÃO] ${playersSnapshot.docs.length} jogadores encontrados.",
      );

      for (final doc in playersSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        bool needsUpdate = false;
        Map<String, dynamic> updateData = {};

        if (!data.containsKey('is_staff')) {
          updateData['is_staff'] = false;
          needsUpdate = true;
        }
        if (!data.containsKey('jersey_number')) {
          updateData['jersey_number'] = null;
          needsUpdate = true;
        }

        if (needsUpdate) {
          batch.update(doc.reference, updateData);
          documentsInBatch++;
          totalUpdated++;
        }

        if (documentsInBatch == 499) {
          debugPrint("[MIGRAÇÃO] Enviando batch de 500...");
          await batch.commit();
          batch = _firestore.batch();
          documentsInBatch = 0;
        }
      }

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
  // --- FIM MIGRAÇÃO ---

  // --- NOVA FUNÇÃO: Sincronizar Logos ---
  Future<String> syncTeamLogosToAllCollections() async {
    debugPrint("[SINCRONIZAÇÃO DE LOGOS] Iniciando...");
    WriteBatch batch = _firestore.batch();
    int batchCount = 0;
    int totalUpdates = 0;

    try {
      // 1. Criar o mapa de referência (Fonte da Verdade)
      final teamsSnapshot = await _firestore.collection('teams').get();
      final Map<String, String> teamLogoCache = {};
      for (var teamDoc in teamsSnapshot.docs) {
        final data = teamDoc.data() as Map<String, dynamic>;
        teamLogoCache[teamDoc.id] = data['shield_url'] ?? '';
      }
      debugPrint("[SINCRONIZAÇÃO] Mapa de logos de ${teamLogoCache.length} times criado.");

      // --- 2. Sincronizar Coleção 'players' ---
      final playersSnapshot = await _firestore.collection('players').get();
      debugPrint("[SINCRONIZAÇÃO] Verificando ${playersSnapshot.docs.length} jogadores...");
      for (var playerDoc in playersSnapshot.docs) {
        final data = playerDoc.data() as Map<String, dynamic>;
        final String? teamId = data['team_id'];
        final String currentLogo = data['team_shield_url'] ?? '';
        
        if (teamId != null && teamLogoCache.containsKey(teamId)) {
          final String correctLogo = teamLogoCache[teamId]!;
          if (currentLogo != correctLogo) {
            batch.update(playerDoc.reference, {'team_shield_url': correctLogo});
            totalUpdates++;
            batchCount++;
          }
        }
      }

      // --- 3. Sincronizar Coleção 'matches' ---
      final matchesSnapshot = await _firestore.collection('matches').get();
      debugPrint("[SINCRONIZAÇÃO] Verificando ${matchesSnapshot.docs.length} partidas...");
      for (var matchDoc in matchesSnapshot.docs) {
        final data = matchDoc.data() as Map<String, dynamic>;
        final String? homeId = data['team_home_id'];
        final String? awayId = data['team_away_id'];
        
        String? correctHomeLogo = (homeId != null) ? teamLogoCache[homeId] : null;
        String? correctAwayLogo = (awayId != null) ? teamLogoCache[awayId] : null;
        
        Map<String, dynamic> updateData = {};
        if (correctHomeLogo != null && data['team_home_shield'] != correctHomeLogo) {
          updateData['team_home_shield'] = correctHomeLogo;
        }
        if (correctAwayLogo != null && data['team_away_shield'] != correctAwayLogo) {
          updateData['team_away_shield'] = correctAwayLogo;
        }

        if (updateData.isNotEmpty) {
          batch.update(matchDoc.reference, updateData);
          totalUpdates++;
          batchCount++;
        }
      }

      // --- 4. Sincronizar Coleção 'suspension_log' ---
      final suspensionSnapshot = await _firestore.collection('suspension_log').get();
      debugPrint("[SINCRONIZAÇÃO] Verificando ${suspensionSnapshot.docs.length} logs de suspensão...");
      for (var logDoc in suspensionSnapshot.docs) {
         final data = logDoc.data() as Map<String, dynamic>;
         final String? teamId = data['teamId'];
         final String currentLogo = data['teamLogoUrl'] ?? '';
         
         if (teamId != null && teamLogoCache.containsKey(teamId)) {
            final String correctLogo = teamLogoCache[teamId]!;
            if (currentLogo != correctLogo) {
              batch.update(logDoc.reference, {'teamLogoUrl': correctLogo});
              totalUpdates++;
              batchCount++;
            }
         }
      }

      // 5. Enviar o Batch
      if (batchCount > 0) {
        await batch.commit();
        return "Sucesso: $totalUpdates URLs de logo foram sincronizadas.";
      } else {
        return "Concluído: Todos os logos já estavam sincronizados.";
      }
      
    } catch (e) {
      debugPrint("[SINCRONIZAÇÃO] ERRO: $e");
      return "Erro ao sincronizar logos: ${e.toString()}";
    }
  }
  // --- FIM DA NOVA FUNÇÃO ---


  // --- Função Excluir Equipe (Sem alteração) ---
  Future<String> deleteTeam(DocumentSnapshot teamDoc) async {
    debugPrint("INICIANDO EXCLUSÃO EM CASCATA PARA: ${teamDoc.id}");
    final teamId = teamDoc.id;
    final WriteBatch batch = _firestore.batch();
    Set<String> opponentsToRecalculate = {};

    try {
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

      final homeMatches = await _firestore
          .collection('matches')
          .where('team_home_id', isEqualTo: teamId)
          .get();
      for (final match in homeMatches.docs) {
        final data = match.data() as Map<String, dynamic>? ?? {};
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

      final awayMatches = await _firestore
          .collection('matches')
          .where('team_away_id', isEqualTo: teamId)
          .get();
      for (final match in awayMatches.docs) {
        final data = match.data() as Map<String, dynamic>? ?? {};
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

      batch.delete(teamDoc.reference);
      debugPrint("Exclusão: Equipe ${teamDoc.id} marcada para deleção.");

      await batch.commit();
      debugPrint("Batch de exclusão concluído.");

      if (opponentsToRecalculate.isNotEmpty) {
        debugPrint(
          "Recalculando classificação para ${opponentsToRecalculate.length} oponentes afetados...",
        );
        for (String opponentId in opponentsToRecalculate) {
          await _recalculateTeamStats(
            opponentId,
          );
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

  // --- CRUD Partida (Sem alteração) ---
  Future<String> createMatch({
    required DocumentSnapshot homeTeam,
    required DocumentSnapshot awayTeam,
    required String location,
    required int round,
    required DateTime dateTime,
  }) async {
    try {
      final homeTeamData = homeTeam.data() as Map<String, dynamic>;
      final awayTeamData = awayTeam.data() as Map<String, dynamic>;

      await _firestore.collection('matches').add({
        'phase': 'first',
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

  Future<String> updateMatchDetails({
    required DocumentSnapshot match,
    required DocumentSnapshot homeTeam,
    required DocumentSnapshot awayTeam,
    required String location,
    required int round,
    required DateTime dateTime,
    required String phase,
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

  Future<String> deleteMatch(DocumentSnapshot match) async {
    try {
      final data = match.data() as Map<String, dynamic>? ?? {};
      final status = data['status'] ?? 'pending';
      final phase = data['phase'] ?? 'first';
      final homeTeamId = data['team_home_id'];
      final awayTeamId = data['team_away_id'];

      await match.reference.delete();

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
  // --- FIM CRUD Partida ---

  // --- Função updateMatchStats (Simplificada para 1CA/1CV) ---
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
    final String? homeTeamId = matchDataBefore['team_home_id'];
    final String? awayTeamId = matchDataBefore['team_away_id'];
    
    if (homeTeamId == null || awayTeamId == null) {
      return "Erro: A partida não possui IDs de time válidos.";
    }

    debugPrint("[SERVICE_UPDATE] Iniciando update para Jogo $matchId");

    try {
      await _firestore.runTransaction((transaction) async {
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

        final homeTeamRef = _firestore.collection('teams').doc(homeTeamId);
        final awayTeamRef = _firestore.collection('teams').doc(awayTeamId);
        final DocumentSnapshot homeTeamSnap = await transaction.get(homeTeamRef);
        final DocumentSnapshot awayTeamSnap = await transaction.get(awayTeamRef);
        
        final homeLogoUrl = (homeTeamSnap.data() as Map<String, dynamic>?)?['shield_url'] ?? '';
        final awayLogoUrl = (awayTeamSnap.data() as Map<String, dynamic>?)?['shield_url'] ?? '';

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
            'starters_home': [], // (Não mais usado aqui)
            'starters_away': [], // (Não mais usado aqui)
          },
        });

        int disciplinaryHomeDelta = 0;
        int disciplinaryAwayDelta = 0;
        int totalYellowHomeDelta = 0;
        int totalYellowAwayDelta = 0;
        int totalRedHomeDelta = 0;
        int totalRedAwayDelta = 0;

        Map<String, int> goalDelta = _calculateDelta(oldGoals, newGoals);
        Map<String, int> assistDelta = _calculateDelta(oldAssists, newAssists);
        Map<String, int> goalsConcededDelta = _calculateDelta(
          oldGoalsConceded,
          newGoalsConceded,
        );
        Map<String, int> yellowDelta = _calculateDelta(oldYellows, newYellows);
        Map<String, int> redDelta = _calculateDelta(oldReds, newReds);

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

        Set<String> affectedCardPlayerIds = {...yellowDelta.keys, ...redDelta.keys};
        for (String playerId in affectedCardPlayerIds) {
          if (!playerSnaps.containsKey(playerId)) continue;

          final playerSnap = playerSnaps[playerId]!;
          final playerData = playerSnap.data() as Map<String, dynamic>? ?? {};

          int yDelta = yellowDelta[playerId] ?? 0;
          int rDelta = redDelta[playerId] ?? 0;

          int currentYellows = playerData['yellow_cards'] ?? 0;
          int currentReds = playerData['red_cards'] ?? 0;
          bool currentlySuspended = playerData['is_suspended'] ?? false;
          int currentTotalYellows = playerData['total_yellow_cards'] ?? 0;
          int currentTotalReds = playerData['total_red_cards'] ?? 0;

           int playerTotalYellowIncrement = yDelta;
           int playerTotalRedIncrement = rDelta;
           int yellowIncrementForCurrent = yDelta;
           
           int teamYellowTotalIncrement = yDelta;
           int teamRedTotalIncrement = rDelta;
           int teamDisciplinaryPointsIncrement = (yDelta * 10) + (rDelta * 21);

          int theoreticalNewYellows = currentYellows + yellowIncrementForCurrent;
          int theoreticalNewReds = currentReds + rDelta;
           
          if (theoreticalNewYellows < 0) theoreticalNewYellows = 0;
          if (theoreticalNewReds < 0) theoreticalNewReds = 0;

          int finalYellows = theoreticalNewYellows;
          int finalReds = theoreticalNewReds;
          bool finalSuspension = currentlySuspended;
          String suspensionReason = ""; 

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
           
           if (rDelta > 0 && AdminService.suspensionOnRed) {
              if (!currentlySuspended) {
                finalSuspension = true;
                suspensionReason = (suspensionReason.isNotEmpty) ? "$suspensionReason e CV" : "CV";
              }
              if (AdminService.resetYellowsOnRed) finalYellows = 0;
           }

           if (suspensionReason.isNotEmpty) {
             final logRef = _firestore.collection('suspension_log').doc();
             DateTime matchDate = DateTime.now();
             if (currentMatchData['datetime'] != null && currentMatchData['datetime'] is Timestamp) {
                matchDate = (currentMatchData['datetime'] as Timestamp).toDate();
             }
             final DateTime returnDate = matchDate.add(const Duration(days: 10));
             String teamLogoUrl = ''; 
             final teamId = playerData['team_id'];
             if (teamId == homeTeamId) teamLogoUrl = homeLogoUrl;
             else if (teamId == awayTeamId) teamLogoUrl = awayLogoUrl;
             
             transaction.set(logRef, {
               'playerId': playerId,
               'playerName': playerData['name'] ?? '?',
               'teamId': playerData['team_id'] ?? '?',
               'teamName': playerData['team_name'] ?? '?',
               'teamLogoUrl': teamLogoUrl,
               'is_staff': playerData['is_staff'] ?? false,
               'timestamp': Timestamp.fromDate(matchDate),
               'return_date': Timestamp.fromDate(returnDate),
               'reason': suspensionReason,
               'matchId_occurred': matchId,
               'match_description': "Rodada ${currentMatchData['round']}: ${currentMatchData['team_home_name']} vs ${currentMatchData['team_away_name']}",
             });
           }
           
          if (rDelta < 0 && finalYellows < AdminService.suspensionYellowCards)
            finalSuspension = false;
          if (yellowIncrementForCurrent < 0 &&
              theoreticalNewYellows < AdminService.suspensionYellowCards &&
              currentYellows >= AdminService.suspensionYellowCards &&
              finalReds == 0)
            finalSuspension = false;

          int finalTotalYellows = currentTotalYellows + playerTotalYellowIncrement;
          int finalTotalReds = currentTotalReds + playerTotalRedIncrement;
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

          final String? playerTeamId = playerData['team_id'];
           if (playerTeamId == homeTeamId) {
             disciplinaryHomeDelta += teamDisciplinaryPointsIncrement;
             totalYellowHomeDelta += teamYellowTotalIncrement;
             totalRedHomeDelta += teamRedTotalIncrement;
           } else if (playerTeamId == awayTeamId) {
             disciplinaryAwayDelta += teamDisciplinaryPointsIncrement;
             totalYellowAwayDelta += teamYellowTotalIncrement;
             totalRedAwayDelta += teamRedTotalIncrement;
           }
        }

        Map<String, dynamic> homeUpdateData = {};
        if (disciplinaryHomeDelta != 0)
          homeUpdateData['disciplinary_points'] = FieldValue.increment(disciplinaryHomeDelta);
        if (totalYellowHomeDelta != 0)
          homeUpdateData['total_yellow_cards'] = FieldValue.increment(totalYellowHomeDelta);
        if (totalRedHomeDelta != 0)
          homeUpdateData['total_red_cards'] = FieldValue.increment(totalRedHomeDelta);

        Map<String, dynamic> awayUpdateData = {};
        if (disciplinaryAwayDelta != 0)
          awayUpdateData['disciplinary_points'] = FieldValue.increment(disciplinaryAwayDelta);
        if (totalYellowAwayDelta != 0)
          awayUpdateData['total_yellow_cards'] = FieldValue.increment(totalYellowAwayDelta);
        if (totalRedAwayDelta != 0)
          awayUpdateData['total_red_cards'] = FieldValue.increment(totalRedAwayDelta);

        if (homeUpdateData.isNotEmpty) {
          transaction.update(homeTeamRef, homeUpdateData);
        }
        if (awayUpdateData.isNotEmpty) {
          transaction.update(awayTeamRef, awayUpdateData);
        }
      });

      final String phaseBeforeUpdate = matchDataBefore['phase'] ?? 'first';
      final String statusBeforeUpdate = matchDataBefore['status'] ?? 'pending';

      bool isFirstPhaseGame = (phaseBeforeUpdate == 'first');
      bool wasFinished = (statusBeforeUpdate == 'finished');
      bool isNowNotFinished = (newStatus != 'finished');
      bool didGameUnfinish = (wasFinished && isNowNotFinished);

      bool shouldRecalculate = isFirstPhaseGame || didGameUnfinish;

      if (shouldRecalculate) {
        debugPrint(
          "[SERVICE_UPDATE] Recalculando stats 1ª Fase para $homeTeamId e $awayTeamId...",
        );
        await _recalculateTeamStats(homeTeamId);
        await _recalculateTeamStats(awayTeamId);
      } else {
        debugPrint("[SERVICE_UPDATE] Recálculo stats 1ª Fase não necessário.");
      }

      return "Sucesso";
    } catch (e) {
      debugPrint('[SERVICE_UPDATE] Erro na transação updateMatchStats: $e');
      return "Erro: ${e.toString()}";
    }
  }

  // --- Funções de Playoff (Corrigidas para o Sorter) ---
  Future<String> calculateAndStorePhase1Ranks() async {
    debugPrint("[SERVICE_RANK] Iniciando cálculo Ranks 1ª Fase...");
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
      
      final List<Map<String, dynamic>> finishedMatchesData = 
          matchesSnapshot.docs.map((doc) => doc.data()).toList();
      
      final sorter = StandingsSorter(finishedMatches: finishedMatchesData);
      
      List<TeamStanding> sortedStandings = sorter.sort(standings);
      debugPrint("[SERVICE_RANK] Classificação ordenada.");

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

      final List<Map<String, dynamic>> finishedMatchesData = 
          matchesSnapshot.docs.map((doc) => doc.data()).toList();
          
      final sorter = StandingsSorter(finishedMatches: finishedMatchesData);

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

  Future<String> generateFinals() async {
    debugPrint("[SERVICE_FINAL] Iniciando geração Final/3º Lugar...");
    try {
      final semisSnapshot = await _firestore
          .collection('matches')
          .where('phase', isEqualTo: 'semifinal')
          .get();
      if (semisSnapshot.docs.length != 2)
        return "Erro: Esperava 2 semifinais, encontrou ${semisSnapshot.docs.length}.";

      debugPrint(
        "[SERVICE_FINAL] Semifinais encontradas: ${semisSnapshot.docs.length}",
      );

      Set<String> teamIdsInSemis = {};
      for (var semi in semisSnapshot.docs) {
        final data = semi.data() as Map<String, dynamic>?;
        if (data != null) {
          if (data['team_home_id'] != null)
            teamIdsInSemis.add(data['team_home_id']);
          if (data['team_away_id'] != null)
            teamIdsInSemis.add(data['team_away_id']);
        }
      }

      Map<String, DocumentSnapshot> teamDataMap = {};

      if (teamIdsInSemis.isNotEmpty) {
        final teamDocs = await _firestore
            .collection('teams')
            .where(FieldPath.documentId, whereIn: teamIdsInSemis.toList())
            .get();
        for (var doc in teamDocs.docs) {
          teamDataMap[doc.id] = doc;
        }
      }
      debugPrint(
        "[SERVICE_FINAL] Dados dos times das semis carregados: ${teamDataMap.length} times encontrados.",
      );

      String? winner1Id, loser1Id, winner2Id, loser2Id;
      String? winner1Name, loser1Name, winner2Name, loser2Name;
      String? winner1Shield, loser1Shield, winner2Shield, loser2Shield;
      List<DocumentSnapshot> semis = semisSnapshot.docs;

      for (int i = 0; i < semis.length; i++) {
        final matchDoc = semis[i];
        final data = matchDoc.data() as Map<String, dynamic>?;
        
        if (data == null ||
            data['status'] != 'finished' ||
            data['score_home'] == null ||
            data['score_away'] == null) {
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
          currentWinnerId = homeId;
          currentWinnerName = homeName;
          currentWinnerShield = homeShield;
          currentLoserId = awayId;
          currentLoserName = awayName;
          currentLoserShield = awayShield;
        } else if (scoreAway > scoreHome) {
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
              AdminService.semifinalTiebreaker;

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
          else {
            return "Erro: Empate não resolvido...";
          }
        }
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
      }

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

      final WriteBatch batch = _firestore.batch();
      final finalRef = _firestore.collection('matches').doc();
      final thirdPlaceRef = _firestore.collection('matches').doc();

      batch.set(finalRef, {
        'phase': 'final',
        'order': 1,
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

      batch.set(thirdPlaceRef, {
        'phase': 'third_place',
        'order': 1,
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

      await batch.commit();
      debugPrint("[SERVICE_FINAL] Batch commit Final/3º Lugar concluído.");
      return "Sucesso! Jogos da Final e 3º Lugar gerados.";
    } catch (e) {
      debugPrint("[SERVICE_FINAL] Erro: $e");
      return "Erro: ${e.toString()}";
    }
  }

} // Fim Classe FirestoreService