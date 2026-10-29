import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fantasy_models.dart';
import '../repositories/fantasy_repository.dart';
import '../models/team_model.dart';

class FantasyMarketViewModel extends ChangeNotifier {
  final FantasyRepository _repository = FantasyRepository();

  List<FantasyPlayer> _allPlayers = [];
  List<FantasyPlayer> _cachedFilteredPlayers = [];
  bool _isFilterDirty = true;
  List<Map<String, String>> _teamOptions = [];
  bool _isLoading = true;
  Set<String> _favoriteIds = {};

  String _selectedPosition = 'Goleiro';
  String _selectedTeamId = 'Todos';
  String _selectedSort = 'Preço';
  String _searchTerm = '';
  bool _onlyProbable = false;
  bool _onlyFavorites = false;
  bool _hideFielded = false;
  Set<String> _fieldedPlayerIds = {};
  int _displayLimit = 20;
  int _totalMatchingCount = 0;

  // Filtro de intervalo de preço (null = sem filtro)
  double _priceBoundsMin = 0;
  double _priceBoundsMax = 0;
  RangeValues? _priceRange;

  // Dados do time do usuário (saldo disponível e atletas escalados)
  FantasyTeam? _myTeam;
  StreamSubscription? _teamSub;
  StreamSubscription? _marketSub;
  StreamSubscription? _roundMatchesSub;
  bool _isMarketOpen = true;
  bool _areAllMatchesFinished = false;
  bool _isDisposed = false;

  bool get isLoading => _isLoading;
  bool get isMarketOpen => _isMarketOpen;
  bool get areAllMatchesFinished => _areAllMatchesFinished;
  bool get isScoutsValidationPeriod => !_isMarketOpen && _areAllMatchesFinished;
  List<Map<String, String>> get teamOptions => _teamOptions;
  Set<String> get favoriteIds => _favoriteIds;

  String get selectedPosition => _selectedPosition;
  String get selectedTeamId => _selectedTeamId;
  String get selectedSort => _selectedSort;
  String get searchTerm => _searchTerm;
  bool get onlyProbable => _onlyProbable;
  bool get onlyFavorites => _onlyFavorites;
  bool get hideFielded => _hideFielded;
  Set<String> get fieldedPlayerIds => _fieldedPlayerIds;
  int get displayLimit => _displayLimit;
  int get totalMatchingCount {
    if (_isFilterDirty) _recomputeFilteredPlayers();
    return _totalMatchingCount;
  }

  double get priceBoundsMin => _priceBoundsMin;
  double get priceBoundsMax => _priceBoundsMax;
  RangeValues get priceRange =>
      _priceRange ?? RangeValues(_priceBoundsMin, _priceBoundsMax);
  bool get hasPriceFilter => _priceRange != null;

  FantasyTeam? get myTeam => _myTeam;
  double? get availableBalance => _myTeam?.currentBalance;
  int get lineupCount => _myTeam?.lineupPlayerIds.length ?? 0;
  bool _isInitialized = false;

  void _markDirtyAndNotify() {
    _isFilterDirty = true;
    if (!_isDisposed) notifyListeners();
  }

