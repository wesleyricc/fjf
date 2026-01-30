import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'admin_service.dart';
import '../models/match_event.dart';

// --- MODELS ---
import '../models/team_model.dart';
import '../models/player_model.dart';
import '../models/match_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(bucket: "fjfapp.firebasestorage.app");

  // ===========================================================================
  // 📍 ROTEAMENTO INTERNO PADRONIZADO (Nova Estrutura)
  // ===========================================================================

  CollectionReference _getMatchesRef(String seasonId) {
    return _firestore.collection('championships').doc(seasonId).collection('matches');
  }

  CollectionReference _getTeamsRef(String seasonId) {
    return _firestore.collection('championships').doc(seasonId).collection('teams_participation');
  }

  CollectionReference _getPlayerStatsRef(String seasonId) {
    return _firestore.collection('championships').doc(seasonId).collection('player_stats');
  }

  CollectionReference _getMediaRef(String seasonId) {
    return _firestore.collection('championships').doc(seasonId).collection('news');
  }

  // ===========================================================================
  // 🔄 LEITURA DE DADOS TIPADOS (STREAMS & FUTURES)
  // ===========================================================================
  
  Stream<List<Team>> streamTeams(String seasonId) {
    return _getTeamsRef(seasonId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Team.fromFirestore(doc)).toList());
  }

  Future<Team?> getTeam(String teamId, String seasonId) async {
    final doc = await _getTeamsRef(seasonId).doc(teamId).get();
    if (!doc.exists) return null;
    return Team.fromFirestore(doc);
  }
  
  Future<DocumentSnapshot?> getTeamSnapshot(String teamId, String seasonId) async {
    try {
      final doc = await _getTeamsRef(seasonId).doc(teamId).get();
      return doc.exists ? doc : null;
    } catch (e) { return null; }
  }

  Stream<List<Player>> streamPlayers(String seasonId, {String? teamId}) {
    Query query = _getPlayerStatsRef(seasonId).where('isActive', isEqualTo: true);
    if (teamId != null) query = query.where('team_id', isEqualTo: teamId);
    return query.snapshots().map((snapshot) {
      final players = snapshot.docs.map((doc) => Player.fromFirestore(doc)).toList();
      players.sort((a, b) => (a.name).compareTo(b.name));
      return players;
    });
  }

  Future<Player?> getPlayer(String playerId, String seasonId) async {
    final doc = await _getPlayerStatsRef(seasonId).doc(playerId).get();
    if (!doc.exists) return null;
    return Player.fromFirestore(doc);
  }

  Stream<List<MatchModel>> streamMatches(String seasonId, {String? phase}) {
    Query query = _getMatchesRef(seasonId).orderBy('datetime');
    if (phase != null) query = query.where('phase', isEqualTo: phase);
    return query.snapshots().map((snapshot) => 
      snapshot.docs.map((doc) => MatchModel.fromFirestore(doc)).toList()
    );
  }

 
  // ===========================================================================
  // 📰 MÍDIAS
  // ===========================================================================

  Future<int> getNextMediaOrder(String seasonId) async {
    try {
      final snapshot = await _getMediaRef(seasonId).orderBy('order', descending: true).limit(1).get();
      if (snapshot.docs.isEmpty) return 1;
      final lastOrder = (snapshot.docs.first.data() as Map<String, dynamic>)['order'] as num? ?? 0;
      return lastOrder.toInt() + 1;
    } catch (e) {
      return 1;
    }
  }

  Future<String> createMediaItem({
    required String seasonId,
    required String title, required String targetUrl, required String imageUrl,
    required int order, required String author,
  }) async {
    try {
      await _getMediaRef(seasonId).add({
        'title': title, 'targetUrl': targetUrl, 'imageUrl': imageUrl,
        'order': order, 'author': author, 'isActive': true,
      });
      return "Sucesso: Mídia criada.";
    } catch (e) { return "Erro: $e"; }
  }

  Future<String> updateMediaItem({
    required String seasonId,
    required String docId, required String title, required String targetUrl,
    required String imageUrl, required int order, required String author,
  }) async {
    try {
      await _getMediaRef(seasonId).doc(docId).update({
        'title': title, 'targetUrl': targetUrl, 'imageUrl': imageUrl,
        'order': order, 'author': author,
      });
      return "Sucesso: Mídia atualizada.";
    } catch (e) { return "Erro: $e"; }
  }

  Future<String> deleteMediaItem(DocumentSnapshot doc, String seasonId) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      if (data['imageUrl'] != null && data['imageUrl'].toString().isNotEmpty) {
        try { await _storage.refFromURL(data['imageUrl']).delete(); } catch (_) {}
      }
      await doc.reference.delete();
      return "Sucesso: Mídia deletada.";
    } catch (e) { return "Erro: $e"; }
  }

  // ===========================================================================
  // ⚡ ASSISTENTE DE SÚMULA (EVENTOS)
  // ===========================================================================

  Future<String> addMatchEvent({
    required String seasonId,
    required String matchId,
    required MatchEvent event,
  }) async {
    final matchRef = _getMatchesRef(seasonId).doc(matchId);
    final eventRef = matchRef.collection('timeline').doc();
    final seasonPlayerRef = _getPlayerStatsRef(seasonId).doc(event.playerId);

    try {
      await _firestore.runTransaction((transaction) async {
        final matchSnap = await transaction.get(matchRef);
        if (!matchSnap.exists) throw Exception("Partida não encontrada");
        
        final matchData = matchSnap.data() as Map<String, dynamic>;
        final homeId = matchData['team_home_id'];
        final awayId = matchData['team_away_id'];
        
        // Verifica existência do jogador na temporada antes de ler
        final playerSnap = await transaction.get(seasonPlayerRef);
        
        String fieldInMatchStats = ''; 
        String fieldInSeasonStats = '';
        int scoreHomeIncrement = 0;
        int scoreAwayIncrement = 0;
        int disciplinaryPoints = 0;

        switch (event.type) {
          case MatchEventType.goal:
            fieldInMatchStats = 'goals';
            fieldInSeasonStats = 'goals';
            if (event.teamId == homeId) scoreHomeIncrement = 1;
            if (event.teamId == awayId) scoreAwayIncrement = 1;
            break;
          case MatchEventType.assist:
            fieldInMatchStats = 'assists';
            fieldInSeasonStats = 'assists';
            break;
          case MatchEventType.yellowCard:
            fieldInMatchStats = 'yellows';
            fieldInSeasonStats = 'total_yellow_cards';
            disciplinaryPoints = 10;
            break;
          case MatchEventType.redCard:
            fieldInMatchStats = 'reds';
            fieldInSeasonStats = 'total_red_cards';
            disciplinaryPoints = 21;
            break;
        }

        transaction.set(eventRef, event.toMap());

        Map<String, dynamic> matchUpdates = {'status': 'in_progress'};
        if (scoreHomeIncrement != 0) matchUpdates['score_home'] = FieldValue.increment(scoreHomeIncrement);
        if (scoreAwayIncrement != 0) matchUpdates['score_away'] = FieldValue.increment(scoreAwayIncrement);

        if (fieldInMatchStats.isNotEmpty) {
           matchUpdates['stats_applied.player_stats.$fieldInMatchStats.${event.playerId}'] = FieldValue.increment(1);
        }
        if (event.type == MatchEventType.goal && event.concededByPlayerId != null) {
           matchUpdates['stats_applied.player_stats.goals_conceded.${event.concededByPlayerId}'] = FieldValue.increment(1);
        }
        transaction.update(matchRef, matchUpdates);

        if (playerSnap.exists && fieldInSeasonStats.isNotEmpty) {
           Map<String, dynamic> playerUpdates = {fieldInSeasonStats: FieldValue.increment(1)};
           if (event.type == MatchEventType.yellowCard) {
              playerUpdates['yellow_cards'] = FieldValue.increment(1);
           } else if (event.type == MatchEventType.redCard) {
              playerUpdates['red_cards'] = FieldValue.increment(1);
              if (AdminService.suspensionOnRed) playerUpdates['is_suspended'] = true;
           }
           transaction.update(seasonPlayerRef, playerUpdates);
        }

        if (event.type == MatchEventType.goal && event.concededByPlayerId != null) {
           final goalkeeperRef = _getPlayerStatsRef(seasonId).doc(event.concededByPlayerId);
           // Usa set com merge caso o goleiro não tenha stats ainda por algum motivo raro
           transaction.set(goalkeeperRef, {'goals_conceded': FieldValue.increment(1)}, SetOptions(merge: true));
        }

        if (disciplinaryPoints > 0) {
           final teamRef = _getTeamsRef(seasonId).doc(event.teamId);
           transaction.update(teamRef, {
             'disciplinary_points': FieldValue.increment(disciplinaryPoints),
             if (event.type == MatchEventType.yellowCard) 'total_yellow_cards': FieldValue.increment(1),
             if (event.type == MatchEventType.redCard) 'total_red_cards': FieldValue.increment(1),
           });
        }
      });
      return "Sucesso";
    } catch (e) { return "Erro ao registrar evento: $e"; }
  }

  Future<String> deleteMatchEvent({
    required String seasonId,
    required String matchId,
    required MatchEvent event,
  }) async {
    final matchRef = _getMatchesRef(seasonId).doc(matchId);
    final eventRef = matchRef.collection('timeline').doc(event.id);
    final seasonPlayerRef = _getPlayerStatsRef(seasonId).doc(event.playerId);

    try {
      await _firestore.runTransaction((transaction) async {
        final matchSnap = await transaction.get(matchRef);
        final matchData = matchSnap.data() as Map<String, dynamic>;
        final homeId = matchData['team_home_id'];
        final awayId = matchData['team_away_id'];

        String fieldInMatchStats = '';
        String fieldInSeasonStats = '';
        int scoreHomeDecrement = 0;
        int scoreAwayDecrement = 0;
        int disciplinaryPoints = 0;

        switch (event.type) {
          case MatchEventType.goal:
            fieldInMatchStats = 'goals';
            fieldInSeasonStats = 'goals';
            if (event.teamId == homeId) scoreHomeDecrement = -1;
            if (event.teamId == awayId) scoreAwayDecrement = -1;
            break;
          case MatchEventType.assist:
            fieldInMatchStats = 'assists';
            fieldInSeasonStats = 'assists';
            break;
          case MatchEventType.yellowCard:
            fieldInMatchStats = 'yellows';
            fieldInSeasonStats = 'total_yellow_cards';
            disciplinaryPoints = -10;
            break;
          case MatchEventType.redCard:
            fieldInMatchStats = 'reds';
            fieldInSeasonStats = 'total_red_cards';
            disciplinaryPoints = -21;
            break;
        }

        transaction.delete(eventRef);

        Map<String, dynamic> matchUpdates = {};
        if (scoreHomeDecrement != 0) matchUpdates['score_home'] = FieldValue.increment(scoreHomeDecrement);
        if (scoreAwayDecrement != 0) matchUpdates['score_away'] = FieldValue.increment(scoreAwayDecrement);
        
        if (fieldInMatchStats.isNotEmpty) {
           matchUpdates['stats_applied.player_stats.$fieldInMatchStats.${event.playerId}'] = FieldValue.increment(-1);
        }
        if (event.type == MatchEventType.goal && event.concededByPlayerId != null) {
           matchUpdates['stats_applied.player_stats.goals_conceded.${event.concededByPlayerId}'] = FieldValue.increment(-1);
        }
        transaction.update(matchRef, matchUpdates);

        if (fieldInSeasonStats.isNotEmpty) {
           Map<String, dynamic> playerUpdates = {fieldInSeasonStats: FieldValue.increment(-1)};
           if (event.type == MatchEventType.yellowCard) playerUpdates['yellow_cards'] = FieldValue.increment(-1);
           else if (event.type == MatchEventType.redCard) playerUpdates['red_cards'] = FieldValue.increment(-1);
           transaction.update(seasonPlayerRef, playerUpdates);
        }

        if (event.type == MatchEventType.goal && event.concededByPlayerId != null) {
           final goalkeeperRef = _getPlayerStatsRef(seasonId).doc(event.concededByPlayerId);
           transaction.update(goalkeeperRef, { 'goals_conceded': FieldValue.increment(-1) });
        }

        if (disciplinaryPoints != 0) {
           final teamRef = _getTeamsRef(seasonId).doc(event.teamId);
           transaction.update(teamRef, {
             'disciplinary_points': FieldValue.increment(disciplinaryPoints),
             if (event.type == MatchEventType.yellowCard) 'total_yellow_cards': FieldValue.increment(-1),
             if (event.type == MatchEventType.redCard) 'total_red_cards': FieldValue.increment(-1),
           });
        }
      });
      return "Sucesso";
    } catch (e) { return "Erro ao reverter evento: $e"; }
  }

  // ===========================================================================
  // 🔄 RECÁLCULO DE ESTATÍSTICAS (ATUALIZADO)
  // ===========================================================================

  Future<void> _recalculateTeamStats(String teamId, String seasonId) async {
    // 1. Variáveis para 1ª Fase
    int p1_MatchPoints = 0;
    int p1_Games = 0;
    int p1_Wins = 0, p1_Draws = 0, p1_Losses = 0;
    int p1_GoalsFor = 0, p1_GoalsAgainst = 0;

    // 2. Variáveis Gerais (Overall)
    int ov_MatchPoints = 0;
    int ov_Games = 0;
    int ov_Wins = 0, ov_Draws = 0, ov_Losses = 0;
    int ov_GoalsFor = 0, ov_GoalsAgainst = 0;

    final matchesRef = _getMatchesRef(seasonId);
    
    Future<void> processMatches(String side) async {
      // ALTERAÇÃO: Removemos o filtro 'phase' da query para pegar TODOS os jogos
      final query = await matchesRef
          .where('team_${side}_id', isEqualTo: teamId)
          .where('status', whereIn: ['finished', 'in_progress'])
          .get();

      for (final doc in query.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final scoreHome = (data['score_home'] ?? 0) as int;
        final scoreAway = (data['score_away'] ?? 0) as int;
        final phase = data['phase'] as String? ?? 'first';

        // Determina placar
        int myScore = (side == 'home') ? scoreHome : scoreAway;
        int opponentScore = (side == 'home') ? scoreAway : scoreHome;
        
        // Cálculos temporários para esta partida
        int points = 0;
        bool isWin = false;
        bool isDraw = false;
        bool isLoss = false;

        if (myScore > opponentScore) {
          points = 3; isWin = true;
        } else if (myScore < opponentScore) {
          isLoss = true;
        } else {
          points = 1; isDraw = true;
        }

        // --- ATUALIZA GERAL (SEMPRE) ---
        ov_Games++;
        ov_GoalsFor += myScore;
        ov_GoalsAgainst += opponentScore;
        ov_MatchPoints += points;
        if (isWin) ov_Wins++;
        if (isDraw) ov_Draws++;
        if (isLoss) ov_Losses++;

        // --- ATUALIZA 1ª FASE (CONDICIONAL) ---
        if (phase == 'first') {
          p1_Games++;
          p1_GoalsFor += myScore;
          p1_GoalsAgainst += opponentScore;
          p1_MatchPoints += points;
          if (isWin) p1_Wins++;
          if (isDraw) p1_Draws++;
          if (isLoss) p1_Losses++;
        }
      }
    }

    await processMatches('home');
    await processMatches('away');

    try {
      final teamRef = _getTeamsRef(seasonId).doc(teamId);
      final teamSnap = await teamRef.get();
      if (!teamSnap.exists) return;

      final currentExtraPoints = (teamSnap.data() as Map<String, dynamic>)['extra_points'] as int? ?? 0;
      
      // Totais Finais
      final int p1_TotalPoints = p1_MatchPoints + currentExtraPoints;
      final int p1_GoalDifference = p1_GoalsFor - p1_GoalsAgainst;

      final int ov_TotalPoints = ov_MatchPoints + currentExtraPoints;
      final int ov_GoalDifference = ov_GoalsFor - ov_GoalsAgainst;

      await teamRef.update({
        // Campos Originais (1ª Fase)
        'match_points': p1_MatchPoints,
        'points': p1_TotalPoints,
        'games_played': p1_Games,
        'wins': p1_Wins,
        'draws': p1_Draws,
        'losses': p1_Losses,
        'goals_for': p1_GoalsFor,
        'goals_against': p1_GoalsAgainst,
        'goal_difference': p1_GoalDifference,

        // Novos Campos (Geral)
        'overall_match_points': ov_MatchPoints,
        'overall_points': ov_TotalPoints,
        'overall_games_played': ov_Games,
        'overall_wins': ov_Wins,
        'overall_draws': ov_Draws,
        'overall_losses': ov_Losses,
        'overall_goals_for': ov_GoalsFor,
        'overall_goals_against': ov_GoalsAgainst,
        'overall_goal_difference': ov_GoalDifference,
      });
    } catch (e) {
      debugPrint("[RECALC] Erro: $e");
    }
  }

  
  // ===========================================================================
  // 🏆 CRUD TIMES & JOGADORES
  // ===========================================================================

  Future<String> createTeam({
    required String seasonId,
    required String name,
    required String shortName,
    required String shieldUrl,
    required List<Map<String, dynamic>> championshipHistory,
  }) async {
    try {
      final newTeamRef = _getTeamsRef(seasonId).doc();
      await newTeamRef.set({
        'name': name,
        'short_name': shortName,
        'shield_url': shieldUrl,
        'championship_history': championshipHistory,
        'points': 0, 'match_points': 0, 'extra_points': 0,
        'games_played': 0, 'wins': 0, 'draws': 0, 'losses': 0,
        'goals_for': 0, 'goals_against': 0, 'goal_difference': 0,
        'phase1_rank': null,
        'disciplinary_points': 0,
        'total_yellow_cards': 0, 'total_red_cards': 0,
        'default_starters': [],
      });
      return "Sucesso: Equipe '$name' criada.";
    } catch (e) { return "Erro: $e"; }
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
      return "Sucesso: Equipe '$name' atualizada.";
    } catch (e) { return "Erro: $e"; }
  }

  Future<String> deleteTeam(DocumentSnapshot teamDoc, String seasonId) async {
    final teamId = teamDoc.id;
    final WriteBatch batch = _firestore.batch();
    try {
      // Deleta Jogadores (Players Stats)
      final playersQ = await _getPlayerStatsRef(seasonId).where('team_id', isEqualTo: teamId).get();
      for (var p in playersQ.docs) batch.delete(p.reference);

      // Deleta Partidas (Casa e Fora)
      final homeMatchesQ = await _getMatchesRef(seasonId).where('team_home_id', isEqualTo: teamId).get();
      for (var m in homeMatchesQ.docs) batch.delete(m.reference);

      final awayMatchesQ = await _getMatchesRef(seasonId).where('team_away_id', isEqualTo: teamId).get();
      for (var m in awayMatchesQ.docs) batch.delete(m.reference);

      batch.delete(teamDoc.reference);
      await batch.commit();
      return "Sucesso: Time e vínculos excluídos.";
    } catch (e) { return "Erro: $e"; }
  }

  Future<String> createPlayer({
    required String seasonId,
    required Map<String, dynamic> data,
  }) async {
    try {
      // 1. Cria no Global (Para manter histórico futuro e ID único)
      final DocumentReference globalRef = await _firestore.collection('players').add({
        ...data,
        'isActive': true,
        'goals': 0, 'assists': 0, 'yellow_cards': 0, 'red_cards': 0,
        'total_yellow_cards': 0, 'total_red_cards': 0,
      });

      // 2. Cria na Temporada Atual (SEMPRE)
      final seasonPlayerRef = _getPlayerStatsRef(seasonId).doc(globalRef.id);
      final seasonData = Map<String, dynamic>.from(data);
      seasonData['isActive'] = true;
      // Zera stats para a temporada
      seasonData['goals'] = 0; seasonData['assists'] = 0;
      seasonData['yellow_cards'] = 0; seasonData['red_cards'] = 0;
      seasonData['total_yellow_cards'] = 0; seasonData['total_red_cards'] = 0;
      seasonData['man_of_the_match_awards'] = 0; seasonData['goals_conceded'] = 0;
      seasonData['is_suspended'] = false;

      await seasonPlayerRef.set(seasonData);
      
      return "Sucesso: Jogador criado.";
    } catch (e) { return "Erro ao criar jogador: $e"; }
  }

  Future<String> updatePlayer({
    required String seasonId,
    required String playerId,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _firestore.collection('players').doc(playerId).update(data); // Atualiza global

      // Atualiza na Temporada Atual (SEMPRE)
      final seasonPlayerRef = _getPlayerStatsRef(seasonId).doc(playerId);
      
      // Usa set com merge para garantir que atualize ou crie se faltar
      await seasonPlayerRef.set(data, SetOptions(merge: true));

      return "Sucesso: Jogador atualizado.";
    } catch (e) { return "Erro ao atualizar jogador: $e"; }
  }

  Future<String> deletePlayer(DocumentSnapshot doc, String seasonId) async {
    try {
      await _firestore.collection('players').doc(doc.id).update({'isActive': false});
      // Inativa na temporada atual
      try {
        await _getPlayerStatsRef(seasonId).doc(doc.id).update({'isActive': false});
      } catch (_) {}
      
      return "Sucesso: Jogador inativado.";
    } catch (e) { return "Erro: $e"; }
  }

  // ===========================================================================
  // 🎮 CRUD PARTIDAS
  // ===========================================================================

  Future<String> createMatch({
    required String seasonId,
    required DocumentSnapshot homeTeam,
    required DocumentSnapshot awayTeam,
    required String location,
    required int round,
    required DateTime dateTime,
  }) async {
    try {
      final hData = homeTeam.data() as Map<String, dynamic>;
      final aData = awayTeam.data() as Map<String, dynamic>;

      await _getMatchesRef(seasonId).add({
        'phase': 'first', 'round': round, 'datetime': Timestamp.fromDate(dateTime), 'location': location,
        'status': 'pending', 'score_home': null, 'score_away': null,
        'team_home_id': homeTeam.id, 'team_home_name': hData['name'], 'team_home_shield': hData['shield_url'],
        'team_away_id': awayTeam.id, 'team_away_name': aData['name'], 'team_away_shield': aData['shield_url'],
      });
      return "Sucesso: Partida criada.";
    } catch (e) { return "Erro: $e"; }
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
      final hData = homeTeam.data() as Map<String, dynamic>;
      final aData = awayTeam.data() as Map<String, dynamic>;

      await match.reference.update({
        'phase': phase, 'round': round, 'datetime': Timestamp.fromDate(dateTime), 'location': location,
        'team_home_id': homeTeam.id, 'team_home_name': hData['name'], 'team_home_shield': hData['shield_url'],
        'team_away_id': awayTeam.id, 'team_away_name': aData['name'], 'team_away_shield': aData['shield_url'],
      });
      return "Sucesso: Partida atualizada.";
    } catch (e) { return "Erro: $e"; }
  }

  Future<String> deleteMatch(DocumentSnapshot match, String seasonId) async {
    try {
      final data = match.data() as Map<String, dynamic>;
      final status = data['status'];
      await match.reference.delete();

      // ALTERAÇÃO: Recalcula se estava finalizada, INDEPENDENTE da fase
      if (status == 'finished') {
        await _recalculateTeamStats(data['team_home_id'], seasonId);
        await _recalculateTeamStats(data['team_away_id'], seasonId);
      }
      return "Sucesso: Partida excluída.";
    } catch (e) { return "Erro: $e"; }
  }

