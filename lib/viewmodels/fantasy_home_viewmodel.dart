import 'dart:async';
import 'dart:io'; 
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart'; 
import 'package:connectivity_plus/connectivity_plus.dart'; 
import 'package:image_picker/image_picker.dart'; 

import '../services/analytics_service.dart';
import '../models/fantasy_models.dart';
import '../models/match_model.dart';
import '../repositories/fantasy_repository.dart'; 
import '../services/fantasy_service.dart';
import '../services/fantasy_scout_service.dart';
import '../services/firestore_cache_service.dart';
import '../services/match_service.dart';

class FantasyHomeViewModel extends ChangeNotifier {
  final FantasyRepository _repository = FantasyRepository();
  final FantasyService _fantasyService = FantasyService();
  final FantasyScoutService _scoutService = FantasyScoutService();
  final MatchService _matchService = MatchService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance; 

  String? _loadedUserId;
  String? _loadedSeasonId;
  bool _isOffline = false; 
  bool _isDisposed = false;

  bool _isLoading = true;
  String? _errorMessage;

  bool _isMarketOpen = true;
  DateTime? _closingTime;
  int _currentRound = 1;
  FantasyGameConfig _gameConfig = FantasyGameConfig.defaults();

  FantasyTeam? _team;
  List<FantasyPlayer> _teamPlayers = [];
  Map<String, LiveScoreData> _liveScores = {}; 

  StreamSubscription? _marketSub;
  StreamSubscription? _teamSub;
  StreamSubscription? _matchesSub;
  StreamSubscription? _marketStatsSub;
  StreamSubscription? _leaderboardSub;
  StreamSubscription? _roundMatchesSub;
  List<MatchModel> _roundMatches = [];
  bool _areAllMatchesFinished = false;
  FantasyLiveLeaderboard? _liveLeaderboard;
  double? _leaderboardScore;
  FantasyLiveTeamScore? _liveTeamScore;

  FantasyPlayer? mostSelectedPlayer;
  FantasyPlayer? mostSelectedCaptain;
  FantasyPlayer? topScorer;
  FantasyPlayer? worstScorer;
  int mostSelectedCount = 0;
  int mostSelectedCaptainCount = 0;
  double topScore = 0.0;
  double worstScore = 0.0;

  // Variáveis para desempenho da última rodada
  int? lastRoundNumber;
  double? lastRoundPoints;
  double? lastRoundAppreciation;

  // 🏆 FinOps: Resumo oficial da rodada anterior (Média, Mito, Maior/Menor Valorização, Menor Pontuação)
  FantasyRoundSummary? _roundSummary;

  bool get isOffline => _isOffline; 
  bool get isDisposed => _isDisposed;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isMarketOpen => _isMarketOpen;
  DateTime? get closingTime => _closingTime;
  int get currentRound => _currentRound;
  FantasyTeam? get team => _team;
  List<FantasyPlayer> get teamPlayers => _teamPlayers;
  Map<String, LiveScoreData> get liveScores => _liveScores;
  FantasyGameConfig get config => _gameConfig;
  FantasyLiveTeamScore? get liveTeamScore => _liveTeamScore;
  FantasyLiveLeaderboard? get liveLeaderboard => _liveLeaderboard;
  FantasyRoundSummary? get roundSummary => _roundSummary;
  List<MatchModel> get roundMatches => _roundMatches;
  bool get areAllMatchesFinished => _areAllMatchesFinished;

  /// Retorna verdadeiro quando a rodada está no período de validação de scouts:
  /// o mercado está fechado e todos os jogos da rodada foram encerrados.
  bool get isScoutsValidationPeriod =>
      !_isMarketOpen && (_areAllMatchesFinished || (_liveLeaderboard?.isFinal == true));

  String _positionForSlot(int slotIndex) {
    switch (slotIndex) {
      case 1:
      case 11:
        return 'Goleiro';
      case 2:
      case 12:
        return 'Fixo';
      case 3:
      case 4:
      case 13:
        return 'Ala';
      case 5:
      case 15:
        return 'Pivô';
      case 6:
      case 16:
        return 'Técnico';
      default:
        return '';
    }
  }

