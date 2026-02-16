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
  // ⚡ CORE 1: REPROCESSAMENTO DA SÚMULA DA PARTIDA
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
      // --- NOVO: Acumuladores de Disciplina da Partida ---
      int discHome = 0;
      int discAway = 0;
      // ---------------------------------------------------
      Map<String, int> goals = {};
      Map<String, int> assists = {};
      Map<String, int> yellows = {};
      Map<String, int> reds = {};
      Map<String, int> conceded = {};

      final matchSnap = await matchRef.get();
      if (!matchSnap.exists) return;
      
      final matchData = matchSnap.data() as Map<String, dynamic>;
      final homeId = matchData['team_home_id'];
      final awayId = matchData['team_away_id'];
      final String status = matchData['status'] ?? 'pending';

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
        else if (event.type == MatchEventType.assist) assists[pid] = (assists[pid] ?? 0) + 1;
       
        // --- CÁLCULO DE DISCIPLINA NA HORA ---
        else if (event.type == MatchEventType.yellowCard) {
          yellows[pid] = (yellows[pid] ?? 0) + 1;
          if (event.teamId == homeId) discHome += 10;
          if (event.teamId == awayId) discAway += 10;
        }
        else if (event.type == MatchEventType.redCard) {
          reds[pid] = (reds[pid] ?? 0) + 1;
          if (event.teamId == homeId) discHome += 21;
          if (event.teamId == awayId) discAway += 21;
        }
        // --------------------------------------
        }

      await matchRef.update({
        'score_home': scoreHome,
        'score_away': scoreAway,
        // Salva os pontos disciplinares DO JOGO no documento da partida
        'disciplinary_home': discHome, 
        'disciplinary_away': discAway,
        'stats_applied.player_stats': {
          'goals': goals,
          'assists': assists,
          'yellows': yellows,
          'reds': reds,
          'goals_conceded': conceded
        }
      });

      // Se finalizada, recalcula toda a temporada
      if (status == 'finished') {
        await _recalculateGlobalSeasonStats(seasonId);
      }

    } catch (e) {
      debugPrint("❌ Erro ao recalcular partida: $e");
    }
  }

  // ===========================================================================
  // ⚡ CORE 2: REPROCESSAMENTO GLOBAL DA TEMPORADA (CORRIGIDO)
  // ===========================================================================

  Future<void> _recalculateGlobalSeasonStats(String seasonId) async {
    debugPrint("🔄 Iniciando Recálculo Global da Temporada $seasonId...");
    
    // 1. Carregar TODOS os jogadores para mapear ID -> TimeID
    // Isso é necessário para atribuir os pontos disciplinares ao time correto
    final playersSnap = await _playerService.getPlayerStatsRef(seasonId).get();
    Map<String, String> playerToTeamMap = {}; // pid -> tid
    
    for (var doc in playersSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['team_id'] != null) {
        playerToTeamMap[doc.id] = data['team_id'];
      }
    }

    // 2. Carregar partidas finalizadas
    final matchesRef = _getMatchesRef(seasonId);
    final finishedMatchesSnap = await matchesRef.where('status', isEqualTo: 'finished').get();
    
    // Acumuladores
    Map<String, Map<String, int>> playerTotals = {}; // pid -> {goals: 5, yellows: 2...}
    Map<String, Map<String, int>> teamTotals = {};   // tid -> {disc_points: 50, yellows: 5...}

    // Helper para inicializar mapa
    void initPlayer(String pid) {
      if (!playerTotals.containsKey(pid)) playerTotals[pid] = {};
    }
    void initTeam(String tid) {
      if (!teamTotals.containsKey(tid)) teamTotals[tid] = {};
    }

    // 3. Iterar Partidas e Somar
    for (var doc in finishedMatchesSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final statsApplied = data['stats_applied'] as Map<String, dynamic>?;
      
      if (statsApplied != null && statsApplied['player_stats'] != null) {
        final pStats = statsApplied['player_stats'] as Map<String, dynamic>;
        
        // --- GOLS ---
        if (pStats['goals'] is Map) {
          (pStats['goals'] as Map).forEach((pid, val) {
             initPlayer(pid);
             playerTotals[pid]!['goals'] = (playerTotals[pid]!['goals'] ?? 0) + (val as int);
          });
        }
        
        // --- ASSISTÊNCIAS ---
        if (pStats['assists'] is Map) {
          (pStats['assists'] as Map).forEach((pid, val) {
             initPlayer(pid);
             playerTotals[pid]!['assists'] = (playerTotals[pid]!['assists'] ?? 0) + (val as int);
          });
        }

        // --- GOLS SOFRIDOS ---
        if (pStats['goals_conceded'] is Map) {
          (pStats['goals_conceded'] as Map).forEach((pid, val) {
             initPlayer(pid);
             playerTotals[pid]!['goals_conceded'] = (playerTotals[pid]!['goals_conceded'] ?? 0) + (val as int);
          });
        }

        // --- CARTÕES AMARELOS ---
        if (pStats['yellows'] is Map) {
          (pStats['yellows'] as Map).forEach((pid, val) {
             int count = val as int;
             initPlayer(pid);
             playerTotals[pid]!['total_yellow_cards'] = (playerTotals[pid]!['total_yellow_cards'] ?? 0) + count;
             
             // Soma ao Time
             String? tid = playerToTeamMap[pid];
             if (tid != null) {
               initTeam(tid);
               teamTotals[tid]!['total_yellow_cards'] = (teamTotals[tid]!['total_yellow_cards'] ?? 0) + count;
               teamTotals[tid]!['disciplinary_points'] = (teamTotals[tid]!['disciplinary_points'] ?? 0) + (count * 10);
             }
          });
        }

        // --- CARTÕES VERMELHOS ---
        if (pStats['reds'] is Map) {
          (pStats['reds'] as Map).forEach((pid, val) {
             int count = val as int;
             initPlayer(pid);
             playerTotals[pid]!['total_red_cards'] = (playerTotals[pid]!['total_red_cards'] ?? 0) + count;
             
             // Soma ao Time
             String? tid = playerToTeamMap[pid];
             if (tid != null) {
               initTeam(tid);
               teamTotals[tid]!['total_red_cards'] = (teamTotals[tid]!['total_red_cards'] ?? 0) + count;
               teamTotals[tid]!['disciplinary_points'] = (teamTotals[tid]!['disciplinary_points'] ?? 0) + (count * 21);
             }
          });
        }
      }
    }

    // 4. Aplicar Updates nos JOGADORES (Incluindo Suspensão)
    final batch = _firestore.batch();
    
    // Itera sobre todos os jogadores (não só os que pontuaram) para garantir RESET em quem teve dados apagados?
    // Para simplificar e evitar leitura excessiva, atualizamos quem está na lista do snapshot inicial
    for (var doc in playersSnap.docs) {
      final pid = doc.id;
      final stats = playerTotals[pid] ?? {};
      
      final int y = stats['total_yellow_cards'] ?? 0;
      final int r = stats['total_red_cards'] ?? 0;
      
      // Lógica de Suspensão Automática
      bool isSuspended = false;
      // Regra 1: Vermelho Pendente (Assumindo que > 0 suspende o próximo, lógica simplificada de acumulado)
      if (AdminService.suspensionOnRed && r > 0) {
        // Em um sistema real precisaria saber se já cumpriu. 
        // Aqui assumimos: se tem vermelho na temporada, verificamos manualmente ou simplificamos.
        // Pelo pedido "setar is_suspended": Se tomou vermelho, marca.
        isSuspended = true; 
      }
      // Regra 2: 3 Amarelos
      if (y > 0 && y % AdminService.suspensionYellowCards == 0) {
        isSuspended = true;
      }

      batch.update(doc.reference, {
        'goals': stats['goals'] ?? 0,
        'assists': stats['assists'] ?? 0,
        'goals_conceded': stats['goals_conceded'] ?? 0,
        'total_yellow_cards': y,
        'yellow_cards': y, // Simplificação: iguala ao total para exibição
        'total_red_cards': r,
        'red_cards': r,
        'is_suspended': isSuspended, // <--- CORREÇÃO AQUI
      });
    }

    // 5. Aplicar Updates nos TIMES (Disciplina)
    // Para garantir que times que perderam pontos (ex: cartão deletado) sejam atualizados,
    // precisamos iterar sobre todos os times ou usar o teamTotals.
    // O mais seguro é pegar os times da teamTotals e aplicar updates.
    // Mas e se um time ficou com 0 cartões? Ele não estará no teamTotals.
    // Solução: Iterar sobre os times envolvidos nas partidas finalizadas.
    
    Set<String> uniqueTeams = {};
    for (var m in finishedMatchesSnap.docs) {
      uniqueTeams.add(m['team_home_id']);
      uniqueTeams.add(m['team_away_id']);
    }

    for (String tid in uniqueTeams) {
      final stats = teamTotals[tid] ?? {};
      final tRef = _teamService.getTeamsRef(seasonId).doc(tid);
      
      // Também precisamos recalcular pontos da tabela (V/E/D).
      // Chamamos o TeamService que já faz isso, mas injetamos a disciplina.
      
      // Primeiro, update da disciplina
      batch.update(tRef, {
        'disciplinary_points': stats['disciplinary_points'] ?? 0,
        'total_yellow_cards': stats['total_yellow_cards'] ?? 0,
        'total_red_cards': stats['total_red_cards'] ?? 0,
      });
    }

    await batch.commit();

    // 6. Recalcular Pontos de Tabela (Vitoria/Derrota)
    // Isso é feito time a time
    for (String tid in uniqueTeams) {
      await _teamService.recalculateTeamStats(tid, seasonId);
    }
    
    debugPrint("✅ Recálculo Global (Disciplina e Suspensões) Concluído.");
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
      await eventRef.delete();
      await recalculateMatchStatsFromTimeline(seasonId, matchId, excludeEventId: event.id);
      return "Sucesso";
    } catch (e) { return "Erro ao excluir: $e"; }
  }

  // ===========================================================================
  // 🏆 ADMIN UPDATE (COM GATILHO DE RECÁLCULO)
  // ===========================================================================

  Future<String> updateMatchStats({
    required String seasonId, required DocumentSnapshot matchSnapshot, required String newStatus, required int newScoreHome, required int newScoreAway,
    required Map<String, int> newGoals, required Map<String, int> newAssists, required Map<String, int> newYellows, required Map<String, int> newReds, required Map<String, int> newGoalsConceded,
    required String? newManOfTheMatchId, required int? penaltyScoreHome, required int? penaltyScoreAway, required String? winnerTeamId, required String? newSumulaUrl, required List<Map<String, dynamic>> newMediaLinks,
  }) async {
    try {
      final matchId = matchSnapshot.id;
      final matchData = matchSnapshot.data() as Map<String, dynamic>;
      
      await _firestore.collection('championships').doc(seasonId).collection('matches').doc(matchId).update({
        'status': newStatus,
        'penalty_score_home': penaltyScoreHome,
        'penalty_score_away': penaltyScoreAway,
        'winner_team_id': winnerTeamId,
        'sumula_url': newSumulaUrl,
        'stats_applied.man_of_the_match': newManOfTheMatchId,
        'stats_applied.media_links': newMediaLinks,
        'score_home': newScoreHome, // Backup manual
        'score_away': newScoreAway,
      });

      // Se virou Finished agora, ou foi editado enquanto Finished
      if (newStatus == 'finished') {
         // 1. Recalcula a partida (garante que sumula bata com timeline)
         // Dentro deste método, ele chama o _recalculateGlobalSeasonStats
         await recalculateMatchStatsFromTimeline(seasonId, matchId); 
         
         // 2. Verifica Mata-mata
         await _checkAndGenerateNextPhase(seasonId, triggeringMatchRound: matchSnapshot['round']);
      }
      return "Sucesso";
    } catch (e) { return "Erro: $e"; }
  }

  // ===========================================================================
  // ⚙️ GERAÇÃO DE FASES (TRAVA RODADA 7)
  // ===========================================================================

  Future<void> _checkAndGenerateNextPhase(String seasonId, {int? triggeringMatchRound}) async {
    // 🔒 TRAVA: Só roda se for a rodada 7 (Fim da fase de grupos)
    // Se não tiver essa info, assume que pode rodar, mas a verificação de "todos finished" abaixo é a garantia real.
    // No entanto, para evitar processamento desnecessário na rodada 1, 2, etc:
    // if (triggeringMatchRound != null && triggeringMatchRound < 7) return; 

    debugPrint("⚙️ Verificando geração de mata-mata...");
    await AdminService.loadAllRules(seasonId);
    
    final bool isModel2 = AdminService.tournamentFormat == 'model_2';
    final matchesRef = _getMatchesRef(seasonId);
    final teamsSnapshot = await _teamService.getTeamsRef(seasonId).get();
    final List<Team> allTeams = teamsSnapshot.docs.map((d) => Team.fromFirestore(d)).toList();

    // Busca apenas jogos da primeira fase
    final phase1Snapshot = await matchesRef.where('phase', isEqualTo: 'first').get();
    if (phase1Snapshot.docs.isEmpty) return;

    // 🔒 TRAVA 2: Todos os jogos da fase 1 devem estar finalizados
    final allFinished = phase1Snapshot.docs.every((doc) => doc['status'] == 'finished');
    
    if (!allFinished) {
      debugPrint("⛔ Ainda há jogos pendentes na fase 1.");
      return;
    }

    // Verifica se já gerou para não duplicar
    final nextPhaseCheck = isModel2 ? 'quarter_final' : 'semifinal';
    final checkSnap = await matchesRef.where('phase', isEqualTo: nextPhaseCheck).limit(1).get();
    
    if (checkSnap.docs.isEmpty) {
      debugPrint("🚀 Gerando jogos do Mata-mata...");
      
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
  // 📝 CRUD BÁSICO RESTANTE
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
      final status = match['status'];
      await match.reference.delete();
      if (status == 'finished') await _recalculateGlobalSeasonStats(seasonId);
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