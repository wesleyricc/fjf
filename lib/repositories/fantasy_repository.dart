import 'dart:async';
import '../models/fantasy_models.dart';
import '../services/fantasy_service.dart';

class FantasyRepository {
  static final FantasyRepository _instance = FantasyRepository._internal();
  factory FantasyRepository() => _instance;
  FantasyRepository._internal();

  final FantasyService _api = FantasyService();

  // --- CACHE EM MEMÓRIA ---
  List<FantasyPlayer>? _cachedPlayers;
  DateTime? _lastPlayersFetch;
  static const Duration PLAYER_CACHE_VALIDITY = Duration(minutes: 5);

  Map<String, dynamic>? _cachedMarketStatus;
  DateTime? _lastMarketFetch;
  static const Duration MARKET_CACHE_VALIDITY = Duration(minutes: 2);

  final Map<String, FantasyTeam> _cachedTeams = {};
  final Map<String, FantasyPlayer> _cachedIndividualPlayers = {};
  
  // ---> OTIMIZAÇÃO: BROADCAST STREAM <---
  // Impede que cada tela crie uma nova ligação ao Firestore em simultâneo
  Stream<Map<String, dynamic>>? _marketStatusStream;
  
  // --- MÉTODOS ---

  Future<List<FantasyPlayer>> getAllPlayers({bool forceRefresh = false}) async {
    final bool isExpired = _lastPlayersFetch == null || 
        DateTime.now().difference(_lastPlayersFetch!) > PLAYER_CACHE_VALIDITY;

    if (_cachedPlayers != null && !isExpired && !forceRefresh) {
      return _cachedPlayers!;
    }

    // A otimização de TTL agora acontece lá no FirestoreCacheService também!
    final players = await _api.getAllPlayers(forceRefresh: forceRefresh);
    
    _cachedPlayers = players;
    _lastPlayersFetch = DateTime.now();
    
    return players;
  }

  Stream<FantasyTeam?> streamUserTeam(String userId) {
    return _api.streamMyTeam(userId);
  }

  Future<FantasyTeam?> getUserTeam(String userId, {bool forceRefresh = false}) async {
    if (_cachedTeams.containsKey(userId) && !forceRefresh) {
      return _cachedTeams[userId];
    }

    final team = await _api.streamMyTeam(userId).first;
    if (team != null) {
      _cachedTeams[userId] = team;
    }
    return team;
  }

  // ---> OTIMIZAÇÃO: BROADCAST <---
  Stream<Map<String, dynamic>> streamMarketStatus() {
    _marketStatusStream ??= _api.streamMarketStatus().asBroadcastStream();
    return _marketStatusStream!;
  }

  Future<List<FantasyPlayer>> getPlayersByIds(List<String> ids, {bool forceRefresh = false}) async {
    final bool isExpired = _lastPlayersFetch == null || 
        DateTime.now().difference(_lastPlayersFetch!) > PLAYER_CACHE_VALIDITY;

    // Se o cache global existir e não estiver expirado (e não for um forceRefresh), filtra localmente
    if (_cachedPlayers != null && !isExpired && !forceRefresh) {
      return _cachedPlayers!.where((p) => ids.contains(p.playerId)).toList();
    }
    
    List<String> missingIds = ids;
    List<FantasyPlayer> resultPlayers = [];
    
    if (!forceRefresh) {
      missingIds = ids.where((id) => !_cachedIndividualPlayers.containsKey(id)).toList();
      resultPlayers = ids.where((id) => _cachedIndividualPlayers.containsKey(id))
                         .map((id) => _cachedIndividualPlayers[id]!).toList();
    }

    if (missingIds.isNotEmpty) {
      final fetchedPlayers = await _api.getPlayersByIds(missingIds);
      for (var p in fetchedPlayers) {
        _cachedIndividualPlayers[p.playerId] = p;
        resultPlayers.add(p);
      }
    }
    
    return resultPlayers;
  }

  Future<String> saveLineup({
    required String userId,
    required List<String> playerIds,
    required List<String> benchIds,
    required String? captainId,
    required String? luxuryReserveId,
    required double expectedOldTeamCost,
    required double newTeamCost,
  }) async {
    final result = await _api.saveLineup(
      userId: userId,
      playerIds: playerIds,
      benchIds: benchIds,
      captainId: captainId,
      luxuryReserveId: luxuryReserveId,
      expectedOldTeamCost: expectedOldTeamCost,
      newTeamCost: newTeamCost,
    );

    if (result == "Sucesso") {
      _cachedTeams.remove(userId);
    }

    return result;
  }
  
  void clearCache() {
    _cachedPlayers = null;
    _cachedMarketStatus = null;
    _cachedTeams.clear();
    _cachedIndividualPlayers.clear();
  }
}