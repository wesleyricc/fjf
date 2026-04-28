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

    final players = await _api.getAllPlayers();
    
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
    
    // Caso contrário, busca direto da API (Firebase)
    final players = await _api.getPlayersByIds(ids);
    
    // Opcional: Atualiza o cache global se necessário, ou apenas retorna
    return players;
  }

  Future<String> saveLineup({
    required String userId,
    required List<String> playerIds,
    required String? captainId,
    required double expectedOldTeamCost,
    required double totalCost, 
  }) async {
    final result = await _api.saveLineup(
      userId: userId,
      playerIds: playerIds,
      captainId: captainId,
      expectedOldTeamCost: expectedOldTeamCost,
      newTeamCost: totalCost,
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
  }
}