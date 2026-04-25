import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; 
import 'admin_service.dart';
import '../models/team_model.dart'; 
import '../models/player_model.dart'; 
import '../models/photo_product_model.dart'; 
import '../models/match_model.dart';

class ChampionshipService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- ESTADO GERAL E CONECTIVIDADE ---
  bool _isOffline = false; 
  String _currentSeasonId = '';
  String _currentSeasonName = 'Carregando...';
  int _currentSeasonYear = DateTime.now().year; // Valor inicial seguro
  String _currentSeasonHonoree = '';
  
  List<Map<String, dynamic>> _availableSeasons = [];
  bool _isLoading = false; 
  
  // TRAVAS DE CONCORRÊNCIA
  bool _isFetchingStaticData = false;
  bool _isFetchingPlayers = false;

  // --- CACHE DE DADOS (EM MEMÓRIA) ---
  List<Team> _cachedTeams = [];
  final Map<String, List<Player>> _cachedPlayersByTeam = {};
  List<Player> _allPlayersCache = [];
  List<Map<String, dynamic>> _cachedSponsors = []; 
  List<Map<String, dynamic>> _cachedNews = [];
  List<MatchModel> _cachedMatches = [];
  List<Map<String, dynamic>> _cachedSuspensions = []; 
  
  PhotoProduct? _cachedLatestPhotoProduct;
  Map<String, dynamic>? _cachedAppSettings; 

  // --- CONTROLE DE VALIDADE DE CACHE ---
  DateTime? _lastTeamsFetch;
  DateTime? _lastMatchesFetch;
  DateTime? _lastMiscFetch; 
  DateTime? _lastAllPlayersFetch; 
  final Map<String, DateTime> _lastTeamRosterFetch = {};

  static const int TEAMS_CACHE_TTL = 60;   
  static const int MATCHES_CACHE_TTL = 5;  
  static const int MISC_CACHE_TTL = 30;    
  static const int ROSTER_CACHE_TTL = 30;  
  static const int ALL_PLAYERS_CACHE_TTL = 15; 

  // Getters
  bool get isOffline => _isOffline; 
  String get currentSeasonId => _currentSeasonId;
  String get currentSeasonName => _currentSeasonName;
  int get currentSeasonYear => _currentSeasonYear;
  String get currentSeasonHonoree => _currentSeasonHonoree;
  List<Map<String, dynamic>> get availableSeasons => _availableSeasons;
  bool get isLoading => _isLoading;

  List<Team> get teams => _cachedTeams;
  List<Map<String, dynamic>> get sponsors => _cachedSponsors;
  List<Map<String, dynamic>> get news => _cachedNews;
  List<MatchModel> get matches => _cachedMatches;
  
  List<Player> get allPlayers {
    if (_allPlayersCache.isNotEmpty) return _allPlayersCache;
    return _cachedPlayersByTeam.values.expand((x) => x).toList();
  }

  List<DocumentSnapshot> _rawSuspensionSnaps = [];
  List<DocumentSnapshot> get suspensions => _rawSuspensionSnaps; 
  List<DocumentSnapshot> _rawSponsorsSnaps = [];
  List<DocumentSnapshot> get sponsorsDocs => _rawSponsorsSnaps;

  PhotoProduct? get latestPhotoProduct => _cachedLatestPhotoProduct;
  Map<String, dynamic>? get appSettings => _cachedAppSettings;

  ChampionshipService(); 

  Future<bool> checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _isOffline = (result == ConnectivityResult.none);
    notifyListeners();
    return !_isOffline;
  }

  // ===========================================================================
  // 🚀 INICIALIZAÇÃO
  // ===========================================================================

  Future<void> init() async {
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
      final snapshot = await _firestore.collection('championships').get();

      _availableSeasons = snapshot.docs.map((doc) {
        final data = doc.data();
        
        // CORREÇÃO: Parsing robusto para o ano virar inteiro independente do tipo no Firestore
        int parsedYear = DateTime.now().year;
        if (data['year'] != null) {
          parsedYear = int.tryParse(data['year'].toString()) ?? parsedYear;
        }
        
        return {
          'id': doc.id,
          'name': data['name'] ?? doc.id,
          'year': parsedYear,
          'honoree': data['honoree'] ?? '',
          'isActive': data['is_active'] ?? false,
        };
      }).toList();

      // Ordena por ano descendente
      _availableSeasons.sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));

      if (_availableSeasons.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final savedSeasonId = prefs.getString('selected_season_id');
        
        String targetId = '';

        if (savedSeasonId != null && _availableSeasons.any((s) => s['id'] == savedSeasonId)) {
           targetId = savedSeasonId;
        } else {
           // Pega a temporada marcada como ativa, ou a mais recente
           final activeSeason = _availableSeasons.firstWhere(
             (s) => s['isActive'] == true, 
             orElse: () => _availableSeasons.first
           );
           targetId = activeSeason['id'];
        }
        
        await _setSeasonInternal(targetId);
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
  // 📦 FETCH OTIMIZADO
  // ===========================================================================

  Future<void> fetchStaticData({bool forceRefresh = false, bool refreshMatchesOnly = false}) async {
    if (_currentSeasonId.isEmpty) return;
    if (_isFetchingStaticData) return;
    if (!await checkConnectivity()) return;

    _isFetchingStaticData = true;
    _isLoading = true;
    notifyListeners();

    try {
      if (forceRefresh || refreshMatchesOnly || _isExpired(_lastMatchesFetch, MATCHES_CACHE_TTL)) {
        await _fetchMatches();
      }

      if (!refreshMatchesOnly) {
        if (forceRefresh || _isExpired(_lastTeamsFetch, TEAMS_CACHE_TTL)) {
          await _fetchTeams();
        }
        if (forceRefresh || _isExpired(_lastMiscFetch, MISC_CACHE_TTL)) {
          await _fetchMisc();
        }
      }
      debugPrint("📦 [CACHE] Dados atualizados com segurança.");
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

  Future<void> _fetchMatches() async {
    final snapshot = await _firestore.collection('championships').doc(_currentSeasonId).collection('matches').orderBy('datetime').get();
    _cachedMatches = snapshot.docs.map((doc) => MatchModel.fromFirestore(doc)).toList();
    _lastMatchesFetch = DateTime.now();
  }

  Future<void> _fetchTeams() async {
    final snapshot = await _firestore.collection('championships').doc(_currentSeasonId).collection('teams_participation').get();
    _cachedTeams = snapshot.docs.map((doc) => Team.fromFirestore(doc)).toList();
    _cachedTeams.sort((a, b) => a.name.compareTo(b.name));
    _lastTeamsFetch = DateTime.now();
  }

  Future<void> _fetchMisc() async {
    await _fetchSponsors();
    await _fetchConfig();
    await _fetchNews();
    await _fetchSuspensions();
    await _fetchLatestPhoto();
    _lastMiscFetch = DateTime.now();
  }

  Future<void> _fetchSponsors() async {
    final snapshot = await _firestore.collection('sponsors').where('isActive', isEqualTo: true).orderBy('order').get();
    _rawSponsorsSnaps = snapshot.docs;
    _cachedSponsors = snapshot.docs.map((d) => d.data()).toList();
  }

  Future<void> _fetchConfig() async {
    final doc = await _firestore.collection('championships').doc(_currentSeasonId).collection('settings').doc('app_settings').get();
    if (doc.exists) _cachedAppSettings = doc.data();
  }

  Future<void> _fetchNews() async {
    final snapshot = await _firestore.collection('championships').doc(_currentSeasonId).collection('news').where('isActive', isEqualTo: true).orderBy('order', descending: true).limit(10).get();
    _cachedNews = snapshot.docs.map((d) => d.data()).toList();
  }

  Future<void> _fetchSuspensions() async {
    final snapshot = await _firestore.collection('championships').doc(_currentSeasonId).collection('disciplinary_log').orderBy('timestamp', descending: true).get();
    _rawSuspensionSnaps = snapshot.docs;
    _cachedSuspensions = snapshot.docs.map((d) => d.data()).toList();
  }

  Future<void> _fetchLatestPhoto() async {
    final snapshot = await _firestore.collection('photo_sales').orderBy('taken_at', descending: true).limit(1).get();
    if (snapshot.docs.isNotEmpty) _cachedLatestPhotoProduct = PhotoProduct.fromFirestore(snapshot.docs.first);
  }

  // ===========================================================================
  // 👥 GESTÃO DE ELENCO
  // ===========================================================================
  
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

    try {
      final snapshot = await _firestore.collection('championships').doc(_currentSeasonId)
          .collection('player_stats').where('team_id', isEqualTo: teamId).where('isActive', isEqualTo: true).get();

      final roster = snapshot.docs.map((d) => Player.fromFirestore(d)).toList();
      _sortRoster(roster);

      _cachedPlayersByTeam[teamId] = roster;
      _lastTeamRosterFetch[teamId] = DateTime.now();
      
      notifyListeners();
      return roster;
    } catch (e) {
      debugPrint("Erro ao carregar elenco $teamId: $e");
      return [];
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
      final snapshot = await _firestore.collection('championships').doc(_currentSeasonId)
          .collection('player_stats').where('isActive', isEqualTo: true).get();
      
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
    await _setSeasonInternal(seasonId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_season_id', seasonId);
  }

  Future<void> _setSeasonInternal(String seasonId) async {
    final season = _availableSeasons.firstWhere(
      (s) => s['id'] == seasonId,
      orElse: () => {'id': '', 'name': 'Desconhecido', 'year': DateTime.now().year, 'honoree': ''},
    );
    
    if (season['id'] != '') {
      _currentSeasonId = seasonId;
      _currentSeasonName = season['name'];
      
      // DINAMISMO DO ANO: Agora garantimos que o ano seja atualizado na memória
      _currentSeasonYear = season['year'] as int;
      _currentSeasonHonoree = season['honoree'] ?? '';
      
      // Carrega regras da temporada selecionada
      await AdminService.loadAllRules(seasonId);

      // Limpa caches da temporada anterior
      _cachedTeams = []; 
      _cachedPlayersByTeam.clear(); 
      _allPlayersCache = []; 
      _cachedMatches = [];
      _cachedSponsors = [];
      _cachedNews = [];
      
      _lastTeamsFetch = null; 
      _lastMatchesFetch = null; 
      _lastMiscFetch = null; 
      _lastTeamRosterFetch.clear();
      _lastAllPlayersFetch = null;
      
      // Força recarga dos dados estáticos da nova temporada
      await fetchStaticData(forceRefresh: true);
    }
    notifyListeners(); // Notifica a UI (Header, Home, Drawer) para atualizar o ano
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
      await init(); 
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
      await init();
      return "Sucesso";
    } catch (e) { return "Erro: $e"; }
  }
  
   Future<String> updateSeason(String seasonId, String name, String honoree) async {
    try {
      await _firestore.collection('championships').doc(seasonId).update({'name': name, 'honoree': honoree});
      await init(); 
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