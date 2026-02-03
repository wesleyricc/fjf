import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Modelo para transportar os detalhes da pontuação
class FantasyScoutDetail {
  final double totalScore;
  final int goals;
  final int assists;
  final int yellows;
  final int reds;
  final int goalsConceded;
  
  FantasyScoutDetail({
    required this.totalScore,
    this.goals = 0,
    this.assists = 0,
    this.yellows = 0,
    this.reds = 0,
    this.goalsConceded = 0,
  });

  bool get hasStats => (goals + assists + yellows + reds + goalsConceded) > 0;
}

class FantasyScoutService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- TABELA DE PONTOS ---
  static const double PTS_GOAL = 5.0;
  static const double PTS_ASSIST = 3.0;
  static const double PTS_YELLOW_CARD = -1.0;
  static const double PTS_RED_CARD = -3.0;
  static const double PTS_GOAL_CONCEDED = -1.0; 

  Stream<Map<String, FantasyScoutDetail>> streamLiveScores(String seasonId, List<String> playerIds) {
    // Debug: Verificar o ID que está chegando
    debugPrint("FantasyScout: Escutando jogos ao vivo na temporada: $seasonId");

    if (playerIds.isEmpty || seasonId.isEmpty) return Stream.value({});

    return _firestore
        .collection('championships')
        .doc(seasonId)
        .collection('matches')
        .where('status', isEqualTo: 'in_progress') 
        .snapshots()
        .map((snapshot) {
      
      debugPrint("FantasyScout: Encontrados ${snapshot.docs.length} jogos em andamento.");

      final Map<String, FantasyScoutDetail> detailsMap = {};

      // 1. Inicializa zerado
      for (var id in playerIds) {
        detailsMap[id] = FantasyScoutDetail(totalScore: 0.0);
      }

      // 2. Itera sobre os jogos
      for (var matchDoc in snapshot.docs) {
        final data = matchDoc.data();
        
        final statsApplied = data['stats_applied'] as Map<String, dynamic>? ?? {};
        final playerStats = statsApplied['player_stats'] as Map<String, dynamic>? ?? {};

        // Helper seguro para converter Map<dynamic, dynamic> em Map<String, int>
        Map<String, int> getStatMap(String key) {
          return _safeCastMap(playerStats[key]);
        }

        final goalsMap = getStatMap('goals');
        final assistsMap = getStatMap('assists');
        final yellowsMap = getStatMap('yellows');
        final redsMap = getStatMap('reds');
        final concededMap = getStatMap('goals_conceded');

        for (var playerId in playerIds) {
          // Recupera valores acumulados (caso haja mais de um jogo simultâneo, o que é raro)
          double currentScore = detailsMap[playerId]?.totalScore ?? 0.0;
          int g = detailsMap[playerId]?.goals ?? 0;
          int a = detailsMap[playerId]?.assists ?? 0;
          int y = detailsMap[playerId]?.yellows ?? 0;
          int r = detailsMap[playerId]?.reds ?? 0;
          int gc = detailsMap[playerId]?.goalsConceded ?? 0;

          // Soma Gols
          if (goalsMap.containsKey(playerId)) {
            int qtd = goalsMap[playerId]!;
            g += qtd;
            currentScore += (qtd * PTS_GOAL);
          }
          // Soma Assistências
          if (assistsMap.containsKey(playerId)) {
            int qtd = assistsMap[playerId]!;
            a += qtd;
            currentScore += (qtd * PTS_ASSIST);
          }
          // Soma Amarelos
          if (yellowsMap.containsKey(playerId)) {
            int qtd = yellowsMap[playerId]!;
            y += qtd;
            currentScore += (qtd * PTS_YELLOW_CARD);
          }
          // Soma Vermelhos
          if (redsMap.containsKey(playerId)) {
            int qtd = redsMap[playerId]!;
            r += qtd;
            currentScore += (qtd * PTS_RED_CARD);
          }
          // Soma Gols Sofridos
          if (concededMap.containsKey(playerId)) {
            int qtd = concededMap[playerId]!;
            gc += qtd;
            currentScore += (qtd * PTS_GOAL_CONCEDED);
          }

          // Atualiza o objeto no mapa
          detailsMap[playerId] = FantasyScoutDetail(
            totalScore: currentScore,
            goals: g,
            assists: a,
            yellows: y,
            reds: r,
            goalsConceded: gc,
          );
        }
      }

      return detailsMap;
    });
  }

  // Helper para evitar erros de cast (ex: _Map<String, dynamic> is not subtype of Map<String, int>)
  Map<String, int> _safeCastMap(dynamic rawMap) {
    if (rawMap == null || rawMap is! Map) return {};
    try {
      return rawMap.map((key, value) {
        final k = key.toString();
        final v = (value is num) ? value.toInt() : 0;
        return MapEntry(k, v);
      });
    } catch (e) {
      debugPrint("FantasyScout Error casting map: $e");
      return {};
    }
  }
}