import 'package:cloud_firestore/cloud_firestore.dart';

// --- JOGO DA COPA ---
class BolaoMatch {
  final String id;
  final String group; 
  final String homeTeam;
  final String awayTeam;
  final String homeFlagUrl; 
  final String awayFlagUrl;
  final DateTime date;
  final String location;
  
  // Placar oficial (preenchido pelo Admin depois do jogo real)
  final int? realScoreHome;
  final int? realScoreAway;
  final String status; // 'pending', 'in_progress', 'finished'

  BolaoMatch({
    required this.id,
    required this.group,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeFlagUrl,
    required this.awayFlagUrl,
    required this.date,
    required this.location,
    this.realScoreHome,
    this.realScoreAway,
    required this.status,
  });

  factory BolaoMatch.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BolaoMatch(
      id: doc.id,
      group: data['group'] ?? '',
      homeTeam: data['home_team'] ?? '',
      awayTeam: data['away_team'] ?? '',
      homeFlagUrl: data['home_flag_url'] ?? '',
      awayFlagUrl: data['away_flag_url'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      location: data['location'] ?? '',
      realScoreHome: data['real_score_home'],
      realScoreAway: data['real_score_away'],
      status: data['status'] ?? 'pending',
    );
  }
}

// --- PALPITE DO USUÁRIO ---
class BolaoPrediction {
  final String matchId;
  final int scoreHome;
  final int scoreAway;
  final int? pointsEarned; 

  BolaoPrediction({
    required this.matchId,
    required this.scoreHome,
    required this.scoreAway,
    this.pointsEarned,
  });

  factory BolaoPrediction.fromMap(String id, Map<String, dynamic> map) {
    return BolaoPrediction(
      matchId: id,
      scoreHome: map['score_home'] ?? 0,
      scoreAway: map['score_away'] ?? 0,
      pointsEarned: map['points_earned'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'score_home': scoreHome,
      'score_away': scoreAway,
    };
  }
}

// --- PERFIL DO USUÁRIO NO BOLÃO ---
class BolaoUser {
  final String userId;
  final String name;
  final int totalPoints;
  final int exactHits;
  final int goalDifferenceHits;
  final int winnerHits;
  final int bonusPoints;
  final String? cpf;
  final String? phone;
  final String? photoUrl;
  
  // BÔNUS
  final String? champion;
  final String? runnerUp;
  final String? bestOffense;
  final String? worstDefense;
  final String? disappointment;

  // BÔNUS PONTOS INDIVIDUAIS
  final int? bonusChampionPoints;
  final int? bonusRunnerUpPoints;
  final int? bonusBestOffensePoints;
  final int? bonusWorstDefensePoints;
  final int? bonusDisappointmentPoints;

  BolaoUser({
    required this.userId,
    required this.name,
    this.totalPoints = 0,
    this.exactHits = 0,
    this.goalDifferenceHits = 0,
    this.winnerHits = 0,
    this.bonusPoints = 0,
    this.champion,
    this.runnerUp,
    this.bestOffense,
    this.worstDefense,
    this.disappointment,
    this.bonusChampionPoints,
    this.bonusRunnerUpPoints,
    this.bonusBestOffensePoints,
    this.bonusWorstDefensePoints,
    this.bonusDisappointmentPoints,
    this.cpf,         
    this.phone,       
    this.photoUrl,    
  });

  // 🚨 NOVO: VALIDADOR DE CADASTRO COMPLETO 🚨
  bool get isProfileComplete {
    return name.trim().isNotEmpty && 
           name != 'Utilizador' &&
           cpf != null && cpf!.trim().isNotEmpty && 
           phone != null && phone!.trim().isNotEmpty;
  }

  factory BolaoUser.fromMap(String id, Map<String, dynamic> data) {
    return BolaoUser(
      userId: id,
      name: data['name'] ?? 'Utilizador',
      totalPoints: (data['total_points'] ?? 0).toInt(),
      exactHits: (data['exact_hits'] ?? 0).toInt(),
      goalDifferenceHits: (data['goal_difference_hits'] ?? 0).toInt(),
      winnerHits: (data['winner_hits'] ?? 0).toInt(),
      bonusPoints: (data['bonus_points'] ?? 0).toInt(),
      champion: data['bonus_champion'],
      runnerUp: data['bonus_runner_up'],
      bestOffense: data['bonus_best_offense'],
      worstDefense: data['bonus_worst_defense'],
      disappointment: data['bonus_disappointment'],
      bonusChampionPoints: data['bonus_champion_points'],
      bonusRunnerUpPoints: data['bonus_runner_up_points'],
      bonusBestOffensePoints: data['bonus_best_offense_points'],
      bonusWorstDefensePoints: data['bonus_worst_defense_points'],
      bonusDisappointmentPoints: data['bonus_disappointment_points'],
      cpf: data['cpf'],               
      phone: data['phone'],           
      photoUrl: data['photo_url'],
    );
  }

  factory BolaoUser.fromFirestore(DocumentSnapshot doc, String defaultName) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return BolaoUser(
      userId: doc.id,
      name: data['name'] ?? defaultName,
      totalPoints: (data['total_points'] ?? 0).toInt(),
      exactHits: (data['exact_hits'] ?? 0).toInt(),
      goalDifferenceHits: (data['goal_difference_hits'] ?? 0).toInt(),
      winnerHits: (data['winner_hits'] ?? 0).toInt(),
      bonusPoints: (data['bonus_points'] ?? 0).toInt(),
      champion: data['bonus_champion'],
      runnerUp: data['bonus_runner_up'],
      bestOffense: data['bonus_best_offense'],
      worstDefense: data['bonus_worst_defense'],
      disappointment: data['bonus_disappointment'],
      bonusChampionPoints: data['bonus_champion_points'],
      bonusRunnerUpPoints: data['bonus_runner_up_points'],
      bonusBestOffensePoints: data['bonus_best_offense_points'],
      bonusWorstDefensePoints: data['bonus_worst_defense_points'],
      bonusDisappointmentPoints: data['bonus_disappointment_points'],
      cpf: data['cpf'],               
      phone: data['phone'],           
      photoUrl: data['photo_url'],    
    );
  }
}