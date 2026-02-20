import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // <-- NOVO
import '../models/fantasy_models.dart';
import '../repositories/fantasy_repository.dart'; 
import '../services/fantasy_service.dart';

class FantasyHomeViewModel extends ChangeNotifier {
  final FantasyRepository _repository = FantasyRepository();
  final FantasyService _fantasyService = FantasyService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- CONTROLE DE INICIALIZAÇÃO E OFFLINE ---
  String? _loadedUserId;
  String? _loadedSeasonId;
  bool _isOffline = false; // <-- NOVO

  // --- ESTADO ---
  bool _isLoading = true;
  String? _errorMessage;

  // Configurações e Mercado
  bool _isMarketOpen = true;
  int _currentRound = 1;
  FantasyGameConfig _gameConfig = FantasyGameConfig.defaults();

  // Time do Usuário
  FantasyTeam? _team;
  Map<String, LiveScoreData> _liveScores = {}; 
  final Map<String, String> _playerTeamMap = {};

  // Assinaturas (Streams)
  StreamSubscription? _marketSub;
  StreamSubscription? _teamSub;

  // --- GETTERS ---
  bool get isOffline => _isOffline; // <-- NOVO
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isMarketOpen => _isMarketOpen;
  int get currentRound => _currentRound;
  FantasyTeam? get team => _team;
  Map<String, LiveScoreData> get liveScores => _liveScores;
  FantasyGameConfig get config => _gameConfig;

  double get teamPartialScore {
    if (_team == null) return 0.0;
    
    double total = 0.0;
    for (String pid in _team!.lineupPlayerIds) {
      double score = _liveScores[pid]?.totalScore ?? 0.0;
      if (_team!.captainId == pid) score *= 2; 
      total += score;
    }
    return total;
  }

  // Helper de Conectividade
  Future<bool> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _isOffline = result == ConnectivityResult.none;
    notifyListeners();
    return !_isOffline;
  }

  // --- INICIALIZAÇÃO ---
  Future<void> init(String userId, String seasonId, {bool force = false}) async {
    if (!force && _loadedUserId == userId && _loadedSeasonId == seasonId && !_isLoading) return;

    _loadedUserId = userId;
    _loadedSeasonId = seasonId;
    _isLoading = true;
    notifyListeners();

    // VERIFICAÇÃO OFFLINE
    if (!await _checkConnectivity()) {
      _isLoading = false;
      notifyListeners();
      return; 
    }

    try {
      _gameConfig = await _fantasyService.getGameConfig();
      await _loadPlayerTeamMap();
    } catch (e) {
      debugPrint("Aviso: Falha ao carregar configurações: $e");
    }

    _marketSub?.cancel();
    _marketSub = _repository.streamMarketStatus().listen((status) {
      _isMarketOpen = status['is_open'] ?? true;
      _currentRound = status['current_round'] ?? 1;
      
      if (!_isMarketOpen) {
        _calculateLiveScores(seasonId, _currentRound);
      } else {
        _liveScores = {}; 
        notifyListeners();
      }
    }, onError: (e) {
      _errorMessage = "Erro no mercado: $e";
      notifyListeners();
    });

    _teamSub?.cancel();
    _teamSub = _repository.streamUserTeam(userId).listen((team) {
      _team = team;
      
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

  Future<void> _loadPlayerTeamMap() async {
    try {
      final players = await _fantasyService.getAllPlayers();
      _playerTeamMap.clear();
      for (var p in players) {
        _playerTeamMap[p.playerId] = p.teamId;
      }
    } catch (e) {
      debugPrint("Erro ao mapear times: $e");
    }
  }

  Future<void> _calculateLiveScores(String seasonId, int round) async {
    if (_team == null) return;
    if (!await _checkConnectivity()) return; // Não tenta calcular parciais sem rede

    try {
      final matchesQuery = await _firestore.collection('championships')
          .doc(seasonId).collection('matches').where('round', isEqualTo: round).get();

      Map<String, double> rawScores = {}; 

      for (var doc in matchesQuery.docs) {
        final data = doc.data();
        if (data['stats_applied'] != null && data['stats_applied']['player_stats'] != null) {
          final stats = data['stats_applied']['player_stats'];
          
          _processStatMap(rawScores, stats['goals'], _gameConfig.ptsGoal);
          _processStatMap(rawScores, stats['assists'], _gameConfig.ptsAssist);
          _processStatMap(rawScores, stats['yellows'], _gameConfig.ptsYellowCard);
          _processStatMap(rawScores, stats['reds'], _gameConfig.ptsRedCard);
          _processStatMap(rawScores, stats['goals_conceded'], _gameConfig.ptsGoalConceded);
        }
      }

      Map<String, List<double>> teamScoresAccumulator = {};
      
      rawScores.forEach((pid, score) {
        final teamId = _playerTeamMap[pid];
        if (teamId != null) {
          if (!teamScoresAccumulator.containsKey(teamId)) teamScoresAccumulator[teamId] = [];
          teamScoresAccumulator[teamId]!.add(score);
        }
      });

      Map<String, double> coachAverages = {};
      teamScoresAccumulator.forEach((teamId, scores) {
        if (scores.isNotEmpty) {
          double total = scores.reduce((a, b) => a + b);
          coachAverages[teamId] = total / scores.length;
        }
      });

      Map<String, LiveScoreData> calculatedScores = {};
      List<FantasyPlayer> myLineupDetails = await _fantasyService.getPlayersByIds(_team!.lineupPlayerIds);

      for (var player in myLineupDetails) {
        double score = 0.0;

        if (player.position == 'Técnico') {
          score = coachAverages[player.teamId] ?? 0.0;
        } else {
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
        if (qtd > 0) scores[playerId.toString()] = (scores[playerId.toString()] ?? 0.0) + (qtd * multiplier);
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

class LiveScoreData {
  final double totalScore;
  final bool isCaptain;
  LiveScoreData({required this.totalScore, required this.isCaptain});
}