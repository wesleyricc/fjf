import 'package:cloud_firestore/cloud_firestore.dart';

class MatchModel {
  final String id;
  final DateTime? datetime;
  final String location;
  final int round;
  final String phase;
  final String status; // 'pending', 'in_progress', 'finished'
  
  // Time Casa
  final String homeTeamId;
  final String homeTeamName;
  final String homeTeamShield;
  final int? scoreHome;
  final int? penaltyScoreHome;
  
  // Time Fora
  final String awayTeamId;
  final String awayTeamName;
  final String awayTeamShield;
  final int? scoreAway;
  final int? penaltyScoreAway;
  
  // Metadados
  final String? winnerTeamId;
  final String? sumulaUrl;
  
  // Nota: stats_applied é muito complexo e específico do backend, 
  // geralmente não precisamos dele mapeado na UI, apenas para lógica interna.
  // Se precisar, podemos criar um sub-model StatsApplied.

  MatchModel({
    required this.id,
    this.datetime,
    required this.location,
    required this.round,
    required this.phase,
    required this.status,
    required this.homeTeamId,
    required this.homeTeamName,
    required this.homeTeamShield,
    this.scoreHome,
    this.penaltyScoreHome,
    required this.awayTeamId,
    required this.awayTeamName,
    required this.awayTeamShield,
    this.scoreAway,
    this.penaltyScoreAway,
    this.winnerTeamId,
    this.sumulaUrl,
  });

  factory MatchModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    return MatchModel(
      id: doc.id,
      datetime: (data['datetime'] as Timestamp?)?.toDate(),
      location: data['location'] ?? 'Local a definir',
      round: (data['round'] as num?)?.toInt() ?? 0,
      phase: data['phase'] ?? 'first',
      status: data['status'] ?? 'pending',
      
      homeTeamId: data['team_home_id'] ?? '',
      homeTeamName: data['team_home_name'] ?? 'Casa',
      homeTeamShield: data['team_home_shield'] ?? '',
      scoreHome: (data['score_home'] as num?)?.toInt(),
      penaltyScoreHome: (data['penalty_score_home'] as num?)?.toInt(),
      
      awayTeamId: data['team_away_id'] ?? '',
      awayTeamName: data['team_away_name'] ?? 'Visitante',
      awayTeamShield: data['team_away_shield'] ?? '',
      scoreAway: (data['score_away'] as num?)?.toInt(),
      penaltyScoreAway: (data['penalty_score_away'] as num?)?.toInt(),
      
      winnerTeamId: data['winner_team_id'],
      sumulaUrl: data['sumula_url'],
    );
  }

  // Helper getters para facilitar a UI
  bool get isFinished => status == 'finished';
  bool get isInProgress => status == 'in_progress';
  bool get isPending => status == 'pending';
  
  String get formattedScore {
    if (isPending) return "v";
    return "${scoreHome ?? 0} x ${scoreAway ?? 0}";
  }
}