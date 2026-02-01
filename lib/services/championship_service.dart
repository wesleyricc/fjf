import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_service.dart';
import 'firestore_service.dart'; 

class ChampionshipService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Estado Atual
  String _currentSeasonId = '';
  String _currentSeasonName = 'Carregando...';
  int _currentSeasonYear = DateTime.now().year;
  String _currentSeasonHonoree = '';
  
  List<Map<String, dynamic>> _availableSeasons = [];
  bool _isLoading = false; // Começa falso, a Splash que ativa

  // Getters
  String get currentSeasonId => _currentSeasonId;
  String get currentSeasonName => _currentSeasonName;
  int get currentSeasonYear => _currentSeasonYear;
  String get currentSeasonHonoree => _currentSeasonHonoree;
  
  List<Map<String, dynamic>> get availableSeasons => _availableSeasons;
  bool get isLoading => _isLoading;

  // --- ALTERAÇÃO 1: Construtor Vazio (Não chama init aqui) ---
  ChampionshipService(); 

  // --- ALTERAÇÃO 2: Método Público (init) ---
  Future<void> init() async {
    // Evita chamadas duplicadas
    if (_isLoading) return; 

    _isLoading = true;
    // O notifyListeners aqui é opcional na primeira chamada, 
    // mas bom para garantir que a UI mostre o loading
    notifyListeners(); 

    try {
      // Busca todas as temporadas padronizadas ordenadas por ano (decrescente)
      final snapshot = await _firestore
          .collection('championships')
          //.orderBy('year', descending: true)
          .get();

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

      if (_availableSeasons.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final savedSeasonId = prefs.getString('selected_season_id');
        
        String targetId = '';

        // 1. Tenta recuperar a última selecionada pelo usuário
        if (savedSeasonId != null && _availableSeasons.any((s) => s['id'] == savedSeasonId)) {
           targetId = savedSeasonId;
        } 
        // 2. Se não, tenta pegar a temporada marcada como "Ativa" (Padrão Global)
        else {
           final activeSeason = _availableSeasons.firstWhere(
             (s) => s['isActive'] == true, 
             orElse: () => _availableSeasons.first
           );
           targetId = activeSeason['id'];
        }
        
        await _setSeasonInternal(targetId);
      } else {
        // Caso: Nenhuma temporada padronizada encontrada (App novo ou pré-migração)
        _currentSeasonName = "Nenhuma Temporada";
        _currentSeasonId = "";
        _currentSeasonHonoree = "";
        
        // Garante que o AdminService tenha valores padrão seguros
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

  Future<void> setSeason(String seasonId) async {
    await _setSeasonInternal(seasonId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_season_id', seasonId);
  }

  // Define a temporada globalmente ativa (padrão para novos usuários)
  Future<String> setGlobalActiveSeason(String seasonId) async {
    try {
      final batch = _firestore.batch();

      // Desativa todas
      final allDocs = await _firestore.collection('championships').get();
      for (var doc in allDocs.docs) {
        if (doc.data()['is_active'] == true) {
          batch.update(doc.reference, {'is_active': false});
        }
      }

      // Ativa a alvo
      final targetRef = _firestore.collection('championships').doc(seasonId);
      batch.update(targetRef, {'is_active': true});

      await batch.commit();
      
      // Recarrega estado local para refletir a mudança na UI
      await init(); // Chama o init público agora
      // Força a seleção da nova temporada ativa
      await setSeason(seasonId); 

      return "Sucesso";
    } catch (e) {
      return "Erro ao ativar temporada: $e";
    }
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
      
      // Carrega regras específicas desta temporada
      await AdminService.loadAllRules(seasonId);
    }
    notifyListeners();
  }

  Future<String> createSeason(int year, String name, String honoree, {bool copyTeams = false, bool copyPlayers = false}) async {
    try {
      final docId = '${year}_fjf';
      final doc = await _firestore.collection('championships').doc(docId).get();
      if (doc.exists) return "Temporada já existe.";

      // Cria o documento da temporada
      await _firestore.collection('championships').doc(docId).set({
        'year': year,
        'name': name,
        'honoree': honoree,
        'is_active': false,
        'status': 'open',
        'created_at': FieldValue.serverTimestamp(),
      });
      
      // Copia dados da temporada ATUAL para a NOVA
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