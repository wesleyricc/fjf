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

  StreamSubscription? _marketSub;
  StreamSubscription? _teamSub;
  StreamSubscription? _matchesSub;
  StreamSubscription? _marketStatsSub;

  FantasyPlayer? mostSelectedPlayer;
  FantasyPlayer? mostSelectedCaptain;
  FantasyPlayer? topScorer;
  FantasyPlayer? worstScorer;
  int mostSelectedCount = 0;
  int mostSelectedCaptainCount = 0;
  double topScore = 0.0;
  double worstScore = 0.0;

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
    String? selectedPresetUrl, // Nova opção: URL de escudo pronto
    XFile? imageFile,          // Opção existente: Upload de arquivo
  }) async {
    if (_team == null) return false;
    _setLoading(true);

    try {
      String? finalLogoUrl = selectedPresetUrl;

      // Se o usuário selecionou um arquivo do celular, o upload tem prioridade
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

      // Só atualiza a logo se houver uma nova (Preset ou Upload)
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
    } catch (e) {
      debugPrint("Aviso: Falha ao carregar configurações: $e");
    }

    _marketSub?.cancel();
    _marketSub = _repository.streamMarketStatus().listen((status) {
      _isMarketOpen = status['is_open'] ?? true;
      _currentRound = status['current_round'] ?? 1;
      
      if (!_isMarketOpen) {
        _subscribeToLiveMatches(seasonId, _currentRound);
        _listenToMarketStats();
      } else {
        _matchesSub?.cancel();
        _marketStatsSub?.cancel();
        _liveScores = {}; 
      }
      if (!_isDisposed) notifyListeners();
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

  void _listenToMarketStats() {
    _marketStatsSub?.cancel();
    _marketStatsSub = _firestore.collection('fantasy_config').doc('market_stats').snapshots().listen((snap) async {
      if (snap.exists && !_isDisposed) {
        final data = snap.data()!;
        if (data['round'] == _currentRound) {
          mostSelectedCount = data['most_selected_player_count'] ?? 0;
          mostSelectedCaptainCount = data['most_selected_captain_count'] ?? 0;
          
          final String? mPid = data['most_selected_player_id'];
          final String? cPid = data['most_selected_captain_id'];
          
          List<String> idsToFetch = [];
          if (mPid != null && mostSelectedPlayer?.playerId != mPid) idsToFetch.add(mPid);
          if (cPid != null && cPid != mPid && mostSelectedCaptain?.playerId != cPid) idsToFetch.add(cPid);
          
          if (idsToFetch.isNotEmpty) {
            final players = await _fantasyService.getPlayersByIds(idsToFetch);
            for (var p in players) {
              if (p.playerId == mPid) mostSelectedPlayer = p;
              if (p.playerId == cPid) mostSelectedCaptain = p;
            }
            if (!_isDisposed) notifyListeners();
          }
        }
      }
    });
  }

  void _subscribeToLiveMatches(String seasonId, int round) {
    if (_team == null) return;
    _matchesSub?.cancel(); 
    
    // 📡 Escuta o documento único da rodada
    _matchesSub = _scoutService.streamLiveScores(seasonId, round).listen((scores) async {
      if (_isDisposed) return;
      Map<String, LiveScoreData> calculatedScores = {};
      
      String? currentTopScorerId;
      String? currentWorstScorerId;
      double maxScore = -999.0;
      double minScore = 999.0;
      
      scores.forEach((pid, s) {
        if (s.hasStats) {
           if (s.totalScore > maxScore) { maxScore = s.totalScore; currentTopScorerId = pid; }
           if (s.totalScore < minScore) { minScore = s.totalScore; currentWorstScorerId = pid; }
        }
      });
      
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
           penaltiesSaved: s.penaltiesSaved,
           penaltiesMissed: s.penaltiesMissed,
           shotsOnPost: s.shotsOnPost,
           cleanSheets: s.cleanSheets,
           ownGoals: s.ownGoals,
           missedFreeKicks: s.missedFreeKicks,
           motm: s.motm,
         );
      }
      
      _liveScores = calculatedScores;
      
      bool needNotify = true;
      
      if (currentTopScorerId != null && (topScorer?.playerId != currentTopScorerId || topScore != maxScore)) {
        topScore = maxScore;
        if (topScorer?.playerId != currentTopScorerId) {
          final pList = await _fantasyService.getPlayersByIds([currentTopScorerId!]);
          if (pList.isNotEmpty) topScorer = pList.first;
        }
      }
      
      if (currentWorstScorerId != null && (worstScorer?.playerId != currentWorstScorerId || worstScore != minScore)) {
        worstScore = minScore;
        if (worstScorer?.playerId != currentWorstScorerId) {
          final pList = await _fantasyService.getPlayersByIds([currentWorstScorerId!]);
          if (pList.isNotEmpty) worstScorer = pList.first;
        }
      }
      
      if (needNotify && !_isDisposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _marketSub?.cancel();
    _teamSub?.cancel();
    _matchesSub?.cancel();
    _marketStatsSub?.cancel();
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
  
  final int penaltiesSaved;
  final int penaltiesMissed;
  final int shotsOnPost;
  final int cleanSheets;
  
  final int ownGoals;
  final int missedFreeKicks;
  final int motm;
  
  bool get hasStats => (goals + assists + yellows + reds + penaltiesSaved + penaltiesMissed + shotsOnPost + cleanSheets + ownGoals + missedFreeKicks + motm) > 0;

  LiveScoreData({
    required this.totalScore,
    required this.isCaptain,
    this.goals = 0,
    this.assists = 0,
    this.yellows = 0,
    this.reds = 0,
    this.goalsConceded = 0,
    this.penaltiesSaved = 0,
    this.penaltiesMissed = 0,
    this.shotsOnPost = 0,
    this.cleanSheets = 0,
    this.ownGoals = 0,
    this.missedFreeKicks = 0,
    this.motm = 0,
  });
}