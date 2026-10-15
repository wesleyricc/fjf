import 'package:cloud_firestore/cloud_firestore.dart';

class FantasyAuditSummary {
  final String id;
  final String seasonId;
  final int round;
  final DateTime? runAt;
  final String runBy;
  final int totalPlayersAudited;
  final int playersWithDiscrepancies;
  final int totalTeamsAudited;
  final int teamsWithDiscrepancies;
  final double maxPlayerDelta;
  final int totalMatches;
  final int matchesFinished;
  final bool liveIsFinal;
  final Map<String, dynamic> configEffective;
  final List<String> configWarnings;
  final String status;

  FantasyAuditSummary({
    required this.id,
    required this.seasonId,
    required this.round,
    this.runAt,
    required this.runBy,
    required this.totalPlayersAudited,
    required this.playersWithDiscrepancies,
    required this.totalTeamsAudited,
    required this.teamsWithDiscrepancies,
    required this.maxPlayerDelta,
    required this.totalMatches,
    required this.matchesFinished,
    required this.liveIsFinal,
    required this.configEffective,
    required this.configWarnings,
    required this.status,
  });

  factory FantasyAuditSummary.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawRunAt = data['run_at'];
    DateTime? dt;
    if (rawRunAt is Timestamp) {
      dt = rawRunAt.toDate();
    } else if (rawRunAt is String) {
      dt = DateTime.tryParse(rawRunAt);
    }

    return FantasyAuditSummary(
      id: doc.id,
      seasonId: data['season_id'] ?? '',
      round: (data['round'] ?? 1).toInt(),
      runAt: dt,
      runBy: data['run_by'] ?? '',
      totalPlayersAudited: (data['total_players_audited'] ?? 0).toInt(),
      playersWithDiscrepancies: (data['players_with_discrepancies'] ?? 0).toInt(),
      totalTeamsAudited: (data['total_teams_audited'] ?? 0).toInt(),
      teamsWithDiscrepancies: (data['teams_with_discrepancies'] ?? 0).toInt(),
      maxPlayerDelta: (data['max_player_delta'] ?? 0.0).toDouble(),
      totalMatches: (data['total_matches'] ?? 0).toInt(),
      matchesFinished: (data['matches_finished'] ?? 0).toInt(),
      liveIsFinal: data['live_is_final'] ?? false,
      configEffective: Map<String, dynamic>.from(data['config_effective'] ?? {}),
      configWarnings: List<String>.from(data['config_warnings'] ?? []),
      status: data['status'] ?? 'UNKNOWN',
    );
  }
}

class FantasyAuditPlayer {
  final String playerId;
  final String name;
  final String position;
  final String teamId;
  final String teamShieldUrl;
  final String photoUrl;
  final bool played;
  final Map<String, int> scouts;
  final double expectedScore;
  final List<Map<String, dynamic>> breakdown;
  final List<Map<String, dynamic>> timelineEvidence;
  final double priceBefore;
  final double priceExpectedVariation;
  final double priceExpectedNew;
  final double publishedLiveScore;
  final double? publishedFinalScore;
  final double? publishedPriceChange;
  final double deltaLive;
  final double? deltaFinal;
  final double? deltaPrice;
  final bool hasDiscrepancy;
  final List<String> flags;
  final Map<String, dynamic>? coachDetails;

  FantasyAuditPlayer({
    required this.playerId,
    required this.name,
    required this.position,
    required this.teamId,
    required this.teamShieldUrl,
    required this.photoUrl,
    required this.played,
    required this.scouts,
    required this.expectedScore,
    required this.breakdown,
    required this.timelineEvidence,
    required this.priceBefore,
    required this.priceExpectedVariation,
    required this.priceExpectedNew,
    required this.publishedLiveScore,
    this.publishedFinalScore,
    this.publishedPriceChange,
    required this.deltaLive,
    this.deltaFinal,
    this.deltaPrice,
    required this.hasDiscrepancy,
    required this.flags,
    this.coachDetails,
  });

  factory FantasyAuditPlayer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawScouts = data['scouts'] as Map<String, dynamic>? ?? {};
    final scoutsMap = rawScouts.map((k, v) => MapEntry(k, (v as num).toInt()));

