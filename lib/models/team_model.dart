import 'package:cloud_firestore/cloud_firestore.dart';

class Team {
  final String id;
  final String name;
  final String shortName;
  final String shieldUrl;
  final List<Map<String, dynamic>> championshipHistory;
  
  // Stats da Temporada
  final int points;
  final int matchPoints;
  final int extraPoints;
  final int gamesPlayed;
  final int wins;
  final int draws;
  final int losses;
  final int goalsFor;
  final int goalsAgainst;
  final int goalDifference;
  final int disciplinaryPoints;
  final int totalYellowCards;
  final int totalRedCards;
  
  // Gestão
  final List<String> defaultStarters;

  Team({
    required this.id,
    required this.name,
    required this.shortName,
    required this.shieldUrl,
    required this.championshipHistory,
    required this.points,
    required this.matchPoints,
    required this.extraPoints,
    required this.gamesPlayed,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.goalDifference,
    required this.disciplinaryPoints,
    required this.totalYellowCards,
    required this.totalRedCards,
    required this.defaultStarters,
  });

  // Fábrica para criar o objeto a partir do Firestore
  factory Team.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    return Team(
      id: doc.id,
      name: data['name'] ?? 'Time Desconhecido',
      shortName: data['short_name'] ?? '',
      shieldUrl: data['shield_url'] ?? '',
      championshipHistory: List<Map<String, dynamic>>.from(data['championship_history'] ?? []),
      
      points: (data['points'] as num?)?.toInt() ?? 0,
      matchPoints: (data['match_points'] as num?)?.toInt() ?? 0,
      extraPoints: (data['extra_points'] as num?)?.toInt() ?? 0,
      gamesPlayed: (data['games_played'] as num?)?.toInt() ?? 0,
      wins: (data['wins'] as num?)?.toInt() ?? 0,
      draws: (data['draws'] as num?)?.toInt() ?? 0,
      losses: (data['losses'] as num?)?.toInt() ?? 0,
      goalsFor: (data['goals_for'] as num?)?.toInt() ?? 0,
      goalsAgainst: (data['goals_against'] as num?)?.toInt() ?? 0,
      goalDifference: (data['goal_difference'] as num?)?.toInt() ?? 0,
      disciplinaryPoints: (data['disciplinary_points'] as num?)?.toInt() ?? 0,
      totalYellowCards: (data['total_yellow_cards'] as num?)?.toInt() ?? 0,
      totalRedCards: (data['total_red_cards'] as num?)?.toInt() ?? 0,
      
      defaultStarters: List<String>.from(data['default_starters'] ?? []),
    );
  }

  // Helper para converter de volta para Map (útil em updates)
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'short_name': shortName,
      'shield_url': shieldUrl,
      'championship_history': championshipHistory,
      'points': points,
      'match_points': matchPoints,
      'extra_points': extraPoints,
      'games_played': gamesPlayed,
      'wins': wins,
      'draws': draws,
      'losses': losses,
      'goals_for': goalsFor,
      'goals_against': goalsAgainst,
      'goal_difference': goalDifference,
      'disciplinary_points': disciplinaryPoints,
      'total_yellow_cards': totalYellowCards,
      'total_red_cards': totalRedCards,
      'default_starters': defaultStarters,
    };
  }
}