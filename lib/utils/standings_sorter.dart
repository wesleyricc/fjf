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

// --- Classe/Funções de Ordenação (MODIFICADA) ---
class StandingsSorter {
  final List<Map<String, dynamic>> finishedMatches;

  StandingsSorter({required this.finishedMatches});

  List<TeamStanding> sort(List<TeamStanding> standings) {
    // 1. Pré-calcular contagem de times por pontuação (Frequência)
    // Isso nos diz quantos times estão empatados com a mesma pontuação.
    Map<int, int> pointsFrequency = {};
    for (var team in standings) {
      pointsFrequency[team.points] = (pointsFrequency[team.points] ?? 0) + 1;
    }

    List<TeamStanding> sortedList = List.from(standings);
    
    // 2. Ordenar usando o mapa de frequência via Closure
    sortedList.sort((a, b) => _customSort(a, b, pointsFrequency));
    
    return sortedList;
  }

  int _customSort(TeamStanding a, TeamStanding b, Map<int, int> pointsFrequency) {
    // 1. Pontos (Decrescente) - Critério Mestre
    int comparison = b.points.compareTo(a.points);
    if (comparison != 0) return comparison;

    // Se chegou aqui, a.points == b.points.
    // Descobrimos quantos times no total têm essa mesma pontuação.
    int tiedCount = pointsFrequency[a.points] ?? 0;

    for (String criterionKey in AdminService.tiebreakerOrder) {
       // Passamos o 'tiedCount' para decidir se aplicamos a regra
       comparison = _compareByCriterion(criterionKey, a, b, tiedCount);
       if (comparison != 0) return comparison;
    }

     if (!AdminService.tiebreakerOrder.contains('draw_sort')) {
        return a.data['name'].compareTo(b.data['name']);
     }
     return 0;
  }

  int _compareByCriterion(String key, TeamStanding a, TeamStanding b, int tiedCount) {
    switch (key) {
      case 'head_to_head':
        // --- NOVA REGRA ---
        // Se houver mais de 2 times empatados (tiedCount > 2),
        // o Confronto Direto é anulado/ignorado.
        if (tiedCount > 2) {
          return 0; // Considera empatado neste critério, pula para o próximo
        }
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
    
    List<Map<String, dynamic>> h2hMatches = finishedMatches.where((match) {
      final homeId = match['team_home_id'];
      final awayId = match['team_away_id'];
      return (homeId == a.id && awayId == b.id) || (homeId == b.id && awayId == a.id);
    }).toList();

    if (h2hMatches.isEmpty) return 0;

    for (var match in h2hMatches) {
      final scoreHome = (match['score_home'] ?? 0) as int;
      final scoreAway = (match['score_away'] ?? 0) as int;
      final homeId = match['team_home_id'];

      if (scoreHome == scoreAway) {
        pointsA += 1; pointsB += 1;
      } else if (homeId == a.id) {
        if (scoreHome > scoreAway) pointsA += 3; else pointsB += 3;
      } else {
         if (scoreAway < scoreHome) pointsB += 3; else pointsA += 3;
      }
    }
    // Quem tem mais pontos no confronto direto fica na frente
    return pointsB.compareTo(pointsA);
  }
}