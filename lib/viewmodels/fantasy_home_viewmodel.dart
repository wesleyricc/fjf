import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; 
import '../models/fantasy_models.dart';
import '../repositories/fantasy_repository.dart'; 
import '../services/fantasy_service.dart';

class FantasyHomeViewModel extends ChangeNotifier {
  final FantasyRepository _repository = FantasyRepository();
  final FantasyService _fantasyService = FantasyService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _loadedUserId;
  String? _loadedSeasonId;
  bool _isOffline = false; 

  bool _isLoading = true;
  String? _errorMessage;

  bool _isMarketOpen = true;
  int _currentRound = 1;
  FantasyGameConfig _gameConfig = FantasyGameConfig.defaults();

  FantasyTeam? _team;
  Map<String, LiveScoreData> _liveScores = {}; 
  final Map<String, String> _playerTeamMap = {};

  StreamSubscription? _marketSub;
  StreamSubscription? _teamSub;
  StreamSubscription? _matchesSub;

  bool get isOffline => _isOffline; 
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isMarketOpen => _isMarketOpen;
  int get currentRound => _currentRound;
  FantasyTeam? get team => _team;
  Map<String, LiveScoreData> get liveScores => _liveScores;
  FantasyGameConfig get config => _gameConfig;

  // 🚨 CÁLCULO REVISADO: Soma exata das parciais exibidas 🚨
  double get teamPartialScore {
    if (_team == null || _liveScores.isEmpty) return 0.0;
    
    double total = 0.0;
    for (String pid in _team!.lineupPlayerIds) {
      final scoreData = _liveScores[pid];
      if (scoreData != null) {
        double pScore = scoreData.totalScore;
        // Aplica o dobro se for o capitão
        if (_team!.captainId == pid) pScore *= 2; 
        total += pScore;
      }
    }
    return double.parse(total.toStringAsFixed(2));
  }

  Future<bool> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _isOffline = result == ConnectivityResult.none;
    notifyListeners();
    return !_isOffline;
  }

  Future<void> init(String userId, String seasonId, {bool force = false}) async {
    if (!force && _loadedUserId == userId && _loadedSeasonId == seasonId && !_isLoading) return;

    _loadedUserId = userId;
    _loadedSeasonId = seasonId;
    _isLoading = true;
    notifyListeners();

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
        _subscribeToLiveMatches(seasonId, _currentRound);
      } else {
        _matchesSub?.cancel();
        _liveScores = {}; 
        notifyListeners();
      }
    });

    _teamSub?.cancel();
    _teamSub = _repository.streamUserTeam(userId).listen((team) {
      _team = team;
      if (!_isMarketOpen) {
        _subscribeToLiveMatches(seasonId, _currentRound);
      }
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> _loadPlayerTeamMap() async {
    try {
      final players = await _repository.getAllPlayers();
      _playerTeamMap.clear();
      for (var p in players) {
        _playerTeamMap[p.playerId] = p.teamId;
      }
    } catch (e) {
      debugPrint("Erro ao mapear times: $e");
    }
  }

  void _subscribeToLiveMatches(String seasonId, int round) {
    if (_team == null) return;

    _matchesSub?.cancel(); 
    _matchesSub = _firestore.collection('championships')
        .doc(seasonId)
        .collection('matches')
        .where('round', isEqualTo: round)
        .snapshots() 
        .listen((snapshot) {
      _processLiveScoresSnapshot(snapshot);
    });
  }

  Future<void> _processLiveScoresSnapshot(QuerySnapshot snapshot) async {
    if (_team == null) return;

    try {
      Map<String, _ScoutCounts> rawScouts = {}; 

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['stats_applied'] != null && data['stats_applied']['player_stats'] != null) {
          final stats = data['stats_applied']['player_stats'];
          
          _accumulateScouts(rawScouts, stats['goals'], 'G');
          _accumulateScouts(rawScouts, stats['assists'], 'A');
          _accumulateScouts(rawScouts, stats['yellows'], 'Y');
          _accumulateScouts(rawScouts, stats['reds'], 'R');
          _accumulateScouts(rawScouts, stats['goals_conceded'], 'GC');
        }
      }

      Map<String, List<double>> teamScoresAccumulator = {};
      rawScouts.forEach((pid, counts) {
        final teamId = _playerTeamMap[pid];
        if (teamId != null) {
          double pPoints = counts.calculate(_gameConfig);
          teamScoresAccumulator.putIfAbsent(teamId, () => []).add(pPoints);
        }
      });

      Map<String, double> coachAverages = {};
      teamScoresAccumulator.forEach((teamId, scores) {
        if (scores.isNotEmpty) {
          coachAverages[teamId] = scores.reduce((a, b) => a + b) / scores.length;
        }
      });

      Map<String, LiveScoreData> calculatedScores = {};
      List<FantasyPlayer> myLineupDetails = await _repository.getPlayersByIds(_team!.lineupPlayerIds);

      for (var player in myLineupDetails) {
        if (player.position == 'Técnico') {
          calculatedScores[player.playerId] = LiveScoreData(
            totalScore: coachAverages[player.teamId] ?? 0.0,
            isCaptain: false,
          );
        } else {
          final s = rawScouts[player.playerId] ?? _ScoutCounts();
          calculatedScores[player.playerId] = LiveScoreData(
            totalScore: s.calculate(_gameConfig),
            isCaptain: (_team!.captainId == player.playerId),
            goals: s.g,
            assists: s.a,
            yellows: s.y,
            reds: s.r,
            goalsConceded: s.gc,
          );
        }
      }

      _liveScores = calculatedScores;
      notifyListeners();

    } catch (e) {
      debugPrint("Erro ao calcular parciais: $e");
    }
  }

  void _accumulateScouts(Map<String, _ScoutCounts> map, dynamic statMap, String type) {
    if (statMap is Map) {
      statMap.forEach((playerId, quantity) {
        final String pid = playerId.toString();
        final int qtd = (quantity is num) ? quantity.toInt() : 0;
        if (qtd <= 0) return;

        map.putIfAbsent(pid, () => _ScoutCounts());
        if (type == 'G') map[pid]!.g += qtd;
        else if (type == 'A') map[pid]!.a += qtd;
        else if (type == 'Y') map[pid]!.y += qtd;
        else if (type == 'R') map[pid]!.r += qtd;
        else if (type == 'GC') map[pid]!.gc += qtd;
      });
    }
  }

  @override
  void dispose() {
    _marketSub?.cancel();
    _teamSub?.cancel();
    _matchesSub?.cancel();
    super.dispose();
  }
}

class _ScoutCounts {
  int g = 0, a = 0, y = 0, r = 0, gc = 0;
  double calculate(FantasyGameConfig c) => (g * c.ptsGoal) + (a * c.ptsAssist) + (y * c.ptsYellowCard) + (r * c.ptsRedCard) + (gc * c.ptsGoalConceded);
}

class LiveScoreData {
  final double totalScore;
  final bool isCaptain;
  final int goals;
  final int assists;
  final int yellows;
  final int reds;
  final int goalsConceded;

  LiveScoreData({
    required this.totalScore,
    required this.isCaptain,
    this.goals = 0,
    this.assists = 0,
    this.yellows = 0,
    this.reds = 0,
    this.goalsConceded = 0,
  });
}