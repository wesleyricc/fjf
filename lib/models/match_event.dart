enum MatchEventType { goal, yellowCard, redCard, assist }

class MatchEvent {
  final String id;
  final MatchEventType type;
  final String playerId;
  final String playerName;
  final String teamId;
  final int minute;
  final String period;
  final DateTime timestamp;
  
  // --- NOVO CAMPO ---
  final String? concededByPlayerId; // ID do goleiro que sofreu o gol
  // ------------------

  MatchEvent({
    required this.id,
    required this.type,
    required this.playerId,
    required this.playerName,
    required this.teamId,
    required this.minute,
    required this.period,
    required this.timestamp,
    this.concededByPlayerId, // Novo
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'playerId': playerId,
      'playerName': playerName,
      'teamId': teamId,
      'minute': minute,
      'period': period,
      'timestamp': timestamp,
      'concededByPlayerId': concededByPlayerId, // Novo
    };
  }

  factory MatchEvent.fromMap(String id, Map<String, dynamic> map) {
    return MatchEvent(
      id: id,
      type: MatchEventType.values.firstWhere((e) => e.name == map['type']),
      playerId: map['playerId'] ?? '',
      playerName: map['playerName'] ?? 'Desconhecido',
      teamId: map['teamId'] ?? '',
      minute: map['minute'] ?? 0,
      period: map['period'] ?? '1T',
      timestamp: (map['timestamp'] as dynamic)?.toDate() ?? DateTime.now(),
      concededByPlayerId: map['concededByPlayerId'], // Novo
    );
  }
}