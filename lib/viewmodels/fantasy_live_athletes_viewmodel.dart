import 'dart:async';
import 'package:flutter/material.dart';
import '../models/fantasy_models.dart';
import '../models/team_model.dart';
import '../repositories/fantasy_repository.dart';
import '../services/fantasy_scout_service.dart';

class AthleteLiveScoreItem {
  final FantasyPlayer player;
  final FantasyScoutDetail scoreDetail;
  final Team? team;

  AthleteLiveScoreItem({
    required this.player,
    required this.scoreDetail,
    this.team,
  });

  double get score => scoreDetail.totalScore;
  bool get hasPlayed => scoreDetail.hasStats || scoreDetail.totalScore != 0;
}

class FantasyLiveAthletesViewModel extends ChangeNotifier {
  final FantasyRepository _repository = FantasyRepository();
  final FantasyScoutService _scoutService = FantasyScoutService();

  List<FantasyPlayer> _allPlayers = [];
  Map<String, Team> _teamsMap = {};
  Map<String, FantasyScoutDetail> _liveScores = {};

  bool _isLoading = true;
  bool _isDisposed = false;
  String _seasonId = '';

  int _currentRound = 1;
  int _selectedRound = 1;
  bool _isMarketOpen = false;

  String _searchTerm = '';
  String _selectedPosition = 'Todos';
  String _selectedTeamId = 'Todos';
  bool _onlyPlayed = false;
  String _selectedSort = 'Maior Pontuação';

  StreamSubscription? _scoutSub;
  StreamSubscription? _marketSub;
  StreamSubscription? _roundMatchesSub;
  bool _areAllMatchesFinished = false;

  // Getters
  bool get isLoading => _isLoading;
  int get currentRound => _currentRound;
  int get selectedRound => _selectedRound;
  bool get isMarketOpen => _isMarketOpen;
  bool get areAllMatchesFinished => _areAllMatchesFinished;
  bool get isScoutsValidationPeriod => !_isMarketOpen && _areAllMatchesFinished;
  String get searchTerm => _searchTerm;
  String get selectedPosition => _selectedPosition;
  String get selectedTeamId => _selectedTeamId;
  bool get onlyPlayed => _onlyPlayed;
  String get selectedSort => _selectedSort;
  List<Team> get teams => _teamsMap.values.toList();
  Map<String, FantasyScoutDetail> get liveScores => _liveScores;

  List<AthleteLiveScoreItem> get filteredItems {
    final query = _searchTerm.trim().toLowerCase();

    return _allPlayers
        .map((p) {
          final detail = _liveScores[p.playerId] ?? FantasyScoutDetail(totalScore: 0.0);
          final team = _teamsMap[p.teamId];
          return AthleteLiveScoreItem(player: p, scoreDetail: detail, team: team);
        })
        .where((item) {
          // Filtro por termo de busca (nome do atleta ou nome do time)
          if (query.isNotEmpty) {
            final nameMatch = item.player.name.toLowerCase().contains(query);
            final teamMatch = item.team != null &&
                (item.team!.name.toLowerCase().contains(query) ||
                    item.team!.shortName.toLowerCase().contains(query));
            if (!nameMatch && !teamMatch) return false;
          }

          // Filtro por posição
          if (_selectedPosition != 'Todos') {
            final matchesPos = item.player.position == _selectedPosition ||
                item.player.secondaryPosition == _selectedPosition;
            if (!matchesPos) return false;
          }

          // Filtro por time
          if (_selectedTeamId != 'Todos') {
            if (item.player.teamId != _selectedTeamId) return false;
          }

          // Filtro "Apenas quem pontuou / jogou"
          if (_onlyPlayed && !item.hasPlayed) {
            return false;
          }

          return true;
        })
        .toList()
      ..sort((a, b) {
        switch (_selectedSort) {
          case 'Maior Pontuação':
            final cmp = b.score.compareTo(a.score);
            return cmp != 0 ? cmp : a.player.name.compareTo(b.player.name);
          case 'Menor Pontuação':
            final cmp = a.score.compareTo(b.score);
            return cmp != 0 ? cmp : a.player.name.compareTo(b.player.name);
          case 'Preço':
            final cmp = b.player.currentPrice.compareTo(a.player.currentPrice);
            return cmp != 0 ? cmp : b.score.compareTo(a.score);
          case 'Nome':
            return a.player.name.compareTo(b.player.name);
          default:
            return b.score.compareTo(a.score);
        }
      });
  }

