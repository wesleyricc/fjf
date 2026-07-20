import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

import '../services/match_service.dart';
import '../services/admin_service.dart';
import '../services/championship_service.dart';
import '../models/player_model.dart';

class AdminMatchViewModel extends ChangeNotifier {
  final MatchService matchService;
  final ChampionshipService championshipService;
  final String seasonId;
  DocumentSnapshot matchSnap;

  // --- CONTROLADORES DE TEXTO ---
  final TextEditingController homeScoreController = TextEditingController();
  final TextEditingController awayScoreController = TextEditingController();
  final TextEditingController penaltyHomeScoreController = TextEditingController();
  final TextEditingController penaltyAwayScoreController = TextEditingController();

  // --- ESTADO DO JOGO ---
  bool isSaving = false;
  bool isLoadingPlayers = true;
  String selectedStatus = 'pending';
  bool showTiebreakerSection = false;
  String tiebreakerRule = '';

  // --- ESTATÍSTICAS ---
  Map<String, int> goals = {};
  Map<String, int> assists = {};
  Map<String, int> yellowCards = {};
  Map<String, int> redCards = {};
  Map<String, int> goalsConceded = {};
  String? selectedManOfTheMatchId;
  String? selectedWinnerId;

  // --- ELENCOS ---
  List<DocumentSnapshot> homePlayers = [];
  List<DocumentSnapshot> awayPlayers = [];
  List<DocumentSnapshot> get allPlayers => [...homePlayers, ...awayPlayers];
  List<String> lineupPlayed = [];

  // --- ARQUIVOS / MÍDIA ---
  String? existingSumulaUrl;
  Uint8List? pickedFileBytes;
  String pickedFileName = '';
  List<Map<String, dynamic>> mediaLinks = [];

  AdminMatchViewModel({
    required this.matchService,
    required this.championshipService,
    required this.seasonId,
    required this.matchSnap,
  }) {
    homeScoreController.addListener(checkShowTiebreakerSection);
    awayScoreController.addListener(checkShowTiebreakerSection);
    initData();
  }

  @override
  void dispose() {
    homeScoreController.dispose();
    awayScoreController.dispose();
    penaltyHomeScoreController.dispose();
    penaltyAwayScoreController.dispose();
    super.dispose();
  }

  void initData() {
    final data = matchSnap.data() as Map<String, dynamic>? ?? {};
    _loadFromMap(data);
    loadPlayersFromCache();
    checkShowTiebreakerSection();
  }