  double get teamPartialScore {
    if (_leaderboardScore != null) return _leaderboardScore!;
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

    // Fallback: Adiciona ganho do reserva de luxo caso ativado
    if (_team!.luxuryReserveId != null &&
        _team!.benchPlayerIds.contains(_team!.luxuryReserveId)) {
      final luxuryPid = _team!.luxuryReserveId!;
      final luxuryScoreData = _liveScores[luxuryPid];
      if (luxuryScoreData != null && _team!.benchSlots != null && _team!.lineupSlots != null) {
        String? luxuryPos;
        for (final entry in _team!.benchSlots!.entries) {
          if (entry.value == luxuryPid) {
            final slot = int.tryParse(entry.key);
            if (slot != null) luxuryPos = _positionForSlot(slot);
            break;
          }
        }

        if (luxuryPos != null && luxuryPos.isNotEmpty) {
          final startersSamePos = <String>[];
          for (final entry in _team!.lineupSlots!.entries) {
            final slot = int.tryParse(entry.key);
            if (slot != null && _positionForSlot(slot) == luxuryPos) {
              if (entry.value.isNotEmpty && _team!.lineupPlayerIds.contains(entry.value)) {
                startersSamePos.add(entry.value);
              }
            }
          }

          if (startersSamePos.isNotEmpty) {
            String worstStarterId = startersSamePos.first;
            double worstScore = _liveScores[worstStarterId]?.totalScore ?? 0.0;

            for (final pid in startersSamePos.skip(1)) {
              final sScore = _liveScores[pid]?.totalScore ?? 0.0;
              if (sScore < worstScore) {
                worstScore = sScore;
                worstStarterId = pid;
              } else if (sScore == worstScore &&
                  worstStarterId == _team!.captainId &&
                  pid != _team!.captainId) {
                worstStarterId = pid;
              }
            }

            final benchScore = luxuryScoreData.totalScore;
            if (benchScore > worstScore) {
              final isWorstCaptain = (_team!.captainId == worstStarterId);
              final starterEffective = isWorstCaptain ? (worstScore * 2) : worstScore;
              final benchEffective = isWorstCaptain ? (benchScore * 2) : benchScore;
              final netGain = benchEffective - starterEffective;
              total += netGain;
            }
          }
        }
      }
    }

    return double.parse(total.toStringAsFixed(2));
  }

