import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/fantasy_models.dart';
import '../repositories/fantasy_repository.dart'; 
import '../services/fantasy_scout_service.dart';

class FantasyHomeViewModel extends ChangeNotifier {
  final FantasyRepository _repository = FantasyRepository();
  final FantasyScoutService _scoutService = FantasyScoutService();

  // --- CONTROLE DE INICIALIZAÇÃO (NOVO) ---
  String? _loadedUserId;
  String? _loadedSeasonId;

  // --- ESTADO ---
  bool _isLoading = true;
  String? _errorMessage;

  // Mercado
  bool _isMarketOpen = true;
  int _currentRound = 1;

  // Time do Usuário
  FantasyTeam? _team;
  
  // Parciais (Scouts)
  Map<String, FantasyScoutDetail> _liveScores = {};

  // Assinaturas (Streams)
  StreamSubscription? _marketSub;
  StreamSubscription? _teamSub;
  StreamSubscription? _scoutSub;

  // --- GETTERS ---
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isMarketOpen => _isMarketOpen;
  int get currentRound => _currentRound;
  FantasyTeam? get team => _team;
  Map<String, FantasyScoutDetail> get liveScores => _liveScores;

  // Lógica Computada
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

  // --- INICIALIZAÇÃO SEGURA ---
  void init(String userId, String seasonId) {
    // PROTEÇÃO: Se já carregamos dados para este usuário e temporada, não faz nada.
    // Isso impede loops infinitos e recargas desnecessárias.
    if (_loadedUserId == userId && _loadedSeasonId == seasonId && !_isLoading) {
      return;
    }

    _loadedUserId = userId;
    _loadedSeasonId = seasonId;
    _isLoading = true;
    
    // Notifica logo para mostrar loading na UI caso estivesse false
    notifyListeners();

    // 1. Monitora Status do Mercado
    _marketSub?.cancel();
    _marketSub = _repository.streamMarketStatus().listen((status) {
      _isMarketOpen = status['is_open'] ?? true;
      _currentRound = status['current_round'] ?? 1;
      
      _updateScoutSubscription(seasonId);
      notifyListeners();
    }, onError: (e) {
      _errorMessage = "Erro no mercado: $e";
      notifyListeners();
    });

    // 2. Monitora o Time do Usuário
    _teamSub?.cancel();
    _teamSub = _repository.streamUserTeam(userId).listen((team) {
      _team = team;
      _updateScoutSubscription(seasonId); 
      _isLoading = false;
      notifyListeners();
    }, onError: (e) {
      _errorMessage = "Erro ao carregar time: $e";
      _isLoading = false;
      notifyListeners();
    });
  }

  void _updateScoutSubscription(String seasonId) {
    _scoutSub?.cancel(); 
    _scoutSub = null;

    if (_isMarketOpen) {
      _liveScores = {}; 
      notifyListeners();
      return;
    }

    if (_team == null || _team!.lineupPlayerIds.isEmpty) return;

    _scoutSub = _scoutService.streamLiveScores(seasonId, _currentRound, _team!.lineupPlayerIds).listen((scores) {
      _liveScores = scores;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _marketSub?.cancel();
    _teamSub?.cancel();
    _scoutSub?.cancel();
    super.dispose();
  }
}