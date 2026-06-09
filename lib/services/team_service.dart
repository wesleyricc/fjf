import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/team_model.dart';

class TeamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference getTeamsRef(String seasonId) {
    return _firestore.collection('championships').doc(seasonId).collection('teams_participation');
  }

  // --- LEITURA ---

  Stream<List<Team>> streamTeams(String seasonId) {
    return getTeamsRef(seasonId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Team.fromFirestore(doc)).toList());
  }

  Future<Team?> getTeam(String teamId, String seasonId) async {
    final doc = await getTeamsRef(seasonId).doc(teamId).get();
    if (!doc.exists) return null;
    return Team.fromFirestore(doc);
  }

  Future<DocumentSnapshot?> getTeamSnapshot(String teamId, String seasonId) async {
    try {
      final doc = await getTeamsRef(seasonId).doc(teamId).get();
      return doc.exists ? doc : null;
    } catch (e) {
      return null;
    }
  }

  // --- ESCRITA ---

  Future<String> createTeam({
    required String seasonId,
    required String name,
    required String shortName,
    required String shieldUrl,
    required List<Map<String, dynamic>> championshipHistory,
  }) async {
    try {
      await getTeamsRef(seasonId).add({
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
        'default_starters': []
      });
      return "Sucesso: Equipe '$name' criada.";
    } catch (e) {
      return "Erro: $e";
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
        'championship_history': championshipHistory
      });
      return "Sucesso: Equipe '$name' atualizada.";
    } catch (e) {
      return "Erro: $e";
    }
  }

  Future<String> deleteTeam(DocumentSnapshot teamDoc, String seasonId) async {
    // Nota: Exclusão em cascata (jogadores/jogos) idealmente seria feita aqui ou via Cloud Functions.
    // Mantendo simples como no original, mas cuidado com referências.
    final batch = _firestore.batch();
    try {
      batch.delete(teamDoc.reference);
      await batch.commit();
      return "Sucesso: Time excluído (Verifique vínculos manualmente).";
    } catch (e) {
      return "Erro: $e";
    }
  }

  // --- CÁLCULO ---

  // --- CÁLCULO ---

  Future<void> recalculateTeamStats(String teamId, String seasonId) async {
    int p1MatchPoints = 0;
    int p1Games = 0;
    int p1Wins = 0;
    int p1Draws = 0;
    int p1Losses = 0;
    int p1GoalsFor = 0;
    int p1GoalsAgainst = 0;

    int ovMatchPoints = 0;
    int ovGames = 0;
    int ovWins = 0;
    int ovDraws = 0;
    int ovLosses = 0;
    int ovGoalsFor = 0;
    int ovGoalsAgainst = 0;

    final matchesRef = _firestore.collection('championships').doc(seasonId).collection('matches');

    Future<void> processMatches(String side) async {
      final query = await matchesRef
          .where('team_${side}_id', isEqualTo: teamId)
          .where('status', whereIn: ['finished', 'in_progress']).get();

      for (final doc in query.docs) {
        final data = doc.data();
        final scoreHome = (data['score_home'] ?? 0) as int;
        final scoreAway = (data['score_away'] ?? 0) as int;
        final phase = data['phase'] as String? ?? 'first';

        int myScore = (side == 'home') ? scoreHome : scoreAway;
        int opponentScore = (side == 'home') ? scoreAway : scoreHome;

        int points = 0;
        bool isWin = false;
        bool isDraw = false;
        bool isLoss = false;

        if (myScore > opponentScore) {
          points = 3;
          isWin = true;
        } else if (myScore < opponentScore) {
          isLoss = true;
        } else {
          points = 1;
          isDraw = true;
        }

        ovGames++;
        ovGoalsFor += myScore;
        ovGoalsAgainst += opponentScore;
        ovMatchPoints += points;
        if (isWin) ovWins++;
        if (isDraw) ovDraws++;
        if (isLoss) ovLosses++;

        if (phase == 'first') {
          p1Games++;
          p1GoalsFor += myScore;
          p1GoalsAgainst += opponentScore;
          p1MatchPoints += points;
          if (isWin) p1Wins++;
          if (isDraw) p1Draws++;
          if (isLoss) p1Losses++;
        }
      }
    }

    await processMatches('home');
    await processMatches('away');

    try {
      final teamRef = getTeamsRef(seasonId).doc(teamId);
      final teamSnap = await teamRef.get();
      if (!teamSnap.exists) return;
      
      final currentData = teamSnap.data() as Map<String, dynamic>;
      final currentExtraPoints = currentData['extra_points'] as int? ?? 0;

      // 🚨 OTIMIZAÇÃO FINOPS: Dirty Check para o Time
      // Só gasta Write no Firestore se alguma estatística realmente alterou
      if (currentData['match_points'] == p1MatchPoints &&
          currentData['games_played'] == p1Games &&
          currentData['wins'] == p1Wins &&
          currentData['draws'] == p1Draws &&
          currentData['losses'] == p1Losses &&
          currentData['goals_for'] == p1GoalsFor &&
          currentData['goals_against'] == p1GoalsAgainst &&
          currentData['overall_match_points'] == ovMatchPoints &&
          currentData['overall_games_played'] == ovGames) {
        return; // Aborta gravação e poupa fatura!
      }

      await teamRef.update({
        'match_points': p1MatchPoints,
        'points': p1MatchPoints + currentExtraPoints,
        'games_played': p1Games,
        'wins': p1Wins,
        'draws': p1Draws,
        'losses': p1Losses,
        'goals_for': p1GoalsFor,
        'goals_against': p1GoalsAgainst,
        'goal_difference': p1GoalsFor - p1GoalsAgainst,
        
        'overall_match_points': ovMatchPoints,
        'overall_points': ovMatchPoints + currentExtraPoints,
        'overall_games_played': ovGames,
        'overall_wins': ovWins,
        'overall_draws': ovDraws,
        'overall_losses': ovLosses,
        'overall_goals_for': ovGoalsFor,
        'overall_goals_against': ovGoalsAgainst,
        'overall_goal_difference': ovGoalsFor - ovGoalsAgainst,
      });
    } catch (_) {}
  }
}