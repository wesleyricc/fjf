// lib/utils/standings_sorter.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // Para debugPrint
import '../services/admin_service.dart'; // Para acessar a ordem dos critérios

// --- Classe TeamStanding (movida para cá) ---
class TeamStanding {
  final DocumentSnapshot teamDoc;
  int points;
  int gamesPlayed;
  int wins;
  int draws;
  int losses;
  int goalDifference;
  int goalsFor;
  int goalsAgainst;
  int disciplinaryPoints;

  TeamStanding(this.teamDoc)
      : points = (teamDoc.data() as Map<String, dynamic>?)?['points'] ?? 0,
        gamesPlayed = (teamDoc.data() as Map<String, dynamic>?)?['games_played'] ?? 0,
        wins = (teamDoc.data() as Map<String, dynamic>?)?['wins'] ?? 0,
        draws = (teamDoc.data() as Map<String, dynamic>?)?['draws'] ?? 0,
        losses = (teamDoc.data() as Map<String, dynamic>?)?['losses'] ?? 0,
        goalDifference = (teamDoc.data() as Map<String, dynamic>?)?['goal_difference'] ?? 0,
        goalsFor = (teamDoc.data() as Map<String, dynamic>?)?['goals_for'] ?? 0,
        goalsAgainst = (teamDoc.data() as Map<String, dynamic>?)?['goals_against'] ?? 0,
        disciplinaryPoints = (teamDoc.data() as Map<String, dynamic>?)?['disciplinary_points'] ?? 0;

  String get id => teamDoc.id;
  Map<String, dynamic> get data => teamDoc.data() as Map<String, dynamic>;
}
// --- FIM TeamStanding ---


// --- Classe/Funções de Ordenação ---
class StandingsSorter {
  // Lista de jogos finalizados, necessária para H2H
  final List<DocumentSnapshot> finishedMatches;

  StandingsSorter({required this.finishedMatches});

  // Função principal que ordena a lista
  List<TeamStanding> sort(List<TeamStanding> standings) {
    // Cria uma cópia para não modificar a original (importante!)
    List<TeamStanding> sortedList = List.from(standings);
    sortedList.sort(_customSort);
    return sortedList;
  }

  // Lógica de ordenação (adaptada da StandingsScreen)
  int _customSort(TeamStanding a, TeamStanding b) {
    int comparison = b.points.compareTo(a.points);
    if (comparison != 0) return comparison;

    for (String criterionKey in AdminService.tiebreakerOrder) { // Usa a ordem do AdminService
       comparison = _compareByCriterion(criterionKey, a, b);
       if (comparison != 0) return comparison;
    }

     if (!AdminService.tiebreakerOrder.contains('draw_sort')) {
        return a.data['name'].compareTo(b.data['name']);
     }
     return 0;
  }

  // Lógica de comparação por critério (adaptada da StandingsScreen)
  int _compareByCriterion(String key, TeamStanding a, TeamStanding b) {
    switch (key) {
      case 'head_to_head':
        return _getHeadToHeadResult(a, b);
      case 'disciplinary_points':
        return a.disciplinaryPoints.compareTo(b.disciplinaryPoints); // Asc
      case 'wins':
        return b.wins.compareTo(a.wins); // Desc
      case 'goal_difference':
        return b.goalDifference.compareTo(a.goalDifference); // Desc
      case 'goals_against':
        return a.goalsAgainst.compareTo(b.goalsAgainst); // Asc
      case 'draw_sort':
        return a.data['name'].compareTo(b.data['name']); // Asc
      default:
        debugPrint("Critério de desempate desconhecido no Sorter: $key");
        return 0;
    }
  }

  // Lógica H2H (adaptada da StandingsScreen)
  int _getHeadToHeadResult(TeamStanding a, TeamStanding b) {
    int pointsA = 0;
    int pointsB = 0;
    List<DocumentSnapshot> h2hMatches = finishedMatches.where((match) { // Usa finishedMatches da classe
      final homeId = (match.data() as Map<String, dynamic>?)?['team_home_id'];
      final awayId = (match.data() as Map<String, dynamic>?)?['team_away_id'];
      return (homeId == a.id && awayId == b.id) || (homeId == b.id && awayId == a.id);
    }).toList();

    if (h2hMatches.isEmpty) return 0;

    for (var match in h2hMatches) {
      final data = match.data() as Map<String, dynamic>;
      final scoreHome = (data['score_home'] ?? 0) as int;
      final scoreAway = (data['score_away'] ?? 0) as int;
      final homeId = data['team_home_id']; // Re-obtém homeId

      if (scoreHome == scoreAway) {
        pointsA += 1; pointsB += 1;
      } else if (homeId == a.id) { // Time A é casa
        if (scoreHome > scoreAway) pointsA += 3; else pointsB += 3;
      } else { // Time B é casa
        // Correção aqui: era if(scoreAway > scoreHome) pointsA += 3; -> Deve ser B
         if (scoreAway < scoreHome) pointsB += 3; else pointsA += 3; // Se Casa(B) perdeu, B ganha 3
      }
    }
    // Compara pontos H2H (Descendente: mais pontos H2H fica na frente)
    return pointsB.compareTo(pointsA);
  }
}
// --- FIM Classe/Funções de Ordenação ---