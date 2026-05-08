import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/fantasy_league_model.dart';
import '../services/fantasy_league_service.dart';

class FantasyLeagueViewModel extends ChangeNotifier {
  final FantasyLeagueService _leagueService = FantasyLeagueService();
  
  String? _userId;
  bool _isLoading = false;
  String? _errorMessage;
  List<FantasyLeague> _myLeagues = [];
  StreamSubscription? _leaguesSub;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<FantasyLeague> get myLeagues => _myLeagues;

  void init(String userId) {
    _userId = userId;
    _leaguesSub?.cancel();
    
    // Fica escutando as ligas em tempo real
    _leaguesSub = _leagueService.streamMyLeagues(userId).listen((leagues) {
      _myLeagues = leagues;
      notifyListeners();
    }, onError: (error) {
      debugPrint("Erro ao escutar ligas: $error");
    });
  }

  Future<bool> createLeague(String name) async {
    if (_userId == null || name.trim().isEmpty) return false;
    
    _setLoading(true);
    try {
      await _leagueService.createLeague(name, _userId!);
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = "Erro ao criar liga: $e";
      _setLoading(false);
      return false;
    }
  }

  Future<bool> joinLeague(String code) async {
    if (_userId == null || code.trim().isEmpty) return false;

    _setLoading(true);
    try {
      final error = await _leagueService.joinLeague(code, _userId!);
      if (error != null) {
        _errorMessage = error;
        _setLoading(false);
        return false;
      }
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = "Erro ao entrar na liga: $e";
      _setLoading(false);
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _leaguesSub?.cancel();
    super.dispose();
  }
}