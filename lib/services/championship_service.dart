import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_service.dart';
import 'firestore_service.dart'; 
import '../models/team_model.dart'; 
import '../models/player_model.dart'; // Import para o cache de elenco
import '../models/photo_product_model.dart'; // Import para o cache da loja

class ChampionshipService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Estado Atual
  String _currentSeasonId = '';
  String _currentSeasonName = 'Carregando...';
  int _currentSeasonYear = DateTime.now().year;
  String _currentSeasonHonoree = '';
  
  List<Map<String, dynamic>> _availableSeasons = [];
  bool _isLoading = false; 

  // --- CACHE CENTRALIZADO (OTIMIZAÇÃO DE CUSTO) ---
  List<Team> _cachedTeams = [];
  List<DocumentSnapshot> _cachedSponsors = [];
  
  // Cache Home
  PhotoProduct? _cachedLatestPhotoProduct;
  Map<String, dynamic>? _cachedAppSettings; // Para o vídeo ao vivo

  // Cache Elencos (Evita baixar jogadores repetidamente)
  final Map<String, List<Player>> _rosterCache = {};

  bool _hasLoadedStaticData = false;

  // Getters
  String get currentSeasonId => _currentSeasonId;
  String get currentSeasonName => _currentSeasonName;
  int get currentSeasonYear => _currentSeasonYear;
  String get currentSeasonHonoree => _currentSeasonHonoree;
  
  List<Map<String, dynamic>> get availableSeasons => _availableSeasons;
  bool get isLoading => _isLoading;

  // Getters do Cache
  List<Team> get teams => _cachedTeams;
  List<DocumentSnapshot> get sponsors => _cachedSponsors;
  PhotoProduct? get latestPhotoProduct => _cachedLatestPhotoProduct;
  Map<String, dynamic>? get appSettings => _cachedAppSettings;

  ChampionshipService(); 

  // --- MÉTODO init ---
  Future<void> init() async {
    if (_isLoading) return; 

    _isLoading = true;
    notifyListeners(); 

    try {
      final snapshot = await _firestore.collection('championships').get();

      print("SERVICE INIT: Encontrados ${snapshot.docs.length} documentos.");

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

  // --- OTIMIZAÇÃO: Carrega TUDO da Home UMA VEZ ---
  Future<void> fetchStaticData() async {
    if (_currentSeasonId.isEmpty) return;
    if (_hasLoadedStaticData) return;

    try {
      debugPrint("🔥 CUSTO FIREBASE: Baixando Dados Estáticos da Home (Leitura Única)...");
      
      // Executa todas as queries em paralelo para ser rápido
      final results = await Future.wait([
        // 0: Times
        _firestore.collection('teams').where('seasonId', isEqualTo: _currentSeasonId).get(),
        // 1: Patrocinadores
        _firestore.collection('sponsors').where('isActive', isEqualTo: true).orderBy('order').get(),
        // 2: Foto Capa Loja (Limit 1)
        _firestore.collection('photo_sales').orderBy('taken_at', descending: true).limit(1).get(),
        // 3: Config App (Vídeo)
        _firestore.collection('config').doc('app_settings').get(),
      ]);
      
      // Processa Times
      final teamsSnap = results[0] as QuerySnapshot;
      _cachedTeams = teamsSnap.docs.map((doc) => Team.fromFirestore(doc)).toList();

      // Processa Patrocinadores
      final sponsorsSnap = results[1] as QuerySnapshot;
      _cachedSponsors = sponsorsSnap.docs;

      // Processa Foto Loja
      final photoSnap = results[2] as QuerySnapshot;
      if (photoSnap.docs.isNotEmpty) {
        _cachedLatestPhotoProduct = PhotoProduct.fromFirestore(photoSnap.docs.first);
      }

      // Processa Config App
      final configSnap = results[3] as DocumentSnapshot;
      if (configSnap.exists) {
        _cachedAppSettings = configSnap.data() as Map<String, dynamic>;
      }
      
      _hasLoadedStaticData = true;
      notifyListeners();
    } catch (e) {
      debugPrint("Erro ao carregar dados estáticos: $e");
    }
  }

  // --- MÉTODOS DE CACHE DE ELENCO ---
  bool hasRosterCached(String teamId) => _rosterCache.containsKey(teamId);

  List<Player> getCachedRoster(String teamId) => _rosterCache[teamId] ?? [];

  void cacheRoster(String teamId, List<Player> players) {
    _rosterCache[teamId] = players;
    // Não precisa de notifyListeners() aqui pois quem usa gerencia seu estado local
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

      // Limpa TODOS os caches ao mudar temporada
      _cachedTeams = [];
      _cachedSponsors = [];
      _rosterCache.clear();
      _cachedLatestPhotoProduct = null;
      _cachedAppSettings = null;
      _hasLoadedStaticData = false;
      
      fetchStaticData();
    }
    notifyListeners();
  }

  // Métodos de Admin (createSeason, updateSeason, etc) mantidos...
  Future<String> setGlobalActiveSeason(String seasonId) async {
    try {
      final batch = _firestore.batch();
      final allDocs = await _firestore.collection('championships').get();
      for (var doc in allDocs.docs) {
        if (doc.data()['is_active'] == true) {
          batch.update(doc.reference, {'is_active': false});
        }
      }
      final targetRef = _firestore.collection('championships').doc(seasonId);
      batch.update(targetRef, {'is_active': true});
      await batch.commit();
      
      await init(); 
      await setSeason(seasonId); 
      return "Sucesso";
    } catch (e) {
      return "Erro ao ativar temporada: $e";
    }
  }
  
  Future<String> createSeason(int year, String name, String honoree, {bool copyTeams = false, bool copyPlayers = false}) async {
    try {
      final docId = '${year}_fjf';
      final doc = await _firestore.collection('championships').doc(docId).get();
      if (doc.exists) return "Temporada já existe.";

      await _firestore.collection('championships').doc(docId).set({
        'year': year,
        'name': name,
        'honoree': honoree,
        'is_active': false,
        'status': 'open',
        'created_at': FieldValue.serverTimestamp(),
      });
      
      if (copyTeams && _currentSeasonId.isNotEmpty) {
        await FirestoreService().copySeasonData(
          sourceSeasonId: _currentSeasonId,
          targetSeasonId: docId,
          includeRoster: copyPlayers,
        );
      }
      
      await init();
      return "Sucesso";
    } catch (e) {
      return "Erro: $e";
    }
  }
  
   Future<String> updateSeason(String seasonId, String name, String honoree) async {
    try {
      await _firestore.collection('championships').doc(seasonId).update({
        'name': name,
        'honoree': honoree,
      });
      await init(); 
      if (_currentSeasonId == seasonId) _setSeasonInternal(seasonId);
      return "Sucesso";
    } catch (e) {
      return "Erro: $e";
    }
  }
}