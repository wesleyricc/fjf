import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fantasy_models.dart';
import '../repositories/fantasy_repository.dart';
import '../models/team_model.dart';

class FantasyMarketViewModel extends ChangeNotifier {
  final FantasyRepository _repository = FantasyRepository();

  List<FantasyPlayer> _allPlayers = [];
  List<Map<String, String>> _teamOptions = [];
  bool _isLoading = true;
  Set<String> _favoriteIds = {};

  String _selectedPosition = 'Goleiro';
  String _selectedTeamId = 'Todos';
  String _selectedSort = 'Preço';
  String _searchTerm = '';
  bool _onlyProbable = false;
  bool _onlyFavorites = false;
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
  bool _isMarketOpen = true;
  bool _isDisposed = false;

  bool get isLoading => _isLoading;
  bool get isMarketOpen => _isMarketOpen;
  List<Map<String, String>> get teamOptions => _teamOptions;
  Set<String> get favoriteIds => _favoriteIds;

  String get selectedPosition => _selectedPosition;
  String get selectedTeamId => _selectedTeamId;
  String get selectedSort => _selectedSort;
  String get searchTerm => _searchTerm;
  bool get onlyProbable => _onlyProbable;
  bool get onlyFavorites => _onlyFavorites;
  int get displayLimit => _displayLimit;
  int get totalMatchingCount => _totalMatchingCount;

  double get priceBoundsMin => _priceBoundsMin;
  double get priceBoundsMax => _priceBoundsMax;
  RangeValues get priceRange =>
      _priceRange ?? RangeValues(_priceBoundsMin, _priceBoundsMax);
  bool get hasPriceFilter => _priceRange != null;

  FantasyTeam? get myTeam => _myTeam;
  double? get availableBalance => _myTeam?.currentBalance;
  int get lineupCount => _myTeam?.lineupPlayerIds.length ?? 0;

  Future<void> init(List<Team> teams,
      {String? requiredPosition, String? userId}) async {
    if (requiredPosition != null) {
      _selectedPosition = requiredPosition;
    }
    _marketSub?.cancel();
    _marketSub = _repository.streamMarketStatus().listen((status) {
      _isMarketOpen = status['is_open'] ?? true;
      if (!_isDisposed) notifyListeners();
    });
    if (userId != null) _listenToTeam(userId);
    await _loadFavorites();
    await loadMarketData(teams);
  }

  void _listenToTeam(String userId) {
    _teamSub?.cancel();
    _teamSub = _repository.streamUserTeam(userId).listen((team) {
      _myTeam = team;
      if (!_isDisposed) notifyListeners();
    }, onError: (e) {
      print("Error streaming user team: $e");
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _teamSub?.cancel();
    _marketSub?.cancel();
    super.dispose();
  }

  Future<void> loadMarketData(List<Team> teams,
      {bool forceRefresh = false}) async {
    _isLoading = true;
    notifyListeners();

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
      _updatePriceBounds();
    } catch (e) {
      print("Error loading market data: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
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
    notifyListeners();
  }

  void clearPriceRange() {
    _displayLimit = 20;
    _priceRange = null;
    notifyListeners();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList('fantasy_favorites') ?? [];
    _favoriteIds = favs.toSet();
    notifyListeners();
  }

  Future<void> toggleFavorite(String playerId) async {
    if (_favoriteIds.contains(playerId)) {
      _favoriteIds.remove(playerId);
    } else {
      _favoriteIds.add(playerId);
    }
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('fantasy_favorites', _favoriteIds.toList());
  }

  void setPosition(String position) {
    _displayLimit = 20;
    _selectedPosition = position;
    notifyListeners();
  }

  void setTeamId(String teamId) {
    _displayLimit = 20;
    _selectedTeamId = teamId;
    notifyListeners();
  }

  void setSort(String sort) {
    _displayLimit = 20;
    _selectedSort = sort;
    notifyListeners();
  }

  void setSearchTerm(String term) {
    _displayLimit = 20;
    _searchTerm = term;
    notifyListeners();
  }

  void setOnlyProbable(bool value) {
    _displayLimit = 20;
    _onlyProbable = value;
    notifyListeners();
  }

  void loadMore() {
    _displayLimit += 20;
    notifyListeners();
  }

  void setOnlyFavorites(bool value) {
    _displayLimit = 20;
    _onlyFavorites = value;
    notifyListeners();
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

  List<FantasyPlayer> get filteredPlayers {
    List<FantasyPlayer> players = List.from(_allPlayers);

    // Filter by position (robusto contra variações de acentuação e posições secundárias)
    final targetPos = _selectedPosition;
    players = players.where((p) => matchesPosition(p.position, p.secondaryPosition, targetPos)).toList();

    // Filter by team
    if (_selectedTeamId != 'Todos') {
      players = players.where((p) => p.teamId == _selectedTeamId).toList();
    }

    // Filter by search
    if (_searchTerm.isNotEmpty) {
      final term = _searchTerm.toLowerCase();
      players =
          players.where((p) => p.name.toLowerCase().contains(term)).toList();
    }

    // Filter by status (Probable)
    if (_onlyProbable) {
      players = players
          .where((p) =>
              p.status == 'provável' ||
              p.status == 'confirmed' ||
              p.status == 'probable')
          .toList();
    }

    // Filter by price range
    if (_priceRange != null) {
      final range = _priceRange!;
      players = players
          .where((p) =>
              p.currentPrice >= range.start - 0.005 &&
              p.currentPrice <= range.end + 0.005)
          .toList();
    }

    // Filter by favorites
    if (_onlyFavorites) {
      players =
          players.where((p) => _favoriteIds.contains(p.playerId)).toList();
    }

    // Sort
    if (_selectedSort == 'Preço') {
      players.sort((a, b) => b.currentPrice.compareTo(a.currentPrice));
    } else if (_selectedSort == 'Média') {
      players.sort((a, b) => b.averageScore.compareTo(a.averageScore));
    } else if (_selectedSort == 'Última') {
      players.sort((a, b) => b.lastScore.compareTo(a.lastScore));
    } else if (_selectedSort == 'Valorização') {
      players.sort((a, b) => b.lastPriceChange.compareTo(a.lastPriceChange));
    }

    _totalMatchingCount = players.length;
    return players.take(_displayLimit).toList();
  }
}
