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

  bool get isLoading => _isLoading;
  List<Map<String, String>> get teamOptions => _teamOptions;
  Set<String> get favoriteIds => _favoriteIds;

  String get selectedPosition => _selectedPosition;
  String get selectedTeamId => _selectedTeamId;
  String get selectedSort => _selectedSort;
  String get searchTerm => _searchTerm;
  bool get onlyProbable => _onlyProbable;
  bool get onlyFavorites => _onlyFavorites;

  Future<void> init(List<Team> teams, {String? requiredPosition}) async {
    if (requiredPosition != null) {
      _selectedPosition = requiredPosition;
    }
    await _loadFavorites();
    await loadMarketData(teams);
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
    } catch (e) {
      print("Error loading market data: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

  List<FantasyPlayer> get filteredPlayers {
    List<FantasyPlayer> players = List.from(_allPlayers);

    // Filter by position
    if (_selectedPosition != 'Técnico') {
      players = players.where((p) => p.position == _selectedPosition).toList();
    } else {
      players = players.where((p) => p.position == 'Técnico').toList();
    }

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

    return players;
  }
}
