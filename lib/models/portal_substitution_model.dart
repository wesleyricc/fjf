import 'package:cloud_firestore/cloud_firestore.dart';

class PlayerStint {
  final DateTime enteredAt;
  final DateTime? leftAt;
  final int durationSeconds;
  final int initialOffsetSeconds;
  final String? note;

  PlayerStint({
    required this.enteredAt,
    this.leftAt,
    required this.durationSeconds,
    this.initialOffsetSeconds = 0,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'entered_at': Timestamp.fromDate(enteredAt),
      'left_at': leftAt != null ? Timestamp.fromDate(leftAt!) : null,
      'duration_seconds': durationSeconds,
      'initial_offset_seconds': initialOffsetSeconds,
      'note': note,
    };
  }

  factory PlayerStint.fromMap(Map<String, dynamic> map) {
    return PlayerStint(
      enteredAt: (map['entered_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      leftAt: (map['left_at'] as Timestamp?)?.toDate(),
      durationSeconds: map['duration_seconds'] ?? 0,
      initialOffsetSeconds: map['initial_offset_seconds'] ?? 0,
      note: map['note'],
    );
  }
}

class PlayerSubstitutionState {
  final String playerId;
  final String playerName;
  final int? jerseyNumber;
  final String photoUrl;
  final String? position;
  final bool isGoalkeeper;
  final bool isOnCourt;
  final DateTime? currentEnteredAt;
  final int initialOffsetSeconds;
  final int maxContinuousSeconds;
  final int totalSecondsPlayed;
  final List<PlayerStint> stints;

  PlayerSubstitutionState({
    required this.playerId,
    required this.playerName,
    this.jerseyNumber,
    required this.photoUrl,
    this.position,
    this.isGoalkeeper = false,
    required this.isOnCourt,
    this.currentEnteredAt,
    this.initialOffsetSeconds = 0,
    this.maxContinuousSeconds = 0,
    this.totalSecondsPlayed = 0,
    List<PlayerStint>? stints,
  }) : stints = stints ?? [];

  /// Retorna o tempo da passagem ATUAL em segundos (se estiver em quadra)
  int getCurrentStintElapsedSeconds({DateTime? now}) {
    if (!isOnCourt || currentEnteredAt == null) return 0;
    final currentNow = now ?? DateTime.now();
    final diff = currentNow.difference(currentEnteredAt!).inSeconds;
    final elapsed = (diff > 0 ? diff : 0) + initialOffsetSeconds;
    return elapsed;
  }

  /// Maior tempo contínuo que o atleta já jogou nesta partida (incluindo a passagem atual se estiver em quadra)
  int getEffectiveContinuousSeconds({DateTime? now}) {
    final current = getCurrentStintElapsedSeconds(now: now);
    return current > maxContinuousSeconds ? current : maxContinuousSeconds;
  }

  /// Retorna o total de segundos jogados somando passagens anteriores e a atual
  int getEffectiveTotalSeconds({DateTime? now}) {
    final current = getCurrentStintElapsedSeconds(now: now);
    return totalSecondsPlayed + current;
  }

  /// Se o atleta cumpriu o regulamento obrigatório de 5 minutos contínuos (300 segundos)
  bool isRuleSatisfied({DateTime? now}) {
    return getEffectiveContinuousSeconds(now: now) >= 300;
  }

  /// Progresso rumo aos 5 minutos (0.0 a 1.0)
  double getProgressTowards5Min({DateTime? now}) {
    final continuous = getEffectiveContinuousSeconds(now: now);
    return (continuous / 300.0).clamp(0.0, 1.0);
  }

  PlayerSubstitutionState copyWith({
    String? playerId,
    String? playerName,
    int? jerseyNumber,
    String? photoUrl,
    String? position,
    bool? isGoalkeeper,
    bool? isOnCourt,
    DateTime? currentEnteredAt,
    int? initialOffsetSeconds,
    int? maxContinuousSeconds,
    int? totalSecondsPlayed,
    List<PlayerStint>? stints,
  }) {
    return PlayerSubstitutionState(
      playerId: playerId ?? this.playerId,
      playerName: playerName ?? this.playerName,
      jerseyNumber: jerseyNumber ?? this.jerseyNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      position: position ?? this.position,
      isGoalkeeper: isGoalkeeper ?? this.isGoalkeeper,
      isOnCourt: isOnCourt ?? this.isOnCourt,
      currentEnteredAt: currentEnteredAt ?? this.currentEnteredAt,
      initialOffsetSeconds: initialOffsetSeconds ?? this.initialOffsetSeconds,
      maxContinuousSeconds: maxContinuousSeconds ?? this.maxContinuousSeconds,
      totalSecondsPlayed: totalSecondsPlayed ?? this.totalSecondsPlayed,
      stints: stints ?? this.stints,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'player_id': playerId,
      'player_name': playerName,
      'jersey_number': jerseyNumber,
      'photo_url': photoUrl,
      'position': position,
      'is_goalkeeper': isGoalkeeper,
      'is_on_court': isOnCourt,
      'current_entered_at': currentEnteredAt != null ? Timestamp.fromDate(currentEnteredAt!) : null,
      'initial_offset_seconds': initialOffsetSeconds,
      'max_continuous_seconds': maxContinuousSeconds,
      'total_seconds_played': totalSecondsPlayed,
      'stints': stints.map((s) => s.toMap()).toList(),
    };
  }

  factory PlayerSubstitutionState.fromMap(Map<String, dynamic> map) {
    return PlayerSubstitutionState(
      playerId: map['player_id'] ?? '',
      playerName: map['player_name'] ?? '',
      jerseyNumber: map['jersey_number'],
      photoUrl: map['photo_url'] ?? '',
      position: map['position'],
      isGoalkeeper: map['is_goalkeeper'] ?? false,
      isOnCourt: map['is_on_court'] ?? false,
      currentEnteredAt: (map['current_entered_at'] as Timestamp?)?.toDate(),
      initialOffsetSeconds: map['initial_offset_seconds'] ?? 0,
      maxContinuousSeconds: map['max_continuous_seconds'] ?? 0,
      totalSecondsPlayed: map['total_seconds_played'] ?? 0,
      stints: (map['stints'] as List<dynamic>?)
              ?.map((s) => PlayerStint.fromMap(Map<String, dynamic>.from(s)))
              .toList() ??
          [],
    );
  }
}

class TeamSubstitutionSession {
  final String id;
  final String teamId;
  final String teamName;
  final String matchName;
  final DateTime startedAt;
  final DateTime updatedAt;
  final Map<String, PlayerSubstitutionState> playerStates;

  TeamSubstitutionSession({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.matchName,
    required this.startedAt,
    required this.updatedAt,
    required this.playerStates,
  });

  int get totalPlayers => playerStates.length;

  int get playersOnCourtCount =>
      playerStates.values.where((p) => p.isOnCourt).length;

  int get ruleSatisfiedCount {
    final now = DateTime.now();
    return playerStates.values.where((p) => p.isRuleSatisfied(now: now)).length;
  }

  int get pendingPlayersCount {
    final now = DateTime.now();
    return playerStates.values.where((p) => !p.isRuleSatisfied(now: now)).length;
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> statesMap = {};
    playerStates.forEach((key, value) {
      statesMap[key] = value.toMap();
    });

    return {
      'team_id': teamId,
      'team_name': teamName,
      'match_name': matchName,
      'started_at': Timestamp.fromDate(startedAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'player_states': statesMap,
    };
  }

  factory TeamSubstitutionSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawStates = data['player_states'] as Map<String, dynamic>? ?? {};

    final Map<String, PlayerSubstitutionState> states = {};
    rawStates.forEach((k, v) {
      states[k] = PlayerSubstitutionState.fromMap(Map<String, dynamic>.from(v));
    });

    return TeamSubstitutionSession(
      id: doc.id,
      teamId: data['team_id'] ?? doc.id,
      teamName: data['team_name'] ?? 'Equipe',
      matchName: data['match_name'] ?? 'Partida Atual',
      startedAt: (data['started_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      playerStates: states,
    );
  }
}
