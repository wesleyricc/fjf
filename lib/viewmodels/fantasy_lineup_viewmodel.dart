import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/fantasy_models.dart';
import '../repositories/fantasy_repository.dart';
import '../services/fantasy_scout_service.dart';

class FantasyLineupViewModel extends ChangeNotifier {
  final FantasyRepository _repository = FantasyRepository();
  final FantasyScoutService _scoutService = FantasyScoutService();

  // --- ESTADO ---
  bool _isLoading = true;
  String? _errorMessage;
  String? _successMessage;

  // Dados do Time
  FantasyTeam? _team;
  final Map<int, FantasyPlayer> _lineup = {}; // Mapa de Slots (1 a 6)
  String? _captainId;
  
  // Financeiro
  double _currentBalance = 0.0;
  double _teamPrice = 0.0;
  double _totalPatrimony = 0.0;
  
  // Controle de Integridade (Necessário para a Transação no Servidor)
  double _expectedOldTeamCost = 0.0;

  // Mercado & Scouts
  bool _isMarketOpen = true;
  int _currentRound = 1;
  Map<String, FantasyScoutDetail> _liveScores = {};

  StreamSubscription? _marketSub;
  StreamSubscription? _scoutSub;

  // --- GETTERS ---
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  
  bool get isMarketOpen => _isMarketOpen;
  int get currentRound => _currentRound;
  
  Map<int, FantasyPlayer> get lineup => _lineup;
  String? get captainId => _captainId;
  
  double get currentBalance => _currentBalance;
  double get teamPrice => _teamPrice;
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
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // 1. Monitora Mercado (Via Repository)
    _marketSub = _repository.streamMarketStatus().listen((status) {
      _isMarketOpen = status['is_open'] ?? true;
      _currentRound = status['current_round'] ?? 1;
      _checkScoutSubscription(seasonId);
      notifyListeners();
    });

    // 2. Carrega Time
    _loadTeamData(userId, seasonId);
  }

  Future<void> _loadTeamData(String userId, String seasonId) async {
    try {
      final team = await _repository.getUserTeam(userId, forceRefresh: true);
      
      if (team != null) {
        _team = team;
        _currentBalance = team.currentBalance;
        _captainId = team.captainId;
        
        if (team.lineupPlayerIds.isNotEmpty) {
          final players = await _repository.getPlayersByIds(team.lineupPlayerIds);
          
          _lineup.clear();
          double calculatedTeamPrice = 0.0;

          for (var p in players) {
            calculatedTeamPrice += p.currentPrice;
            if (p.position == 'Goleiro') _lineup[1] = p;
            else if (p.position == 'Fixo') _lineup[2] = p;
            else if (p.position == 'Pivô') _lineup[5] = p;
            else if (p.position == 'Técnico') _lineup[6] = p;
            else if (p.position == 'Ala') {
              if (!_lineup.containsKey(3)) _lineup[3] = p;
              else _lineup[4] = p;
            }
          }
          _teamPrice = calculatedTeamPrice;
          // Armazena o custo que o time tinha no banco para validação de transação posterior
          _expectedOldTeamCost = calculatedTeamPrice;
        }

        // Define patrimônio base
        _totalPatrimony = team.teamValue;
        
        _checkScoutSubscription(seasonId);
      }
    } catch (e) {
      _errorMessage = "Erro ao carregar time: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- LÓGICA DE ESCALAÇÃO ---

  void addPlayer(int slotIndex, FantasyPlayer player) {
    if (!_isMarketOpen) {
      _errorMessage = "Mercado Fechado!";
      notifyListeners();
      return;
    }

    bool isDuplicate = _lineup.entries.any((entry) => 
      entry.key != slotIndex && entry.value.playerId == player.playerId
    );

    if (isDuplicate) {
      _errorMessage = "${player.name} já está escalado.";
      notifyListeners();
      return;
    }

    if (_lineup.containsKey(slotIndex)) {
      final oldPlayer = _lineup[slotIndex]!;
      _currentBalance += oldPlayer.currentPrice;
      _teamPrice -= oldPlayer.currentPrice;
      if (_captainId == oldPlayer.playerId) _captainId = null;
    }

    _currentBalance -= player.currentPrice;
    _teamPrice += player.currentPrice;
    _lineup[slotIndex] = player;

    if (_captainId == null && player.position != 'Técnico') {
      _captainId = player.playerId;
    }

    notifyListeners();
  }

  void removePlayer(int slotIndex) {
    if (!_isMarketOpen || !_lineup.containsKey(slotIndex)) return;

    final player = _lineup[slotIndex]!;
    _currentBalance += player.currentPrice;
    _teamPrice -= player.currentPrice;
    
    if (_captainId == player.playerId) _captainId = null;
    
    _lineup.remove(slotIndex);
    notifyListeners();
  }

  void sellAll() {
    if (!_isMarketOpen) return;
    _lineup.clear();
    _captainId = null;
    _currentBalance = _totalPatrimony; 
    _teamPrice = 0.0;
    notifyListeners();
  }

  void setCaptain(String playerId) {
    if (!_isMarketOpen) return;
    _captainId = playerId;
    notifyListeners();
  }

  Future<void> saveLineup(String userId) async {
    if (!_isMarketOpen) return;
    
    if (_lineup.length < 6) {
      _errorMessage = "Sua equipe deve ter 6 integrantes.";
      notifyListeners();
      return;
    }

    if (_captainId == null) {
      _errorMessage = "Selecione um capitão.";
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final playerIds = _lineup.values.map((p) => p.playerId).toList();
      
      // CORREÇÃO: Chama o repositório com os parâmetros de validação de custo
      final result = await _repository.saveLineup(
        userId: userId,
        playerIds: playerIds,
        captainId: _captainId,
        expectedOldTeamCost: _expectedOldTeamCost,
        totalCost: _teamPrice, // O novo custo total da equipe escalada
      );

      if (result == "Sucesso") {
        _successMessage = "Time escalado com sucesso!";
        // Atualiza o custo antigo esperado para a próxima edição sem precisar de refresh
        _expectedOldTeamCost = _teamPrice;
      } else {
        _errorMessage = result;
      }
    } catch (e) {
      _errorMessage = "Erro ao salvar: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
  }

  // --- SCOUTS ---
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
    _scoutSub?.cancel();
    super.dispose();
  }
}