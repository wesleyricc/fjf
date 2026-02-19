import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fantasy_models.dart';
import '../repositories/fantasy_repository.dart'; 
import '../services/fantasy_service.dart';

class FantasyHomeViewModel extends ChangeNotifier {
  final FantasyRepository _repository = FantasyRepository();
  final FantasyService _fantasyService = FantasyService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- CONTROLE DE INICIALIZAÇÃO ---
  String? _loadedUserId;
  String? _loadedSeasonId;

  // --- ESTADO ---
  bool _isLoading = true;
  String? _errorMessage;

  // Configurações e Mercado
  bool _isMarketOpen = true;
  int _currentRound = 1;
  FantasyGameConfig _gameConfig = FantasyGameConfig.defaults();

  // Time do Usuário
  FantasyTeam? _team;
  
  // Parciais (Scouts) calculadas localmente
  Map<String, LiveScoreData> _liveScores = {}; // Use a classe auxiliar LiveScoreData

  // Cache para cálculo do Técnico (PlayerID -> TeamID)
  final Map<String, String> _playerTeamMap = {};

  // Assinaturas (Streams)
  StreamSubscription? _marketSub;
  StreamSubscription? _teamSub;

  // --- GETTERS ---
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isMarketOpen => _isMarketOpen;
  int get currentRound => _currentRound;
  FantasyTeam? get team => _team;
  Map<String, LiveScoreData> get liveScores => _liveScores;
  FantasyGameConfig get config => _gameConfig;

  // Lógica Computada do Total
  double get teamPartialScore {
    if (_team == null) return 0.0;
    
    double total = 0.0;
    for (String pid in _team!.lineupPlayerIds) {
      // Busca pontuação calculada ou 0.0
      double score = _liveScores[pid]?.totalScore ?? 0.0;
      
      // Regra do Capitão: Multiplica o valor final (mesmo se negativo)
      if (_team!.captainId == pid) score *= 2; 
      
      total += score;
    }
    return total;
  }

  // --- INICIALIZAÇÃO ---
  Future<void> init(String userId, String seasonId) async {
    if (_loadedUserId == userId && _loadedSeasonId == seasonId && !_isLoading) return;

    _loadedUserId = userId;
    _loadedSeasonId = seasonId;
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Carrega Regras de Pontuação (Fonte da Verdade)
      _gameConfig = await _fantasyService.getGameConfig();
      
      // 2. Pré-carrega mapa de times para cálculo do técnico
      await _loadPlayerTeamMap();

    } catch (e) {
      debugPrint("Aviso: Falha ao carregar configurações: $e");
    }

    // 3. Monitora Status do Mercado
    _marketSub?.cancel();
    _marketSub = _repository.streamMarketStatus().listen((status) {
      _isMarketOpen = status['is_open'] ?? true;
      _currentRound = status['current_round'] ?? 1;
      
      // Se mercado fechou, calcula parciais
      if (!_isMarketOpen) {
        _calculateLiveScores(seasonId, _currentRound);
      } else {
        _liveScores = {}; // Limpa parciais se mercado abriu
        notifyListeners();
      }
    }, onError: (e) {
      _errorMessage = "Erro no mercado: $e";
      notifyListeners();
    });

