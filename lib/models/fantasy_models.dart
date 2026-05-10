import 'package:cloud_firestore/cloud_firestore.dart';

class FantasyPlayer {
  final String playerId;
  final String name;
  final String position;
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

  factory FantasyPlayer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FantasyPlayer(
      playerId: doc.id,
      name: data['name'] ?? '',
      position: data['position'] ?? '',
      teamId: data['team_id'] ?? '',
      teamShieldUrl: data['team_shield_url'] ?? '',
      photoUrl: data['photo_url'] ?? '',
      currentPrice: (data['current_price'] ?? 0).toDouble(),
      lastPriceChange: (data['last_price_change'] ?? 0).toDouble(),
      lastScore: (data['last_score'] ?? 0).toDouble(),
      averageScore: (data['average_score'] ?? 0).toDouble(),
      matchesPlayed: (data['matches_played'] ?? 0).toInt(),
      status: data['status'] ?? 'probable',
      history: List<Map<String, dynamic>>.from(data['history'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'position': position,
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
  final double currentBalance;
  final List<String> lineupPlayerIds;
  final String? captainId;
  final String shieldType; 
  final String? customLogoUrl;

  FantasyTeam({
    required this.id,
    required this.userId,
    required this.ownerId,
    required this.ownerName,
    required this.teamName,
    required this.totalPoints,
    required this.lastScore, 
    required this.teamValue,
    required this.currentBalance,
    required this.lineupPlayerIds,
    this.captainId,
    required this.shieldType,
    this.customLogoUrl,
  });

  factory FantasyTeam.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return FantasyTeam(
      id: doc.id,
      userId: data['user_id'] ?? doc.id,
      ownerId: data['owner_id'] ?? doc.id,
      ownerName: data['owner_name'] ?? 'Cartoleiro',
      teamName: data['team_name'] ?? 'Time sem nome',
      totalPoints: (data['total_points'] ?? 0).toDouble(),
      lastScore: (data['last_score'] ?? 0).toDouble(), 
      teamValue: (data['team_value'] ?? 100).toDouble(),
      currentBalance: (data['current_balance'] ?? 100).toDouble(),
      lineupPlayerIds: List<String>.from(
          data['lineup_player_ids'] ?? data['lineup'] ?? []
      ),
      captainId: data['captain_id'],
      shieldType: data['shield_type'] ?? '1',
      customLogoUrl: data['custom_logo_url'],
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
      'current_balance': currentBalance,
      'lineup_player_ids': lineupPlayerIds,
      'captain_id': captainId,
      'shield_type': shieldType,
      'custom_logo_url': customLogoUrl,
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
      factorExpectation: 0.35,
      factorVariation: 0.25,
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
      ptsYellowCard: toDouble(map['ptsYellowCard'] ?? map['pts_yellow_card'], -1.0),
      ptsRedCard: toDouble(map['ptsRedCard'] ?? map['pts_red_card'], -3.0),
      ptsPenaltySaved: toDouble(map['ptsPenaltySaved'] ?? map['pts_penalty_saved'], 5.0),
      ptsPenaltyMissed: toDouble(map['ptsPenaltyMissed'] ?? map['pts_penalty_missed'], -3.0),
      ptsShotOnPost: toDouble(map['ptsShotOnPost'] ?? map['pts_shot_on_post'], 3.0),
      ptsCleanSheet: toDouble(map['ptsCleanSheet'] ?? map['pts_clean_sheet'], 5.0),
      factorExpectation: toDouble(map['factorExpectation'] ?? map['factor_expectation'], 0.35),
      factorVariation: toDouble(map['factorVariation'] ?? map['factor_variation'], 0.25),
      capLimitPercent: toDouble(map['capLimitPercent'] ?? map['cap_limit_percent'], 0.25),
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
      'factorExpectation': factorExpectation,
      'factorVariation': factorVariation,
      'capLimitPercent': capLimitPercent,
      'minPrice': minPrice,
    };
  }
}