  Future<void> reloadMatchData() async {
    try {
      final newSnap = await FirebaseFirestore.instance
          .collection('championships')
          .doc(seasonId)
          .collection('matches')
          .doc(matchSnap.id)
          .get();

      if (newSnap.exists) {
        matchSnap = newSnap;
        _loadFromMap(newSnap.data() as Map<String, dynamic>);
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Erro ao recarregar dados da partida: $e");
    }
  }

  void _loadFromMap(Map<String, dynamic> data) {
    penaltyHomeScoreController.text = data['penalty_score_home']?.toString() ?? '';
    penaltyAwayScoreController.text = data['penalty_score_away']?.toString() ?? '';
    existingSumulaUrl = data['sumula_url'];
    homeScoreController.text = data['score_home']?.toString() ?? '0';
    awayScoreController.text = data['score_away']?.toString() ?? '0';
    selectedStatus = data['status'] ?? 'pending';
    selectedWinnerId = data['winner_team_id'];

    final String phase = data['phase'] ?? '';
    if (phase == 'quarter_final') tiebreakerRule = AdminService.playoffTiebreaker;
    else if (phase == 'semifinal') tiebreakerRule = AdminService.semifinalTiebreaker;
    else if (phase == 'third_place') tiebreakerRule = AdminService.thirdPlaceTiebreaker;
    else if (phase == 'final') tiebreakerRule = AdminService.finalTiebreaker;

    goals.clear();
    assists.clear();
    yellowCards.clear();
    redCards.clear();
    goalsConceded.clear();
    mediaLinks.clear();
    lineupPlayed.clear();
    
    final lpDb = data['lineup_played'];
    if (lpDb != null && lpDb is List) {
      lineupPlayed = List<String>.from(lpDb);
    }

    if (data.containsKey('stats_applied') && data['stats_applied'] != null) {
      final stats = data['stats_applied']['player_stats'];
      _safeFill(goals, stats['goals']);
      _safeFill(assists, stats['assists']);
      _safeFill(yellowCards, stats['yellows']);
      _safeFill(redCards, stats['reds']);
      _safeFill(goalsConceded, stats['goals_conceded']);
      
      selectedManOfTheMatchId = data['stats_applied']['man_of_the_match'];
      
      if (data['stats_applied']['media_links'] != null) {
         final linksFromDb = data['stats_applied']['media_links'] as List<dynamic>;
         mediaLinks = List<Map<String, dynamic>>.from(linksFromDb.map((item) => Map<String, dynamic>.from(item)));
      }
    }
  }

  void _safeFill(Map<String, int> target, dynamic source) {
    if (source is Map) {
      source.forEach((k, v) {
        if (v is num) target[k.toString()] = v.toInt();
      });
    }
  }

  Future<void> loadPlayersFromCache() async {
    isLoadingPlayers = true;
    notifyListeners();
    
    final data = matchSnap.data() as Map<String, dynamic>;
    final homeId = data['team_home_id'];
    final awayId = data['team_away_id'];

    try {
      await Future.wait([
        championshipService.fetchRoster(homeId),
        championshipService.fetchRoster(awayId),
      ]);

      final all = championshipService.allPlayers;

      int sortFunc(Player a, Player b) {
        if (!a.isStaff && b.isStaff) return -1;
        if (a.isStaff && !b.isStaff) return 1;
        int nA = a.jerseyNumber ?? 999;
        int nB = b.jerseyNumber ?? 999;
        if (nA != nB) return nA.compareTo(nB);
        return a.name.compareTo(b.name);
      }

      final homeList = all.where((p) => p.teamId == homeId).toList()..sort(sortFunc);
      final awayList = all.where((p) => p.teamId == awayId).toList()..sort(sortFunc);

      homePlayers = homeList.map((p) => MockDocumentSnapshot(p.id, {
        'name': p.name,
        'jersey_number': p.jerseyNumber,
        'is_staff': p.isStaff,
        'is_goalkeeper': p.isGoalkeeper,
        'team_id': p.teamId,
      })).toList();
      
      awayPlayers = awayList.map((p) => MockDocumentSnapshot(p.id, {
        'name': p.name,
        'jersey_number': p.jerseyNumber,
        'is_staff': p.isStaff,
        'is_goalkeeper': p.isGoalkeeper,
        'team_id': p.teamId,
      })).toList();

      if (data['lineup_played'] == null) {
        lineupPlayed = [
          ...homeList.map((p) => p.id),
          ...awayList.map((p) => p.id)
        ];
      }

    } catch (e) {
      debugPrint("Erro ao carregar jogadores no Admin: $e");
    } finally {
      isLoadingPlayers = false;
      notifyListeners();
    }
  }

  void checkShowTiebreakerSection() {
    bool needsTiebreaker = false;
    final data = matchSnap.data() as Map<String, dynamic>? ?? {};
    final String phase = data['phase'] ?? '';
    final isPlayoff = ['quarter_final', 'semifinal', 'third_place', 'final'].contains(phase);
    
    if (isPlayoff && selectedStatus == 'finished') {
      final int scoreHome = int.tryParse(homeScoreController.text) ?? -1;
      final int scoreAway = int.tryParse(awayScoreController.text) ?? -1;
      if (scoreHome != -1 && scoreAway != -1 && scoreHome == scoreAway) {
        needsTiebreaker = true;
      }
    }
    if (needsTiebreaker != showTiebreakerSection) {
      showTiebreakerSection = needsTiebreaker;
      notifyListeners();
    }
  }

  void updateStatus(String status) {
    selectedStatus = status;
    checkShowTiebreakerSection();
    notifyListeners();
  }

  void updateMotm(String? id) {
    selectedManOfTheMatchId = id;
    notifyListeners();
  }

  void togglePlayerInLineup(String playerId) {
    if (lineupPlayed.contains(playerId)) {
      lineupPlayed.remove(playerId);
    } else {
      lineupPlayed.add(playerId);
    }
    notifyListeners();
  }

  Future<void> pickSumulaFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
      if (result != null && result.files.single.bytes != null) {
        pickedFileBytes = result.files.single.bytes;
        pickedFileName = result.files.single.name;
        existingSumulaUrl = null;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<String> saveStats() async {
    isSaving = true;
    notifyListeners();

    final int scoreHome = int.tryParse(homeScoreController.text) ?? 0;
    final int scoreAway = int.tryParse(awayScoreController.text) ?? 0;

    int? penaltyScoreHome;
    int? penaltyScoreAway;
    String? winnerId = selectedWinnerId; 

    final matchData = matchSnap.data() as Map<String, dynamic>;

    if (showTiebreakerSection && tiebreakerRule.contains('penalties')) {
      penaltyScoreHome = int.tryParse(penaltyHomeScoreController.text);
      penaltyScoreAway = int.tryParse(penaltyAwayScoreController.text);
      
      if (penaltyScoreHome != null && penaltyScoreAway != null && penaltyScoreHome != penaltyScoreAway) {
         winnerId = (penaltyScoreHome > penaltyScoreAway) ? matchData['team_home_id'] : matchData['team_away_id'];
      }
    }

    String? finalSumulaUrl = existingSumulaUrl;
    if (pickedFileBytes != null) {
      try {
        final String matchId = matchSnap.id;
        final String fileName = pickedFileName.isNotEmpty ? pickedFileName : '$matchId.pdf';
        final ref = FirebaseStorage.instance.ref().child('sumulas/$fileName');
        final metadata = SettableMetadata(contentType: 'application/pdf');
        await ref.putData(pickedFileBytes!, metadata);
        finalSumulaUrl = await ref.getDownloadURL();
      } catch (_) {}
    }

    final result = await matchService.updateMatchStats(
      seasonId: seasonId,
      matchSnapshot: matchSnap,
      newStatus: selectedStatus,
      newScoreHome: scoreHome,
      newScoreAway: scoreAway,
      newGoals: goals,
      newAssists: assists,
      newYellows: yellowCards,
      newReds: redCards,
      newGoalsConceded: goalsConceded,
      newManOfTheMatchId: selectedManOfTheMatchId,
      penaltyScoreHome: penaltyScoreHome,
      penaltyScoreAway: penaltyScoreAway,
      winnerTeamId: winnerId,
      newSumulaUrl: finalSumulaUrl,
      newMediaLinks: mediaLinks,
      newLineupPlayed: lineupPlayed,
    );

    isSaving = false;
    notifyListeners();
    return result;
  }

  Future<String> deleteMatch() async {
    isSaving = true;
    notifyListeners();
    
    final result = await matchService.deleteMatch(matchSnap, seasonId);
    
    isSaving = false;
    notifyListeners();
    return result;
  }
}

// Classe Mock de compatibilidade
class MockDocumentSnapshot implements DocumentSnapshot {
  @override final String id;
  final Map<String, dynamic> _data;
  MockDocumentSnapshot(this.id, this._data);
  @override Map<String, dynamic> data() => _data;
  @override dynamic get(Object field) => _data[field as String];
  @override dynamic operator [](Object field) => _data[field as String];
  @override bool get exists => true;
  @override DocumentReference get reference => throw UnimplementedError();
  @override SnapshotMetadata get metadata => throw UnimplementedError();
}