    return FantasyAuditPlayer(
      playerId: doc.id,
      name: data['name'] ?? 'Desconhecido',
      position: data['position'] ?? 'Linha',
      teamId: data['teamId'] ?? '',
      teamShieldUrl: data['teamShieldUrl'] ?? '',
      photoUrl: data['photoUrl'] ?? '',
      played: data['played'] ?? false,
      scouts: scoutsMap,
      expectedScore: (data['expectedScore'] ?? 0.0).toDouble(),
      breakdown: List<Map<String, dynamic>>.from(data['breakdown'] ?? []),
      timelineEvidence: List<Map<String, dynamic>>.from(data['timelineEvidence'] ?? []),
      priceBefore: (data['priceBefore'] ?? 1.0).toDouble(),
      priceExpectedVariation: (data['priceExpectedVariation'] ?? 0.0).toDouble(),
      priceExpectedNew: (data['priceExpectedNew'] ?? 1.0).toDouble(),
      publishedLiveScore: (data['publishedLiveScore'] ?? 0.0).toDouble(),
      publishedFinalScore: data['publishedFinalScore'] != null ? (data['publishedFinalScore'] as num).toDouble() : null,
      publishedPriceChange: data['publishedPriceChange'] != null ? (data['publishedPriceChange'] as num).toDouble() : null,
      deltaLive: (data['deltaLive'] ?? 0.0).toDouble(),
      deltaFinal: data['deltaFinal'] != null ? (data['deltaFinal'] as num).toDouble() : null,
      deltaPrice: data['deltaPrice'] != null ? (data['deltaPrice'] as num).toDouble() : null,
      hasDiscrepancy: data['hasDiscrepancy'] ?? false,
      flags: List<String>.from(data['flags'] ?? []),
      coachDetails: data['coachDetails'] != null ? Map<String, dynamic>.from(data['coachDetails']) : null,
    );
  }
}

class FantasyAuditMatch {
  final String matchId;
  final String matchLabel;
  final String homeId;
  final String awayId;
  final int scoreHome;
  final int scoreAway;
  final String status;
  final int lineupPlayedCount;
  final int timelineEventsCount;
  final String? motmId;
  final bool cleanSheetHome;
  final bool cleanSheetAway;
  final bool statsAppliedPresent;
  final List<String> discrepancies;

  FantasyAuditMatch({
    required this.matchId,
    required this.matchLabel,
    required this.homeId,
    required this.awayId,
    required this.scoreHome,
    required this.scoreAway,
    required this.status,
    required this.lineupPlayedCount,
    required this.timelineEventsCount,
    this.motmId,
    required this.cleanSheetHome,
    required this.cleanSheetAway,
    required this.statsAppliedPresent,
    required this.discrepancies,
  });

  factory FantasyAuditMatch.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FantasyAuditMatch(
      matchId: doc.id,
      matchLabel: data['matchLabel'] ?? '',
      homeId: data['homeId'] ?? '',
      awayId: data['awayId'] ?? '',
      scoreHome: (data['scoreHome'] ?? 0).toInt(),
      scoreAway: (data['scoreAway'] ?? 0).toInt(),
      status: data['status'] ?? 'pending',
      lineupPlayedCount: (data['lineupPlayedCount'] ?? 0).toInt(),
      timelineEventsCount: (data['timelineEventsCount'] ?? 0).toInt(),
      motmId: data['motmId'],
      cleanSheetHome: data['cleanSheetHome'] ?? false,
      cleanSheetAway: data['cleanSheetAway'] ?? false,
      statsAppliedPresent: data['statsAppliedPresent'] ?? false,
      discrepancies: List<String>.from(data['discrepancies'] ?? []),
    );
  }
}

class FantasyAuditTeam {
  final String teamId;
  final String teamName;
  final String ownerName;
  final String? captainId;
  final int lineupCount;
  final double expectedPoints;
  final double publishedPoints;
  final double delta;
  final bool hasDiscrepancy;
  final List<Map<String, dynamic>> players;
  final List<dynamic> substitutions;

  FantasyAuditTeam({
    required this.teamId,
    required this.teamName,
    required this.ownerName,
    this.captainId,
    required this.lineupCount,
    required this.expectedPoints,
    required this.publishedPoints,
    required this.delta,
    required this.hasDiscrepancy,
    required this.players,
    required this.substitutions,
  });

  factory FantasyAuditTeam.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FantasyAuditTeam(
      teamId: doc.id,
      teamName: data['teamName'] ?? 'Sem nome',
      ownerName: data['ownerName'] ?? 'Desconhecido',
      captainId: data['captainId'],
      lineupCount: (data['lineupCount'] ?? 0).toInt(),
      expectedPoints: (data['expectedPoints'] ?? 0.0).toDouble(),
      publishedPoints: (data['publishedPoints'] ?? 0.0).toDouble(),
      delta: (data['delta'] ?? 0.0).toDouble(),
      hasDiscrepancy: data['hasDiscrepancy'] ?? false,
      players: List<Map<String, dynamic>>.from(data['players'] ?? []),
      substitutions: List<dynamic>.from(data['substitutions'] ?? []),
    );
  }
}
