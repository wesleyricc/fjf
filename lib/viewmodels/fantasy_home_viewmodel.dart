import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/fantasy_models.dart';
import '../repositories/fantasy_repository.dart'; // <--- Uso do Repository
import '../services/fantasy_scout_service.dart';

class FantasyHomeViewModel extends ChangeNotifier {
  // Instância do Repository (Singleton ou injetado)
  final FantasyRepository _repository = FantasyRepository();
  final FantasyScoutService _scoutService = FantasyScoutService();

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

  // Lógica Computada: Calcula o total parcial do time
  double get teamPartialScore {
    if (_team == null) return 0.0;
    
    double total = 0.0;
    for (String pid in _team!.lineupPlayerIds) {
      double score = _liveScores[pid]?.totalScore ?? 0.0;
      if (_team!.captainId == pid) score *= 2; // Regra do Capitão
      total += score;
    }
    return total;
  }

  // --- INICIALIZAÇÃO ---
  void init(String userId, String seasonId) {
    _isLoading = true;
    notifyListeners();

    // 1. Monitora Status do Mercado (Via Repository)
    _marketSub = _repository.streamMarketStatus().listen((status) {
      _isMarketOpen = status['is_open'] ?? true;
      _currentRound = status['current_round'] ?? 1;
      
      // Se mercado fechar, precisamos garantir que estamos ouvindo os scouts
      _updateScoutSubscription(seasonId);
      notifyListeners();
    }, onError: (e) {
      _errorMessage = "Erro no mercado: $e";
      notifyListeners();
    });

    // 2. Monitora o Time do Usuário (Via Repository)
    _teamSub = _repository.streamUserTeam(userId).listen((team) {
      _team = team;
      _updateScoutSubscription(seasonId); // Atualiza scouts se o time mudou
      _isLoading = false;
      notifyListeners();
    }, onError: (e) {
      _errorMessage = "Erro ao carregar time: $e";
      _isLoading = false;
      notifyListeners();
    });
  }

  // Lógica Inteligente: Só ouve scouts se necessário
  void _updateScoutSubscription(String seasonId) {
    _scoutSub?.cancel(); 
    _scoutSub = null;

    if (_isMarketOpen) {
      // Se mercado aberto, não precisamos de parciais ao vivo
      _liveScores = {}; 
      notifyListeners();
      return;
    }

    if (_team == null || _team!.lineupPlayerIds.isEmpty) return;

    // Inicia stream de scouts AO VIVO (Direto do Service de Scouts, pois é realtime puro)
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