  Future<void> init(List<Team> teams,
      {String? requiredPosition, String? userId, String? seasonId}) async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (requiredPosition != null) {
      _selectedPosition = requiredPosition;
      _isFilterDirty = true;
    }
    _marketSub?.cancel();
    _marketSub = _repository.streamMarketStatus().listen((status) {
      _isMarketOpen = status['is_open'] ?? true;
      final int currentRound = status['current_round'] ?? 1;

      if (!_isMarketOpen && seasonId != null && seasonId.isNotEmpty) {
        _roundMatchesSub?.cancel();
        _roundMatchesSub = _repository
            .streamRoundMatches(seasonId, currentRound)
            .listen((matches) {
          if (_isDisposed) return;
          _areAllMatchesFinished =
              matches.isNotEmpty && matches.every((m) => m.isFinished);
          notifyListeners();
        });
      } else {
        _roundMatchesSub?.cancel();
        _areAllMatchesFinished = false;
      }

      if (!_isDisposed) notifyListeners();
    });
    if (userId != null) {
      final cachedTeam = _repository.getCachedUserTeam(userId);
      if (cachedTeam != null) {
        _myTeam = cachedTeam;
      }
      _listenToTeam(userId);
    }
    await _loadFavorites();
    await loadMarketData(teams);
  }

  void _listenToTeam(String userId) {
    _teamSub?.cancel();
    _teamSub = _repository.streamUserTeam(userId).listen((team) {
      _myTeam = team;
      if (_fieldedPlayerIds.isEmpty && team != null) {
        _fieldedPlayerIds = {
          ...team.lineupPlayerIds,
          ...team.benchPlayerIds,
        };
        _isFilterDirty = true;
      }
      if (!_isDisposed) notifyListeners();
    }, onError: (e) {
      debugPrint("Error streaming user team: $e");
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _teamSub?.cancel();
    _marketSub?.cancel();
    _roundMatchesSub?.cancel();
    super.dispose();
  }

  Future<void> loadMarketData(List<Team> teams,
      {bool forceRefresh = false}) async {
    if (!_repository.hasCachedPlayers || forceRefresh) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final players =
          await _repository.getAllPlayers(forceRefresh: forceRefresh);

      final Map<String, String> teamDictionary = {};
      for (var team in teams) {
        teamDictionary[team.id] = team.name;
      }

      final Set<String> uniqueTeamIds = {};
      for (var p in players) {
        if (p.teamId.isNotEmpty) uniqueTeamIds.add(p.teamId);
      }

      final List<Map<String, String>> options = [
        {'id': 'Todos', 'name': 'Todas as Equipes'}
      ];

      for (var tId in uniqueTeamIds) {
        final String teamName = teamDictionary[tId] ?? 'Equipe Desconhecida';
        options.add({'id': tId, 'name': teamName});
      }

      final todosOption = options.removeAt(0);
      options.sort((a, b) => a['name']!.compareTo(b['name']!));
      options.insert(0, todosOption);

      _allPlayers = players;
      _teamOptions = options;
      _isFilterDirty = true;
      _updatePriceBounds();
    } catch (e) {
      debugPrint("Error loading market data: $e");
    } finally {
      _isLoading = false;
      _markDirtyAndNotify();
    }
  }

  void _updatePriceBounds() {
    if (_allPlayers.isEmpty) {
      _priceBoundsMin = 0;
      _priceBoundsMax = 0;
      _priceRange = null;
      return;
    }
    double minP = _allPlayers.first.currentPrice;
    double maxP = minP;
    for (var p in _allPlayers) {
      if (p.currentPrice < minP) minP = p.currentPrice;
      if (p.currentPrice > maxP) maxP = p.currentPrice;
    }
    _priceBoundsMin = minP.floorToDouble();
    _priceBoundsMax = maxP.ceilToDouble();
    if (_priceBoundsMax <= _priceBoundsMin) _priceBoundsMax = _priceBoundsMin + 1;

    // Ajusta um filtro existente aos novos limites
    if (_priceRange != null) {
      final start = _priceRange!.start.clamp(_priceBoundsMin, _priceBoundsMax).toDouble();
      final end = _priceRange!.end.clamp(_priceBoundsMin, _priceBoundsMax).toDouble();
      _priceRange = RangeValues(start, end);
    }
  }

  void setPriceRange(RangeValues range) {
    _displayLimit = 20;
    final coversAll =
        range.start <= _priceBoundsMin && range.end >= _priceBoundsMax;
    _priceRange = coversAll ? null : range;
    _markDirtyAndNotify();
  }

  void clearPriceRange() {
    _displayLimit = 20;
    _priceRange = null;
    _markDirtyAndNotify();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList('fantasy_favorites') ?? [];
    _favoriteIds = favs.toSet();
    _markDirtyAndNotify();
  }

  Future<void> toggleFavorite(String playerId) async {
    if (_favoriteIds.contains(playerId)) {
      _favoriteIds.remove(playerId);
    } else {
      _favoriteIds.add(playerId);
    }
    _markDirtyAndNotify();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('fantasy_favorites', _favoriteIds.toList());
  }

  void setPosition(String position) {
    _displayLimit = 20;
    _selectedPosition = position;
    _markDirtyAndNotify();
  }

  void setTeamId(String teamId) {
    _displayLimit = 20;
    _selectedTeamId = teamId;
    _markDirtyAndNotify();
  }

  void setSort(String sort) {
    _displayLimit = 20;
    _selectedSort = sort;
    _markDirtyAndNotify();
  }

  void setSearchTerm(String term) {
    _displayLimit = 20;
    _searchTerm = term;
    _markDirtyAndNotify();
  }

  void setOnlyProbable(bool value) {
    _displayLimit = 20;
    _onlyProbable = value;
    _markDirtyAndNotify();
  }

  void loadMore() {
    _displayLimit += 20;
    if (!_isDisposed) notifyListeners();
  }

  void setOnlyFavorites(bool value) {
    _displayLimit = 20;
    _onlyFavorites = value;
    _markDirtyAndNotify();
  }

  void setHideFielded(bool value) {
    _displayLimit = 20;
    _hideFielded = value;
    _markDirtyAndNotify();
  }

  void setFieldedPlayerIds(Set<String> ids) {
    _fieldedPlayerIds = ids;
    _markDirtyAndNotify();
  }

  static String normalizePosition(String pos) {
    final lower = pos.trim().toLowerCase();
    if (lower.contains('gol')) return 'goleiro';
    if (lower.contains('fix')) return 'fixo';
    if (lower.contains('ala')) return 'ala';
    if (lower.contains('piv')) return 'pivo';
    if (lower.contains('téc') || lower.contains('tec')) return 'tecnico';
    return lower;
  }

  static bool matchesPosition(String playerPos, String? secondaryPos, String targetPos) {
    final targetNorm = normalizePosition(targetPos);
    if (normalizePosition(playerPos) == targetNorm) return true;
    if (secondaryPos != null && secondaryPos.isNotEmpty && normalizePosition(secondaryPos) == targetNorm) return true;
    return false;
  }

  void _recomputeFilteredPlayers() {
    final targetNorm = normalizePosition(_selectedPosition);
    final bool filterTeam = _selectedTeamId != 'Todos';
    final String termLower = _searchTerm.trim().toLowerCase();
    final bool filterSearch = termLower.isNotEmpty;
    final RangeValues? range = _priceRange;
    final bool filterFielded = _hideFielded && _fieldedPlayerIds.isNotEmpty;

    final List<FantasyPlayer> players = [];
    for (final p in _allPlayers) {
      // 1. Position
      final bool posMatch = normalizePosition(p.position) == targetNorm ||
          (p.secondaryPosition != null &&
              p.secondaryPosition!.isNotEmpty &&
              normalizePosition(p.secondaryPosition!) == targetNorm);
      if (!posMatch) continue;

      // 2. Team
      if (filterTeam && p.teamId != _selectedTeamId) continue;

      // 3. Search
      if (filterSearch && !p.name.toLowerCase().contains(termLower)) continue;

      // 4. Status
      if (_onlyProbable &&
          p.status != 'provável' &&
          p.status != 'confirmed' &&
          p.status != 'probable') {
        continue;
      }

      // 5. Price range
      if (range != null &&
          (p.currentPrice < range.start - 0.005 ||
              p.currentPrice > range.end + 0.005)) {
        continue;
      }

      // 6. Favorites
      if (_onlyFavorites && !_favoriteIds.contains(p.playerId)) continue;

      // 7. Fielded
      if (filterFielded && _fieldedPlayerIds.contains(p.playerId)) continue;

      players.add(p);
    }

    if (_selectedSort == 'Preço') {
      players.sort((a, b) => b.currentPrice.compareTo(a.currentPrice));
    } else if (_selectedSort == 'Média') {
      players.sort((a, b) => b.averageScore.compareTo(a.averageScore));
    } else if (_selectedSort == 'Última') {
      players.sort((a, b) => b.lastScore.compareTo(a.lastScore));
    } else if (_selectedSort == 'Valorização') {
      players.sort((a, b) => b.lastPriceChange.compareTo(a.lastPriceChange));
    }

    _cachedFilteredPlayers = players;
    _totalMatchingCount = players.length;
    _isFilterDirty = false;
  }

  List<FantasyPlayer> get filteredPlayers {
    if (_isFilterDirty) {
      _recomputeFilteredPlayers();
    }
    return _cachedFilteredPlayers.take(_displayLimit).toList();
  }
}
