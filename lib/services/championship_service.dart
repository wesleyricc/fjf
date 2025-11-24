import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firestore_service.dart'; // <-- Importante para acessar LEGACY_ID
import 'admin_service.dart';

class ChampionshipService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Estado
  String _currentSeasonId = FirestoreService.LEGACY_ID;
  String _currentSeasonName = 'Carregando...';
  int _currentSeasonYear = 2025;
  String _currentSeasonHonoree = '';
  
  List<Map<String, dynamic>> _availableSeasons = [];
  bool _isLoading = true;

  // Getters
  String get currentSeasonId => _currentSeasonId;
  String get currentSeasonName => _currentSeasonName;
  int get currentSeasonYear => _currentSeasonYear;
  String get currentSeasonHonoree => _currentSeasonHonoree;
  
  List<Map<String, dynamic>> get availableSeasons => _availableSeasons;
  bool get isLoading => _isLoading;

  ChampionshipService() {
    _init();
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('championships')
          .orderBy('year', descending: true)
          .get();

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

        // --- CORREÇÃO AQUI ---
        // Inicializa com valor seguro para evitar erro de Null Safety
        String targetId = FirestoreService.LEGACY_ID; 

        if (savedSeasonId != null && _availableSeasons.any((s) => s['id'] == savedSeasonId)) {
           targetId = savedSeasonId;
        } else {
           // Busca a temporada marcada como ativa no banco
           final activeSeason = _availableSeasons.firstWhere(
            (s) => s['isActive'] == true,
            orElse: () => _availableSeasons.first, 
          );
          targetId = activeSeason['id'];
        }
        
        _setSeasonInternal(targetId); // Agora targetId é garantido como String
        
      } else {
        // Fallback Legado
        _setSeasonInternal(FirestoreService.LEGACY_ID);
      }

    } catch (e) {
      debugPrint("Erro ao carregar temporadas: $e");
      _setSeasonInternal(FirestoreService.LEGACY_ID);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setSeason(String seasonId) async {
    await _setSeasonInternal(seasonId); // Agora espera carregar regras
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_season_id', seasonId);
  }

  // Define como Ativa Globalmente
  Future<String> setGlobalActiveSeason(String seasonId) async {
    try {
      final batch = _firestore.batch();

      final allDocs = await _firestore.collection('championships').get();
      for (var doc in allDocs.docs) {
        if (doc.data()['is_active'] == true) {
          batch.update(doc.reference, {'is_active': false});
        }
      }

      if (seasonId != FirestoreService.LEGACY_ID) {
        final targetRef = _firestore.collection('championships').doc(seasonId);
        batch.update(targetRef, {'is_active': true});
      }

      await batch.commit();
      await _init();
      await setSeason(seasonId); 

      return "Sucesso";
    } catch (e) {
      return "Erro ao ativar temporada: $e";
    }
  }

  Future<void> _setSeasonInternal(String seasonId) async {
    if (seasonId == FirestoreService.LEGACY_ID) {
      _currentSeasonId = seasonId;
      _currentSeasonName = 'FJF 2025 (Original)';
      _currentSeasonYear = 2025;
      _currentSeasonHonoree = 'Taça Mary Neusa Espíndola Bif';
    } else {
      final season = _availableSeasons.firstWhere(
        (s) => s['id'] == seasonId,
        orElse: () => {'id': seasonId, 'name': 'Desconhecido', 'year': 0, 'honoree': ''},
      );
      
      _currentSeasonId = seasonId;
      _currentSeasonName = season['name'];
      _currentSeasonYear = season['year'];
      _currentSeasonHonoree = season['honoree'] ?? '';
    }

    await AdminService.loadAllRules(seasonId);
    notifyListeners();
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
      
      if (copyTeams) {
        await FirestoreService().copySeasonData(
          sourceSeasonId: _currentSeasonId,
          targetSeasonId: docId,
          includeRoster: copyPlayers,
        );
      }
      
      await _init();
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
      await _init(); 
      if (_currentSeasonId == seasonId) _setSeasonInternal(seasonId);
      return "Sucesso";
    } catch (e) {
      return "Erro: $e";
    }
  }
}