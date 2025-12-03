import 'package:cloud_firestore/cloud_firestore.dart';

class Player {
  final String id;
  final String name;
  final int? jerseyNumber;
  final String? position;
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

  Player({
    required this.id,
    required this.name,
    this.jerseyNumber,
    this.position,
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
  });

  factory Player.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    return Player(
      id: doc.id,
      name: data['name'] ?? 'Sem Nome',
      jerseyNumber: data['jersey_number'],
      position: data['position'],
      dateOfBirth: (data['date_of_birth'] as Timestamp?)?.toDate(),
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
    );
  }
}