import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_service.dart';
import '../models/team_model.dart'; 
import '../models/player_model.dart'; 
import '../models/photo_product_model.dart'; 
import '../models/match_model.dart';

class ChampionshipService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Estado Atual
  String _currentSeasonId = '';
  String _currentSeasonName = 'Carregando...';
  int _currentSeasonYear = DateTime.now().year;
  String _currentSeasonHonoree = '';
  
  List<Map<String, dynamic>> _availableSeasons = [];
  bool _isLoading = false; 

  // --- CACHE CENTRALIZADO ---
  List<Team> _cachedTeams = [];
  List<Player> _cachedPlayers = [];
  List<DocumentSnapshot> _cachedSponsors = [];
  List<Map<String, dynamic>> _cachedNews = [];
  List<MatchModel> _cachedMatches = [];
  List<DocumentSnapshot> _cachedSuspensions = [];
  
  // Cache Home
  PhotoProduct? _cachedLatestPhotoProduct;
  Map<String, dynamic>? _cachedAppSettings; 

  // Cache Elencos
  final Map<String, List<Player>> _rosterCache = {};

  bool _hasLoadedStaticData = false;
  
  // Constante de Validade do Cache
  static const int CACHE_VALIDITY_MINUTES = 15;

  // Getters
  String get currentSeasonId => _currentSeasonId;
  String get currentSeasonName => _currentSeasonName;
  int get currentSeasonYear => _currentSeasonYear;
  String get currentSeasonHonoree => _currentSeasonHonoree;
  
  List<Map<String, dynamic>> get availableSeasons => _availableSeasons;
  bool get isLoading => _isLoading;

  // Getters do Cache
  List<Team> get teams => _cachedTeams;
  List<Player> get allPlayers => _cachedPlayers;
  List<DocumentSnapshot> get sponsors => _cachedSponsors;
  List<Map<String, dynamic>> get news => _cachedNews;
  List<MatchModel> get matches => _cachedMatches;
  List<DocumentSnapshot> get suspensions => _cachedSuspensions;
  PhotoProduct? get latestPhotoProduct => _cachedLatestPhotoProduct;
  Map<String, dynamic>? get appSettings => _cachedAppSettings;

  ChampionshipService(); 

  Future<void> init() async {
    if (_isLoading) return; 

    _isLoading = true;
    notifyListeners(); 

    try {
      final snapshot = await _firestore.collection('championships').get();

      _availableSeasons = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? doc.id,
          'year': data['year'] ?? 0,
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
        
        await _setSeasonInternal(targetId);
      } else {
        _currentSeasonName = "Nenhuma Temporada";
        _currentSeasonId = "";
        
        AdminService.pendingYellowCards = 2;
        AdminService.suspensionYellowCards = 3;
      }

    } catch (e) {
      debugPrint("Erro inicialização ChampionshipService: $e");
      _currentSeasonName = "Erro de Conexão";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchStaticData({bool forceRefresh = false}) async {
    if (_currentSeasonId.isEmpty) return;
    if (_hasLoadedStaticData && !forceRefresh) return;

    try {
      Source source = Source.server;
      
      if (!forceRefresh) {
        final prefs = await SharedPreferences.getInstance();
        final lastFetch = prefs.getInt('last_static_fetch_${_currentSeasonId}') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        final diffMinutes = (now - lastFetch) / 1000 / 60;

        if (diffMinutes < CACHE_VALIDITY_MINUTES) {
          source = Source.cache;
          debugPrint("💾 [CACHE] Usando dados locais (Última atualização: ${diffMinutes.toStringAsFixed(1)} min atrás).");
        } else {
          debugPrint("☁️ [SERVER] Cache expirado. Buscando dados novos...");
        }
      } else {
        debugPrint("🔄 [REFRESH] Forçando atualização do servidor...");
      }

      try {
        await _performFetch(source);
      } catch (e) {
        if (source == Source.cache) {
          debugPrint("⚠️ Erro ao ler cache ($e). Tentando servidor...");
          await _performFetch(Source.server);
        } else {
          rethrow;
        }
      }
      
      if (source == Source.server) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_static_fetch_${_currentSeasonId}', DateTime.now().millisecondsSinceEpoch);
      }

      _hasLoadedStaticData = true;
      notifyListeners();

    } catch (e) {
      debugPrint("❌ Erro fatal ao carregar dados estáticos: $e");
    }
  }

  Future<void> _performFetch(Source source) async {
    final options = GetOptions(source: source);

    final results = await Future.wait([
      _firestore.collection('championships').doc(_currentSeasonId).collection('teams_participation').get(options),
      _firestore.collection('sponsors').where('isActive', isEqualTo: true).orderBy('order').get(options),
      _firestore.collection('photo_sales').orderBy('taken_at', descending: true).limit(1).get(options),
      _firestore.collection('config').doc('app_settings').get(options),
      _firestore.collection('championships').doc(_currentSeasonId).collection('player_stats').where('isActive', isEqualTo: true).get(options),
      _firestore.collection('championships').doc(_currentSeasonId).collection('news').where('isActive', isEqualTo: true).orderBy('order', descending: true).limit(10).get(options),
      _firestore.collection('championships').doc(_currentSeasonId).collection('matches').orderBy('datetime').get(options),
      _firestore.collection('championships').doc(_currentSeasonId).collection('disciplinary_log').orderBy('return_date', descending: true).get(options),
    ]);
    
    final teamsSnap = results[0] as QuerySnapshot;
    _cachedTeams = teamsSnap.docs.map((doc) => Team.fromFirestore(doc)).toList();
    _cachedTeams.sort((a, b) => a.name.compareTo(b.name));

    final sponsorsSnap = results[1] as QuerySnapshot;
    _cachedSponsors = sponsorsSnap.docs;

    final photoSnap = results[2] as QuerySnapshot;
    if (photoSnap.docs.isNotEmpty) {
      _cachedLatestPhotoProduct = PhotoProduct.fromFirestore(photoSnap.docs.first);
    }

    final configSnap = results[3] as DocumentSnapshot;
    if (configSnap.exists) {
      _cachedAppSettings = configSnap.data() as Map<String, dynamic>;
    }

    final playersSnap = results[4] as QuerySnapshot;
    _cachedPlayers = playersSnap.docs.map((doc) => Player.fromFirestore(doc)).toList();

    final newsSnap = results[5] as QuerySnapshot;
    _cachedNews = newsSnap.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

    final matchesSnap = results[6] as QuerySnapshot;
    _cachedMatches = matchesSnap.docs.map((doc) => MatchModel.fromFirestore(doc)).toList();

    final suspensionSnap = results[7] as QuerySnapshot;
    _cachedSuspensions = suspensionSnap.docs;

    debugPrint("✅ Dados carregados (${source.name.toUpperCase()}). Times: ${_cachedTeams.length}, Jogadores: ${_cachedPlayers.length}");
  }

  // --- MÉTODOS DE CACHE DE ELENCO ---
  bool hasRosterCached(String teamId) => _rosterCache.containsKey(teamId);

  List<Player> getCachedRoster(String teamId) {
    if (_rosterCache.containsKey(teamId)) return _rosterCache[teamId]!;
    
    if (_cachedPlayers.isNotEmpty) {
      final roster = _cachedPlayers.where((p) => p.teamId == teamId).toList();
      roster.sort((a, b) {
         if (a.isGoalkeeper && !b.isGoalkeeper) return -1;
         if (!a.isGoalkeeper && b.isGoalkeeper) return 1;
         return (a.jerseyNumber ?? 99).compareTo(b.jerseyNumber ?? 99);
      });
      _rosterCache[teamId] = roster;
      return roster;
    }
    return [];
  }

  void cacheRoster(String teamId, List<Player> players) {
    _rosterCache[teamId] = players;
  }

  Future<void> setSeason(String seasonId) async {
    await _setSeasonInternal(seasonId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_season_id', seasonId);
  }

  Future<void> _setSeasonInternal(String seasonId) async {
    final season = _availableSeasons.firstWhere(
      (s) => s['id'] == seasonId,
      orElse: () => {'id': '', 'name': 'Desconhecido', 'year': 0, 'honoree': ''},
    );
    
    if (season['id'] != '') {
      _currentSeasonId = seasonId;
      _currentSeasonName = season['name'];
      _currentSeasonYear = season['year'];
      _currentSeasonHonoree = season['honoree'] ?? '';
      
      await AdminService.loadAllRules(seasonId);

      _cachedTeams = [];
      _cachedPlayers = [];
      _cachedSponsors = [];
      _cachedNews = [];
      _cachedMatches = [];
      _cachedSuspensions = [];
      _rosterCache.clear();
      _cachedLatestPhotoProduct = null;
      _cachedAppSettings = null;
      _hasLoadedStaticData = false;
      
      fetchStaticData();
    }
    notifyListeners();
  }

  // Métodos Admin
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
        // Implementação interna da cópia
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

  // --- LÓGICA DE MIGRAÇÃO INTERNA ---
  Future<void> _copySeasonData({required String sourceSeasonId, required String targetSeasonId, required bool includeRoster}) async {
    final batch = _firestore.batch();
    
    // Configurações
    for (String docId in ['app_settings', 'disciplinary_rules', 'playoff_rules', 'tiebreaker_rules']) { 
      final docSnap = await _firestore.collection('championships').doc(sourceSeasonId).collection('settings').doc(docId).get(); 
      if (docSnap.exists) {
        batch.set(_firestore.collection('championships').doc(targetSeasonId).collection('settings').doc(docId), docSnap.data()!); 
      }
    }
    
    // Times
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