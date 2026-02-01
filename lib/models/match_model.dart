import 'package:cloud_firestore/cloud_firestore.dart';

class MatchModel {
  final String id;
  final DateTime? datetime;
  final String location;
  final int round;
  final String phase;
  final String status;
  
  // Palpitômetro
  final int votesHome;
  final int votesAway;

  final String homeTeamId;
  final String homeTeamName;
  final String homeTeamShield;
  final int? scoreHome;
  final int? penaltyScoreHome;
  
  final String awayTeamId;
  final String awayTeamName;
  final String awayTeamShield;
  final int? scoreAway;
  final int? penaltyScoreAway;
  
  final String? winnerTeamId;
  final String? sumulaUrl;

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
    this.votesHome = 0,
    this.votesAway = 0,
  });

  factory MatchModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // Helper para converter números de forma segura (evita erro de null ou double)
    int toInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is double) return value.toInt();
      return 0;
    }

    try {
      return MatchModel(
        id: doc.id,
        datetime: (data['datetime'] as Timestamp?)?.toDate(),
        location: data['location']?.toString() ?? 'Local a definir',
        round: toInt(data['round']),
        phase: data['phase']?.toString() ?? 'first',
        status: data['status']?.toString() ?? 'pending',
        
        homeTeamId: data['team_home_id']?.toString() ?? '',
        homeTeamName: data['team_home_name']?.toString() ?? 'Casa',
        homeTeamShield: data['team_home_shield']?.toString() ?? '',
        scoreHome: data['score_home'] != null ? toInt(data['score_home']) : null,
        penaltyScoreHome: data['penalty_score_home'] != null ? toInt(data['penalty_score_home']) : null,
        
        awayTeamId: data['team_away_id']?.toString() ?? '',
        awayTeamName: data['team_away_name']?.toString() ?? 'Visitante',
        awayTeamShield: data['team_away_shield']?.toString() ?? '',
        scoreAway: data['score_away'] != null ? toInt(data['score_away']) : null,
        penaltyScoreAway: data['penalty_score_away'] != null ? toInt(data['penalty_score_away']) : null,
        
        // --- AQUI ESTAVA O ERRO ---
        // Agora usamos a função toInt() que aceita null e retorna 0
        votesHome: toInt(data['votes_home']),
        votesAway: toInt(data['votes_away']),
        
        winnerTeamId: data['winner_team_id']?.toString(),
        sumulaUrl: data['sumula_url']?.toString(),
      );
    } catch (e) {
      print("🔥 ERRO FATAL AO LER JOGO ${doc.id}: $e");
      // Retorna um objeto vazio para não travar o app
      return MatchModel(
        id: doc.id,
        location: 'Erro de Leitura',
        round: 0, phase: 'first', status: 'pending',
        homeTeamId: '', homeTeamName: 'Erro', homeTeamShield: '',
        awayTeamId: '', awayTeamName: 'Erro', awayTeamShield: '',
      );
    }
  }

  bool get isFinished => status == 'finished';
  bool get isInProgress => status == 'in_progress';
  bool get isPending => status == 'pending';
  
  String get formattedScore {
    if (isPending) return "vs";
    return "${scoreHome ?? 0} x ${scoreAway ?? 0}";
  }
}