  int get totalPlayedCount {
    return _allPlayers.where((p) {
      final s = _liveScores[p.playerId];
      return s != null && (s.hasStats || s.totalScore != 0);
    }).length;
  }

  AthleteLiveScoreItem? get topScorer {
    if (_allPlayers.isEmpty) return null;
    AthleteLiveScoreItem? top;
    double maxScore = -999.0;
    for (var p in _allPlayers) {
      final s = _liveScores[p.playerId] ?? FantasyScoutDetail(totalScore: 0.0);
      if (s.hasStats && s.totalScore > maxScore) {
        maxScore = s.totalScore;
        top = AthleteLiveScoreItem(player: p, scoreDetail: s, team: _teamsMap[p.teamId]);
      }
    }
    return top;
  }

  Future<void> init(String seasonId, {List<Team>? teams, int? targetRound}) async {
    _seasonId = seasonId;
    if (teams != null) {
      _teamsMap = {for (var t in teams) t.id: t};
    }

    // ⚡ Sincroniza imediatamente com o status em cache se disponível
    final cachedStatus = _repository.cachedMarketStatus;
    if (cachedStatus != null) {
      _isMarketOpen = cachedStatus['is_open'] ?? false;
      _currentRound = cachedStatus['current_round'] ?? 1;
      _selectedRound = targetRound ?? _currentRound;
    } else if (targetRound != null) {
      _selectedRound = targetRound;
    }

    _marketSub?.cancel();
    _marketSub = _repository.streamMarketStatus().listen((status) {
      _isMarketOpen = status['is_open'] ?? false;
      final newRound = status['current_round'] ?? 1;
      final roundChanged = newRound != _currentRound;
      _currentRound = newRound;

      if (targetRound == null && (roundChanged || _selectedRound != _currentRound)) {
        _selectedRound = _currentRound;
        _subscribeToScouts();
      }
      if (!_isDisposed) notifyListeners();
    });

    await _loadPlayers();
    _subscribeToScouts();
  }

  Future<void> _loadPlayers({bool forceRefresh = false}) async {
    try {
      _allPlayers = await _repository.getAllPlayers(forceRefresh: forceRefresh);
    } catch (e) {
      debugPrint("Erro ao carregar jogadores no LiveAthletesViewModel: $e");
    } finally {
      _isLoading = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  void _subscribeToScouts() {
    _scoutSub?.cancel();
    _roundMatchesSub?.cancel();
    _liveScores = {};
    if (_seasonId.isEmpty || _selectedRound <= 0) return;

    if (!_isMarketOpen && _selectedRound > 0) {
      _roundMatchesSub = _repository.streamRoundMatches(_seasonId, _selectedRound).listen((matches) {
        if (_isDisposed) return;
        _areAllMatchesFinished = matches.isNotEmpty && matches.every((m) => m.isFinished);
        notifyListeners();
      });
    } else {
      _areAllMatchesFinished = false;
    }

    _scoutSub = _scoutService.streamLiveScores(_seasonId, _selectedRound).listen((scores) {
      _liveScores = scores;
      if (!_isDisposed) notifyListeners();
    }, onError: (e) {
      debugPrint("Erro ao escutar live scores: $e");
    });
  }

  void setRound(int round) {
    if (_selectedRound == round) return;
    _selectedRound = round;
    _subscribeToScouts();
    if (!_isDisposed) notifyListeners();
  }

  void setSearchTerm(String term) {
    _searchTerm = term;
    if (!_isDisposed) notifyListeners();
  }

  void setSelectedPosition(String pos) {
    _selectedPosition = pos;
    if (!_isDisposed) notifyListeners();
  }

  void setSelectedTeamId(String teamId) {
    _selectedTeamId = teamId;
    if (!_isDisposed) notifyListeners();
  }

  void setOnlyPlayed(bool value) {
    _onlyPlayed = value;
    if (!_isDisposed) notifyListeners();
  }

  void setSelectedSort(String sort) {
    _selectedSort = sort;
    if (!_isDisposed) notifyListeners();
  }

  void clearFilters() {
    _searchTerm = '';
    _selectedPosition = 'Todos';
    _selectedTeamId = 'Todos';
    _onlyPlayed = false;
    _selectedSort = 'Maior Pontuação';
    if (!_isDisposed) notifyListeners();
  }

  Future<void> refresh() async {
    await _loadPlayers(forceRefresh: true);
    _subscribeToScouts();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scoutSub?.cancel();
    _marketSub?.cancel();
    _roundMatchesSub?.cancel();
    super.dispose();
  }
}
