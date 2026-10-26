import 'package:cloud_firestore/cloud_firestore.dart';

class FantasyLeague {
  final String id;
  final String name;
  final String inviteCode;
  final String ownerId;
  final List<String> members;
  final String type; 
  final int? maxTeams;
  final String status;
  final int? startRound;
  final bool isSponsored;
  final String? sponsorImageUrl;
  final String? prizeDescription;

  final String? imageUrl;

  FantasyLeague({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.ownerId,
    required this.members,
    this.type = 'classic',
    this.maxTeams,
    this.status = 'active',
    this.startRound,
    this.isSponsored = false,
    this.sponsorImageUrl,
    this.prizeDescription,
    this.imageUrl,
  });

  factory FantasyLeague.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final sponsorImg = data['sponsor_image_url'] as String?;
    final img = (data['image_url'] ?? data['logo_url'] ?? sponsorImg) as String?;
    return FantasyLeague(
      id: doc.id,
      name: data['name'] ?? 'Liga Sem Nome',
      inviteCode: data['invite_code'] ?? '',
      ownerId: data['owner_id'] ?? '',
      members: List<String>.from(data['members'] ?? []),
      type: data['type'] ?? 'classic',
      maxTeams: data['max_teams'],
      status: data['status'] ?? 'active',
      startRound: data['start_round'],
      isSponsored: data['is_sponsored'] ?? false,
      sponsorImageUrl: sponsorImg,
      prizeDescription: data['prize_description'],
      imageUrl: img,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'invite_code': inviteCode,
      'owner_id': ownerId,
      'members': members,
      'type': type,
      'max_teams': maxTeams,
      'status': status,
      'start_round': startRound,
      'is_sponsored': isSponsored,
      'sponsor_image_url': sponsorImageUrl,
      'prize_description': prizeDescription,
      'image_url': imageUrl,
      'created_at': FieldValue.serverTimestamp(),
    };
  }

  FantasyLeague copyWith({
    String? id,
    String? name,
    String? inviteCode,
    String? ownerId,
    List<String>? members,
    String? type,
    int? maxTeams,
    String? status,
    int? startRound,
    bool? isSponsored,
    String? sponsorImageUrl,
    String? prizeDescription,
    String? imageUrl,
  }) {
    return FantasyLeague(
      id: id ?? this.id,
      name: name ?? this.name,
      inviteCode: inviteCode ?? this.inviteCode,
      ownerId: ownerId ?? this.ownerId,
      members: members ?? this.members,
      type: type ?? this.type,
      maxTeams: maxTeams ?? this.maxTeams,
      status: status ?? this.status,
      startRound: startRound ?? this.startRound,
      isSponsored: isSponsored ?? this.isSponsored,
      sponsorImageUrl: sponsorImageUrl ?? this.sponsorImageUrl,
      prizeDescription: prizeDescription ?? this.prizeDescription,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}

class KnockoutMatch {
  final String id;
  final String phase;
  final int round;
  final String? teamAId;
  final String? teamBId;
  final double teamAScore;
  final double teamBScore;
  final String? winnerId;
  final String? nextMatchId;
  final int matchIndex; 

  KnockoutMatch({
    required this.id,
    required this.phase,
    required this.round,
    this.teamAId,
    this.teamBId,
    this.teamAScore = 0.0,
    this.teamBScore = 0.0,
    this.winnerId,
    this.nextMatchId,
    required this.matchIndex,
  });

  factory KnockoutMatch.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return KnockoutMatch(
      id: doc.id,
      phase: data['phase'] ?? '',
      round: data['round'] ?? 0,
      teamAId: data['team_a_id'],
      teamBId: data['team_b_id'],
      teamAScore: (data['team_a_score'] ?? 0.0).toDouble(),
      teamBScore: (data['team_b_score'] ?? 0.0).toDouble(),
      winnerId: data['winner_id'],
      nextMatchId: data['next_match_id'],
      matchIndex: data['match_index'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'phase': phase,
      'round': round,
      'team_a_id': teamAId,
      'team_b_id': teamBId,
      'team_a_score': teamAScore,
      'team_b_score': teamBScore,
      'winner_id': winnerId,
      'next_match_id': nextMatchId,
      'match_index': matchIndex,
    };
  }
}