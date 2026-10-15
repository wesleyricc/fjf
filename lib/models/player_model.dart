import 'package:cloud_firestore/cloud_firestore.dart';

class Player {
  final String id;
  final String name;
  final int? jerseyNumber;
  final String? position;
  final String? secondaryPosition; // NEW FIELD
  final double? fantasyInitialPrice; // NEW FIELD
  final DateTime? dateOfBirth;
  final int? heightCm;
  final int? weightKg;
  final String? preferredFoot;
  final String photoUrl;

  // Contexto do Time
  final String teamId;
  final String teamName;
  final String teamShieldUrl;

  // Flags de Tipo
  final bool isStaff;
  final String? staffRole;
  final bool isGoalkeeper;
  final bool isActive;
  final bool isSuspended;

  // Estatísticas da Temporada
  final int goals;
  final int assists;
  final int yellowCards;
  final int redCards;
  final int totalYellowCards;
  final int totalRedCards;
  final int goalsConceded;
  final int motmAwards;
  final int matchesPlayed;

  Player({
    required this.id,
    required this.name,
    this.jerseyNumber,
    this.position,
    this.secondaryPosition,
    this.fantasyInitialPrice,
    this.dateOfBirth,
    this.heightCm,
    this.weightKg,
    this.preferredFoot,
    required this.photoUrl,
    required this.teamId,
    required this.teamName,
    required this.teamShieldUrl,
    required this.isStaff,
    this.staffRole,
    required this.isGoalkeeper,
    required this.isActive,
    required this.isSuspended,
    required this.goals,
    required this.assists,
    required this.yellowCards,
    required this.redCards,
    required this.totalYellowCards,
    required this.totalRedCards,
    required this.goalsConceded,
    required this.motmAwards,
    required this.matchesPlayed,
  });

  factory Player.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    return Player.fromMap({...data, 'id': doc.id});
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'jersey_number': jerseyNumber,
      'position': position,
      'secondary_position': secondaryPosition,
      'fantasy_initial_price': fantasyInitialPrice,
      'date_of_birth':
          dateOfBirth != null ? Timestamp.fromDate(dateOfBirth!) : null,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'preferred_foot': preferredFoot,
      'photo_url': photoUrl,
      'team_id': teamId,
      'team_name': teamName,
      'team_shield_url': teamShieldUrl,
      'is_staff': isStaff,
      'staff_role': staffRole,
      'is_goalkeeper': isGoalkeeper,
      'isActive': isActive,
      'is_suspended': isSuspended,
      'goals': goals,
      'assists': assists,
      'yellow_cards': yellowCards,
      'red_cards': redCards,
      'total_yellow_cards': totalYellowCards,
      'total_red_cards': totalRedCards,
      'goals_conceded': goalsConceded,
      'man_of_the_match_awards': motmAwards,
      'matches_played': matchesPlayed,
    };
  }

  factory Player.fromMap(Map<String, dynamic> data) {
    return Player(
      id: data['id'] ?? '',
      name: data['name'] ?? 'Sem Nome',
      jerseyNumber: data['jersey_number'],
      position: data['position'],
      secondaryPosition: data['secondary_position'],
      fantasyInitialPrice: (data['fantasy_initial_price'] as num?)?.toDouble(),
      dateOfBirth: data['date_of_birth'] != null
          ? (data['date_of_birth'] is Timestamp
              ? (data['date_of_birth'] as Timestamp).toDate()
              : null)
          : null,
      heightCm: (data['height_cm'] as num?)?.toInt(),
      weightKg: (data['weight_kg'] as num?)?.toInt(),
      preferredFoot: data['preferred_foot'],
      photoUrl: data['photo_url'] ?? '',
      teamId: data['team_id'] ?? '',
      teamName: data['team_name'] ?? '',
      teamShieldUrl: data['team_shield_url'] ?? '',
      isStaff: data['is_staff'] ?? false,
      staffRole: data['staff_role'],
      isGoalkeeper: data['is_goalkeeper'] ?? false,
      isActive: data['isActive'] ?? true,
      isSuspended: data['is_suspended'] ?? false,
      goals: (data['goals'] as num?)?.toInt() ?? 0,
      assists: (data['assists'] as num?)?.toInt() ?? 0,
      yellowCards: (data['yellow_cards'] as num?)?.toInt() ?? 0,
      redCards: (data['red_cards'] as num?)?.toInt() ?? 0,
      totalYellowCards: (data['total_yellow_cards'] as num?)?.toInt() ?? 0,
      totalRedCards: (data['total_red_cards'] as num?)?.toInt() ?? 0,
      goalsConceded: (data['goals_conceded'] as num?)?.toInt() ?? 0,
      motmAwards: (data['man_of_the_match_awards'] as num?)?.toInt() ?? 0,
      matchesPlayed: (data['matches_played'] as num?)?.toInt() ?? 0,
    );
  }
}
