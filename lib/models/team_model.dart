import 'package:cloud_firestore/cloud_firestore.dart';

class Team {
  final String id;
  final String name;
  final String shortName;
  final String shieldUrl;
  final List<Map<String, dynamic>> championshipHistory;
  
  // Stats da 1ª Fase (Mantido comportamento padrão)
  final int points;
  final int matchPoints;
  final int gamesPlayed;
  final int wins;
  final int draws;
  final int losses;
  final int goalsFor;
  final int goalsAgainst;
  final int goalDifference;
  
  // Stats Gerais (Todo o Campeonato) -- NOVOS CAMPOS --
  final int overallPoints;
  final int overallMatchPoints;
  final int overallGamesPlayed;
  final int overallWins;
  final int overallDraws;
  final int overallLosses;
  final int overallGoalsFor;
  final int overallGoalsAgainst;
  final int overallGoalDifference;

  // Disciplinar e Extras
  final int extraPoints;
  final int disciplinaryPoints;
  final int totalYellowCards;
  final int totalRedCards;
  
  // Gestão
  final List<String> defaultStarters;
  
  // Customização
  final String? primaryColor;

  Team({
    required this.id,
    required this.name,
    required this.shortName,
    required this.shieldUrl,
    required this.championshipHistory,
    
    // 1ª Fase
    required this.points,
    required this.matchPoints,
    required this.gamesPlayed,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.goalDifference,

    // Geral
    required this.overallPoints,
    required this.overallMatchPoints,
    required this.overallGamesPlayed,
    required this.overallWins,
    required this.overallDraws,
    required this.overallLosses,
    required this.overallGoalsFor,
    required this.overallGoalsAgainst,
    required this.overallGoalDifference,

    required this.extraPoints,
    required this.disciplinaryPoints,
    required this.totalYellowCards,
    required this.totalRedCards,
    required this.defaultStarters,
    this.primaryColor,
  });

  factory Team.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    return Team(
      id: doc.id,
      name: data['name'] ?? 'Time Desconhecido',
      shortName: data['short_name'] ?? '',
      shieldUrl: (data['shield_url'] ??
              data['shieldUrl'] ??
              data['team_shield_url'] ??
              data['teamShieldUrl'] ??
              data['logo_url'] ??
              data['logoUrl'] ??
              data['shield'] ??
              '')
          .toString(),
      championshipHistory: List<Map<String, dynamic>>.from(data['championship_history'] ?? []),
      
      // 1ª Fase
      points: (data['points'] as num?)?.toInt() ?? 0,
      matchPoints: (data['match_points'] as num?)?.toInt() ?? 0,
      gamesPlayed: (data['games_played'] as num?)?.toInt() ?? 0,
      wins: (data['wins'] as num?)?.toInt() ?? 0,
      draws: (data['draws'] as num?)?.toInt() ?? 0,
      losses: (data['losses'] as num?)?.toInt() ?? 0,
      goalsFor: (data['goals_for'] as num?)?.toInt() ?? 0,
      goalsAgainst: (data['goals_against'] as num?)?.toInt() ?? 0,
      goalDifference: (data['goal_difference'] as num?)?.toInt() ?? 0,

      // Geral (Novos campos, com fallback para 0)
      overallPoints: (data['overall_points'] as num?)?.toInt() ?? 0,
      overallMatchPoints: (data['overall_match_points'] as num?)?.toInt() ?? 0,
      overallGamesPlayed: (data['overall_games_played'] as num?)?.toInt() ?? 0,
      overallWins: (data['overall_wins'] as num?)?.toInt() ?? 0,
      overallDraws: (data['overall_draws'] as num?)?.toInt() ?? 0,
      overallLosses: (data['overall_losses'] as num?)?.toInt() ?? 0,
      overallGoalsFor: (data['overall_goals_for'] as num?)?.toInt() ?? 0,
      overallGoalsAgainst: (data['overall_goals_against'] as num?)?.toInt() ?? 0,
      overallGoalDifference: (data['overall_goal_difference'] as num?)?.toInt() ?? 0,

      // Extras
      extraPoints: (data['extra_points'] as num?)?.toInt() ?? 0,
      disciplinaryPoints: (data['disciplinary_points'] as num?)?.toInt() ?? 0,
      totalYellowCards: (data['total_yellow_cards'] as num?)?.toInt() ?? 0,
      totalRedCards: (data['total_red_cards'] as num?)?.toInt() ?? 0,
      
      defaultStarters: List<String>.from(data['default_starters'] ?? []),
      primaryColor: data['primary_color'] as String? ?? data['color'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'short_name': shortName,
      'shield_url': shieldUrl,
      'championship_history': championshipHistory,
      
      // 1ª Fase
      'points': points,
      'match_points': matchPoints,
      'games_played': gamesPlayed,
      'wins': wins,
      'draws': draws,
      'losses': losses,
      'goals_for': goalsFor,
      'goals_against': goalsAgainst,
      'goal_difference': goalDifference,

      // Geral
      'overall_points': overallPoints,
      'overall_match_points': overallMatchPoints,
      'overall_games_played': overallGamesPlayed,
      'overall_wins': overallWins,
      'overall_draws': overallDraws,
      'overall_losses': overallLosses,
      'overall_goals_for': overallGoalsFor,
      'overall_goals_against': overallGoalsAgainst,
      'overall_goal_difference': overallGoalDifference,

      'extra_points': extraPoints,
      'disciplinary_points': disciplinaryPoints,
      'total_yellow_cards': totalYellowCards,
      'total_red_cards': totalRedCards,
      'default_starters': defaultStarters,
      if (primaryColor != null) 'primary_color': primaryColor,
    };
  }