// --- CÓPIA DE TEMPORADA (Refatorado para não depender de Legacy) ---
  Future<void> copySeasonData({
    required String sourceSeasonId,
    required String targetSeasonId,
    required bool includeRoster,
  }) async {
    final WriteBatch batch = _firestore.batch();
    
    // 1. Configs
    final configDocs = ['app_settings', 'disciplinary_rules', 'playoff_rules', 'tiebreaker_rules'];
    for (String docId in configDocs) {
        // Agora busca sempre na estrutura de temporada
        final docSnap = await _firestore.collection('championships').doc(sourceSeasonId).collection('settings').doc(docId).get();
        if (docSnap.exists) {
           final targetRef = _firestore.collection('championships').doc(targetSeasonId).collection('settings').doc(docId);
           batch.set(targetRef, docSnap.data()!);
        }
    }

    // 2. Times e Jogadores
    final sourceTeamsSnapshot = await _firestore.collection('championships').doc(sourceSeasonId).collection('teams_participation').get();

    final targetTeamsRef = _firestore.collection('championships').doc(targetSeasonId).collection('teams_participation');
    final targetPlayerStatsRef = _firestore.collection('championships').doc(targetSeasonId).collection('player_stats');

    for (var teamDoc in sourceTeamsSnapshot.docs) {
      final teamData = teamDoc.data();
      final String teamId = teamDoc.id;

      // Cria Time na Nova Temporada
      Map<String, dynamic> newTeamData = {
        'name': teamData['name'], 'short_name': teamData['short_name'], 'shield_url': teamData['shield_url'],
        'championship_history': teamData['championship_history'] ?? [],
        'points': 0, 'match_points': 0, 'extra_points': 0,
        'games_played': 0, 'wins': 0, 'draws': 0, 'losses': 0,
        'goals_for': 0, 'goals_against': 0, 'goal_difference': 0,
        'phase1_rank': null, 'disciplinary_points': 0,
        'total_yellow_cards': 0, 'total_red_cards': 0,
        'default_starters': includeRoster ? (teamData['default_starters'] ?? []) : [],
      };
      batch.set(targetTeamsRef.doc(teamId), newTeamData);

      if (includeRoster) {
        // Busca jogadores sempre na estrutura de temporada
        final playersInTeamSnap = await _firestore.collection('championships').doc(sourceSeasonId).collection('player_stats').where('team_id', isEqualTo: teamId).get();

        for (var playerDoc in playersInTeamSnap.docs) {
          final pData = playerDoc.data();
          batch.set(targetPlayerStatsRef.doc(playerDoc.id), {
            'name': pData['name'], 'photo_url': pData['photo_url'],
            'position': pData['position'], 'is_goalkeeper': pData['is_goalkeeper'] ?? false,
            'is_staff': pData['is_staff'] ?? false, 'jersey_number': pData['jersey_number'],
            'team_id': teamId, 'team_name': teamData['name'], 'team_shield_url': teamData['shield_url'],
            'goals': 0, 'assists': 0, 'goals_conceded': 0, 'yellow_cards': 0, 'red_cards': 0,
            'total_yellow_cards': 0, 'total_red_cards': 0, 'man_of_the_match_awards': 0,
            'is_suspended': false, 'isActive': true,
          });
        }
      }
    }
    await batch.commit();
  }

  // --- UPDATE COMPLEXO (Stats de Partida) ---
  Future<String> updateMatchStats({
    required String seasonId,
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
    final matchDataBefore = matchSnapshot.data() as Map<String, dynamic>;
    final String? homeTeamId = matchDataBefore['team_home_id'];
    final String? awayTeamId = matchDataBefore['team_away_id'];

    if (homeTeamId == null || awayTeamId == null) return "Erro: IDs dos times inválidos.";

    final CollectionReference matchesRef = _getMatchesRef(seasonId);
    final CollectionReference teamsRef = _getTeamsRef(seasonId);
    final CollectionReference playersRef = _getPlayerStatsRef(seasonId);

    try {
      await _firestore.runTransaction((transaction) async {
        final freshMatchDoc = await transaction.get(matchesRef.doc(matchId));
        if (!freshMatchDoc.exists) throw Exception("Partida não encontrada!");
        final currentMatchData = freshMatchDoc.data() as Map<String, dynamic>;
        
        final oldStats = currentMatchData['stats_applied'] as Map<String, dynamic>? ?? {};
        final oldPlayerStats = oldStats['player_stats'] as Map<String, dynamic>? ?? {};
        
        Map<String, int> oldGoals = Map<String, int>.from(oldPlayerStats['goals'] ?? {});
        Map<String, int> oldAssists = Map<String, int>.from(oldPlayerStats['assists'] ?? {});
        Map<String, int> oldYellows = Map<String, int>.from(oldPlayerStats['yellows'] ?? {});
        Map<String, int> oldReds = Map<String, int>.from(oldPlayerStats['reds'] ?? {});
        Map<String, int> oldGoalsConceded = Map<String, int>.from(oldPlayerStats['goals_conceded'] ?? {});
        String? oldManOfTheMatchId = oldStats['man_of_the_match'];

        Set<String> playersToReadIds = {
          ...newGoals.keys, ...oldGoals.keys, ...newAssists.keys, ...oldAssists.keys,
          ...newYellows.keys, ...oldYellows.keys, ...newReds.keys, ...oldReds.keys,
          ...newGoalsConceded.keys, ...oldGoalsConceded.keys,
          if (newManOfTheMatchId != null) newManOfTheMatchId,
          if (oldManOfTheMatchId != null) oldManOfTheMatchId,
        };
        playersToReadIds.removeWhere((id) => id.isEmpty);

        Map<String, DocumentSnapshot> playerSnaps = {};
        for (String playerId in playersToReadIds) {
          final snap = await transaction.get(playersRef.doc(playerId));
          if (snap.exists) playerSnaps[playerId] = snap;
        }

        final Map<String, dynamic> newPlayerStatsToSave = {
          'goals': newGoals, 'assists': newAssists, 'yellows': newYellows, 'reds': newReds, 'goals_conceded': newGoalsConceded,
        };

        transaction.update(freshMatchDoc.reference, {
          'score_home': newScoreHome, 'score_away': newScoreAway, 'status': newStatus,
          'penalty_score_home': penaltyScoreHome, 'penalty_score_away': penaltyScoreAway,
          'winner_team_id': winnerTeamId, 'sumula_url': newSumulaUrl,
          'stats_applied': {
            'player_stats': newPlayerStatsToSave, 'man_of_the_match': newManOfTheMatchId, 'media_links': newMediaLinks,
            'starters_home': [], 'starters_away': [],
          },
        });

        // Deltas
        Map<String, int> goalDelta = _calculateDelta(oldGoals, newGoals);
        Map<String, int> assistDelta = _calculateDelta(oldAssists, newAssists);
        Map<String, int> goalsConcededDelta = _calculateDelta(oldGoalsConceded, newGoalsConceded);
        Map<String, int> yellowDelta = _calculateDelta(oldYellows, newYellows);
        Map<String, int> redDelta = _calculateDelta(oldReds, newReds);

        // Atualiza Players
        goalDelta.forEach((pid, d) { if (d != 0 && playerSnaps.containsKey(pid)) transaction.update(playerSnaps[pid]!.reference, {'goals': FieldValue.increment(d)}); });
        assistDelta.forEach((pid, d) { if (d != 0 && playerSnaps.containsKey(pid)) transaction.update(playerSnaps[pid]!.reference, {'assists': FieldValue.increment(d)}); });
        goalsConcededDelta.forEach((pid, d) { if (d != 0 && playerSnaps.containsKey(pid)) transaction.update(playerSnaps[pid]!.reference, {'goals_conceded': FieldValue.increment(d)}); });

        if (oldManOfTheMatchId != newManOfTheMatchId) {
          if (oldManOfTheMatchId != null && playerSnaps.containsKey(oldManOfTheMatchId)) transaction.update(playerSnaps[oldManOfTheMatchId]!.reference, {'man_of_the_match_awards': FieldValue.increment(-1)});
          if (newManOfTheMatchId != null && playerSnaps.containsKey(newManOfTheMatchId)) transaction.update(playerSnaps[newManOfTheMatchId]!.reference, {'man_of_the_match_awards': FieldValue.increment(1)});
        }

        int disciplinaryHomeDelta = 0, disciplinaryAwayDelta = 0;
        int totalYellowHomeDelta = 0, totalYellowAwayDelta = 0;
        int totalRedHomeDelta = 0, totalRedAwayDelta = 0;

        Set<String> affectedCardPlayerIds = {...yellowDelta.keys, ...redDelta.keys};
        for (String playerId in affectedCardPlayerIds) {
          if (!playerSnaps.containsKey(playerId)) continue;
          final playerSnap = playerSnaps[playerId]!;
          final playerData = playerSnap.data() as Map<String, dynamic>;

          int yDelta = yellowDelta[playerId] ?? 0;
          int rDelta = redDelta[playerId] ?? 0;
          
          transaction.update(playerSnap.reference, {
            'yellow_cards': FieldValue.increment(yDelta),
            'red_cards': FieldValue.increment(rDelta),
            'total_yellow_cards': FieldValue.increment(yDelta),
            'total_red_cards': FieldValue.increment(rDelta),
          });

          final pTeamId = playerData['team_id'];
          final int discPoints = (yDelta * 10) + (rDelta * 21);
          if (pTeamId == homeTeamId) {
            disciplinaryHomeDelta += discPoints; totalYellowHomeDelta += yDelta; totalRedHomeDelta += rDelta;
          } else if (pTeamId == awayTeamId) {
            disciplinaryAwayDelta += discPoints; totalYellowAwayDelta += yDelta; totalRedAwayDelta += rDelta;
          }
        }

        if (disciplinaryHomeDelta != 0 || totalYellowHomeDelta != 0) {
           transaction.update(teamsRef.doc(homeTeamId), {
             'disciplinary_points': FieldValue.increment(disciplinaryHomeDelta),
             'total_yellow_cards': FieldValue.increment(totalYellowHomeDelta),
             'total_red_cards': FieldValue.increment(totalRedHomeDelta),
           });
        }
        if (disciplinaryAwayDelta != 0 || totalYellowAwayDelta != 0) {
           transaction.update(teamsRef.doc(awayTeamId), {
             'disciplinary_points': FieldValue.increment(disciplinaryAwayDelta),
             'total_yellow_cards': FieldValue.increment(totalYellowAwayDelta),
             'total_red_cards': FieldValue.increment(totalRedAwayDelta),
           });
        }
      });

      // ALTERAÇÃO: Recalcula se o status é finished, INDEPENDENTE da fase
      if ((newStatus == 'finished' || matchDataBefore['status'] == 'finished')) {
        await _recalculateTeamStats(homeTeamId, seasonId);
        await _recalculateTeamStats(awayTeamId, seasonId);
      }
      return "Sucesso";
    } catch (e) { return "Erro: $e"; }
  }

  Map<String, int> _calculateDelta(Map<String, int> oldMap, Map<String, int> newMap) {
    Map<String, int> delta = {};
    newMap.forEach((k, v) {
      int old = oldMap[k] ?? 0;
      if (v != old) delta[k] = v - old;
    });
    oldMap.forEach((k, v) {
      if (!newMap.containsKey(k) && v > 0) delta[k] = -v;
    });
    return delta;
  }
}