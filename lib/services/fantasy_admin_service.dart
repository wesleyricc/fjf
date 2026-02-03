import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/fantasy_models.dart';

class FantasyAdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- NOVA TABELA DE PONTUAÇÃO ---
  static const double PTS_GOAL = 5.0;
  static const double PTS_ASSIST = 3.0;
  static const double PTS_YELLOW_CARD = -1.0;
  static const double PTS_RED_CARD = -3.0;
  static const double PTS_GOAL_CONCEDED = -1.0;

  // --- CONSTANTES DA ECONOMIA ---
  static const double FACTOR_EXPECTATION = 0.35; // Fator de Expectativa
  static const double FACTOR_VARIATION = 0.25;   // Multiplicador da Variação
  static const double CAP_LIMIT_PERCENT = 0.25;  // Teto de 25% (Valorização/Desvalorização)
  static const double MIN_PRICE = 1.0;           // Preço Mínimo

  // --- 0. LEITURA DOS SCOUTS (FILTRADO POR RODADA) ---

  Future<Map<String, double>> _fetchSeasonScores(String seasonId, int round) async {
    final Map<String, double> scoresMap = {};
    debugPrint("--- INICIANDO LEITURA DE SCOUTS (SISTEMA DE EXPECTATIVA) ---");
    debugPrint("Temporada: $seasonId | Rodada: $round");

    try {
      final matchesRef = _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('matches')
          .where('round', isEqualTo: round); 
      
      final matchesSnap = await matchesRef.get();

      debugPrint("Partidas encontradas nesta rodada: ${matchesSnap.docs.length}");

      for (var matchDoc in matchesSnap.docs) {
        final data = matchDoc.data();
        
        if (data['stats_applied'] == null) continue;

        final statsApplied = data['stats_applied'] as Map<String, dynamic>;
        final playerStats = statsApplied['player_stats'] as Map<String, dynamic>? ?? {};

        Map<String, int> getStatMap(String key) => _safeCastMap(playerStats[key]);

        final goalsMap = getStatMap('goals');
        final assistsMap = getStatMap('assists');
        final yellowsMap = getStatMap('yellows');
        final redsMap = getStatMap('reds');
        // final concededMap = getStatMap('goals_conceded'); // Se não for usar, ignorar

        final Set<String> allPlayerIds = {
          ...goalsMap.keys, ...assistsMap.keys, ...yellowsMap.keys, 
          ...redsMap.keys
        };

        for (String pid in allPlayerIds) {
          double points = 0.0;
          points += (goalsMap[pid] ?? 0) * PTS_GOAL;
          points += (assistsMap[pid] ?? 0) * PTS_ASSIST;
          points += (yellowsMap[pid] ?? 0) * PTS_YELLOW_CARD;
          points += (redsMap[pid] ?? 0) * PTS_RED_CARD;
          
          scoresMap[pid] = (scoresMap[pid] ?? 0.0) + points;
        }
      }
      
      debugPrint("Jogadores Pontuados na Rodada $round: ${scoresMap.length}");
      
    } catch (e) {
      debugPrint("ERRO CRÍTICO ao consolidar scouts: $e");
    }
    
    return scoresMap;
  }

  Map<String, int> _safeCastMap(dynamic rawMap) {
    if (rawMap == null || rawMap is! Map) return {};
    return rawMap.map((key, value) => MapEntry(key.toString(), (value is num) ? value.toInt() : 0));
  }

  // --- 1. PROCESSAMENTO DE JOGADORES (MERCADO) ---

  Future<Map<String, double>> processMarketValuation(String seasonId, Map<String, double> actualScores) async {
    final Map<String, double> newPricesMap = {};
    final WriteBatch batch = _firestore.batch();
    
    final marketSnap = await _firestore.collection('fantasy_market_players').get();

    for (var doc in marketSnap.docs) {
      final player = FantasyPlayer.fromFirestore(doc);
      
      double score = actualScores[player.playerId] ?? 0.0;
      double currentPrice = player.currentPrice;

      // ==========================================================
      // NOVA LÓGICA DE VALORIZAÇÃO (EXPECTATIVA)
      // ==========================================================
      
      // 1. Calcular Expectativa (Valor * 0.35)
      double expectation = currentPrice * FACTOR_EXPECTATION;

      // 2. Calcular Desempenho (Pontos - Expectativa)
      double performance = score - expectation;

      // 3. Calcular Variação Bruta (Desempenho * 0.15)
      double rawVariation = performance * FACTOR_VARIATION;

      // 4. Calcular Limites (15% do Valor Atual)
      double limit = currentPrice * CAP_LIMIT_PERCENT;

      // 5. Aplicar Travas (Clamp)
      double finalVariation = rawVariation;
      if (finalVariation > limit) finalVariation = limit;   // Teto Valorização
      if (finalVariation < -limit) finalVariation = -limit; // Teto Desvalorização

      // 6. Novo Preço
      double newPrice = currentPrice + finalVariation;

      // 7. Preço Mínimo
      if (newPrice < MIN_PRICE) newPrice = MIN_PRICE;

      // 8. Arredondamento (1 casa decimal)
      // Ex: 18.705 -> "18.7" -> 18.7
      finalVariation = double.parse(finalVariation.toStringAsFixed(1));
      newPrice = double.parse(newPrice.toStringAsFixed(1));

      // ==========================================================

      newPricesMap[player.playerId] = newPrice;

      // Se não jogou, salvamos score 0.0, mas o preço pode ter variado (pela expectativa)
      // OBS: Na lógica de expectativa, se score é 0, a expectativa (ex: 6.3) gera desempenho negativo (-6.3),
      // logo, quem não joga DESVALORIZA. Se quiser evitar isso, coloque um `if (!actualScores.containsKey)`
      
      // Decisão de Projeto: Jogador que não jogou deve desvalorizar?
      // Pela sua lógica "Atleta caro = expectativa alta", se ele não joga, ele frustra a expectativa.
      // Vou manter a desvalorização. Se quiser proteger quem não jogou, descomente abaixo:
      
      /*if (!actualScores.containsKey(player.playerId)) {
         newPrice = currentPrice;
         finalVariation = 0.0;
         newPricesMap[player.playerId] = newPrice;
      }*/
      

      batch.update(doc.reference, {
        'current_price': newPrice,
        'last_price_change': finalVariation,
        'last_score': actualScores.containsKey(player.playerId) ? score : 0.0, 
      });
    }

    await batch.commit();
    return newPricesMap;
  }

  // --- 2. PROCESSAMENTO DE TIMES (USUÁRIOS) ---
  // (Mantido igual, apenas consome os novos preços)

  Future<String> processUserTeams(Map<String, double> newPricesMap, Map<String, double> actualScores, int round) async {
    try {
      final teamsSnap = await _firestore.collection('fantasy_teams').get();
      final WriteBatch batch = _firestore.batch();
      int count = 0;

      for (var doc in teamsSnap.docs) {
        final team = FantasyTeam.fromFirestore(doc);
        
        double roundPoints = 0.0;
        double newTeamValueFromPlayers = 0.0;

        for (String playerId in team.lineupPlayerIds) {
          // Pontos
          double pScore = actualScores[playerId] ?? 0.0;
          if (team.captainId == playerId) pScore *= 2;
          roundPoints += pScore;

          // Patrimônio (Usa o novo preço calculado com a nova regra)
          double updatedPrice = newPricesMap[playerId] ?? 1.0; // Fallback min 1.0
          newTeamValueFromPlayers += updatedPrice;
        }

        double newTotalPatrimony = team.currentBalance + newTeamValueFromPlayers;

        // Arredondar patrimônio também para 1 ou 2 casas para ficar limpo
        newTotalPatrimony = double.parse(newTotalPatrimony.toStringAsFixed(2));

        // 1. Cria a referência para a sub-coleção 'history' dentro do time
        final historyRef = _firestore
        .collection('fantasy_teams')
        .doc(doc.id) // ID do time (usuário)
        .collection('history')
        .doc(round.toString()); // Doc ID é o número da rodada (ex: "1")

        // 2. Salva os dados estáticos daquela rodada
        batch.set(historyRef, {
          'round': round,
          'points': roundPoints,
          'patrimony': newTotalPatrimony, // Para ver a evolução da riqueza
          'processed_at': FieldValue.serverTimestamp(),
          // Opcional: Salvar o time que jogou para consulta futura
          'lineup_snapshot': team.lineupPlayerIds, 
        });

        batch.update(doc.reference, {
          'total_points': team.totalPoints + roundPoints,
          'last_score': roundPoints, 
          'team_value': newTotalPatrimony,
        });
        
        count++;
      }

      await batch.commit();
      return "Sucesso! $count times processados.";
    } catch (e) {
      return "Erro ao processar times: $e";
    }
  }

  // --- ORQUESTRADOR ---
  
  Future<String> closeRoundFullRoutine(String seasonId, int round) async {
    try {
      final Map<String, double> scores = await _fetchSeasonScores(seasonId, round);
      
      if (scores.isEmpty) {
        return "AVISO: Nenhum scout encontrado na Rodada $round.";
      }

      final newPrices = await processMarketValuation(seasonId, scores);
      final resultTeams = await processUserTeams(newPrices, scores, round);
      
      return "Rodada $round fechada.\nRegra: Expectativa\nJogadores: ${scores.length}\nTimes: $resultTeams";
    } catch (e) {
      return "Erro crítico: $e";
    }
  }
}