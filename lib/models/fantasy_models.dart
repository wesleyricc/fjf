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
  
  // --- NOVO: Histórico para auditoria e recálculo exato da média ---
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
    required this.history, // Obrigatório
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
      // Carrega o histórico (ou lista vazia se não existir)
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
      'history': history, // Salva o histórico
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
    };
  }
}