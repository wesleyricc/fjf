import '../models/team_model.dart';
import '../models/match_model.dart';
import 'standings_sorter.dart';

class StandingsCalculator {
  
  static List<TeamStanding> calculate({
    required List<Team> teams,
    required List<MatchModel> matches,
    Map<String, Map<String, int>>? simulatedScores,
  }) {
    // 1. Inicializa: COPIA os dados do banco (Histórico consolidado)
    // Diferente da versão anterior, NÃO zeramos as variáveis, pois elas contêm
    // o histórico dos jogos finalizados.
    List<TeamStanding> standings = teams.map((t) {
      final s = TeamStanding(t);
      
      // Dados base (vindos do banco de dados/Team)
      s.points = t.points; 
      s.matchPoints = t.matchPoints; // Assume que o banco já tem os pontos de jogo
      s.gamesPlayed = t.gamesPlayed;
      s.wins = t.wins;
      s.draws = t.draws;
      s.losses = t.losses;
      s.goalsFor = t.goalsFor;
      s.goalsAgainst = t.goalsAgainst;
      s.goalDifference = t.goalDifference;
      s.disciplinaryPoints = t.disciplinaryPoints; // Importante para o critério de desempate
      
      return s;
    }).toList();

    final Map<String, TeamStanding> teamMap = {
      for (var t in standings) t.id: t
    };

    // Lista para o Sorter calcular Confronto Direto
    List<MatchModel> matchesForTiebreaker = [];

    // 2. Processa Partidas
    for (var match in matches) {
      final homeTeam = teamMap[match.homeTeamId];
      final awayTeam = teamMap[match.awayTeamId];

      if (homeTeam == null || awayTeam == null) continue;

      int? scoreHome;
      int? scoreAway;
      
      bool isSimulated = false;
      bool isLive = false;

      // A. Verifica Simulação
      if (simulatedScores != null && simulatedScores.containsKey(match.id)) {
        final simul = simulatedScores[match.id]!;
        if (simul['home'] != -1 && simul['away'] != -1) {
          scoreHome = simul['home'];
          scoreAway = simul['away'];
          isSimulated = true;
        }
      }

      // B. Verifica Dados Reais (Se não for simulado)
      if (!isSimulated) {
        if (match.isFinished) {
          // Se finalizado, apenas adicionamos à lista de desempate.
          // NÃO somamos stats, pois já estão no objeto Team vindo do banco.
          matchesForTiebreaker.add(match);
          continue; 
        } 
        else if (match.isInProgress && match.scoreHome != null && match.scoreAway != null) {
          // Se em andamento, é LIVE. Precisamos somar.
          scoreHome = match.scoreHome;
          scoreAway = match.scoreAway;
          isLive = true;
        }
      }

      // C. Aplica Estatísticas (Apenas para Simulação ou Live)
      if ((isSimulated || isLive) && scoreHome != null && scoreAway != null) {
        
        // Adiciona à lista de desempate considerando o placar atual/simulado
        // Isso permite que o confronto direto funcione "em tempo real"
        matchesForTiebreaker.add(MatchModel(
          id: match.id,
          location: match.location,
          round: match.round,
          phase: match.phase,
          status: 'finished', // Finge que terminou para o Sorter
          datetime: match.datetime,
          homeTeamId: match.homeTeamId,
          homeTeamName: match.homeTeamName,
          homeTeamShield: match.homeTeamShield,
          scoreHome: scoreHome,
          awayTeamId: match.awayTeamId,
          awayTeamName: match.awayTeamName,
          awayTeamShield: match.awayTeamShield,
          scoreAway: scoreAway,
        ));

        // Atualiza Stats do Time da Casa
        homeTeam.gamesPlayed++;
        homeTeam.goalsFor += scoreHome;
        homeTeam.goalsAgainst += scoreAway;
        homeTeam.goalDifference = homeTeam.goalsFor - homeTeam.goalsAgainst; // Recalcula saldo
        
        // Atualiza Stats do Time Visitante
        awayTeam.gamesPlayed++;
        awayTeam.goalsFor += scoreAway;
        awayTeam.goalsAgainst += scoreHome;
        awayTeam.goalDifference = awayTeam.goalsFor - awayTeam.goalsAgainst; // Recalcula saldo

        // Pontos de Tabela
        if (scoreHome > scoreAway) {
          homeTeam.matchPoints += 3;
          homeTeam.wins++;
          awayTeam.losses++;
        } else if (scoreHome < scoreAway) {
          awayTeam.matchPoints += 3;
          awayTeam.wins++;
          homeTeam.losses++;
        } else {
          homeTeam.matchPoints += 1;
          homeTeam.draws++;
          awayTeam.matchPoints += 1;
          awayTeam.draws++;
        }

        // --- PONTOS DISCIPLINARES (Apenas no Live) ---
        // Na simulação, geralmente não simulamos cartões, então ignoramos.
        // Se for Live, somamos o que está acontecendo agora ao histórico do time.
        if (isLive) {
          homeTeam.disciplinaryPoints += match.disciplinaryHome;
          awayTeam.disciplinaryPoints += match.disciplinaryAway;
        }
      }
    }

    // 3. Atualiza Totais Finais
    for (var t in standings) {
      // Garante que pontos totais sejam a soma correta (match + extra)
      // Nota: matchPoints agora contém (Histórico + Live/Simulado)
      t.points = t.matchPoints + t.extraPoints;
    }

    // 4. Ordena
    final sorter = StandingsSorter(finishedMatches: matchesForTiebreaker);
    return sorter.sort(standings);
  }
}