  Future<bool> updateTeamProfile({
    required String newName,
    String? cpf,
    String? phone,
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
        if (cpf != null) 'owner_cpf': cpf.trim(),
        if (phone != null) 'owner_phone': phone.trim(),
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
    _isOffline = result.contains(ConnectivityResult.none);
    if (!_isDisposed) notifyListeners();
    return !_isOffline;
  }

  void _updateMarketStatus(Map<String, dynamic> data, String seasonId, {bool notify = true}) {
    final bool isOpenFlag = data['is_open'] ?? true;
    final dynamic closingRaw = data['closing_time'];
    _closingTime = closingRaw is Timestamp ? closingRaw.toDate() : null;
    final bool isExpired = _closingTime != null && DateTime.now().isAfter(_closingTime!);

    _isMarketOpen = isOpenFlag && !isExpired;
    _currentRound = data['current_round'] ?? 1;

    if (!_isMarketOpen) {
      _subscribeToLiveMatches(seasonId, _currentRound);
      _listenToMarketStats();
    } else {
      _matchesSub?.cancel();
      _marketStatsSub?.cancel();
      _roundMatchesSub?.cancel();
      _roundMatches = [];
      _areAllMatchesFinished = false;
      _liveLeaderboard = null;
      if (_currentRound > 1) {
        _fetchPreviousRoundScouts(seasonId, _currentRound - 1);
        _fetchRoundSummary(_currentRound - 1);
      } else {
        _liveScores = {}; 
        _roundSummary = null;
      }
    }
    if (notify && !_isDisposed) notifyListeners();
  }

  Future<void> init(String userId, String seasonId, {bool force = false}) async {
    // 🚨 CORREÇÃO DO BUG 2: Impede o loop infinito ao não exigir que !_isLoading seja true para retornar
    if (!force && _loadedUserId == userId && _loadedSeasonId == seasonId) return;

    _loadedUserId = userId;
    _loadedSeasonId = seasonId;

    // ⚡ INSTANT LOAD: Se já houver dados no cache RAM, inicia imediatamente sem skeleton
    final cachedTeam = _repository.getCachedUserTeam(userId);
    final cachedMarket = _repository.cachedMarketStatus;

    if (cachedMarket != null) {
      _updateMarketStatus(cachedMarket, seasonId, notify: false);
    }

    if (cachedTeam != null) {
      _team = cachedTeam;
      final allIds = <String>{
        ...cachedTeam.lineupPlayerIds,
        ...cachedTeam.benchPlayerIds,
      }.toList();
      if (_repository.hasCachedPlayers && allIds.isNotEmpty) {
        _teamPlayers = _repository.cachedPlayers!
            .where((p) => allIds.contains(p.playerId))
            .toList();
      }
      _isLoading = false;
    } else {
      _isLoading = true;
    }
    if (!_isDisposed) notifyListeners();

    if (!await _checkConnectivity()) {
      _isLoading = false;
      if (!_isDisposed) notifyListeners();
      return; 
    }

    _fetchLastRoundPerformance(userId);

    try {
      _gameConfig = await _fantasyService.getGameConfig();
    } catch (e) {
      debugPrint("Aviso: Falha ao carregar configurações: $e");
    }

    // 🚨 CORREÇÃO DO BUG 1 & FINOPS: Busca o status inicial do cache local para não pagar leitura dupla 
    // (a leitura real do servidor já será cobrada ao se conectar no .snapshots() logo abaixo).
    FirestoreCacheService.getDocumentWithCache(
      docRef: _firestore.collection('fantasy_config').doc('status'),
      cacheKey: 'fantasy_status',
      ttl: const Duration(minutes: 5),
    ).then((doc) {
      if (doc.exists && doc.data() != null && !_isDisposed) {
        _updateMarketStatus(doc.data() as Map<String, dynamic>, seasonId);
      }
    });

    _marketSub?.cancel();
    _marketSub = _repository.streamMarketStatus().listen((status) {
      _updateMarketStatus(status, seasonId);
    });

    _teamSub?.cancel();
    _teamSub = _repository.streamUserTeam(userId).listen((team) async {
      _team = team;
      if (team != null) {
        final allIds = <String>{
          ...team.lineupPlayerIds,
          ...team.benchPlayerIds,
        }.toList();
        if (allIds.isNotEmpty) {
          try {
            _teamPlayers = await _repository.getPlayersByIds(allIds);
          } catch (_) {}
        } else {
          _teamPlayers = [];
        }
      } else {
        _teamPlayers = [];
      }
      if (!_isMarketOpen) {
        _subscribeToLiveMatches(seasonId, _currentRound);
      }
      _isLoading = false;

      // 🚨 Sincroniza a valorização da rodada caso o histórico tenha ficado defasado
      if (team != null && lastRoundNumber == 1) {
        lastRoundAppreciation = double.parse((team.teamValue - 50.0).toStringAsFixed(2));
        _firestore
            .collection('fantasy_teams')
            .doc(userId)
            .collection('history')
            .doc('1')
            .update({'patrimony': team.teamValue})
            .catchError((e) {
          debugPrint("Aviso ao sincronizar patrimônio R1 no Firestore: $e");
        });
      }

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
    // 📡 Escuta as partidas da rodada para verificar encerramento de todos os jogos
    _roundMatchesSub?.cancel();
    _roundMatchesSub = _matchService.streamRoundMatches(seasonId, round).listen((matches) {
      if (_isDisposed) return;
      _roundMatches = matches;
      _areAllMatchesFinished = matches.isNotEmpty && matches.every((m) => m.isFinished);
      notifyListeners();
    }, onError: (e) {
      debugPrint("Erro ao escutar partidas da rodada $round: $e");
    });

    if (_team == null) return;
    _matchesSub?.cancel(); 
    _leaderboardSub?.cancel();

    // 🏆 FINOPS: Escuta o leaderboard consolidado da rodada para pontuação oficial sincronizada
    _leaderboardSub = _fantasyService
        .streamLiveLeaderboard(seasonId: seasonId, round: round)
        .listen((leaderboard) {
      if (_isDisposed || leaderboard == null) return;
      _liveLeaderboard = leaderboard;
      try {
        final myEntry = leaderboard.teams.firstWhere(
          (t) => t.teamId == _team?.userId || t.userId == _team?.userId,
        );
        _leaderboardScore = myEntry.roundScore;
        _liveTeamScore = myEntry;
        if (!_isDisposed) notifyListeners();
      } catch (_) {}
    });
    
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
      
      final allTeamPids = <String>{..._team!.lineupPlayerIds, ..._team!.benchPlayerIds};
      for (String pid in allTeamPids) {
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
           difficultSaves: s.difficultSaves,
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
    _leaderboardSub?.cancel();
    _roundMatchesSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchLastRoundPerformance(String userId) async {
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _firestore
            .collection('fantasy_teams')
            .doc(userId)
            .collection('history')
            .orderBy('round', descending: true)
            .limit(2)
            .get();
      } catch (e) {
        debugPrint("Aviso: fallback em memória para histórico da última rodada ($e)");
        snap = await _firestore
            .collection('fantasy_teams')
            .doc(userId)
            .collection('history')
            .get();
      }

      if (snap.docs.isNotEmpty) {
        final docs = snap.docs.toList()
          ..sort((a, b) => ((b.data()['round'] ?? 0) as num)
              .compareTo((a.data()['round'] ?? 0) as num));

        final lastDoc = docs.first.data();
        lastRoundNumber = lastDoc['round'];
        lastRoundPoints = (lastDoc['points'] ?? 0).toDouble();
        
        double lastPatrimony = (lastDoc['patrimony'] ?? 50.0).toDouble();
        if (lastRoundNumber == 1 && _team != null) {
          lastPatrimony = _team!.teamValue;
          if ((lastDoc['patrimony'] as num?)?.toDouble() != _team!.teamValue) {
            docs.first.reference.update({'patrimony': _team!.teamValue}).catchError((e) {
              debugPrint("Aviso ao sincronizar patrimônio no histórico: $e");
            });
          }
        }
        
        double prevPatrimony = 50.0;
        if (docs.length > 1) {
          prevPatrimony = (docs[1].data()['patrimony'] ?? 50.0).toDouble();
        }
        
        lastRoundAppreciation = double.parse((lastPatrimony - prevPatrimony).toStringAsFixed(2));
        if (!_isDisposed) notifyListeners();
      }
    } catch (e) {
      debugPrint("Erro ao buscar histórico da última rodada: $e");
    }
  }

  Future<void> _fetchPreviousRoundScouts(String seasonId, int round) async {
    try {
      final scores = await _scoutService.getLiveScores(seasonId, round);
      Map<String, LiveScoreData> calculatedScores = {};
      
      scores.forEach((pid, s) {
         calculatedScores[pid] = LiveScoreData(
           totalScore: s.totalScore,
           isCaptain: (_team?.captainId == pid),
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
      });
      _liveScores = calculatedScores;
      if (!_isDisposed) notifyListeners();
    } catch (e) {
      debugPrint("Erro ao buscar scouts anteriores: $e");
    }
  }

  /// 🏆 FINOPS: Busca o resumo consolidado da rodada em documento único com cache
  Future<void> _fetchRoundSummary(int round, {bool force = false}) async {
    try {
      FantasyRoundSummary? summary = await _fantasyService.getRoundSummary(round: round, forceRefresh: force);
      summary ??= await _fantasyService.getRoundSummary(forceRefresh: force);
      if (summary != null && !_isDisposed) {
        _roundSummary = summary;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Aviso: Falha ao carregar resumo da rodada no ViewModel: $e");
    }
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
  final int difficultSaves;
  
  bool get hasStats => (goals + assists + yellows + reds + penaltiesSaved + penaltiesMissed + shotsOnPost + cleanSheets + ownGoals + missedFreeKicks + motm + difficultSaves) > 0;

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
    this.difficultSaves = 0,
  });
}