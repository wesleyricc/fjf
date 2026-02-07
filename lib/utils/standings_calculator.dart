import '../models/team_model.dart';
import '../models/match_model.dart';
import 'standings_sorter.dart';

class StandingsCalculator {
  
  static List<TeamStanding> calculate({
    required List<Team> teams,
    required List<MatchModel> matches,
    Map<String, Map<String, int>>? simulatedScores,
  }) {
    // 1. Inicializa
    List<TeamStanding> standings = teams.map((t) {
      final s = TeamStanding(t);
      // Zera variáveis dinâmicas
      s.points = s.extraPoints; 
      s.matchPoints = 0;
      s.gamesPlayed = 0;
      s.wins = 0;
      s.draws = 0;
      s.losses = 0;
      s.goalsFor = 0;
      s.goalsAgainst = 0;
      s.goalDifference = 0;
      return s;
    }).toList();

    final Map<String, TeamStanding> teamMap = {
      for (var t in standings) t.id: t
    };

    List<MatchModel> finishedMatches = [];

    // 2. Processa Partidas
    for (var match in matches) {
      // Ignora jogos de outras fases se necessário, mas aqui assumimos que a lista já vem filtrada
      
      int? scoreHome;
      int? scoreAway;
      bool isFinished = false;

      // A. Simulação
      if (simulatedScores != null && simulatedScores.containsKey(match.id)) {
        final simul = simulatedScores[match.id]!;
        if (simul['home'] != -1 && simul['away'] != -1) {
          scoreHome = simul['home'];
          scoreAway = simul['away'];
          isFinished = true;
        }
      }

      // B. Dados Reais
      if (scoreHome == null) {
        if (match.isFinished || (match.isInProgress && match.scoreHome != null)) {
          scoreHome = match.scoreHome;
          scoreAway = match.scoreAway;
          isFinished = true;
        }
      }

      if (isFinished && scoreHome != null && scoreAway != null) {
        final homeTeam = teamMap[match.homeTeamId];
        final awayTeam = teamMap[match.awayTeamId];

        // Cria objeto temporário com placar definido para o Sorter
        finishedMatches.add(MatchModel(
          id: match.id,
          location: match.location,
          round: match.round,
          phase: match.phase,
          status: 'finished',
          homeTeamId: match.homeTeamId,
          homeTeamName: match.homeTeamName,
          homeTeamShield: match.homeTeamShield,
          scoreHome: scoreHome,
          awayTeamId: match.awayTeamId,
          awayTeamName: match.awayTeamName,
          awayTeamShield: match.awayTeamShield,
          scoreAway: scoreAway,
        ));

        if (homeTeam != null) {
          homeTeam.gamesPlayed++;
          homeTeam.goalsFor += scoreHome;
          homeTeam.goalsAgainst += scoreAway;
          
          if (scoreHome > scoreAway) {
            homeTeam.matchPoints += 3;
            homeTeam.wins++;
          } else if (scoreHome < scoreAway) {
            homeTeam.losses++;
          } else {
            homeTeam.matchPoints += 1;
            homeTeam.draws++;
          }
        }

        if (awayTeam != null) {
          awayTeam.gamesPlayed++;
          awayTeam.goalsFor += scoreAway;
          awayTeam.goalsAgainst += scoreHome;

          if (scoreAway > scoreHome) {
            awayTeam.matchPoints += 3;
            awayTeam.wins++;
          } else if (scoreAway < scoreHome) {
            awayTeam.losses++;
          } else {
            awayTeam.matchPoints += 1;
            awayTeam.draws++;
          }
        }
      }
    }

    // 3. Totais
    for (var t in standings) {
      t.points = t.matchPoints + t.extraPoints;
      t.goalDifference = t.goalsFor - t.goalsAgainst;
    }

    // 4. Ordena
    final sorter = StandingsSorter(finishedMatches: finishedMatches);
    return sorter.sort(standings);
  }
}