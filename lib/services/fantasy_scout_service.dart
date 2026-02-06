import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/fantasy_models.dart';
import 'fantasy_service.dart'; // Para buscar a config

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

  // Removidas as constantes STATIC CONST.
  // Agora buscamos via FantasyGameConfig.

  Stream<Map<String, FantasyScoutDetail>> streamLiveScores(String seasonId, int round, List<String> playerIds) async* {
    // Debug: Verificar o ID que está chegando
    debugPrint("FantasyScout: Inicializando Stream para temporada: $seasonId");

    if (playerIds.isEmpty || seasonId.isEmpty) {
      yield {};
      return;
    }

    // 1. Busca a configuração do banco antes de iniciar o stream
    final FantasyGameConfig config = await FantasyService().getGameConfig();
    debugPrint("FantasyScout: Configuração carregada (Gol=${config.ptsGoal})");

    // 2. Inicia o listen no Firestore
    yield* _firestore
        .collection('championships')
        .doc(seasonId)
        .collection('matches')
        .where('round', isEqualTo: round)
        .snapshots()
        .map((snapshot) {
      
      // debugPrint("FantasyScout: Encontrados ${snapshot.docs.length} jogos em andamento.");

      final Map<String, FantasyScoutDetail> detailsMap = {};

      // Inicializa zerado
      for (var id in playerIds) {
        detailsMap[id] = FantasyScoutDetail(totalScore: 0.0);
      }

      // Itera sobre os jogos
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
          // Recupera valores acumulados
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
            currentScore += (qtd * config.ptsGoal);
          }
          // Soma Assistências
          if (assistsMap.containsKey(playerId)) {
            int qtd = assistsMap[playerId]!;
            a += qtd;
            currentScore += (qtd * config.ptsAssist);
          }
          // Soma Amarelos
          if (yellowsMap.containsKey(playerId)) {
            int qtd = yellowsMap[playerId]!;
            y += qtd;
            currentScore += (qtd * config.ptsYellowCard);
          }
          // Soma Vermelhos
          if (redsMap.containsKey(playerId)) {
            int qtd = redsMap[playerId]!;
            r += qtd;
            currentScore += (qtd * config.ptsRedCard);
          }
          // Soma Gols Sofridos
          if (concededMap.containsKey(playerId)) {
            int qtd = concededMap[playerId]!;
            gc += qtd;
            currentScore += (qtd * config.ptsGoalConceded);
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

  // Helper para evitar erros de cast
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