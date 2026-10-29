import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; 
import 'admin_service.dart';
import '../models/team_model.dart'; 
import '../models/player_model.dart'; 
import '../models/match_model.dart';
import 'firestore_cache_service.dart';

class ChampionshipService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- ESTADO GERAL E CONECTIVIDADE ---
  bool _isOffline = false; 
  String _currentSeasonId = '';
  String _currentSeasonName = 'Carregando...';
  int _currentSeasonYear = DateTime.now().year; 
  String _currentSeasonHonoree = '';
  
  List<Map<String, dynamic>> _availableSeasons = [];
  bool _isLoading = false; 
  
  bool _isFetchingStaticData = false;
  bool _isFetchingPlayers = false;

  // --- CACHE DE DADOS (APENAS DESPORTO E EQUIPES) ---
  List<Team> _cachedTeams = [];
  final Map<String, List<Player>> _cachedPlayersByTeam = {};
  List<Player> _allPlayersCache = [];
  List<MatchModel> _cachedMatches = [];
  Map<String, dynamic>? _cachedAppSettings; 

  DateTime? _lastMatchesFetch;
  DateTime? _lastTeamsFetch;
  DateTime? _lastAllPlayersFetch; 
  final Map<String, DateTime> _lastTeamRosterFetch = {};

  static const int TEAMS_CACHE_TTL = 60;   
  static const int MATCHES_CACHE_TTL = 5;  
  static const int ROSTER_CACHE_TTL = 30;  
  static const int ALL_PLAYERS_CACHE_TTL = 15; 

  bool get isOffline => _isOffline; 
  String get currentSeasonId => _currentSeasonId;
  String get currentSeasonName => _currentSeasonName;
  int get currentSeasonYear => _currentSeasonYear;
  String get currentSeasonHonoree => _currentSeasonHonoree;
  List<Map<String, dynamic>> get availableSeasons => _availableSeasons;
  bool get isLoading => _isLoading;

  List<Team> get teams => _cachedTeams;
  List<MatchModel> get matches => _cachedMatches;
  Map<String, dynamic>? get appSettings => _cachedAppSettings;
  
  bool get isFantasyEnabled => _cachedAppSettings?['feature_fantasy'] ?? false;
  bool get isBolaoEnabled => _cachedAppSettings?['feature_bolao'] ?? false;
  bool get isPhotoStoreEnabled => _cachedAppSettings?['feature_photo_store'] ?? false;
  bool get isMiniBolaoEnabled => _cachedAppSettings?['feature_mini_bolao'] ?? false;
  bool get isAppOpenAdEnabled => _cachedAppSettings?['feature_app_open_ad'] ?? true;

  bool get isLiveActive {
    if (_cachedAppSettings == null) return false;
    final String? remoteId = _cachedAppSettings!['live_video_id'];
    final Timestamp? timestamp = _cachedAppSettings!['live_video_timestamp'] is Timestamp
        ? _cachedAppSettings!['live_video_timestamp'] as Timestamp
        : null;
    if (remoteId != null && remoteId.isNotEmpty && timestamp != null && remoteId != 'ByBvdFS1jko') {
      final diff = DateTime.now().difference(timestamp.toDate());
      return diff.inHours < 24;
    }
    return false;
  }

  List<Player> get allPlayers {
    if (_allPlayersCache.isNotEmpty) return _allPlayersCache;
    return _cachedPlayersByTeam.values.expand((x) => x).toList();
  }

  Future<bool> checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _isOffline = result.contains(ConnectivityResult.none);
    notifyListeners();
    return !_isOffline;
  }

  // ===========================================================================
  // 🚀 INICIALIZAÇÃO
  // ===========================================================================

  Future<void> ensureInitialized() async {
    if (_currentSeasonId.isNotEmpty && !_isLoading) return;
    await init();
  }

  Future<void> init({bool forceRefresh = false}) async {
    if (_isLoading) return; 

    _isLoading = true;
    notifyListeners(); 

    if (!await checkConnectivity()) {
      _isLoading = false;
      _currentSeasonName = "Modo Offline";
      notifyListeners();
      return;
    }

    try {
      // ⚡ FinOps PWA: Cacheia a lista de temporadas por 30 minutos no localStorage
      final seasonDocs = await FirestoreCacheService.getDocsDataWithCache(
        query: _firestore.collection('championships'),
        cacheKey: 'championships_seasons_list',
        ttl: const Duration(minutes: 30),
        forceRefresh: forceRefresh,
      );

      _availableSeasons = seasonDocs.map((data) {
        final docId = data['_docId']?.toString() ?? '';
        int parsedYear = DateTime.now().year;
        if (data['year'] != null) {
          parsedYear = int.tryParse(data['year'].toString()) ?? parsedYear;
        }
        
        return {
          'id': docId,
          'name': data['name'] ?? docId,
          'year': parsedYear,
          'honoree': data['honoree'] ?? '',
          'isActive': data['is_active'] ?? false,
        };
      }).toList();

      _availableSeasons.sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));

      if (_availableSeasons.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final savedSeasonId = prefs.getString('selected_season_id');
        
        String targetId = '';

        if (savedSeasonId != null && _availableSeasons.any((s) => s['id'] == savedSeasonId)) {
           targetId = savedSeasonId;
        } else {
           final activeSeason = _availableSeasons.firstWhere(
             (s) => s['isActive'] == true, 
             orElse: () => _availableSeasons.first
           );
           targetId = activeSeason['id'];
        }
        
        await _setSeasonInternal(targetId, forceRefresh: forceRefresh);
      } else {
        _handleNoSeason();
      }

    } catch (e) {
      debugPrint("Erro inicialização ChampionshipService: $e");
      _currentSeasonName = "Erro de Conexão";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _handleNoSeason() {
    _currentSeasonName = "Nenhuma Temporada";
    _currentSeasonId = "";
    _currentSeasonYear = DateTime.now().year;
    AdminService.pendingYellowCards = 2;
    AdminService.suspensionYellowCards = 3;
  }

  // ===========================================================================
  // 🚀 FETCH ULTRA ENXUTO E ACELERAÇÃO DO BOOT
  // ===========================================================================
  Future<void> fetchStaticData({bool forceRefresh = false, bool refreshMatchesOnly = false}) async {
    if (_currentSeasonId.isEmpty) return;
    if (_isFetchingStaticData) return;
    if (!await checkConnectivity()) return;

    _isFetchingStaticData = true;
    _isLoading = true;
    notifyListeners();

    try {
      final List<Future<void>> tasks = [];

      if (forceRefresh || refreshMatchesOnly || _isExpired(_lastMatchesFetch, MATCHES_CACHE_TTL)) {
        tasks.add(_fetchMatches(forceRefresh: forceRefresh));
      }

      if (!refreshMatchesOnly) {
        if (forceRefresh || _isExpired(_lastTeamsFetch, TEAMS_CACHE_TTL)) {
          tasks.add(_fetchTeams(forceRefresh: forceRefresh));
        }
        tasks.add(_fetchConfig(forceRefresh: forceRefresh));
      }

      if (tasks.isNotEmpty) {
        await Future.wait(tasks);
      }

      if (forceRefresh) {
        invalidatePlayerCache();
      }
      debugPrint("🚀 [FinOps Boot] Sucesso: Apenas dados vitais indexados na inicialização.");
    } catch (e) {
      debugPrint("❌ Erro ao atualizar dados: $e");
    } finally {
      _isFetchingStaticData = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _isExpired(DateTime? lastFetch, int ttlMinutes) {
    if (lastFetch == null) return true;
    final diff = DateTime.now().difference(lastFetch);
    return diff.inMinutes >= ttlMinutes;
  }

  Future<void> _fetchMatches({bool forceRefresh = false}) async {
    final query = _firestore.collection('championships').doc(_currentSeasonId).collection('matches').orderBy('datetime');
    final docs = await FirestoreCacheService.getDocsDataWithCache(
      query: query,
      cacheKey: 'matches_$_currentSeasonId',
      ttl: const Duration(minutes: MATCHES_CACHE_TTL),
      forceRefresh: forceRefresh,
    );
    _cachedMatches = docs.map((d) => MatchModel.fromMap(d['_docId']?.toString() ?? '', d)).toList();
    _lastMatchesFetch = DateTime.now();
  }

  Future<void> _fetchTeams({bool forceRefresh = false}) async {
    final query = _firestore.collection('championships').doc(_currentSeasonId).collection('teams_participation');
    final docs = await FirestoreCacheService.getDocsDataWithCache(
      query: query,
      cacheKey: 'teams_$_currentSeasonId',
      ttl: const Duration(minutes: TEAMS_CACHE_TTL),
      forceRefresh: forceRefresh,
    );
    _cachedTeams = docs.map((d) => Team.fromMap(d['_docId']?.toString() ?? '', d)).toList();
    _cachedTeams.sort((a, b) => a.name.compareTo(b.name));
    _lastTeamsFetch = DateTime.now();
  }

  Future<void> _fetchConfig({bool forceRefresh = false}) async {
    final docRef = _firestore.collection('championships').doc(_currentSeasonId).collection('settings').doc('app_settings');
    final data = await FirestoreCacheService.getDocDataWithCache(
      docRef: docRef,
      cacheKey: 'app_settings_$_currentSeasonId',
      ttl: const Duration(hours: 12), // Configurações mudam raramente
      forceRefresh: forceRefresh,
    );
    if (data != null) _cachedAppSettings = data;
  }

  // ===========================================================================
  // 👥 GESTÃO DE ELENCO
  // ===========================================================================
  
  final Set<String> _fetchingRosters = {};

  List<Player> getCachedRoster(String teamId) {
    if (_cachedPlayersByTeam.containsKey(teamId)) return List.from(_cachedPlayersByTeam[teamId]!);
    if (_allPlayersCache.isNotEmpty) {
      final roster = _allPlayersCache.where((p) => p.teamId == teamId).toList();
      _sortRoster(roster);
      return roster;
    }
    return [];
  }

  Future<List<Player>> fetchRoster(String teamId, {bool force = false}) async {
    if (_currentSeasonId.isEmpty) return [];
    if (!await checkConnectivity()) return _cachedPlayersByTeam[teamId] ?? [];

    final lastFetch = _lastTeamRosterFetch[teamId];
    if (!force && lastFetch != null && !_isExpired(lastFetch, ROSTER_CACHE_TTL)) {
      return _cachedPlayersByTeam[teamId] ?? [];
    }

    if (_fetchingRosters.contains(teamId)) {
      return _cachedPlayersByTeam[teamId] ?? [];
    }
    _fetchingRosters.add(teamId);

    try {
      final query = _firestore.collection('championships').doc(_currentSeasonId)
          .collection('player_stats').where('team_id', isEqualTo: teamId).where('isActive', isEqualTo: true);
      final snapshot = await FirestoreCacheService.getWithCache(
        query: query,
        cacheKey: 'roster_${_currentSeasonId}_$teamId',
        ttl: const Duration(minutes: ROSTER_CACHE_TTL),
        forceRefresh: force,
      );

      final roster = snapshot.docs.map((d) => Player.fromFirestore(d)).toList();
      _sortRoster(roster);

      _cachedPlayersByTeam[teamId] = roster;
      _lastTeamRosterFetch[teamId] = DateTime.now();
      
      notifyListeners();
      return roster;
    } catch (e) {
      debugPrint("Erro ao carregar elenco $teamId: $e");
      return [];
    } finally {
      _fetchingRosters.remove(teamId);
    }
  }

  Future<void> fetchAllPlayers({bool force = false}) async {
    if (!force && _allPlayersCache.isNotEmpty && !_isExpired(_lastAllPlayersFetch, ALL_PLAYERS_CACHE_TTL)) {
      return;
    }
    
    if (_isFetchingPlayers) return;
    if (!await checkConnectivity()) return; 

    _isFetchingPlayers = true;
    try {
      final query = _firestore.collection('championships').doc(_currentSeasonId)
          .collection('player_stats').where('isActive', isEqualTo: true);
      final snapshot = await FirestoreCacheService.getWithCache(
        query: query,
        cacheKey: 'all_players_$_currentSeasonId',
        ttl: const Duration(minutes: ALL_PLAYERS_CACHE_TTL),
        forceRefresh: force,
      );
      
      _allPlayersCache = snapshot.docs.map((d) => Player.fromFirestore(d)).toList();
      _lastAllPlayersFetch = DateTime.now(); 
      notifyListeners();
    } catch (e) { 
      debugPrint("Erro fetchAllPlayers: $e"); 
    } finally {
      _isFetchingPlayers = false;
    }
  }

  void _sortRoster(List<Player> roster) {
     roster.sort((a, b) {
       if (a.isGoalkeeper && !b.isGoalkeeper) return -1;
       if (!a.isGoalkeeper && b.isGoalkeeper) return 1;
       return (a.jerseyNumber ?? 99).compareTo(b.jerseyNumber ?? 99);
    });
  }

  void invalidatePlayerCache() {
    _cachedPlayersByTeam.clear();
    _allPlayersCache.clear();
    _lastTeamRosterFetch.clear();
    _lastAllPlayersFetch = null;
    notifyListeners();
  }

  // ===========================================================================
  // ⚙️ GESTÃO DE TEMPORADA
  // ===========================================================================

  Future<void> setSeason(String seasonId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_season_id', seasonId);
    await _setSeasonInternal(seasonId, forceRefresh: true);
  }

  Future<void> _setSeasonInternal(String seasonId, {bool forceRefresh = false}) async {
    final season = _availableSeasons.firstWhere(
      (s) => s['id'] == seasonId,
      orElse: () => {'id': '', 'name': 'Desconhecido', 'year': DateTime.now().year, 'honoree': ''},
    );
    
    if (season['id'] != '') {
      final bool seasonChanged = _currentSeasonId != seasonId;
      _currentSeasonId = seasonId;
      _currentSeasonName = season['name'];
      _currentSeasonYear = season['year'] as int;
      _currentSeasonHonoree = season['honoree'] ?? '';
      
      if (seasonChanged || forceRefresh) {
        _cachedTeams = []; 
        _cachedPlayersByTeam.clear(); 
        _allPlayersCache = []; 
        _cachedMatches = [];
        _lastTeamsFetch = null; 
        _lastMatchesFetch = null; 
        _lastTeamRosterFetch.clear();
        _lastAllPlayersFetch = null;
      }
      
      // Executa regras e dados estáticos em paralelo para acelerar o boot no PWA
      await Future.wait([
        AdminService.loadAllRules(seasonId),
        fetchStaticData(forceRefresh: forceRefresh),
      ]);
    }
    notifyListeners(); 
  }

  Future<String> setGlobalActiveSeason(String seasonId) async {
    try {
      final batch = _firestore.batch();
      final allDocs = await _firestore.collection('championships').get();
      for (var doc in allDocs.docs) {
        if (doc.data()['is_active'] == true) batch.update(doc.reference, {'is_active': false});
      }
      final targetRef = _firestore.collection('championships').doc(seasonId);
      batch.update(targetRef, {'is_active': true});
      await batch.commit();
      await FirestoreCacheService.invalidateCache('championships_seasons_list');
      await init(forceRefresh: true); 
      await setSeason(seasonId); 
      return "Sucesso";
    } catch (e) { return "Erro: $e"; }
  }
  
  Future<String> createSeason(int year, String name, String honoree, {bool copyTeams = false, bool copyPlayers = false}) async {
    try {
      final docId = '${year}_fjf';
      final doc = await _firestore.collection('championships').doc(docId).get();
      if (doc.exists) return "Temporada já existe.";

      await _firestore.collection('championships').doc(docId).set({
        'year': year, 'name': name, 'honoree': honoree,
        'is_active': false, 'status': 'open', 'created_at': FieldValue.serverTimestamp(),
      });
      
      if (copyTeams && _currentSeasonId.isNotEmpty) {
        await _copySeasonData(
          sourceSeasonId: _currentSeasonId, targetSeasonId: docId, includeRoster: copyPlayers,
        );
      }
      await FirestoreCacheService.invalidateCache('championships_seasons_list');
      await init(forceRefresh: true);
      return "Sucesso";
    } catch (e) { return "Erro: $e"; }
  }
  
  Future<String> updateSeason(String seasonId, String name, String honoree) async {
    try {
      await _firestore.collection('championships').doc(seasonId).update({'name': name, 'honoree': honoree});
      await FirestoreCacheService.invalidateCache('championships_seasons_list');
      await init(forceRefresh: true); 
      if (_currentSeasonId == seasonId) _setSeasonInternal(seasonId);
      return "Sucesso";
    } catch (e) { return "Erro: $e"; }
  }

  Future<void> _copySeasonData({required String sourceSeasonId, required String targetSeasonId, required bool includeRoster}) async {
    final batch = _firestore.batch();
    
    for (String docId in ['app_settings', 'disciplinary_rules', 'playoff_rules', 'tiebreaker_rules']) { 
      final docSnap = await _firestore.collection('championships').doc(sourceSeasonId).collection('settings').doc(docId).get(); 
      if (docSnap.exists) {
        batch.set(_firestore.collection('championships').doc(targetSeasonId).collection('settings').doc(docId), docSnap.data()!); 
      }
    }
    
    final sourceTeamsSnapshot = await _firestore.collection('championships').doc(sourceSeasonId).collection('teams_participation').get();
    for (var teamDoc in sourceTeamsSnapshot.docs) {
      final teamData = teamDoc.data(); 
      final String teamId = teamDoc.id;
      
      batch.set(_firestore.collection('championships').doc(targetSeasonId).collection('teams_participation').doc(teamId), {
        'name': teamData['name'], 
        'short_name': teamData['short_name'], 
        'shield_url': teamData['shield_url'], 
        'championship_history': teamData['championship_history'] ?? [], 
        'points': 0, 'match_points': 0, 'extra_points': 0, 
        'games_played': 0, 'wins': 0, 'draws': 0, 'losses': 0, 
        'goals_for': 0, 'goals_against': 0, 'goal_difference': 0, 
        'phase1_rank': null, 'disciplinary_points': 0, 
        'total_yellow_cards': 0, 'total_red_cards': 0, 
        'default_starters': includeRoster ? (teamData['default_starters'] ?? []) : []
      });

      if (includeRoster) {
        final playersInTeamSnap = await _firestore.collection('championships').doc(sourceSeasonId).collection('player_stats').where('team_id', isEqualTo: teamId).get();
        for (var pDoc in playersInTeamSnap.docs) { 
          final pData = pDoc.data(); 
          batch.set(_firestore.collection('championships').doc(targetSeasonId).collection('player_stats').doc(pDoc.id), {
            'name': pData['name'], 'photo_url': pData['photo_url'], 
            'position': pData['position'], 'is_goalkeeper': pData['is_goalkeeper'] ?? false, 
            'is_staff': pData['is_staff'] ?? false, 'jersey_number': pData['jersey_number'], 
            'team_id': teamId, 'team_name': teamData['name'], 'team_shield_url': teamData['shield_url'], 
            'goals': 0, 'assists': 0, 'goals_conceded': 0, 
            'yellow_cards': 0, 'red_cards': 0, 
            'total_yellow_cards': 0, 'total_red_cards': 0, 
            'man_of_the_match_awards': 0, 'is_suspended': false, 'isActive': true
          }); 
        }
      }
    }
    await batch.commit();
  }
}
