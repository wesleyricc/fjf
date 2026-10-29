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

class FantasyLineupViewModel extends ChangeNotifier
    with WidgetsBindingObserver {
  final FantasyRepository _repository = FantasyRepository();
  final FantasyScoutService _scoutService = FantasyScoutService();
  final MatchService _matchService = MatchService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  FantasyLineupViewModel() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
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

  /// Indica se há pelo menos um jogador no banco elegível para Reserva de Luxo (exclui Técnico - slot 16)
  bool get hasEligibleLuxuryBench => _bench.entries.any(
        (e) => e.key != 16 && normalizePosition(e.value.position) != 'tecnico',
      );

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

  static bool matchesPosition(
      String playerPos, String? secondaryPos, String targetPos) {
    final targetNorm = normalizePosition(targetPos);
    if (normalizePosition(playerPos) == targetNorm) return true;
    if (secondaryPos != null &&
        secondaryPos.isNotEmpty &&
        normalizePosition(secondaryPos) == targetNorm) return true;
    return false;
  }

  static List<int> starterSlotsForPosition(String pos) {
    switch (normalizePosition(pos)) {
      case 'goleiro':
        return const [1];
      case 'fixo':
        return const [2];
      case 'ala':
        return const [3, 4];
      case 'pivo':
        return const [5];
      case 'tecnico':
        return const [6];
      default:
        return const [];
    }
  }

  static int? benchSlotForPosition(String pos) {
    switch (normalizePosition(pos)) {
      case 'goleiro':
        return 11;
      case 'fixo':
        return 12;
      case 'ala':
        return 13;
      case 'pivo':
        return 15;
      case 'tecnico':
        return 16;
      default:
        return null;
    }
  }

  static String? positionForSlot(int slotIndex) {
    switch (slotIndex) {
      case 1:
      case 11:
        return 'Goleiro';
      case 2:
      case 12:
        return 'Fixo';
      case 3:
      case 4:
      case 13:
        return 'Ala';
      case 5:
      case 15:
        return 'Pivô';
      case 6:
      case 16:
        return 'Técnico';
      default:
        return null;
    }
  }

  /// Retorna os titulares escalados especificamente nos slots da posição informada
  List<FantasyPlayer> getStartersForPosition(String pos) {
    final slots = starterSlotsForPosition(pos);
    final result = <FantasyPlayer>[];
    for (final s in slots) {
      final p = _lineup[s];
      if (p != null) result.add(p);
    }
    return result;
  }

  /// Calcula a pontuação parcial considerando substituições normais, Reserva de Luxo e herança de Capitão
  double get partialScore {
    if (_isMarketOpen || _lineup.isEmpty) return 0.0;

    final Set<String> playedIds = {..._liveScores.keys};
    for (final m in _roundMatches) {
      if (m.status == 'in_progress' || m.status == 'finished') {
        playedIds.addAll(m.lineupPlayed);
      }
    }
    for (final entry in _liveScores.entries) {
      if (entry.value.totalScore != 0 ||
          entry.value.goals > 0 ||
          entry.value.assists > 0 ||
          entry.value.yellows > 0 ||
          entry.value.reds > 0 ||
          entry.value.difficultSaves > 0 ||
          entry.value.cleanSheets > 0 ||
          entry.value.motm > 0) {
        playedIds.add(entry.key);
      }
    }

    final Map<int, FantasyPlayer> activeLineup =
        Map<int, FantasyPlayer>.from(_lineup);
    String? activeCaptain = _captainId;

    for (final bConfig in benchSlotsConfig) {
      final int benchSlot = bConfig['index'] as int;
      final String posLabel = bConfig['pos'] as String;
      final benchPlayer = _bench[benchSlot];
      if (benchPlayer == null) continue;

      final starterSlots = starterSlotsForPosition(posLabel);
      final currentStarters = starterSlots
          .where((s) => activeLineup.containsKey(s))
          .map((s) => MapEntry(s, activeLineup[s]!))
          .toList();
      if (currentStarters.isEmpty) continue;

      final bool benchPlayed = playedIds.contains(benchPlayer.playerId) ||
          (_liveScores.containsKey(benchPlayer.playerId) &&
              normalizePosition(posLabel) == 'tecnico' &&
              (_liveScores[benchPlayer.playerId]?.totalScore ?? 0) != 0);
      if (!benchPlayed) continue;

      bool starterHasPlayed(FantasyPlayer p) {
        if (playedIds.contains(p.playerId)) return true;
        if (normalizePosition(posLabel) == 'tecnico' &&
            (_liveScores[p.playerId]?.totalScore ?? 0) != 0) {
          return true;
        }
        return false;
      }

      final bool allStartersPlayed =
          currentStarters.every((e) => starterHasPlayed(e.value));

      if (!allStartersPlayed) {
        final missed =
            currentStarters.where((e) => !starterHasPlayed(e.value)).toList();
        missed.sort((a, b) {
          if (a.value.playerId == activeCaptain) return -1;
          if (b.value.playerId == activeCaptain) return 1;
          return b.value.currentPrice.compareTo(a.value.currentPrice);
        });
        final outEntry = missed.first;
        activeLineup[outEntry.key] = benchPlayer;
        if (outEntry.value.playerId == activeCaptain) {
          activeCaptain = benchPlayer.playerId;
        }
      } else if (_luxuryReserveId == benchPlayer.playerId) {
        final double benchScore =
            _liveScores[benchPlayer.playerId]?.totalScore ?? 0.0;
        MapEntry<int, FantasyPlayer> worstEntry = currentStarters.first;
        double worstScore =
            _liveScores[worstEntry.value.playerId]?.totalScore ?? 0.0;

        for (final entry in currentStarters) {
          final double s = _liveScores[entry.value.playerId]?.totalScore ?? 0.0;
          if (s < worstScore) {
            worstScore = s;
            worstEntry = entry;
          } else if (s == worstScore &&
              worstEntry.value.playerId == activeCaptain &&
              entry.value.playerId != activeCaptain) {
            worstEntry = entry;
          }
        }

        if (benchScore > worstScore) {
          activeLineup[worstEntry.key] = benchPlayer;
          if (worstEntry.value.playerId == activeCaptain) {
            activeCaptain = benchPlayer.playerId;
          }
        }
      }
    }

    double total = 0.0;
    for (final p in activeLineup.values) {
      double s = _liveScores[p.playerId]?.totalScore ?? 0.0;
      if (p.playerId == activeCaptain) s *= 2;
      total += s;
    }
    return double.parse(total.toStringAsFixed(2));
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

  void _updateMarketStatus(Map<String, dynamic> data, String seasonId,
      {bool notify = true}) {
    final bool isOpenFlag = data['is_open'] ?? true;
    final dynamic closingRaw = data['closing_time'];
    _closingTime = closingRaw is Timestamp ? closingRaw.toDate() : null;
    final bool isExpired =
        _closingTime != null && DateTime.now().isAfter(_closingTime!);

    _isMarketOpen = isOpenFlag && !isExpired;
    _currentRound = data['current_round'] ?? 1;
    _checkScoutSubscription(seasonId);

    if (!_isMarketOpen) {
      _roundMatchesSub?.cancel();
      _roundMatchesSub = _matchService
          .streamRoundMatches(seasonId, _currentRound)
          .listen((matches) {
        if (_isDisposed) return;
        _roundMatches = matches;
        _areAllMatchesFinished =
            matches.isNotEmpty && matches.every((m) => m.isFinished);
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
        _gameConfig =
            FantasyGameConfig.fromMap(doc.data() as Map<String, dynamic>);
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

  Future<void> _syncLocalStateWithDatabase(
      FantasyTeam team, String seasonId) async {
    _team = team;
    _currentBalance = team.currentBalance;
    _captainId = team.captainId;
    _luxuryReserveId = team.luxuryReserveId;
    _totalPatrimony = team.teamValue;

    final allIds =
        <String>{...team.lineupPlayerIds, ...team.benchPlayerIds}.toList();
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
                if (parsedSlot != null && id == p.playerId)
                  _lineup[parsedSlot] = p;
              });
            } else if (team.benchPlayerIds.contains(p.playerId)) {
              team.benchSlots?.forEach((slot, id) {
                final parsedSlot = int.tryParse(slot);
                if (parsedSlot != null && id == p.playerId)
                  _bench[parsedSlot] = p;
              });
            }
          } else {
            // BACKWARD COMPATIBILITY
            final pos = p.position.toLowerCase();

            if (team.lineupPlayerIds.contains(p.playerId)) {
              calculatedTeamPrice += p.currentPrice;
              if (pos.contains('gol'))
                _lineup[1] = p;
              else if (pos.contains('fix'))
                _lineup[2] = p;
              else if (pos.contains('piv'))
                _lineup[5] = p;
              else if (pos.contains('téc'))
                _lineup[6] = p;
              else if (pos.contains('ala')) {
                if (!_lineup.containsKey(3))
                  _lineup[3] = p;
                else
                  _lineup[4] = p;
              }
            } else if (team.benchPlayerIds.contains(p.playerId)) {
              if (pos.contains('gol'))
                _bench[11] = p;
              else if (pos.contains('fix'))
                _bench[12] = p;
              else if (pos.contains('ala'))
                _bench[13] = p;
              else if (pos.contains('piv'))
                _bench[15] = p;
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

    final existingStarter = _lineup[slotIndex];
    final bool alreadyInOtherSlot = _lineup.entries.any(
          (e) => e.key != slotIndex && e.value.playerId == player.playerId,
        ) ||
        _bench.values.any((p) => p.playerId == player.playerId);

    if (alreadyInOtherSlot) {
      _errorMessage = "${player.name} já está no seu time ou banco.";
      if (!_isDisposed) notifyListeners();
      return;
    }

    final requiredPos = positionForSlot(slotIndex);
    if (requiredPos != null &&
        !matchesPosition(
            player.position, player.secondaryPosition, requiredPos)) {
      _errorMessage = "${player.name} não atua na posição de $requiredPos.";
      if (!_isDisposed) notifyListeners();
      return;
    }

    final double oldPrice = existingStarter?.currentPrice ?? 0.0;
    final double netCost = player.currentPrice - oldPrice;
    if (_currentBalance - netCost < -0.01) {
      final double needed =
          double.parse((netCost - _currentBalance).toStringAsFixed(2));
      _errorMessage =
          "Saldo insuficiente para contratar ${player.name} (Faltam C\$ ${needed.toStringAsFixed(2)}).";
      if (!_isDisposed) notifyListeners();
      return;
    }

    if (existingStarter != null && _captainId == existingStarter.playerId) {
      _captainId = null;
    }

    _lineup[slotIndex] = player;
    HapticFeedback.lightImpact();

    // Validar banco existente com base nos slots titulares atuais
    _validateBenchAfterLineupChange();

    _calculateFinancials();
    _autoSave();
  }

  bool canAddBenchPlayer(FantasyPlayer player,
      {int? slotIndex, String? slotPosition}) {
    final String pos = slotPosition ??
        (slotIndex != null ? positionForSlot(slotIndex) : null) ??
        player.position;

    if (!matchesPosition(player.position, player.secondaryPosition, pos)) {
      _errorMessage = "${player.name} não atua na posição de $pos.";
      if (!_isDisposed) notifyListeners();
      return false;
    }

    final startersOfPos = getStartersForPosition(pos);
    if (startersOfPos.isEmpty) {
      _errorMessage = "Você precisa escalar um titular de $pos primeiro.";
      if (!_isDisposed) notifyListeners();
      return false;
    }
    final double minPrice = startersOfPos
        .map((p) => p.currentPrice)
        .reduce((a, b) => a < b ? a : b);
    if (player.currentPrice > minPrice + 0.001) {
      _errorMessage =
          "O reserva de $pos deve custar no máximo C\$ ${minPrice.toStringAsFixed(2)} (titular mais barato da posição).";
      if (!_isDisposed) notifyListeners();
      return false;
    }
    return true;
  }

  void addBenchPlayer(int slotIndex, FantasyPlayer player) {
    if (!_isMarketOpen) return;

    final existingBench = _bench[slotIndex];
    final bool alreadyInOtherSlot = _lineup.values
            .any((p) => p.playerId == player.playerId) ||
        _bench.entries.any(
            (e) => e.key != slotIndex && e.value.playerId == player.playerId);

    if (alreadyInOtherSlot) {
      _errorMessage = "${player.name} já está no seu time ou banco.";
      if (!_isDisposed) notifyListeners();
      return;
    }

    if (!canAddBenchPlayer(player, slotIndex: slotIndex)) return;

    if (existingBench != null && _luxuryReserveId == existingBench.playerId) {
      _luxuryReserveId = null;
    }

    _bench[slotIndex] = player;
    HapticFeedback.lightImpact();
    _calculateFinancials();
    _autoSave();
  }

  void _validateBenchAfterLineupChange([String? _]) {
    final slotsToRemove = <int>[];
    String? removedPosLabel;

    for (final bConfig in benchSlotsConfig) {
      final int benchSlot = bConfig['index'] as int;
      final String posLabel = bConfig['pos'] as String;
      final benchPlayer = _bench[benchSlot];
      if (benchPlayer == null) continue;

      final startersOfPos = getStartersForPosition(posLabel);
      if (startersOfPos.isEmpty) {
        slotsToRemove.add(benchSlot);
        removedPosLabel ??= posLabel;
      } else {
        final double minPrice = startersOfPos
            .map((p) => p.currentPrice)
            .reduce((a, b) => a < b ? a : b);
        if (benchPlayer.currentPrice > minPrice + 0.001) {
          slotsToRemove.add(benchSlot);
          removedPosLabel ??= posLabel;
        }
      }
    }

    for (final slot in slotsToRemove) {
      final removed = _bench.remove(slot);
      if (removed != null && _luxuryReserveId == removed.playerId) {
        _luxuryReserveId = null;
      }
    }

    if (removedPosLabel != null) {
      _errorMessage =
          "Reserva de $removedPosLabel removido pois ficou sem titular correspondente ou mais caro que o titular mais barato.";
      if (!_isDisposed) notifyListeners();
    }
  }

  void removePlayer(int slotIndex) {
    if (!_isMarketOpen) return;
    final p = _lineup.remove(slotIndex);
    if (p != null) {
      HapticFeedback.lightImpact();
      if (_captainId == p.playerId) _captainId = null;
      _validateBenchAfterLineupChange();
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
    // Técnico (slot 6) não pode ser Capitão
    if (_lineup[6]?.playerId == playerId) {
      _errorMessage = "O Técnico não pode ser escolhido como Capitão.";
      if (!_isDisposed) notifyListeners();
      return;
    }
    final starter =
        _lineup.values.where((p) => p.playerId == playerId).firstOrNull;
    if (starter != null && normalizePosition(starter.position) == 'tecnico') {
      _errorMessage = "O Técnico não pode ser escolhido como Capitão.";
      if (!_isDisposed) notifyListeners();
      return;
    }
    _captainId = (_captainId == playerId) ? null : playerId;
    HapticFeedback.mediumImpact();
    _autoSave();
  }

  void setLuxuryReserve(String playerId) {
    if (!_isMarketOpen) return;
    // Técnico reserva (slot 16) não pode ser Reserva de Luxo
    if (_bench[16]?.playerId == playerId) {
      _errorMessage = "O Técnico reserva não pode ser Reserva de Luxo.";
      if (!_isDisposed) notifyListeners();
      return;
    }
    final reserve =
        _bench.values.where((p) => p.playerId == playerId).firstOrNull;
    if (reserve != null && normalizePosition(reserve.position) == 'tecnico') {
      _errorMessage = "O Técnico reserva não pode ser Reserva de Luxo.";
      if (!_isDisposed) notifyListeners();
      return;
    }
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
      _lineup.forEach(
          (key, value) => lineupSlots[key.toString()] = value.playerId);

      final Map<String, String> benchSlots = {};
      _bench
          .forEach((key, value) => benchSlots[key.toString()] = value.playerId);

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
      List<FantasyPlayer> validPlayers =
          allPlayers.where((p) => p.status == 'probable').toList();

      // Fallback de contingência caso hajam poucos prováveis (mercado não atualizado, etc)
      if (validPlayers.length < 15) {
        validPlayers = allPlayers
            .where((p) => p.status != 'suspended' && p.status != 'injured')
            .toList();
      }

      // Separar por posições primárias (evita colisão de mesmo atleta em duas listas durante o sorteio)
      List<FantasyPlayer> goleiros = validPlayers
          .where((p) => normalizePosition(p.position) == 'goleiro')
          .toList();
      List<FantasyPlayer> fixos = validPlayers
          .where((p) => normalizePosition(p.position) == 'fixo')
          .toList();
      List<FantasyPlayer> alas = validPlayers
          .where((p) => normalizePosition(p.position) == 'ala')
          .toList();
      List<FantasyPlayer> pivos = validPlayers
          .where((p) => normalizePosition(p.position) == 'pivo')
          .toList();
      List<FantasyPlayer> tecnicos = validPlayers
          .where((p) => normalizePosition(p.position) == 'tecnico')
          .toList();

      // Introduzir um fator de aleatoriedade para variar a escalação entre as tentativas
      final random = math.Random();
      double randomizedScore(FantasyPlayer p) {
        double noise = 0.7 + (random.nextDouble() * 0.6);
        return (p.averageScore > 0 ? p.averageScore : 1.0) * noise;
      }

      // Ordenar por média ponderada aleatoriamente
      goleiros.sort((a, b) => randomizedScore(b).compareTo(randomizedScore(a)));
      fixos.sort((a, b) => randomizedScore(b).compareTo(randomizedScore(a)));
      alas.sort((a, b) => randomizedScore(b).compareTo(randomizedScore(a)));
      pivos.sort((a, b) => randomizedScore(b).compareTo(randomizedScore(a)));
      tecnicos.sort((a, b) => randomizedScore(b).compareTo(randomizedScore(a)));

      if (goleiros.isEmpty ||
          fixos.isEmpty ||
          alas.length < 2 ||
          pivos.isEmpty ||
          tecnicos.isEmpty) {
        _errorMessage =
            "Não há jogadores suficientes para sugerir uma escalação.";
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Limpa tudo antes de começar
      sellAll();

      // Seleção Gulosa (Greedy) Inicial
      List<FantasyPlayer> starters = [];
      int golIdx = 0,
          fixIdx = 0,
          ala1Idx = 0,
          ala2Idx = 1,
          pivIdx = 0,
          tecIdx = 0;

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

        double currentCost =
            starters.fold(0.0, (sum, p) => sum + p.currentPrice);

        if (currentCost <= _totalPatrimony) {
          foundTeam = true;
          break;
        }

        // Tentar rebaixar o jogador mais caro do time escolhido
        starters.sort((a, b) => b.currentPrice.compareTo(a.currentPrice));
        bool downgraded = false;

        for (var expensivePlayer in starters) {
          final pos = normalizePosition(expensivePlayer.position);

          if (pos == 'goleiro' && golIdx + 1 < goleiros.length) {
            golIdx++;
            downgraded = true;
            break;
          }
          if (pos == 'fixo' && fixIdx + 1 < fixos.length) {
            fixIdx++;
            downgraded = true;
            break;
          }
          if (pos == 'pivo' && pivIdx + 1 < pivos.length) {
            pivIdx++;
            downgraded = true;
            break;
          }
          if (pos == 'tecnico' && tecIdx + 1 < tecnicos.length) {
            tecIdx++;
            downgraded = true;
            break;
          }
          if (pos == 'ala') {
            if (expensivePlayer.playerId == alas[ala1Idx].playerId) {
              int nextIdx = ala1Idx + 1;
              while (nextIdx == ala2Idx && nextIdx < alas.length) nextIdx++;
              if (nextIdx < alas.length) {
                ala1Idx = nextIdx;
                downgraded = true;
                break;
              }
            } else if (expensivePlayer.playerId == alas[ala2Idx].playerId) {
              int nextIdx = ala2Idx + 1;
              while (nextIdx == ala1Idx && nextIdx < alas.length) nextIdx++;
              if (nextIdx < alas.length) {
                ala2Idx = nextIdx;
                downgraded = true;
                break;
              }
            }
          }
        }

        if (!downgraded) break;
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

      // Definir Capitão apenas entre atletas de linha/goleiro (exclui Técnico no slot 6)
      final captainCandidates = [
        _lineup[1]!,
        _lineup[2]!,
        _lineup[3]!,
        _lineup[4]!,
        _lineup[5]!,
      ];
      _captainId = captainCandidates
          .reduce((a, b) => a.averageScore >= b.averageScore ? a : b)
          .playerId;

      // 3. Selecionar Reservas (Focando na maior média com preço <= titular mais barato do slot da posição)
      void pickBench(int slot, List<FantasyPlayer> allPos, String posLabel) {
        final posStarters = getStartersForPosition(posLabel);
        if (posStarters.isEmpty) return;
        final minPrice = posStarters
            .map((p) => p.currentPrice)
            .reduce((a, b) => a < b ? a : b);

        final candidates = allPos
            .where((p) =>
                p.currentPrice <= minPrice + 0.001 &&
                !_lineup.values.any((s) => s.playerId == p.playerId) &&
                !_bench.values.any((b) => b.playerId == p.playerId))
            .toList();

        if (candidates.isNotEmpty) {
          _bench[slot] = candidates.first;
        }
      }

      pickBench(11, goleiros, 'Goleiro');
      pickBench(12, fixos, 'Fixo');
      pickBench(13, alas, 'Ala');
      pickBench(15, pivos, 'Pivô');
      pickBench(16, tecnicos, 'Técnico');

      // Definir Reserva de Luxo automaticamente entre os reservas de linha/goleiro (exclui Técnico slot 16)
      final luxuryCandidates = _bench.entries
          .where((e) =>
              e.key != 16 && normalizePosition(e.value.position) != 'tecnico')
          .map((e) => e.value)
          .toList();
      if (luxuryCandidates.isNotEmpty) {
        _luxuryReserveId = luxuryCandidates
            .reduce((a, b) => a.averageScore >= b.averageScore ? a : b)
            .playerId;
      }

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
      final allIds = <String>{
        ..._lineup.values.map((p) => p.playerId),
        ..._bench.values.map((p) => p.playerId),
        ..._team!.lineupPlayerIds,
        ..._team!.benchPlayerIds,
      }.toList();
      if (allIds.isEmpty) return;

      final players =
          await _repository.getPlayersByIds(allIds, forceRefresh: true);
      final playersById = {for (final p in players) p.playerId: p};

      if (_lineup.isNotEmpty || _bench.isNotEmpty) {
        // Preserva rigorosamente os slots onde os atletas (inclusive de dupla posição) estão escalados
        for (final slot in _lineup.keys.toList()) {
          final current = _lineup[slot];
          if (current != null && playersById.containsKey(current.playerId)) {
            _lineup[slot] = playersById[current.playerId]!;
          }
        }
        for (final slot in _bench.keys.toList()) {
          final current = _bench[slot];
          if (current != null && playersById.containsKey(current.playerId)) {
            _bench[slot] = playersById[current.playerId]!;
          }
        }
        _calculateFinancials();
      } else if (_seasonId != null) {
        await _syncLocalStateWithDatabase(_team!, _seasonId!);
      } else {
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Erro ao recarregar jogadores: $e");
    }
  }

  void _checkScoutSubscription(String seasonId) async {
    _scoutSub?.cancel();
    if (!_isMarketOpen) {
      if (_lineup.isNotEmpty) {
        _scoutSub = _scoutService
            .streamLiveScores(seasonId, _currentRound)
            .listen((scores) {
          _liveScores = scores;
          if (!_isDisposed) notifyListeners();
        });
      }
    } else {
      // Se mercado está aberto, busca os scouts da rodada anterior (para exibir como histórico detalhado)
      if (_currentRound > 1) {
        final scores =
            await _scoutService.getLiveScores(seasonId, _currentRound - 1);
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
