import 'dart:async';
import 'dart:io'; 
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart'; 
import 'package:connectivity_plus/connectivity_plus.dart'; 
import 'package:image_picker/image_picker.dart'; 

import '../services/analytics_service.dart';
import '../models/fantasy_models.dart';
import '../repositories/fantasy_repository.dart'; 
import '../services/fantasy_service.dart';
import '../services/fantasy_scout_service.dart';

class FantasyHomeViewModel extends ChangeNotifier {
  final FantasyRepository _repository = FantasyRepository();
  final FantasyService _fantasyService = FantasyService();
  final FantasyScoutService _scoutService = FantasyScoutService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance; 

  String? _loadedUserId;
  String? _loadedSeasonId;
  bool _isOffline = false; 
  bool _isDisposed = false;

  bool _isLoading = true;
  String? _errorMessage;

  bool _isMarketOpen = true;
  int _currentRound = 1;
  FantasyGameConfig _gameConfig = FantasyGameConfig.defaults();

  FantasyTeam? _team;
  Map<String, LiveScoreData> _liveScores = {}; 
  final Map<String, String> _playerTeamMap = {};

  StreamSubscription? _marketSub;
  StreamSubscription? _teamSub;
  StreamSubscription? _matchesSub;

  bool get isOffline => _isOffline; 
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isMarketOpen => _isMarketOpen;
  int get currentRound => _currentRound;
  FantasyTeam? get team => _team;
  Map<String, LiveScoreData> get liveScores => _liveScores;
  FantasyGameConfig get config => _gameConfig;

  double get teamPartialScore {
    if (_team == null || _liveScores.isEmpty) return 0.0;
    double total = 0.0;
    for (String pid in _team!.lineupPlayerIds) {
      final scoreData = _liveScores[pid];
      if (scoreData != null) {
        double pScore = scoreData.totalScore;
        if (_team!.captainId == pid) pScore *= 2; 
        total += pScore;
      }
    }
    return double.parse(total.toStringAsFixed(2));
  }

  Future<bool> updateTeamProfile({
    required String newName,
    String? selectedPresetUrl,
    XFile? imageFile,
  }) async {
    if (_team == null) return false;
    _setLoading(true);

    try {
      String? finalLogoUrl = selectedPresetUrl;

      if (imageFile != null) {
        final ref = _storage
            .ref()
            .child('fantasy_teams')
            .child('${_team!.userId}_logo.jpg');
        
        if (kIsWeb) {
          final bytes = await imageFile.readAsBytes();
          await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        } else {
          await ref.putFile(File(imageFile.path));
        }

        finalLogoUrl = await ref.getDownloadURL();
      } 

      final Map<String, dynamic> updates = {
        'team_name': newName.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (finalLogoUrl != null) {
        updates['custom_logo_url'] = finalLogoUrl;
      }

      await _firestore.collection('fantasy_teams').doc(_team!.userId).update(updates);

      _setLoading(false);
      return true;
    } catch (e) {
      debugPrint("Erro ao atualizar perfil: $e");
      _errorMessage = "Falha ao salvar: $e";
      _setLoading(false);
      return false;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    if (!_isDisposed) notifyListeners();
  }

  Future<bool> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _isOffline = result == ConnectivityResult.none;
    if (!_isDisposed) notifyListeners();
    return !_isOffline;
  }

  Future<void> init(String userId, String seasonId, {bool force = false}) async {
    if (!force && _loadedUserId == userId && _loadedSeasonId == seasonId && !_isLoading) return;

    _loadedUserId = userId;
    _loadedSeasonId = seasonId;
    _isLoading = true;
    if (!_isDisposed) notifyListeners();

    if (!await _checkConnectivity()) {
      _isLoading = false;
      if (!_isDisposed) notifyListeners();
      return; 
    }

    try {
      _gameConfig = await _fantasyService.getGameConfig();
      await _loadPlayerTeamMap();
    } catch (e) {
      debugPrint("Aviso: Falha ao carregar configurações: $e");
    }

    _marketSub?.cancel();
    _marketSub = _repository.streamMarketStatus().listen((status) {
      _isMarketOpen = status['is_open'] ?? true;
      _currentRound = status['current_round'] ?? 1;
      
      if (!_isMarketOpen) {
        _subscribeToLiveMatches(seasonId, _currentRound);
      } else {
        _matchesSub?.cancel();
        _liveScores = {}; 
        if (!_isDisposed) notifyListeners();
      }
    });

    _teamSub?.cancel();
    _teamSub = _repository.streamUserTeam(userId).listen((team) {
      _team = team;
      if (!_isMarketOpen) {
        _subscribeToLiveMatches(seasonId, _currentRound);
      }
      _isLoading = false;

      // 🚨 EVENTO DE NEGÓCIO: O usuário carregou o painel do time
      if (team != null) AnalyticsService.logFantasyAccess(userId);
      
      if (!_isDisposed) notifyListeners();
    });
  }

  Future<void> _loadPlayerTeamMap() async {
    try {
      final players = await _repository.getAllPlayers();
      _playerTeamMap.clear();
      for (var p in players) {
        _playerTeamMap[p.playerId] = p.teamId;
      }
    } catch (e) {
      debugPrint("Erro ao mapear times: $e");
    }
  }

  void _subscribeToLiveMatches(String seasonId, int round) {
    if (_team == null) return;
    _matchesSub?.cancel(); 
    
    // 📡 Escuta o documento único da rodada
    _matchesSub = _scoutService.streamLiveScores(seasonId, round).listen((scores) {
      Map<String, LiveScoreData> calculatedScores = {};
      
      for (String pid in _team!.lineupPlayerIds) {
         final s = scores[pid] ?? FantasyScoutDetail(totalScore: 0.0);
         calculatedScores[pid] = LiveScoreData(
           totalScore: s.totalScore,
           isCaptain: (_team!.captainId == pid),
           goals: s.goals,
           assists: s.assists,
           yellows: s.yellows,
           reds: s.reds,
           goalsConceded: s.goalsConceded,
         );
      }
      
      _liveScores = calculatedScores;
      if (!_isDisposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _marketSub?.cancel();
    _teamSub?.cancel();
    _matchesSub?.cancel();
    super.dispose();
  }
}

class LiveScoreData {
  final double totalScore;
  final bool isCaptain;
  final int goals;
  final int assists;
  final int yellows;
  final int reds;
  final int goalsConceded;

  LiveScoreData({
    required this.totalScore,
    required this.isCaptain,
    this.goals = 0,
    this.assists = 0,
    this.yellows = 0,
    this.reds = 0,
    this.goalsConceded = 0,
  });
}