import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'admin_service.dart';
import '../models/match_event.dart';
import '../models/match_model.dart';
import '../models/team_model.dart';
import '../utils/standings_calculator.dart';
import 'team_service.dart';
import 'player_service.dart';
import 'disciplinary_service.dart';

class MatchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  final TeamService _teamService = TeamService();
  final PlayerService _playerService = PlayerService();
  final DisciplinaryService _disciplinaryService = DisciplinaryService();

  CollectionReference _getMatchesRef(String seasonId) {
    return _firestore.collection('championships').doc(seasonId).collection('matches');
  }

  // ===========================================================================
  // 🔄 LEITURA
  // ===========================================================================

  Stream<List<MatchModel>> streamMatches(String seasonId, {String? phase, int? round}) {
    Query query = _getMatchesRef(seasonId);
    if (phase != null) query = query.where('phase', isEqualTo: phase);
    if (round != null) query = query.where('round', isEqualTo: round);

    return query
        .orderBy('datetime')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => MatchModel.fromFirestore(doc))
            .toList());
  }

  // ===========================================================================
  // ⚡ CORE: PROCESSAMENTO DE SÚMULA E ESTATÍSTICAS
  // ===========================================================================

  Future<void> recalculateMatchStatsFromTimeline(String seasonId, String matchId, {String? excludeEventId}) async {
    final matchRef = _getMatchesRef(seasonId).doc(matchId);
    final timelineRef = matchRef.collection('timeline');

    try {
      await Future.delayed(const Duration(milliseconds: 300));

      final snapshot = await timelineRef.get();
      final List<MatchEvent> events = [];
      for (var doc in snapshot.docs) {
        try {
          events.add(MatchEvent.fromMap(doc.id, doc.data()));
        } catch (_) {}
      }

      int scoreHome = 0;
      int scoreAway = 0;
      int discHome = 0;
      int discAway = 0;

      Map<String, int> goals = {};
      Map<String, int> assists = {};
      Map<String, int> yellows = {};
      Map<String, int> reds = {};
      Map<String, int> conceded = {};
      
      // 🚨 NOVOS SCOUTS 🚨
      Map<String, int> penaltiesSaved = {};
      Map<String, int> penaltiesMissed = {};
      Map<String, int> shotsOnPost = {};

      final matchSnap = await matchRef.get();
      if (!matchSnap.exists) return;
      
      final matchData = matchSnap.data() as Map<String, dynamic>;
      final homeId = matchData['team_home_id'];
      final awayId = matchData['team_away_id'];
      final String status = matchData['status'] ?? 'pending';
      final String matchLabel = "Rodada ${matchData['round']} - ${matchData['team_home_name']} x ${matchData['team_away_name']}";

      await _firestore.runTransaction((transaction) async {
        for (var event in events) {
          if (event.id == excludeEventId) continue;
          final pid = event.playerId;
          if (pid.isEmpty) continue;

          if (event.type == MatchEventType.goal) {
            if (event.teamId == homeId) scoreHome++;
            else if (event.teamId == awayId) scoreAway++;
            goals[pid] = (goals[pid] ?? 0) + 1;
            if (event.concededByPlayerId != null) conceded[event.concededByPlayerId!] = (conceded[event.concededByPlayerId!] ?? 0) + 1;
          }
          else if (event.type == MatchEventType.assist) {
            assists[pid] = (assists[pid] ?? 0) + 1;
          }
          else if (event.type == MatchEventType.yellowCard) {
            yellows[pid] = (yellows[pid] ?? 0) + 1;
            if (event.teamId == homeId) discHome += 10;
            if (event.teamId == awayId) discAway += 10;

            if (status == 'finished' && (yellows[pid] ?? 0) >= AdminService.suspensionYellowCards) {
               _disciplinaryService.recordDisciplinaryLog(
                 transaction, seasonId, matchId, pid, 
                 {'name': event.playerName, 'team_id': event.teamId}, 
                 matchLabel, "Acúmulo de ${AdminService.suspensionYellowCards} CA"
               );
            }
          }
          else if (event.type == MatchEventType.redCard) {
            reds[pid] = (reds[pid] ?? 0) + 1;
            if (event.teamId == homeId) discHome += 21;
            if (event.teamId == awayId) discAway += 21;

            if (status == 'finished') {
              _disciplinaryService.recordDisciplinaryLog(
                transaction, seasonId, matchId, pid, 
                {'name': event.playerName, 'team_id': event.teamId}, 
                matchLabel, "Cartão Vermelho (Expulsão)"
              );
            }
          }
          // 🚨 ADICIONANDO REGISTRO DOS NOVOS SCOUTS
          else if (event.type == MatchEventType.penaltySaved) {
            penaltiesSaved[pid] = (penaltiesSaved[pid] ?? 0) + 1;
          }
          else if (event.type == MatchEventType.penaltyMissed) {
            penaltiesMissed[pid] = (penaltiesMissed[pid] ?? 0) + 1;
          }
          else if (event.type == MatchEventType.shotOnPost) {
            shotsOnPost[pid] = (shotsOnPost[pid] ?? 0) + 1;
          }
        }

        transaction.update(matchRef, {
          'score_home': scoreHome,
          'score_away': scoreAway,
          'disciplinary_home': discHome, 
          'disciplinary_away': discAway,
          'stats_applied.player_stats': {
            'goals': goals,
            'assists': assists,
            'yellows': yellows,
            'reds': reds,
            'goals_conceded': conceded, // Mantido apenas para visualização de estatísticas no perfil
            'penalties_saved': penaltiesSaved,
            'penalties_missed': penaltiesMissed,
            'shots_on_post': shotsOnPost,
          }
        });
      });

      if (status == 'finished') {
        await _recalculateSpecificTeamsAndPlayers(seasonId, [homeId, awayId]);
      }

    } catch (e) {
      debugPrint("❌ Erro ao recalcular partida e logs: $e");
    }
  }

  // ===========================================================================
  // 🚀 OTIMIZAÇÃO: RECÁLCULO INCREMENTAL (Senior Fix)
  // ===========================================================================

  Future<void> _recalculateSpecificTeamsAndPlayers(String seasonId, List<String> teamIds) async {
    final batch = _firestore.batch();
    final matchesRef = _getMatchesRef(seasonId);

    final playersQuery = await _playerService.getPlayerStatsRef(seasonId)
        .where('team_id', whereIn: teamIds)
        .get();

    final matchesHome = await matchesRef.where('team_home_id', whereIn: teamIds).where('status', isEqualTo: 'finished').get();
    final matchesAway = await matchesRef.where('team_away_id', whereIn: teamIds).where('status', isEqualTo: 'finished').get();

    final Map<String, DocumentSnapshot> relevantMatches = {};
    for (var doc in matchesHome.docs) relevantMatches[doc.id] = doc;
    for (var doc in matchesAway.docs) relevantMatches[doc.id] = doc;

    Map<String, Map<String, int>> playerTotals = {}; 
    Map<String, Map<String, int>> teamTotals = {};   

    for (var tid in teamIds) {
      teamTotals[tid] = {'disciplinary_points': 0, 'total_yellow_cards': 0, 'total_red_cards': 0};
    }

    for (var matchDoc in relevantMatches.values) {
      final data = matchDoc.data() as Map<String, dynamic>;
      final statsApplied = data['stats_applied'] as Map<String, dynamic>?;
      
      if (statsApplied != null && statsApplied['player_stats'] != null) {
        final pStats = statsApplied['player_stats'] as Map<String, dynamic>;
        
        void processStat(String type, Map<String, dynamic> map, int multiplier) {
          map.forEach((pid, val) {
            int count = (val as num).toInt();
            if (!playerTotals.containsKey(pid)) playerTotals[pid] = {};
            playerTotals[pid]![type] = (playerTotals[pid]![type] ?? 0) + count;
          });
        }

        if (pStats['goals'] is Map) processStat('goals', pStats['goals'], 1);
        if (pStats['assists'] is Map) processStat('assists', pStats['assists'], 1);
        if (pStats['goals_conceded'] is Map) processStat('goals_conceded', pStats['goals_conceded'], 1);
        if (pStats['yellows'] is Map) processStat('total_yellow_cards', pStats['yellows'], 1);
        if (pStats['reds'] is Map) processStat('total_red_cards', pStats['reds'], 1);
        
        // 🚨 AGREGANDO OS NOVOS SCOUTS NOS STATS (Opcional, mas limpo)
        if (pStats['penalties_saved'] is Map) processStat('penalties_saved', pStats['penalties_saved'], 1);
        if (pStats['penalties_missed'] is Map) processStat('penalties_missed', pStats['penalties_missed'], 1);
        if (pStats['shots_on_post'] is Map) processStat('shots_on_post', pStats['shots_on_post'], 1);

        String hId = data['team_home_id'];
        String aId = data['team_away_id'];
        
        if (teamTotals.containsKey(hId)) teamTotals[hId]!['disciplinary_points'] = (teamTotals[hId]!['disciplinary_points'] ?? 0) + (data['disciplinary_home'] as int? ?? 0);
        if (teamTotals.containsKey(aId)) teamTotals[aId]!['disciplinary_points'] = (teamTotals[aId]!['disciplinary_points'] ?? 0) + (data['disciplinary_away'] as int? ?? 0);
      }
    }

    final activeSuspensionsSnap = await _firestore.collection('championships').doc(seasonId).collection('disciplinary_log').where('return_date', isNull: true).get();
        
    Set<String> suspendedPlayerIds = activeSuspensionsSnap.docs.map((d) => d['playerId'] as String).toSet();

    for (var pDoc in playersQuery.docs) {
      final pid = pDoc.id;
      final stats = playerTotals[pid] ?? {}; 
      
      final int y = stats['total_yellow_cards'] ?? 0;
      final int r = stats['total_red_cards'] ?? 0;
      
      batch.update(pDoc.reference, {
        'goals': stats['goals'] ?? 0,
        'assists': stats['assists'] ?? 0,
        'goals_conceded': stats['goals_conceded'] ?? 0,
        'total_yellow_cards': y,
        'yellow_cards': y % AdminService.suspensionYellowCards, 
        'total_red_cards': r,
        'red_cards': r, 
        'is_suspended': suspendedPlayerIds.contains(pid),
      });
    }

    for (var tid in teamIds) {
      int teamY = 0;
      int teamR = 0;
      final teamPlayers = playersQuery.docs.where((d) => d['team_id'] == tid);
      
      for(var p in teamPlayers) {
         final pid = p.id;
         teamY += playerTotals[pid]?['total_yellow_cards'] ?? 0;
         teamR += playerTotals[pid]?['total_red_cards'] ?? 0;
      }

      final tRef = _teamService.getTeamsRef(seasonId).doc(tid);
      final discPoints = teamTotals[tid]?['disciplinary_points'] ?? 0;

      batch.update(tRef, {
        'disciplinary_points': discPoints,
        'total_yellow_cards': teamY,
        'total_red_cards': teamR,
      });
    }

    await batch.commit();

    for (String tid in teamIds) {
      await _teamService.recalculateTeamStats(tid, seasonId);
    }
  }

  // ===========================================================================
  // ➕ ADICIONAR EVENTO
  // ===========================================================================

  Future<String> addMatchEvent({required String seasonId, required String matchId, required MatchEvent event}) async {
    final matchRef = _getMatchesRef(seasonId).doc(matchId);
    final eventRef = matchRef.collection('timeline').doc();
    
    try {
      await _firestore.runTransaction((transaction) async {
        transaction.set(eventRef, event.toMap());
        transaction.update(matchRef, {'status': 'in_progress'});
      });

      await recalculateMatchStatsFromTimeline(seasonId, matchId);
      return "Sucesso";
    } catch (e) {
      return "Erro ao adicionar: $e";
    }
  }

  // ===========================================================================
  // ✏️ EDITAR EVENTO
  // ===========================================================================

  Future<String> updateMatchEvent({
    required String seasonId,
    required String matchId,
    required MatchEvent oldEvent,
    required MatchEvent newEvent,
  }) async {
    final eventRef = _getMatchesRef(seasonId).doc(matchId).collection('timeline').doc(oldEvent.id);
    
    try {
      await eventRef.update(newEvent.toMap());
      await recalculateMatchStatsFromTimeline(seasonId, matchId);
      return "Sucesso";
    } catch (e) {
      return "Erro ao editar: $e";
    }
  }

  // ===========================================================================
  // 🗑️ EXCLUIR EVENTO
  // ===========================================================================

  Future<String> deleteMatchEvent({required String seasonId, required String matchId, required MatchEvent event}) async {
    final eventRef = _getMatchesRef(seasonId).doc(matchId).collection('timeline').doc(event.id);
    
    try {
      await _firestore.runTransaction((transaction) async {
        transaction.delete(eventRef);
        if (event.type == MatchEventType.redCard || event.type == MatchEventType.yellowCard) {
          _disciplinaryService.removeDisciplinaryLog(transaction, seasonId, matchId, event.playerId);
        }
      });
      
      await recalculateMatchStatsFromTimeline(seasonId, matchId, excludeEventId: event.id);
      return "Sucesso";
    } catch (e) { return "Erro ao excluir: $e"; }
  }

  // ===========================================================================
  // 🏆 ADMIN UPDATE (Metadados da Partida)
  // ===========================================================================

  Future<String> updateMatchStats({
    required String seasonId, required DocumentSnapshot matchSnapshot, required String newStatus, required int newScoreHome, required int newScoreAway,
    required Map<String, int> newGoals, required Map<String, int> newAssists, required Map<String, int> newYellows, required Map<String, int> newReds, required Map<String, int> newGoalsConceded,
    required String? newManOfTheMatchId, required int? penaltyScoreHome, required int? penaltyScoreAway, required String? winnerTeamId, required String? newSumulaUrl, required List<Map<String, dynamic>> newMediaLinks,
  }) async {
    try {
      final matchId = matchSnapshot.id;
      
      await _firestore.collection('championships').doc(seasonId).collection('matches').doc(matchId).update({
        'status': newStatus,
        'penalty_score_home': penaltyScoreHome,
        'penalty_score_away': penaltyScoreAway,
        'winner_team_id': winnerTeamId,
        'sumula_url': newSumulaUrl,
        'stats_applied.man_of_the_match': newManOfTheMatchId,
        'stats_applied.media_links': newMediaLinks,
        'score_home': newScoreHome, 
        'score_away': newScoreAway,
      });

      if (newStatus == 'finished') {
         await recalculateMatchStatsFromTimeline(seasonId, matchId); 
         await _checkAndGenerateNextPhase(seasonId, triggeringMatchRound: matchSnapshot['round']);
      }
      return "Sucesso";
    } catch (e) { return "Erro: $e"; }
  }

  // ===========================================================================
  // ⚙️ GERAÇÃO DE FASES
  // ===========================================================================

  Future<void> _checkAndGenerateNextPhase(String seasonId, {int? triggeringMatchRound}) async {
    await AdminService.loadAllRules(seasonId);
    
    final bool isModel2 = AdminService.tournamentFormat == 'model_2';
    final matchesRef = _getMatchesRef(seasonId);
    final teamsSnapshot = await _teamService.getTeamsRef(seasonId).get();
    final List<Team> allTeams = teamsSnapshot.docs.map((d) => Team.fromFirestore(d)).toList();

    final phase1Snapshot = await matchesRef.where('phase', isEqualTo: 'first').get();
    if (phase1Snapshot.docs.isEmpty) return;

    final allFinished = phase1Snapshot.docs.every((doc) => doc['status'] == 'finished');
    
    if (!allFinished) return;

    final nextPhaseCheck = isModel2 ? 'quarter_final' : 'semifinal';
    final checkSnap = await matchesRef.where('phase', isEqualTo: nextPhaseCheck).limit(1).get();
    
    if (checkSnap.docs.isEmpty) {
      final List<MatchModel> allPhase1Matches = phase1Snapshot.docs.map((d) => MatchModel.fromFirestore(d)).toList();
      final standings = StandingsCalculator.calculate(teams: allTeams, matches: allPhase1Matches, simulatedScores: null);

      if (standings.length >= 4) {
        final baseDate = DateTime.now().add(const Duration(days: 7));
        
        if (isModel2 && standings.length >= 6) {
           await _createMatchInternal(seasonId, standings[2].team.id, standings[5].team.id, standings[2].team.name, standings[5].team.name, standings[2].team.shieldUrl, standings[5].team.shieldUrl, 'Playoff 1', 8, baseDate, 'quarter_final');
           await _createMatchInternal(seasonId, standings[3].team.id, standings[4].team.id, standings[3].team.name, standings[4].team.name, standings[3].team.shieldUrl, standings[4].team.shieldUrl, 'Playoff 2', 8, baseDate.add(const Duration(hours: 1)), 'quarter_final');
        } else {
           await _createMatchInternal(seasonId, standings[0].team.id, standings[3].team.id, standings[0].team.name, standings[3].team.name, standings[0].team.shieldUrl, standings[3].team.shieldUrl, 'Semifinal 1', 9, baseDate, 'semifinal');
           await _createMatchInternal(seasonId, standings[1].team.id, standings[2].team.id, standings[1].team.name, standings[2].team.name, standings[1].team.shieldUrl, standings[2].team.shieldUrl, 'Semifinal 2', 9, baseDate.add(const Duration(hours: 1)), 'semifinal');
        }
      }
    }
  }

  // ===========================================================================
  // 📝 CRUD BÁSICO
  // ===========================================================================

  Future<String> createMatch({required String seasonId, required DocumentSnapshot homeTeam, required DocumentSnapshot awayTeam, required String location, required int round, required DateTime dateTime}) async {
    try {
      final hData = homeTeam.data() as Map<String, dynamic>;
      final aData = awayTeam.data() as Map<String, dynamic>;
      await _getMatchesRef(seasonId).add({
        'phase': 'first', 'round': round, 'datetime': Timestamp.fromDate(dateTime), 'location': location, 'status': 'pending',
        'score_home': 0, 'score_away': 0,
        'team_home_id': homeTeam.id, 'team_home_name': hData['name'], 'team_home_shield': hData['shield_url'],
        'team_away_id': awayTeam.id, 'team_away_name': aData['name'], 'team_away_shield': aData['shield_url']
      });
      return "Sucesso: Partida criada.";
    } catch (e) { return "Erro: $e"; }
  }

  Future<String> updateMatchDetails({required DocumentSnapshot match, required DocumentSnapshot homeTeam, required DocumentSnapshot awayTeam, required String location, required int round, required DateTime dateTime, required String phase}) async {
    try {
      final hData = homeTeam.data() as Map<String, dynamic>;
      final aData = awayTeam.data() as Map<String, dynamic>;
      await match.reference.update({
        'phase': phase, 'round': round, 'datetime': Timestamp.fromDate(dateTime), 'location': location,
        'team_home_id': homeTeam.id, 'team_home_name': hData['name'], 'team_home_shield': hData['shield_url'],
        'team_away_id': awayTeam.id, 'team_away_name': aData['name'], 'team_away_shield': aData['shield_url']
      });
      return "Sucesso: Partida atualizada.";
    } catch (e) { return "Erro: $e"; }
  }

  Future<String> deleteMatch(DocumentSnapshot match, String seasonId) async {
    try {
      final data = match.data() as Map<String, dynamic>;
      final hId = data['team_home_id'];
      final aId = data['team_away_id'];
      final status = data['status'];

      await match.reference.delete();
      
      if (status == 'finished') {
        await _recalculateSpecificTeamsAndPlayers(seasonId, [hId, aId]);
      }
      return "Sucesso: Partida excluída.";
    } catch (e) { return "Erro: $e"; }
  }

  Future<void> _createMatchInternal(String seasonId, String hId, String aId, String hName, String aName, String hShield, String aShield, String loc, int round, DateTime date, String phase) async {
    await _getMatchesRef(seasonId).add({
      'phase': phase, 'round': round, 'datetime': Timestamp.fromDate(date), 'location': loc,
      'status': 'pending', 'score_home': null, 'score_away': null,
      'team_home_id': hId, 'team_home_name': hName, 'team_home_shield': hShield,
      'team_away_id': aId, 'team_away_name': aName, 'team_away_shield': aShield,
    });
  }
}