import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fantasy_models.dart';
import '../models/match_model.dart';
import '../repositories/fantasy_repository.dart';
import '../services/fantasy_scout_service.dart';
import '../services/analytics_service.dart';
import '../services/firestore_cache_service.dart';
import '../services/match_service.dart';

enum SyncStatus { idle, syncing, saved, error }

class FantasyLineupViewModel extends ChangeNotifier with WidgetsBindingObserver {
  final FantasyRepository _repository = FantasyRepository();
  final FantasyScoutService _scoutService = FantasyScoutService();
  final MatchService _matchService = MatchService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  FantasyLineupViewModel() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_hasUnsavedChanges) {
        _performSave();
      }
    }
  }

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _successMessage;
  String? _userId;
  String? _seasonId;

  bool _isDisposed = false; 
  bool _hasUnsavedChanges = false; 
  Timer? _debounceTimer;
  SyncStatus _syncStatus = SyncStatus.idle;

  FantasyGameConfig _gameConfig = FantasyGameConfig.defaults();
  FantasyTeam? _team;
  final Map<int, FantasyPlayer> _lineup = {}; 
  final Map<int, FantasyPlayer> _bench = {};
  String? _captainId;
  String? _luxuryReserveId;
  
  double _currentBalance = 0.0;
  double _teamPrice = 0.0;
  double _totalPatrimony = 0.0;
  double _expectedOldTeamCost = 0.0;

  bool _isMarketOpen = true;
  DateTime? _closingTime;
  int _currentRound = 1;
  Map<String, FantasyScoutDetail> _liveScores = {};

  StreamSubscription? _marketSub;
  StreamSubscription? _teamSub; 
  StreamSubscription? _scoutSub;
  StreamSubscription? _roundMatchesSub;
  List<MatchModel> _roundMatches = [];
  bool _areAllMatchesFinished = false;

  String? get userId => _userId;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  bool get isMarketOpen => _isMarketOpen;
  DateTime? get closingTime => _closingTime;
  int get currentRound => _currentRound;
  SyncStatus get syncStatus => _syncStatus;
  Map<int, FantasyPlayer> get lineup => _lineup;
  Map<int, FantasyPlayer> get bench => _bench;
  String? get captainId => _captainId;
  String? get luxuryReserveId => _luxuryReserveId;
  double get currentBalance => _currentBalance;
  double get totalPatrimony => _totalPatrimony;
  double get teamPrice => _teamPrice;

  /// Valor total da escalação de titulares atual
  double get lineupPrice {
    if (_teamPrice > 0) return _teamPrice;
    return _lineup.values.fold(0.0, (total, p) => total + p.currentPrice);
  }
  Map<String, FantasyScoutDetail> get liveScores => _liveScores;
  FantasyGameConfig get gameConfig => _gameConfig;
  List<MatchModel> get roundMatches => _roundMatches;
  bool get areAllMatchesFinished => _areAllMatchesFinished;
  FantasyTeam? get team => _team;

  /// Retorna verdadeiro quando a rodada está no período de validação de scouts:
  /// o mercado está fechado e todos os jogos da rodada foram encerrados.
  bool get isScoutsValidationPeriod => !_isMarketOpen && _areAllMatchesFinished;

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

  final List<Map<String, dynamic>> slotsConfig = [
    {'index': 1, 'pos': 'Goleiro'},
    {'index': 2, 'pos': 'Fixo'},
    {'index': 3, 'pos': 'Ala'},
    {'index': 4, 'pos': 'Ala'},
    {'index': 5, 'pos': 'Pivô'},
    {'index': 6, 'pos': 'Técnico'},
  ];

  final List<Map<String, dynamic>> benchSlotsConfig = [
    {'index': 11, 'pos': 'Goleiro'},
    {'index': 12, 'pos': 'Fixo'},
    {'index': 13, 'pos': 'Ala'},
    {'index': 15, 'pos': 'Pivô'},
    {'index': 16, 'pos': 'Técnico'},
  ];

  void _updateMarketStatus(Map<String, dynamic> data, String seasonId, {bool notify = true}) {
    final bool isOpenFlag = data['is_open'] ?? true;
    final dynamic closingRaw = data['closing_time'];
    _closingTime = closingRaw is Timestamp ? closingRaw.toDate() : null;
    final bool isExpired = _closingTime != null && DateTime.now().isAfter(_closingTime!);

    _isMarketOpen = isOpenFlag && !isExpired;
    _currentRound = data['current_round'] ?? 1;
    _checkScoutSubscription(seasonId);

    if (!_isMarketOpen) {
      _roundMatchesSub?.cancel();
      _roundMatchesSub = _matchService.streamRoundMatches(seasonId, _currentRound).listen((matches) {
        if (_isDisposed) return;
        _roundMatches = matches;
        _areAllMatchesFinished = matches.isNotEmpty && matches.every((m) => m.isFinished);
        notifyListeners();
      }, onError: (e) {
        debugPrint("Erro ao escutar partidas na escalação: $e");
      });
    } else {
      _roundMatchesSub?.cancel();
      _roundMatches = [];
      _areAllMatchesFinished = false;
    }

    if (notify && !_isDisposed) notifyListeners();
  }

  void init(String userId, String seasonId) {
    _userId = userId;
    _seasonId = seasonId;

    // ⚡ INSTANT LOAD: Sincroniza imediatamente com o time e status em cache se disponíveis
    final cachedMarket = _repository.cachedMarketStatus;
    if (cachedMarket != null) {
      _updateMarketStatus(cachedMarket, seasonId, notify: false);
    }

    final cachedTeam = _repository.getCachedUserTeam(userId);
    if (cachedTeam != null) {
      _syncLocalStateWithDatabase(cachedTeam, seasonId);
    } else {
      _isLoading = true;
      notifyListeners();
    }

    // 🚨 CORREÇÃO DO BUG & FINOPS: Busca o status inicial do cache local para não pagar leitura dupla 
    // (a leitura real do servidor já será cobrada ao se conectar no .snapshots() logo abaixo).
    FirestoreCacheService.getDocumentWithCache(
      docRef: _firestore.collection('fantasy_config').doc('status'),
      cacheKey: 'fantasy_status',
      ttl: const Duration(minutes: 5),
    ).then((doc) {
      if (doc.exists && doc.data() != null) {
        _updateMarketStatus(doc.data() as Map<String, dynamic>, seasonId);
      }
    });

    FirestoreCacheService.getDocumentWithCache(
      docRef: _firestore.collection('fantasy_config').doc('rules'),
      cacheKey: 'fantasy_rules',
      ttl: const Duration(hours: 24),
    ).then((doc) {
      if (doc.exists && doc.data() != null) {
        _gameConfig = FantasyGameConfig.fromMap(doc.data() as Map<String, dynamic>);
        if (!_isDisposed) notifyListeners();
      }
    });

    _marketSub?.cancel();
    _marketSub = _repository.streamMarketStatus().listen((status) {
      _updateMarketStatus(status, seasonId);
    });

    _teamSub?.cancel();
    _teamSub = _repository.streamUserTeam(userId).listen((team) async {
      if (team != null) {
        await _syncLocalStateWithDatabase(team, seasonId);
      } else {
        _isLoading = false;
        if (!_isDisposed) notifyListeners();
      }
    });
  }

  Future<void> _syncLocalStateWithDatabase(FantasyTeam team, String seasonId) async {
    _team = team;
    _currentBalance = team.currentBalance;
    _captainId = team.captainId;
    _luxuryReserveId = team.luxuryReserveId;
    _totalPatrimony = team.teamValue;

    final allIds = <String>{...team.lineupPlayerIds, ...team.benchPlayerIds}.toList();
    if (allIds.isNotEmpty) {
      try {
        final players = await _repository.getPlayersByIds(allIds);
        
        _lineup.clear();
        _bench.clear();
        double calculatedTeamPrice = 0.0;

        for (var p in players) {
          if (team.lineupSlots != null && team.lineupSlots!.isNotEmpty) {
            if (team.lineupPlayerIds.contains(p.playerId)) {
              calculatedTeamPrice += p.currentPrice;
              team.lineupSlots!.forEach((slot, id) {
                final parsedSlot = int.tryParse(slot);
                if (parsedSlot != null && id == p.playerId) _lineup[parsedSlot] = p;
              });
            } else if (team.benchPlayerIds.contains(p.playerId)) {
              team.benchSlots?.forEach((slot, id) {
                final parsedSlot = int.tryParse(slot);
                if (parsedSlot != null && id == p.playerId) _bench[parsedSlot] = p;
              });
            }
          } else {
            // BACKWARD COMPATIBILITY
            final pos = p.position.toLowerCase();

            if (team.lineupPlayerIds.contains(p.playerId)) {
              calculatedTeamPrice += p.currentPrice;
              if (pos.contains('gol')) _lineup[1] = p;
              else if (pos.contains('fix')) _lineup[2] = p;
              else if (pos.contains('piv')) _lineup[5] = p;
              else if (pos.contains('téc')) _lineup[6] = p;
              else if (pos.contains('ala')) {
                if (!_lineup.containsKey(3)) _lineup[3] = p; else _lineup[4] = p;
              }
            } else if (team.benchPlayerIds.contains(p.playerId)) {
              if (pos.contains('gol')) _bench[11] = p;
              else if (pos.contains('fix')) _bench[12] = p;
              else if (pos.contains('ala')) _bench[13] = p;
              else if (pos.contains('piv')) _bench[15] = p;
              else if (pos.contains('téc')) _bench[16] = p;
            }
          }
        }
        _teamPrice = calculatedTeamPrice;
        _expectedOldTeamCost = calculatedTeamPrice;
      } catch (e) {
        _errorMessage = "Falha ao carregar detalhes dos atletas: $e";
      }
    } else {
      _lineup.clear();
      _bench.clear();
      _teamPrice = 0.0;
    }

    _checkScoutSubscription(seasonId);
    _isLoading = false;
    if (!_isDisposed) notifyListeners();
  }

  void addPlayer(int slotIndex, FantasyPlayer player) {
    if (!_isMarketOpen) return;
    
    if (_lineup.values.any((p) => p.playerId == player.playerId) || _bench.values.any((p) => p.playerId == player.playerId)) {
      _errorMessage = "${player.name} já está no seu time ou banco.";
      if (!_isDisposed) notifyListeners();
      return;
    }

    final double oldPrice = _lineup[slotIndex]?.currentPrice ?? 0.0;
    final double netCost = player.currentPrice - oldPrice;
    if (_currentBalance - netCost < -0.01) {
      final double needed = double.parse((netCost - _currentBalance).toStringAsFixed(2));
      _errorMessage = "Saldo insuficiente para contratar ${player.name} (Faltam C\$ ${needed.toStringAsFixed(2)}).";
      if (!_isDisposed) notifyListeners();
      return;
    }

    _lineup[slotIndex] = player;
    HapticFeedback.lightImpact();
    
    // Validar banco existente (se um titular foi adicionado e o banco dessa posição ficou mais caro)
    _validateBenchAfterLineupChange(player.position);

    _calculateFinancials();
    _autoSave();
  }
  
  bool canAddBenchPlayer(FantasyPlayer player) {
    final pos = player.position;
    final startersOfPos = _lineup.values
        .where((p) => matchesPosition(p.position, p.secondaryPosition, pos))
        .toList();
    if (startersOfPos.isEmpty) {
      _errorMessage = "Você precisa escalar um titular dessa posição primeiro.";
      if (!_isDisposed) notifyListeners();
      return false;
    }
    final double minPrice = startersOfPos.map((p) => p.currentPrice).reduce((a, b) => a < b ? a : b);
    if (player.currentPrice > minPrice) {
      _errorMessage = "O reserva deve custar no máximo C\$ ${minPrice.toStringAsFixed(2)} (titular mais barato da posição).";
      if (!_isDisposed) notifyListeners();
      return false;
    }
    return true;
  }

  void addBenchPlayer(int slotIndex, FantasyPlayer player) {
    if (!_isMarketOpen) return;
    
    if (_lineup.values.any((p) => p.playerId == player.playerId) || _bench.values.any((p) => p.playerId == player.playerId)) {
      _errorMessage = "${player.name} já está no seu time ou banco.";
      if (!_isDisposed) notifyListeners();
      return;
    }

    if (!canAddBenchPlayer(player)) return;

    _bench[slotIndex] = player;
    HapticFeedback.lightImpact();
    _calculateFinancials();
    _autoSave();
  }

  void _validateBenchAfterLineupChange(String position) {
    final startersOfPos = _lineup.values
        .where((p) => matchesPosition(p.position, p.secondaryPosition, position))
        .toList();
    final benchPlayerEntry = _bench.entries
        .where((e) => matchesPosition(e.value.position, e.value.secondaryPosition, position))
        .firstOrNull;
    
    if (benchPlayerEntry != null) {
      if (startersOfPos.isEmpty) {
        removeBenchPlayer(benchPlayerEntry.key);
      } else {
        final double minPrice = startersOfPos.map((p) => p.currentPrice).reduce((a, b) => a < b ? a : b);
        if (benchPlayerEntry.value.currentPrice > minPrice) {
          removeBenchPlayer(benchPlayerEntry.key);
          _errorMessage = "Reserva de ${position} removido pois ficou mais caro que o titular mais barato.";
          if (!_isDisposed) notifyListeners();
        }
      }
    }
  }

  void removePlayer(int slotIndex) {
    if (!_isMarketOpen) return;
    final p = _lineup.remove(slotIndex);
    if (p != null) {
      HapticFeedback.lightImpact();
      if (_captainId == p.playerId) _captainId = null;
      _validateBenchAfterLineupChange(p.position);
    }
    _calculateFinancials();
    _autoSave();
  }

  void removeBenchPlayer(int slotIndex) {
    if (!_isMarketOpen) return;
    final p = _bench.remove(slotIndex);
    if (p != null) {
      HapticFeedback.lightImpact();
      if (_luxuryReserveId == p.playerId) _luxuryReserveId = null;
    }
    _calculateFinancials();
    _autoSave();
  }

  void sellAll() {
    if (!_isMarketOpen) return;
    _lineup.clear();
    _bench.clear();
    _captainId = null;
    _luxuryReserveId = null;
    _currentBalance = _totalPatrimony;
    _teamPrice = 0.0;
    _autoSave();
  }

  void setCaptain(String playerId) {
    if (!_isMarketOpen) return;
    _captainId = (_captainId == playerId) ? null : playerId;
    HapticFeedback.mediumImpact();
    _autoSave();
  }

  void setLuxuryReserve(String playerId) {
    if (!_isMarketOpen) return;
    _luxuryReserveId = (_luxuryReserveId == playerId) ? null : playerId;
    HapticFeedback.mediumImpact();
    _autoSave();
  }

  void _calculateFinancials() {
    double price = 0;
    for (var p in _lineup.values) price += p.currentPrice;
    // Reservas não reduzem o patrimônio
    _teamPrice = price;
    _currentBalance = _totalPatrimony - _teamPrice;
    if (!_isDisposed) notifyListeners();
  }

  void _autoSave() {
    if (!_isMarketOpen || _userId == null) return;
    
    _hasUnsavedChanges = true;
    _isSaving = true;
    _syncStatus = SyncStatus.syncing;
    if (!_isDisposed) notifyListeners();

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _debounceTimer = Timer(const Duration(seconds: 2), () {
      _performSave();
    });
  }

  Future<void> _performSave() async {
    if (!_hasUnsavedChanges || _userId == null) return;

    try {
      final playerIds = _lineup.values.map((p) => p.playerId).toList();
      final benchIds = _bench.values.map((p) => p.playerId).toList();
      
      final Map<String, String> lineupSlots = {};
      _lineup.forEach((key, value) => lineupSlots[key.toString()] = value.playerId);
      
      final Map<String, String> benchSlots = {};
      _bench.forEach((key, value) => benchSlots[key.toString()] = value.playerId);
      
      final result = await _repository.saveLineup(
        userId: _userId!,
        playerIds: playerIds,
        benchIds: benchIds,
        lineupSlots: lineupSlots,
        benchSlots: benchSlots,
        captainId: _captainId,
        luxuryReserveId: _luxuryReserveId,
        expectedOldTeamCost: _expectedOldTeamCost,
        newTeamCost: _teamPrice,
      );

      if (result == "Sucesso") {
        _expectedOldTeamCost = _teamPrice;
        _hasUnsavedChanges = false; 
        _syncStatus = SyncStatus.saved;

        AnalyticsService.logLineupSaved(_teamPrice, _captainId != null);
        
        Future.delayed(const Duration(seconds: 3), () {
          if (_syncStatus == SyncStatus.saved && !_hasUnsavedChanges) {
            _syncStatus = SyncStatus.idle;
            if (!_isDisposed) notifyListeners();
          }
        });
      } else {
        _errorMessage = result;
        _syncStatus = SyncStatus.error;
        if (_team != null && _seasonId != null) {
          await _syncLocalStateWithDatabase(_team!, _seasonId!);
        }
        Future.delayed(const Duration(seconds: 4), () {
          if (_syncStatus == SyncStatus.error && !_hasUnsavedChanges) {
            _syncStatus = SyncStatus.idle;
            if (!_isDisposed) notifyListeners();
          }
        });
      }
      
    } catch (e) {
      debugPrint("Erro no Auto-Save Debounce: $e");
      _errorMessage = "Erro ao salvar escalação: $e";
      _syncStatus = SyncStatus.error;
      if (_team != null && _seasonId != null) {
        await _syncLocalStateWithDatabase(_team!, _seasonId!);
      }
      Future.delayed(const Duration(seconds: 3), () {
        if (_syncStatus == SyncStatus.error && !_hasUnsavedChanges) {
          _syncStatus = SyncStatus.idle;
          if (!_isDisposed) notifyListeners();
        }
      });
    } finally {
      _isSaving = false;
      if (!_isDisposed) notifyListeners(); 
    }
  }

  void clearMessages() { 
    _errorMessage = null; 
    _successMessage = null; 
  }

  Future<void> suggestLineup() async {
    if (!_isMarketOpen) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      // 1. FinOps: O _repository.getAllPlayers() possui cache em memória para economizar acessos ao Firebase
      final allPlayers = await _repository.getAllPlayers();
      
      // 2. Filtrar apenas prováveis
      List<FantasyPlayer> validPlayers = allPlayers.where((p) => p.status == 'probable').toList();
      
      // Fallback de contingência caso hajam poucos prováveis (mercado não atualizado, etc)
      if (validPlayers.length < 15) {
         validPlayers = allPlayers.where((p) => p.status != 'suspended' && p.status != 'injured').toList();
      }

      // Separar por posições
      List<FantasyPlayer> goleiros = validPlayers.where((p) => p.position.toLowerCase().contains('gol')).toList();
      List<FantasyPlayer> fixos = validPlayers.where((p) => p.position.toLowerCase().contains('fix')).toList();
      List<FantasyPlayer> alas = validPlayers.where((p) => p.position.toLowerCase().contains('ala')).toList();
      List<FantasyPlayer> pivos = validPlayers.where((p) => p.position.toLowerCase().contains('piv')).toList();
      List<FantasyPlayer> tecnicos = validPlayers.where((p) => p.position.toLowerCase().contains('téc')).toList();

      // Introduzir um fator de aleatoriedade para variar a escalação entre as tentativas
      // Favorecendo ainda quem tem média alta, mas não de forma estritamente determinística
      final random = math.Random();
      double randomizedScore(FantasyPlayer p) {
        // +- 30% de variação na média de pontos
        double noise = 0.7 + (random.nextDouble() * 0.6); 
        return (p.averageScore > 0 ? p.averageScore : 1.0) * noise;
      }

      // Ordenar por média ponderada aleatoriamente
      goleiros.sort((a, b) => randomizedScore(b).compareTo(randomizedScore(a)));
      fixos.sort((a, b) => randomizedScore(b).compareTo(randomizedScore(a)));
      alas.sort((a, b) => randomizedScore(b).compareTo(randomizedScore(a)));
      pivos.sort((a, b) => randomizedScore(b).compareTo(randomizedScore(a)));
      tecnicos.sort((a, b) => randomizedScore(b).compareTo(randomizedScore(a)));

      if (goleiros.isEmpty || fixos.isEmpty || alas.length < 2 || pivos.isEmpty || tecnicos.isEmpty) {
        _errorMessage = "Não há jogadores suficientes para sugerir uma escalação.";
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Limpa tudo antes de começar
      sellAll();

      // Seleção Gulosa (Greedy) Inicial
      List<FantasyPlayer> starters = [];
      int golIdx = 0, fixIdx = 0, ala1Idx = 0, ala2Idx = 1, pivIdx = 0, tecIdx = 0;
      
      bool foundTeam = false;
      int maxAttempts = 100;
      
      while (maxAttempts > 0) {
        starters = [
          goleiros[golIdx],
          fixos[fixIdx],
          alas[ala1Idx],
          alas[ala2Idx],
          pivos[pivIdx],
          tecnicos[tecIdx],
        ];
        
        double currentCost = starters.fold(0.0, (sum, p) => sum + p.currentPrice);
        
        if (currentCost <= _totalPatrimony) {
          foundTeam = true;
          break;
        }

        // Tentar rebaixar o jogador mais caro do time escolhido
        starters.sort((a, b) => b.currentPrice.compareTo(a.currentPrice));
        bool downgraded = false;

        for (var expensivePlayer in starters) {
          final pos = expensivePlayer.position.toLowerCase();
          
          if (pos.contains('gol') && golIdx + 1 < goleiros.length) { golIdx++; downgraded = true; break; }
          if (pos.contains('fix') && fixIdx + 1 < fixos.length) { fixIdx++; downgraded = true; break; }
          if (pos.contains('piv') && pivIdx + 1 < pivos.length) { pivIdx++; downgraded = true; break; }
          if (pos.contains('téc') && tecIdx + 1 < tecnicos.length) { tecIdx++; downgraded = true; break; }
          if (pos.contains('ala')) {
            // Ala precisa de atenção pois temos dois índices
            if (expensivePlayer.playerId == alas[ala1Idx].playerId) {
               int nextIdx = ala1Idx + 1;
               while (nextIdx == ala2Idx && nextIdx < alas.length) nextIdx++; // Pula se já for o ala2
               if (nextIdx < alas.length) { ala1Idx = nextIdx; downgraded = true; break; }
            } else if (expensivePlayer.playerId == alas[ala2Idx].playerId) {
               int nextIdx = ala2Idx + 1;
               while (nextIdx == ala1Idx && nextIdx < alas.length) nextIdx++; // Pula se já for o ala1
               if (nextIdx < alas.length) { ala2Idx = nextIdx; downgraded = true; break; }
            }
          }
        }
        
        if (!downgraded) break; // Não tem mais quem baratear
        maxAttempts--;
      }

      if (!foundTeam) {
        _errorMessage = "Seu patrimônio é muito baixo para sugerir um time.";
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Adicionar Titulares no Time
      _lineup[1] = goleiros[golIdx];
      _lineup[2] = fixos[fixIdx];
      _lineup[3] = alas[ala1Idx];
      _lineup[4] = alas[ala2Idx];
      _lineup[5] = pivos[pivIdx];
      _lineup[6] = tecnicos[tecIdx];

      // Definir Capitão (maior média)
      _captainId = starters.reduce((a, b) => a.averageScore > b.averageScore ? a : b).playerId;

      // 3. Selecionar Reservas (Focando na maior média com preço menor que o titular mais barato)
      void pickBench(int slot, List<FantasyPlayer> allPos, String posLabel) {
        final posStarters = _lineup.values.where((p) => p.position.toLowerCase().contains(posLabel)).toList();
        if (posStarters.isEmpty) return;
        final minPrice = posStarters.map((p) => p.currentPrice).reduce((a, b) => a < b ? a : b);
        
        // Pega os válidos que não estão no time e cabem na regra do reserva
        final candidates = allPos.where((p) => p.currentPrice <= minPrice && !_lineup.values.any((s) => s.playerId == p.playerId)).toList();
        
        if (candidates.isNotEmpty) {
           // Já estão ordenados por média de pontos
           _bench[slot] = candidates.first;
        }
      }

      pickBench(11, goleiros, 'gol');
      pickBench(12, fixos, 'fix');
      pickBench(13, alas, 'ala');
      pickBench(15, pivos, 'piv');
      pickBench(16, tecnicos, 'téc');

      _successMessage = "Escalação mágica gerada com sucesso!";
      HapticFeedback.heavyImpact();
      _calculateFinancials();
      _autoSave();

    } catch (e) {
      _errorMessage = "Erro ao sugerir escalação: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshPlayers() async {
    if (_team == null) return;
    try {
      final allIds = <String>{..._team!.lineupPlayerIds, ..._team!.benchPlayerIds}.toList();
      if (allIds.isEmpty) return;

      final players = await _repository.getPlayersByIds(allIds, forceRefresh: true);
      
      _lineup.clear();
      _bench.clear();
      for (var p in players) {
        final pos = p.position.toLowerCase();
        if (_team!.lineupPlayerIds.contains(p.playerId)) {
          if (pos.contains('gol')) _lineup[1] = p;
          else if (pos.contains('fix')) _lineup[2] = p;
          else if (pos.contains('piv')) _lineup[5] = p;
          else if (pos.contains('téc')) _lineup[6] = p;
          else if (pos.contains('ala')) {
            if (!_lineup.containsKey(3)) _lineup[3] = p; else _lineup[4] = p;
          }
        } else if (_team!.benchPlayerIds.contains(p.playerId)) {
            if (pos.contains('gol')) _bench[11] = p;
            else if (pos.contains('fix')) _bench[12] = p;
            else if (pos.contains('ala')) _bench[13] = p;
            else if (pos.contains('piv')) _bench[15] = p;
            else if (pos.contains('téc')) _bench[16] = p;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Erro ao recarregar jogadores: $e");
    }
  }

  void _checkScoutSubscription(String seasonId) async {
    _scoutSub?.cancel();
    if (!_isMarketOpen) {
      if (_lineup.isNotEmpty) {
        _scoutSub = _scoutService.streamLiveScores(seasonId, _currentRound).listen((scores) {
          _liveScores = scores;
          if (!_isDisposed) notifyListeners();
        });
      }
    } else {
      // Se mercado está aberto, busca os scouts da rodada anterior (para exibir como histórico detalhado)
      if (_currentRound > 1) {
        final scores = await _scoutService.getLiveScores(seasonId, _currentRound - 1);
        _liveScores = scores;
        if (!_isDisposed) notifyListeners();
      } else {
        _liveScores = {};
        if (!_isDisposed) notifyListeners();
      }
    }
  }

  @override
  void dispose() { 
    WidgetsBinding.instance.removeObserver(this);
    _isDisposed = true;
    _marketSub?.cancel(); 
    _teamSub?.cancel(); 
    _scoutSub?.cancel(); 
    _roundMatchesSub?.cancel();
    _debounceTimer?.cancel();
    
    if (_hasUnsavedChanges) {
      _performSave();
    }
    
    super.dispose(); 
  }
}