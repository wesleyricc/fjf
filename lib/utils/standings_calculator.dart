import 'package:cloud_firestore/cloud_firestore.dart';
import 'standings_sorter.dart'; // Reutiliza sua classe de ordenação existente

class StandingsCalculator {
  
  /// Calcula e ordena a tabela baseada nos times e partidas fornecidos.
  /// [simulatedScores] é um mapa opcional: { matchId: {'home': 2, 'away': 1} }
  static List<TeamStanding> calculate({
    required List<DocumentSnapshot> teamsDocs,
    required List<DocumentSnapshot> matchesDocs,
    Map<String, Map<String, int>>? simulatedScores,
  }) {
    // 1. Inicializa os objetos de classificação zerados (mas mantendo pontos extras do banco)
    List<TeamStanding> standings = teamsDocs.map((doc) {
      final t = TeamStanding(doc);
      // Zera stats calculáveis, mantém o que é fixo/manual
      t.points = t.extraPoints; 
      t.matchPoints = 0;
      t.gamesPlayed = 0;
      t.wins = 0;
      t.draws = 0;
      t.losses = 0;
      t.goalsFor = 0;
      t.goalsAgainst = 0;
      t.goalDifference = 0;
      return t;
    }).toList();

    // Cria um mapa para acesso rápido: TeamId -> TeamStanding
    final Map<String, TeamStanding> teamMap = {
      for (var t in standings) t.id: t
    };

    // Lista para guardar os dados dos jogos finalizados (para o Sorter usar no confronto direto)
    List<Map<String, dynamic>> finishedMatchesData = [];

    // 2. Processa as partidas
    for (var match in matchesDocs) {
      final data = match.data() as Map<String, dynamic>;
      final String matchId = match.id;
      final String homeId = data['team_home_id'];
      final String awayId = data['team_away_id'];

      int? scoreHome;
      int? scoreAway;
      String status = data['status'] ?? 'pending';

      // A. Verifica se tem simulação para este jogo
      if (simulatedScores != null && simulatedScores.containsKey(matchId)) {
        final simul = simulatedScores[matchId]!;
        if (simul['home'] != -1 && simul['away'] != -1) {
          scoreHome = simul['home'];
          scoreAway = simul['away'];
          status = 'finished'; // Trata como finalizado para o cálculo
        }
      }

      // B. Se não for simulado, usa o dado real se estiver finalizado ou em andamento (live)
      if (scoreHome == null) {
        if (status == 'finished' || (status == 'in_progress' && data['score_home'] != null)) {
          scoreHome = (data['score_home'] ?? 0) as int;
          scoreAway = (data['score_away'] ?? 0) as int;
        }
      }

      // C. Aplica Estatísticas se tivermos um placar válido
      if (scoreHome != null && scoreAway != null) {
        final homeTeam = teamMap[homeId];
        final awayTeam = teamMap[awayId];

        // Guarda dados para o Sorter (Critério de Desempate)
        finishedMatchesData.add({
          'team_home_id': homeId,
          'team_away_id': awayId,
          'score_home': scoreHome,
          'score_away': scoreAway,
        });

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

    // 3. Atualiza totais derivados
    for (var t in standings) {
      t.points = t.matchPoints + t.extraPoints; // Soma pontos de jogo + pontos extras
      t.goalDifference = t.goalsFor - t.goalsAgainst;
    }

    // 4. Ordena usando o Sorter existente
    final sorter = StandingsSorter(finishedMatches: finishedMatchesData);
    return sorter.sort(standings);
  }
}