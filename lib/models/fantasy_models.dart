import 'package:cloud_firestore/cloud_firestore.dart';

enum RankingMetric { points, patrimony }

class FantasyPlayer {
  final String playerId;
  final String name;
  final String position;
  final String? secondaryPosition; // NEW FIELD
  final String teamId;
  final String teamShieldUrl;
  final String photoUrl;
  final double currentPrice;
  final double lastPriceChange;
  final double lastScore;
  final double averageScore;
  final int matchesPlayed;
  final String status;

  // Histórico
  final List<Map<String, dynamic>> history;

  FantasyPlayer({
    required this.playerId,
    required this.name,
    required this.position,
    this.secondaryPosition,
    required this.teamId,
    required this.teamShieldUrl,
    required this.photoUrl,
    required this.currentPrice,
    required this.lastPriceChange,
    required this.lastScore,
    required this.averageScore,
    required this.matchesPlayed,
    required this.status,
    required this.history,
  });

  // Factory fromFirestore delega para fromMap
  // Usa docId em fromMap
  factory FantasyPlayer.fromFirestore(DocumentSnapshot doc) => FantasyPlayer.fromMap(doc.id, (doc.data() as Map<String, dynamic>?) ?? {});

  factory FantasyPlayer.fromMap(String docId, Map<String, dynamic> data) {
    final historyList = (data['history'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    double lastScore = (data['last_score'] ?? 0).toDouble();
    double lastPriceChange = (data['last_price_change'] ?? 0).toDouble();

    // Se lastScore ou lastPriceChange estiverem zerados mas houver histórico de partidas jogadas,
    // recupera a pontuação/variação da última partida que o atleta efetivamente disputou
    if (historyList.isNotEmpty) {
      final playedMatches =
          historyList.where((h) => h['played'] == true).toList();
      if (playedMatches.isNotEmpty) {
        if (lastScore == 0) {
          lastScore = (playedMatches.last['score'] ?? 0).toDouble();
        }
        if (lastPriceChange == 0 && playedMatches.last['variation'] != null) {
          lastPriceChange = (playedMatches.last['variation'] ?? 0).toDouble();
        }
      }
    }

    return FantasyPlayer(
      playerId: docId,
      name: data['name'] ?? '',
      position: data['position'] ?? '',
      secondaryPosition: data['secondary_position'],
      teamId: data['team_id'] ?? '',
      teamShieldUrl: data['team_shield_url'] ?? '',
      photoUrl: data['photo_url'] ?? '',
      currentPrice: (data['current_price'] ?? 0).toDouble(),
      lastPriceChange: lastPriceChange,
      lastScore: lastScore,
      averageScore: (data['average_score'] ?? 0).toDouble(),
      matchesPlayed: (data['matches_played'] ?? 0).toInt(),
      status: data['status'] ?? 'probable',
      history: historyList,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'position': position,
      'secondary_position': secondaryPosition,
      'team_id': teamId,
      'team_shield_url': teamShieldUrl,
      'photo_url': photoUrl,
      'current_price': currentPrice,
      'last_price_change': lastPriceChange,
      'last_score': lastScore,
      'average_score': averageScore,
      'matches_played': matchesPlayed,
      'status': status,
      'history': history,
    };
  }
}

class FantasyTeam {
  final String id;
  final String userId;
  final String ownerId;
  final String ownerName;
  final String teamName;
  final double totalPoints;
  final double lastScore;
  final double teamValue;
  final double lastVariation;
  final double currentBalance;
  final List<String> lineupPlayerIds;
  final List<String> benchPlayerIds;
  final Map<String, String>? lineupSlots;
  final Map<String, String>? benchSlots;
  final String? captainId;
  final String? luxuryReserveId;
  final String shieldType;
  final String? customLogoUrl;
  final String? ownerCpf;
  final String? ownerPhone;

  FantasyTeam({
    required this.id,
    required this.userId,
    required this.ownerId,
    required this.ownerName,
    required this.teamName,
    required this.totalPoints,
    required this.lastScore,
    required this.teamValue,
    this.lastVariation = 0.0,
    required this.currentBalance,
    required this.lineupPlayerIds,
    this.benchPlayerIds = const [],
    this.lineupSlots,
    this.benchSlots,
    this.captainId,
    this.luxuryReserveId,
    required this.shieldType,
    this.customLogoUrl,
    this.ownerCpf,
    this.ownerPhone,
  });

  factory FantasyTeam.fromFirestore(DocumentSnapshot doc) => FantasyTeam.fromMap(doc.id, (doc.data() as Map<String, dynamic>?) ?? {});

  factory FantasyTeam.fromMap(String docId, Map<String, dynamic> data) {
    final double totalPoints = (data['total_points'] ?? 0).toDouble();
    final double lastScore = (data['last_score'] ?? 0).toDouble();

    return FantasyTeam(
      id: docId,
      userId: data['user_id'] ?? docId,
      ownerId: data['owner_id'] ?? docId,
      ownerName: data['owner_name'] ?? 'Cartoleiro',
      teamName: data['team_name'] ?? 'Time sem nome',
      totalPoints: totalPoints,
      lastScore: lastScore,
      teamValue: (data['team_value'] ?? 50).toDouble(),
      lastVariation: (data['last_variation'] ?? 0).toDouble(),
      currentBalance: (data['current_balance'] ?? 50).toDouble(),
      lineupPlayerIds:
          List<String>.from(data['lineup_player_ids'] ?? data['lineup'] ?? []),
      benchPlayerIds: List<String>.from(data['bench_player_ids'] ?? []),
      lineupSlots: data['lineup_slots'] != null
          ? Map<String, String>.from(data['lineup_slots'])
          : null,
      benchSlots: data['bench_slots'] != null
          ? Map<String, String>.from(data['bench_slots'])
          : null,
      captainId: data['captain_id'],
      luxuryReserveId: data['luxury_reserve_id'],
      shieldType: data['shield_type'] ?? '1',
      customLogoUrl: data['custom_logo_url'],
      ownerCpf: data['owner_cpf'],
      ownerPhone: data['owner_phone'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'owner_id': ownerId,
      'owner_name': ownerName,
      'team_name': teamName,
      'total_points': totalPoints,
      'last_score': lastScore,
      'team_value': teamValue,
      'last_variation': lastVariation,
      'current_balance': currentBalance,
      'lineup_player_ids': lineupPlayerIds,
      'bench_player_ids': benchPlayerIds,
      'lineup_slots': lineupSlots,
      'bench_slots': benchSlots,
      'captain_id': captainId,
      'luxury_reserve_id': luxuryReserveId,
      'shield_type': shieldType,
      'custom_logo_url': customLogoUrl,
      'owner_cpf': ownerCpf,
      'owner_phone': ownerPhone,
    };
  }
}

class FantasyGameConfig {
  final double ptsGoal;
  final double ptsAssist;
  final double ptsYellowCard;
  final double ptsRedCard;

  // Novos
  final double ptsPenaltySaved;
  final double ptsPenaltyMissed;
  final double ptsShotOnPost;
  final double ptsCleanSheet;

  // Novíssimos
  final double ptsOwnGoal;
  final double ptsMissedFreeKick;
  final double ptsMotm;
  final double ptsDifficultSave;

  final double factorExpectation;
  final double factorVariation;
  final double capLimitPercent;
  final double minPrice;

  FantasyGameConfig({
    required this.ptsGoal,
    required this.ptsAssist,
    required this.ptsYellowCard,
    required this.ptsRedCard,
    required this.ptsPenaltySaved,
    required this.ptsPenaltyMissed,
    required this.ptsShotOnPost,
    required this.ptsCleanSheet,
    required this.ptsOwnGoal,
    required this.ptsMissedFreeKick,
    required this.ptsMotm,
    required this.ptsDifficultSave,
    required this.factorExpectation,
    required this.factorVariation,
    required this.capLimitPercent,
    required this.minPrice,
  });

  factory FantasyGameConfig.defaults() {
    return FantasyGameConfig(
      ptsGoal: 8.0,
      ptsAssist: 5.0,
      ptsYellowCard: -1.0,
      ptsRedCard: -3.0,
      ptsPenaltySaved: 5.0,
      ptsPenaltyMissed: -3.0,
      ptsShotOnPost: 3.0,
      ptsCleanSheet: 5.0,
      ptsOwnGoal: -3.0,
      ptsMissedFreeKick: -3.0,
      ptsMotm: 5.0,
      ptsDifficultSave: 1.0,
      factorExpectation: 0.30,
      factorVariation: 0.18,
      capLimitPercent: 0.25,
      minPrice: 1.0,
    );
  }

  factory FantasyGameConfig.fromMap(Map<String, dynamic> map) {
    double toDouble(dynamic val, double def) {
      if (val == null) return def;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? def;
      return def;
    }

    return FantasyGameConfig(
      ptsGoal: toDouble(map['ptsGoal'] ?? map['pts_goal'], 8.0),
      ptsAssist: toDouble(map['ptsAssist'] ?? map['pts_assist'], 5.0),
      ptsYellowCard:
          toDouble(map['ptsYellowCard'] ?? map['pts_yellow_card'], -1.0),
      ptsRedCard: toDouble(map['ptsRedCard'] ?? map['pts_red_card'], -3.0),
      ptsPenaltySaved:
          toDouble(map['ptsPenaltySaved'] ?? map['pts_penalty_saved'], 5.0),
      ptsPenaltyMissed:
          toDouble(map['ptsPenaltyMissed'] ?? map['pts_penalty_missed'], -3.0),
      ptsShotOnPost:
          toDouble(map['ptsShotOnPost'] ?? map['pts_shot_on_post'], 3.0),
      ptsCleanSheet:
          toDouble(map['ptsCleanSheet'] ?? map['pts_clean_sheet'], 5.0),
      ptsOwnGoal: toDouble(map['ptsOwnGoal'] ?? map['pts_own_goal'], -3.0),
      ptsMissedFreeKick: toDouble(
          map['ptsMissedFreeKick'] ?? map['pts_missed_free_kick'], -3.0),
      ptsMotm: toDouble(map['ptsMotm'] ?? map['pts_motm'], 5.0),
      ptsDifficultSave:
          toDouble(map['ptsDifficultSave'] ?? map['pts_difficult_save'], 1.0),
      factorExpectation:
          toDouble(map['factorExpectation'] ?? map['factor_expectation'], 0.30),
      factorVariation:
          toDouble(map['factorVariation'] ?? map['factor_variation'], 0.18),
      capLimitPercent:
          toDouble(map['capLimitPercent'] ?? map['cap_limit_percent'], 0.25),
      minPrice: toDouble(map['minPrice'] ?? map['min_price'], 1.0),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ptsGoal': ptsGoal,
      'ptsAssist': ptsAssist,
      'ptsYellowCard': ptsYellowCard,
      'ptsRedCard': ptsRedCard,
      'ptsPenaltySaved': ptsPenaltySaved,
      'ptsPenaltyMissed': ptsPenaltyMissed,
      'ptsShotOnPost': ptsShotOnPost,
      'ptsCleanSheet': ptsCleanSheet,
      'ptsOwnGoal': ptsOwnGoal,
      'ptsMissedFreeKick': ptsMissedFreeKick,
      'ptsMotm': ptsMotm,
      'ptsDifficultSave': ptsDifficultSave,
      'factorExpectation': factorExpectation,
      'factorVariation': factorVariation,
      'capLimitPercent': capLimitPercent,
      'minPrice': minPrice,
    };
  }
}

class FantasyLiveTeamScore {
  final String teamId;
  final String userId;
  final String teamName;
  final String ownerName;
  final String shieldType;
  final String? customLogoUrl;
  final double roundScore;
  final double totalPoints;
  final double teamValue;
  final double lastVariation;
  final int playersPlayed;
  final int playersTotal;
  final String? captainId;

  final List<FantasySubstitutionItem> substitutions;
  final List<String>? finalLineup;

  FantasyLiveTeamScore({
    required this.teamId,
    required this.userId,
    required this.teamName,
    required this.ownerName,
    required this.shieldType,
    this.customLogoUrl,
    required this.roundScore,
    required this.totalPoints,
    this.teamValue = 50.0,
    this.lastVariation = 0.0,
    required this.playersPlayed,
    required this.playersTotal,
    this.captainId,
    this.substitutions = const [],
    this.finalLineup,
  });

  factory FantasyLiveTeamScore.fromMap(Map<String, dynamic> map) {
    final rawSubs = (map['substitutions'] as List<dynamic>?) ?? [];
    return FantasyLiveTeamScore(
      teamId: map['team_id'] ?? '',
      userId: map['user_id'] ?? map['team_id'] ?? '',
      teamName: map['team_name'] ?? 'Time sem nome',
      ownerName: map['owner_name'] ?? 'Cartoleiro',
      shieldType: map['shield_type'] ?? 'shield_1',
      customLogoUrl: map['custom_logo_url'],
      roundScore: (map['round_score'] ?? 0).toDouble(),
      totalPoints: (map['total_points'] ?? 0).toDouble(),
      teamValue: (map['team_value'] ?? 50.0).toDouble(),
      lastVariation: (map['last_variation'] ?? 0.0).toDouble(),
      playersPlayed: (map['players_played'] ?? 0) is int
          ? map['players_played']
          : (map['players_played'] ?? 0).toInt(),
      playersTotal: (map['players_total'] ?? 6) is int
          ? map['players_total']
          : (map['players_total'] ?? 6).toInt(),
      captainId: map['captain_id'],
      substitutions: rawSubs
          .map((s) => FantasySubstitutionItem.fromMap(
              Map<String, dynamic>.from(s as Map)))
          .toList(),
      finalLineup: (map['final_lineup'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'team_id': teamId,
      'user_id': userId,
      'team_name': teamName,
      'owner_name': ownerName,
      'shield_type': shieldType,
      'custom_logo_url': customLogoUrl,
      'round_score': roundScore,
      'total_points': totalPoints,
      'players_played': playersPlayed,
      'players_total': playersTotal,
      'captain_id': captainId,
      'substitutions': substitutions.map((s) => s.toMap()).toList(),
      'final_lineup': finalLineup,
    };
  }
}

class FantasySubstitutionItem {
  final String outPlayerId;
  final String inPlayerId;
  final String type; // 'normal' | 'luxury'
  final String slotPosition;

  FantasySubstitutionItem({
    required this.outPlayerId,
    required this.inPlayerId,
    required this.type,
    required this.slotPosition,
  });

  factory FantasySubstitutionItem.fromMap(Map<String, dynamic> map) {
    return FantasySubstitutionItem(
      outPlayerId: (map['out'] ?? '').toString(),
      inPlayerId: (map['in'] ?? '').toString(),
      type: (map['type'] ?? 'normal').toString(),
      slotPosition: (map['slot_position'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'out': outPlayerId,
      'in': inPlayerId,
      'type': type,
      'slot_position': slotPosition,
    };
  }
}

class FantasyLiveLeaderboard {
  final int round;
  final String seasonId;
  final DateTime? updatedAt;
  final bool isFinal;
  final int teamsCount;
  final List<FantasyLiveTeamScore> teams;

  FantasyLiveLeaderboard({
    required this.round,
    required this.seasonId,
    this.updatedAt,
    this.isFinal = false,
    required this.teamsCount,
    required this.teams,
  });

  factory FantasyLiveLeaderboard.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final rawTeams = (data['teams'] as List<dynamic>?) ?? [];
    final teamsList = rawTeams
        .map((t) => FantasyLiveTeamScore.fromMap(
            Map<String, dynamic>.from(t as Map)))
        .toList();

    DateTime? updated;
    if (data['updated_at'] != null) {
      if (data['updated_at'] is Timestamp) {
        updated = (data['updated_at'] as Timestamp).toDate();
      }
    }

    return FantasyLiveLeaderboard(
      round: (data['round'] ?? 1) is int
          ? data['round']
          : int.tryParse(data['round'].toString()) ?? 1,
      seasonId: data['season_id'] ?? '',
      updatedAt: updated,
      isFinal: data['is_final'] == true,
      teamsCount: (data['teams_count'] ?? teamsList.length) is int
          ? (data['teams_count'] ?? teamsList.length)
          : teamsList.length,
      teams: teamsList,
    );
  }
}

class FantasyRoundHighlightTeam {
  final String teamId;
  final String userId;
  final String teamName;
  final String ownerName;
  final String? customLogoUrl;
  final String shieldType;
  final double score;
  final double variation;
  final double patrimony;

  FantasyRoundHighlightTeam({
    required this.teamId,
    required this.userId,
    required this.teamName,
    required this.ownerName,
    this.customLogoUrl,
    required this.shieldType,
    required this.score,
    required this.variation,
    required this.patrimony,
  });

  factory FantasyRoundHighlightTeam.fromMap(Map<String, dynamic> data) {
    return FantasyRoundHighlightTeam(
      teamId: data['team_id'] ?? '',
      userId: data['user_id'] ?? data['team_id'] ?? '',
      teamName: data['team_name'] ?? 'Time sem nome',
      ownerName: data['owner_name'] ?? 'Cartoleiro',
      customLogoUrl: data['custom_logo_url'],
      shieldType: data['shield_type'] ?? '1',
      score: (data['score'] ?? 0).toDouble(),
      variation: (data['variation'] ?? 0).toDouble(),
      patrimony: (data['patrimony'] ?? 50.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'team_id': teamId,
      'user_id': userId,
      'team_name': teamName,
      'owner_name': ownerName,
      'custom_logo_url': customLogoUrl,
      'shield_type': shieldType,
      'score': score,
      'variation': variation,
      'patrimony': patrimony,
    };
  }
}

class FantasyRoundSummary {
  final int round;
  final int totalTeams;
  final int activeTeams;
  final double averageScore;
  final FantasyRoundHighlightTeam? highestScoreTeam;      // Mito da Rodada
  final FantasyRoundHighlightTeam? lowestScoreTeam;       // Menor Pontuação (escalados)
  final FantasyRoundHighlightTeam? highestAppreciationTeam;// Maior Valorização
  final FantasyRoundHighlightTeam? lowestAppreciationTeam; // Maior Desvalorização (escalados)
  final DateTime? updatedAt;

  FantasyRoundSummary({
    required this.round,
    required this.totalTeams,
    required this.activeTeams,
    required this.averageScore,
    this.highestScoreTeam,
    this.lowestScoreTeam,
    this.highestAppreciationTeam,
    this.lowestAppreciationTeam,
    this.updatedAt,
  });

  factory FantasyRoundSummary.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return FantasyRoundSummary.fromMap(data);
  }

  factory FantasyRoundSummary.fromMap(Map<String, dynamic> data) {
    return FantasyRoundSummary(
      round: (data['round'] ?? 1) is int ? data['round'] : int.tryParse(data['round'].toString()) ?? 1,
      totalTeams: (data['total_teams'] ?? 0) is int ? data['total_teams'] : int.tryParse(data['total_teams'].toString()) ?? 0,
      activeTeams: (data['active_teams'] ?? 0) is int ? data['active_teams'] : int.tryParse(data['active_teams'].toString()) ?? 0,
      averageScore: (data['average_score'] ?? 0).toDouble(),
      highestScoreTeam: data['highest_score_team'] != null
          ? FantasyRoundHighlightTeam.fromMap(Map<String, dynamic>.from(data['highest_score_team']))
          : null,
      lowestScoreTeam: data['lowest_score_team'] != null
          ? FantasyRoundHighlightTeam.fromMap(Map<String, dynamic>.from(data['lowest_score_team']))
          : null,
      highestAppreciationTeam: data['highest_appreciation_team'] != null
          ? FantasyRoundHighlightTeam.fromMap(Map<String, dynamic>.from(data['highest_appreciation_team']))
          : null,
      lowestAppreciationTeam: data['lowest_appreciation_team'] != null
          ? FantasyRoundHighlightTeam.fromMap(Map<String, dynamic>.from(data['lowest_appreciation_team']))
          : null,
      updatedAt: data['updated_at'] is Timestamp ? (data['updated_at'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'round': round,
      'total_teams': totalTeams,
      'active_teams': activeTeams,
      'average_score': averageScore,
      'highest_score_team': highestScoreTeam?.toMap(),
      'lowest_score_team': lowestScoreTeam?.toMap(),
      'highest_appreciation_team': highestAppreciationTeam?.toMap(),
      'lowest_appreciation_team': lowestAppreciationTeam?.toMap(),
      'updated_at': updatedAt != null ? Timestamp.fromDate(updatedAt!) : FieldValue.serverTimestamp(),
    };
  }
}
