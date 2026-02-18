import 'dart:async';
import '../models/fantasy_models.dart';
import '../services/fantasy_service.dart';

class FantasyRepository {
  // Singleton (Opcional, mas útil se não usar injeção de dependência estrita)
  static final FantasyRepository _instance = FantasyRepository._internal();
  factory FantasyRepository() => _instance;
  FantasyRepository._internal();

  final FantasyService _api = FantasyService();

  // --- CACHE EM MEMÓRIA ---
  
  // Cache de Jogadores (Pesado)
  List<FantasyPlayer>? _cachedPlayers;
  DateTime? _lastPlayersFetch;
  static const Duration PLAYER_CACHE_VALIDITY = Duration(minutes: 10);

  // Cache de Status do Mercado (Leve, mas consultado sempre)
  Map<String, dynamic>? _cachedMarketStatus;
  DateTime? _lastMarketFetch;
  static const Duration MARKET_CACHE_VALIDITY = Duration(minutes: 2);

  // Cache do Time do Usuário (Por ID)
  final Map<String, FantasyTeam> _cachedTeams = {};
  
  // --- MÉTODOS ---

  // 1. Buscar Jogadores (Com Cache de 10 min)
  Future<List<FantasyPlayer>> getAllPlayers({bool forceRefresh = false}) async {
    final bool isExpired = _lastPlayersFetch == null || 
        DateTime.now().difference(_lastPlayersFetch!) > PLAYER_CACHE_VALIDITY;

    if (_cachedPlayers != null && !isExpired && !forceRefresh) {
      return _cachedPlayers!;
    }

    // Busca na API
    final players = await _api.getAllPlayers();
    
    // Atualiza Cache
    _cachedPlayers = players;
    _lastPlayersFetch = DateTime.now();
    
    return players;
  }

  // 2. Buscar Time do Usuário (Específico)
  Stream<FantasyTeam?> streamUserTeam(String userId) {
    return _api.streamMyTeam(userId);
  }

  // Versão Future para one-shot loads (Escalação)
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

  // 3. Status do Mercado
  Stream<Map<String, dynamic>> streamMarketStatus() {
    return _api.streamMarketStatus();
  }

  // Método auxiliar para buscar IDs específicos (usando o cache local se possível)
  Future<List<FantasyPlayer>> getPlayersByIds(List<String> ids) async {
    if (_cachedPlayers != null) {
      return _cachedPlayers!.where((p) => ids.contains(p.playerId)).toList();
    }
    
    return _api.getPlayersByIds(ids);
  }

  // --- MÉTODOS DE AÇÃO (Pass-through + Invalidação de Cache) ---

  // CORREÇÃO: Parâmetros atualizados para suportar a transação atômica do FantasyService
  Future<String> saveLineup({
    required String userId,
    required List<String> playerIds,
    required String? captainId,
    required double expectedOldTeamCost,
    required double totalCost, // Representa o novo custo (newTeamCost)
  }) async {
    final result = await _api.saveLineup(
      userId: userId,
      playerIds: playerIds,
      captainId: captainId,
      expectedOldTeamCost: expectedOldTeamCost,
      newTeamCost: totalCost,
    );

    if (result == "Sucesso") {
      // Invalida cache do time específico para forçar recarga na próxima leitura
      _cachedTeams.remove(userId);
    }

    return result;
  }
  
  // Método para limpar cache (útil ao fazer logout)
  void clearCache() {
    _cachedPlayers = null;
    _cachedMarketStatus = null;
    _cachedTeams.clear();
  }
}