import 'package:flutter/foundation.dart';
import '../services/admin_service.dart';
import '../models/team_model.dart';
import '../models/match_model.dart';

// --- Wrapper para cálculo ---
class TeamStanding {
  final Team team; // Model
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
  
  TeamStanding(this.team)
      : points = team.points,
        matchPoints = team.matchPoints,
        gamesPlayed = team.gamesPlayed,
        wins = team.wins,
        draws = team.draws,
        losses = team.losses,
        goalDifference = team.goalDifference,
        goalsFor = team.goalsFor,
        goalsAgainst = team.goalsAgainst,
        disciplinaryPoints = team.disciplinaryPoints,
        extraPoints = team.extraPoints;

  String get id => team.id;
  String get name => team.name;
}

class StandingsSorter {
  final List<MatchModel> finishedMatches; // Usa MatchModel

  StandingsSorter({required this.finishedMatches});

  List<TeamStanding> sort(List<TeamStanding> standings) {
    Map<int, int> pointsFrequency = {};
    for (var team in standings) {
      pointsFrequency[team.points] = (pointsFrequency[team.points] ?? 0) + 1;
    }

    List<TeamStanding> sortedList = List.from(standings);
    sortedList.sort((a, b) => _customSort(a, b, pointsFrequency));
    return sortedList;
  }

  int _customSort(TeamStanding a, TeamStanding b, Map<int, int> pointsFrequency) {
    int comparison = b.points.compareTo(a.points);
    if (comparison != 0) return comparison;

    int tiedCount = pointsFrequency[a.points] ?? 0;

    for (String criterionKey in AdminService.tiebreakerOrder) {
       comparison = _compareByCriterion(criterionKey, a, b, tiedCount);
       if (comparison != 0) return comparison;
    }

     if (!AdminService.tiebreakerOrder.contains('draw_sort')) {
        return a.name.compareTo(b.name);
     }
     return 0;
  }

  int _compareByCriterion(String key, TeamStanding a, TeamStanding b, int tiedCount) {
    switch (key) {
      case 'head_to_head':
        if (tiedCount > 2) return 0; 
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
        return a.name.compareTo(b.name);
      default:
        return 0;
    }
  }

  int _getHeadToHeadResult(TeamStanding a, TeamStanding b) {
    int pointsA = 0;
    int pointsB = 0;
    
    // Filtra partidas locais
    List<MatchModel> h2hMatches = finishedMatches.where((match) {
      return (match.homeTeamId == a.id && match.awayTeamId == b.id) || (match.homeTeamId == b.id && match.awayTeamId == a.id);
    }).toList();

    if (h2hMatches.isEmpty) return 0;

    for (var match in h2hMatches) {
      final scoreHome = match.scoreHome ?? 0;
      final scoreAway = match.scoreAway ?? 0;

      if (scoreHome == scoreAway) {
        pointsA += 1; pointsB += 1;
      } else if (match.homeTeamId == a.id) {
        if (scoreHome > scoreAway) pointsA += 3; else pointsB += 3;
      } else {
         if (scoreAway < scoreHome) pointsB += 3; else pointsA += 3;
      }
    }
    return pointsB.compareTo(pointsA);
  }
}