  Team copyWith({
    String? id,
    String? name,
    String? shortName,
    String? shieldUrl,
    List<Map<String, dynamic>>? championshipHistory,
    int? points,
    int? matchPoints,
    int? gamesPlayed,
    int? wins,
    int? draws,
    int? losses,
    int? goalsFor,
    int? goalsAgainst,
    int? goalDifference,
    int? overallPoints,
    int? overallMatchPoints,
    int? overallGamesPlayed,
    int? overallWins,
    int? overallDraws,
    int? overallLosses,
    int? overallGoalsFor,
    int? overallGoalsAgainst,
    int? overallGoalDifference,
    int? extraPoints,
    int? disciplinaryPoints,
    int? totalYellowCards,
    int? totalRedCards,
    List<String>? defaultStarters,
    String? primaryColor,
  }) {
    return Team(
      id: id ?? this.id,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      shieldUrl: shieldUrl ?? this.shieldUrl,
      championshipHistory: championshipHistory ?? this.championshipHistory,
      points: points ?? this.points,
      matchPoints: matchPoints ?? this.matchPoints,
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      wins: wins ?? this.wins,
      draws: draws ?? this.draws,
      losses: losses ?? this.losses,
      goalsFor: goalsFor ?? this.goalsFor,
      goalsAgainst: goalsAgainst ?? this.goalsAgainst,
      goalDifference: goalDifference ?? this.goalDifference,
      overallPoints: overallPoints ?? this.overallPoints,
      overallMatchPoints: overallMatchPoints ?? this.overallMatchPoints,
      overallGamesPlayed: overallGamesPlayed ?? this.overallGamesPlayed,
      overallWins: overallWins ?? this.overallWins,
      overallDraws: overallDraws ?? this.overallDraws,
      overallLosses: overallLosses ?? this.overallLosses,
      overallGoalsFor: overallGoalsFor ?? this.overallGoalsFor,
      overallGoalsAgainst: overallGoalsAgainst ?? this.overallGoalsAgainst,
      overallGoalDifference: overallGoalDifference ?? this.overallGoalDifference,
      extraPoints: extraPoints ?? this.extraPoints,
      disciplinaryPoints: disciplinaryPoints ?? this.disciplinaryPoints,
      totalYellowCards: totalYellowCards ?? this.totalYellowCards,
      totalRedCards: totalRedCards ?? this.totalRedCards,
      defaultStarters: defaultStarters ?? this.defaultStarters,
      primaryColor: primaryColor ?? this.primaryColor,
    );
  }
}