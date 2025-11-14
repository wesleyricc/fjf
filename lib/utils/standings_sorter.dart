// lib/utils/standings_sorter.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // Para debugPrint
import '../services/admin_service.dart'; // Para acessar a ordem dos critérios

// --- Classe TeamStanding (Sem alterações) ---
class TeamStanding {
  final DocumentSnapshot teamDoc;
  int points;
  int matchPoints;
  int gamesPlayed;
  int wins;
  int draws;
  int losses;
  int goalDifference;
  int goalsFor;
  int goalsAgainst;
  int disciplinaryPoints;
  int extraPoints;
  
  TeamStanding(this.teamDoc)
      : points = (teamDoc.data() as Map<String, dynamic>?)?['points'] ?? 0,
        matchPoints = (teamDoc.data() as Map<String, dynamic>?)?['match_points'] ?? 0,
        gamesPlayed = (teamDoc.data() as Map<String, dynamic>?)?['games_played'] ?? 0,
        wins = (teamDoc.data() as Map<String, dynamic>?)?['wins'] ?? 0,
        draws = (teamDoc.data() as Map<String, dynamic>?)?['draws'] ?? 0,
        losses = (teamDoc.data() as Map<String, dynamic>?)?['losses'] ?? 0,
        goalDifference = (teamDoc.data() as Map<String, dynamic>?)?['goal_difference'] ?? 0,
        goalsFor = (teamDoc.data() as Map<String, dynamic>?)?['goals_for'] ?? 0,
        goalsAgainst = (teamDoc.data() as Map<String, dynamic>?)?['goals_against'] ?? 0,
        disciplinaryPoints = (teamDoc.data() as Map<String, dynamic>?)?['disciplinary_points'] ?? 0,
        extraPoints = (teamDoc.data() as Map<String, dynamic>?)?['extra_points'] ?? 0;

  String get id => teamDoc.id;
  Map<String, dynamic> get data => teamDoc.data() as Map<String, dynamic>;
}
// --- FIM TeamStanding ---


// --- Classe/Funções de Ordenação (MODIFICADA) ---
class StandingsSorter {
  // --- ALTERAÇÃO: Aceita List<Map> em vez de List<DocumentSnapshot> ---
  final List<Map<String, dynamic>> finishedMatches;

  StandingsSorter({required this.finishedMatches});
  // --- FIM DA ALTERAÇÃO ---

  List<TeamStanding> sort(List<TeamStanding> standings) {
    List<TeamStanding> sortedList = List.from(standings);
    sortedList.sort(_customSort);
    return sortedList;
  }

  int _customSort(TeamStanding a, TeamStanding b) {
    int comparison = b.points.compareTo(a.points);
    if (comparison != 0) return comparison;

    for (String criterionKey in AdminService.tiebreakerOrder) {
       comparison = _compareByCriterion(criterionKey, a, b);
       if (comparison != 0) return comparison;
    }

     if (!AdminService.tiebreakerOrder.contains('draw_sort')) {
        return a.data['name'].compareTo(b.data['name']);
     }
     return 0;
  }

  int _compareByCriterion(String key, TeamStanding a, TeamStanding b) {
    switch (key) {
      case 'head_to_head':
        return _getHeadToHeadResult(a, b);
      case 'disciplinary_points':
        return a.disciplinaryPoints.compareTo(b.disciplinaryPoints);
      case 'wins':
        return b.wins.compareTo(a.wins);
      case 'goal_difference':
        return b.goalDifference.compareTo(a.goalDifference);
      case 'goals_against':
        return a.goalsAgainst.compareTo(b.goalsAgainst);
      case 'draw_sort':
        return a.data['name'].compareTo(b.data['name']);
      default:
        debugPrint("Critério de desempate desconhecido no Sorter: $key");
        return 0;
    }
  }

  int _getHeadToHeadResult(TeamStanding a, TeamStanding b) {
    int pointsA = 0;
    int pointsB = 0;
    
    // --- ALTERAÇÃO: Itera sobre List<Map> ---
    List<Map<String, dynamic>> h2hMatches = finishedMatches.where((match) {
      final homeId = match['team_home_id'];
      final awayId = match['team_away_id'];
      return (homeId == a.id && awayId == b.id) || (homeId == b.id && awayId == a.id);
    }).toList();
    // --- FIM DA ALTERAÇÃO ---

    if (h2hMatches.isEmpty) return 0;

    for (var match in h2hMatches) {
      // --- ALTERAÇÃO: Acesso direto ao Map ---
      final data = match;
      final scoreHome = (data['score_home'] ?? 0) as int;
      final scoreAway = (data['score_away'] ?? 0) as int;
      final homeId = data['team_home_id'];
      // --- FIM DA ALTERAÇÃO ---

      if (scoreHome == scoreAway) {
        pointsA += 1; pointsB += 1;
      } else if (homeId == a.id) {
        if (scoreHome > scoreAway) pointsA += 3; else pointsB += 3;
      } else {
         if (scoreAway < scoreHome) pointsB += 3; else pointsA += 3;
      }
    }
    return pointsB.compareTo(pointsA);
  }
}