    // 4. Monitora o Time do Usuário
    _teamSub?.cancel();
    _teamSub = _repository.streamUserTeam(userId).listen((team) {
      _team = team;
      
      // Se o time mudou e o mercado está fechado, recalcula
      if (!_isMarketOpen) {
        _calculateLiveScores(seasonId, _currentRound);
      }
      
      _isLoading = false;
      notifyListeners();
    }, onError: (e) {
      _errorMessage = "Erro ao carregar time: $e";
      _isLoading = false;
      notifyListeners();
    });
  }

  // --- PREPARAÇÃO DO CÁLCULO (Mapeamento) ---
  Future<void> _loadPlayerTeamMap() async {
    try {
      // Busca todos os jogadores para saber qual time eles pertencem (para média do técnico)
      final players = await _fantasyService.getAllPlayers();
      _playerTeamMap.clear();
      for (var p in players) {
        _playerTeamMap[p.playerId] = p.teamId;
      }
    } catch (e) {
      debugPrint("Erro ao mapear times: $e");
    }
  }

  // --- CÁLCULO MATEMÁTICO DAS PARCIAIS (Igual à Cloud Function) ---
  Future<void> _calculateLiveScores(String seasonId, int round) async {
    if (_team == null) return;

    try {
      // A. Busca Partidas da Rodada com Scouts
      final matchesQuery = await _firestore.collection('championships')
          .doc(seasonId)
          .collection('matches')
          .where('round', isEqualTo: round)
          .get();

      Map<String, double> rawScores = {}; // PlayerID -> Pontos Individuais

      // B. Processa Scouts Individuais
      for (var doc in matchesQuery.docs) {
        final data = doc.data();
        if (data['stats_applied'] != null && data['stats_applied']['player_stats'] != null) {
          final stats = data['stats_applied']['player_stats'];
          
          _processStatMap(rawScores, stats['goals'], _gameConfig.ptsGoal);
          _processStatMap(rawScores, stats['assists'], _gameConfig.ptsAssist);
          _processStatMap(rawScores, stats['yellows'], _gameConfig.ptsYellowCard);
          _processStatMap(rawScores, stats['reds'], _gameConfig.ptsRedCard);
          _processStatMap(rawScores, stats['goals_conceded'], _gameConfig.ptsGoalConceded);
          // Opcionais
          //if (data['stats_applied']['clean_sheets'] != null) {
             //_processStatMap(rawScores, data['stats_applied']['clean_sheets'], _gameConfig.ptsCleanSheet); // 5.0
          //}
        }
      }

      // C. Cálculo da Média dos Técnicos (Regra Específica)
      Map<String, List<double>> teamScoresAccumulator = {};
      
      // Agrupa pontuações pelo Time Real do jogador
      rawScores.forEach((pid, score) {
        final teamId = _playerTeamMap[pid];
        if (teamId != null) {
          if (!teamScoresAccumulator.containsKey(teamId)) {
            teamScoresAccumulator[teamId] = [];
          }
          teamScoresAccumulator[teamId]!.add(score);
        }
      });

      // Calcula a média aritmética por time
      Map<String, double> coachAverages = {};
      teamScoresAccumulator.forEach((teamId, scores) {
        if (scores.isNotEmpty) {
          double total = scores.reduce((a, b) => a + b);
          coachAverages[teamId] = total / scores.length;
        }
      });

      // D. Monta o Objeto Final para a UI (Apenas jogadores do meu time)
      Map<String, LiveScoreData> calculatedScores = {};
      
      // Precisamos dos dados completos dos jogadores do meu time para saber a posição
      List<FantasyPlayer> myLineupDetails = await _fantasyService.getPlayersByIds(_team!.lineupPlayerIds);

      for (var player in myLineupDetails) {
        double score = 0.0;

        if (player.position == 'Técnico') {
          // Se for técnico, usa a média calculada do time dele
          score = coachAverages[player.teamId] ?? 0.0;
        } else {
          // Se for jogador, usa o scout individual
          score = rawScores[player.playerId] ?? 0.0;
        }

        bool isCap = (_team!.captainId == player.playerId);
        
        calculatedScores[player.playerId] = LiveScoreData(
          totalScore: score,
          isCaptain: isCap
        );
      }

      _liveScores = calculatedScores;
      notifyListeners();

    } catch (e) {
      debugPrint("Erro ao calcular parciais: $e");
    }
  }

  void _processStatMap(Map<String, double> scores, dynamic statMap, double multiplier) {
    if (statMap is Map) {
      statMap.forEach((playerId, quantity) {
        double qtd = (quantity is num) ? quantity.toDouble() : 0.0;
        if (qtd > 0) {
          scores[playerId.toString()] = (scores[playerId.toString()] ?? 0.0) + (qtd * multiplier);
        }
      });
    }
  }

  @override
  void dispose() {
    _marketSub?.cancel();
    _teamSub?.cancel();
    super.dispose();
  }
}

// Classe Auxiliar para UI
class LiveScoreData {
  final double totalScore;
  final bool isCaptain;

  LiveScoreData({required this.totalScore, required this.isCaptain});
}