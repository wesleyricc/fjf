import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fantasy_models.dart';
import '../repositories/fantasy_repository.dart';
import '../services/fantasy_scout_service.dart';

class FantasyLineupViewModel extends ChangeNotifier {
  final FantasyRepository _repository = FantasyRepository();
  final FantasyScoutService _scoutService = FantasyScoutService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- ESTADO ---
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _successMessage;
  String? _userId;

  FantasyTeam? _team;
  final Map<int, FantasyPlayer> _lineup = {}; 
  String? _captainId;
  
  double _currentBalance = 0.0;
  double _teamPrice = 0.0;
  double _totalPatrimony = 0.0;
  double _expectedOldTeamCost = 0.0;

  bool _isMarketOpen = true;
  int _currentRound = 1;
  Map<String, FantasyScoutDetail> _liveScores = {};

  StreamSubscription? _marketSub;
  StreamSubscription? _teamSub; 
  StreamSubscription? _scoutSub;

  // --- GETTERS ---
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  bool get isMarketOpen => _isMarketOpen;
  int get currentRound => _currentRound;
  Map<int, FantasyPlayer> get lineup => _lineup;
  String? get captainId => _captainId;
  double get currentBalance => _currentBalance;
  double get totalPatrimony => _totalPatrimony;
  Map<String, FantasyScoutDetail> get liveScores => _liveScores;

  final List<Map<String, dynamic>> slotsConfig = [
    {'index': 1, 'pos': 'Goleiro'},
    {'index': 2, 'pos': 'Fixo'},
    {'index': 3, 'pos': 'Ala'},
    {'index': 4, 'pos': 'Ala'},
    {'index': 5, 'pos': 'Pivô'},
    {'index': 6, 'pos': 'Técnico'},
  ];

  // --- INICIALIZAÇÃO ---
  void init(String userId, String seasonId) {
    _userId = userId;
    _isLoading = true;
    notifyListeners();

    // 1. Monitora Mercado
    _marketSub?.cancel();
    _marketSub = _repository.streamMarketStatus().listen((status) {
      _isMarketOpen = status['is_open'] ?? true;
      _currentRound = status['current_round'] ?? 1;
      _checkScoutSubscription(seasonId);
      notifyListeners();
    });

    // 2. Monitoramento em Tempo Real do Time
    _teamSub?.cancel();
    _teamSub = _repository.streamUserTeam(userId).listen((team) async {
      if (team != null) {
        await _syncLocalStateWithDatabase(team, seasonId);
      } else {
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  // --- SINC LOCAL COM DATABASE ---
  // --- SINC LOCAL COM DATABASE ---
  Future<void> _syncLocalStateWithDatabase(FantasyTeam team, String seasonId) async {
    _team = team;
    _currentBalance = team.currentBalance;
    _captainId = team.captainId;
    _totalPatrimony = team.teamValue;

    if (team.lineupPlayerIds.isNotEmpty) {
      try {
        // 🚨 CORREÇÃO: Removido o forceRefresh que não existia no repositório
        final players = await _repository.getPlayersByIds(team.lineupPlayerIds);
        
        _lineup.clear();
        double calculatedTeamPrice = 0.0;

        // Mapeamento Inteligente (Case Insensitive)
        for (var p in players) {
          calculatedTeamPrice += p.currentPrice;
          final pos = p.position.toLowerCase();

          if (pos.contains('gol')) _lineup[1] = p;
          else if (pos.contains('fix')) _lineup[2] = p;
          else if (pos.contains('piv')) _lineup[5] = p;
          else if (pos.contains('téc')) _lineup[6] = p;
          else if (pos.contains('ala')) {
            if (!_lineup.containsKey(3)) _lineup[3] = p; else _lineup[4] = p;
          }
        }
        _teamPrice = calculatedTeamPrice;
        _expectedOldTeamCost = calculatedTeamPrice;
      } catch (e) {
        _errorMessage = "Falha ao carregar detalhes dos atletas: $e";
      }
    } else {
      _lineup.clear();
      _teamPrice = 0.0;
    }

    _checkScoutSubscription(seasonId);
    _isLoading = false;
    notifyListeners();
  }

  // --- LÓGICA DE ESCALAÇÃO ---
  void addPlayer(int slotIndex, FantasyPlayer player) {
    if (!_isMarketOpen) return;
    
    if (_lineup.values.any((p) => p.playerId == player.playerId)) {
      _errorMessage = "${player.name} já está no seu time.";
      notifyListeners();
      return;
    }

    _lineup[slotIndex] = player;
    _calculateFinancials();
    _autoSave();
  }

  void removePlayer(int slotIndex) {
    if (!_isMarketOpen) return;
    final p = _lineup.remove(slotIndex);
    if (p != null && _captainId == p.playerId) _captainId = null;
    _calculateFinancials();
    _autoSave();
  }

  void sellAll() {
    if (!_isMarketOpen) return;
    _lineup.clear();
    _captainId = null;
    _currentBalance = _totalPatrimony;
    _teamPrice = 0.0;
    _autoSave();
  }

  void setCaptain(String playerId) {
    if (!_isMarketOpen) return;
    _captainId = (_captainId == playerId) ? null : playerId;
    _autoSave();
  }

  void _calculateFinancials() {
    double price = 0;
    for (var p in _lineup.values) {
      price += p.currentPrice;
    }
    _teamPrice = price;
    _currentBalance = _totalPatrimony - _teamPrice;
    notifyListeners();
  }

  // --- AUTO-SAVE DIRETO ---
  Future<void> _autoSave() async {
    if (!_isMarketOpen || _userId == null) return;
    
    _isSaving = true;
    notifyListeners();

    try {
      final playerIds = _lineup.values.map((p) => p.playerId).toList();
      
      await _firestore.collection('fantasy_teams').doc(_userId).update({
        'lineup_player_ids': playerIds,
        'captain_id': _captainId,
        'balance': _currentBalance,
        'updated_at': FieldValue.serverTimestamp(),
      });
      _expectedOldTeamCost = _teamPrice;
    } catch (e) {
      debugPrint("Erro no Auto-Save: $e");
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void clearMessages() { 
    _errorMessage = null; 
    _successMessage = null; 
  }

  void _checkScoutSubscription(String seasonId) {
    _scoutSub?.cancel();
    if (!_isMarketOpen && _lineup.isNotEmpty) {
      final ids = _lineup.values.map((p) => p.playerId).toList();
      _scoutSub = _scoutService.streamLiveScores(seasonId, _currentRound, ids).listen((scores) {
        _liveScores = scores;
        notifyListeners();
      });
    }
  }

  @override
  void dispose() { 
    _marketSub?.cancel(); 
    _teamSub?.cancel(); 
    _scoutSub?.cancel(); 
    super.dispose(); 
  }
}