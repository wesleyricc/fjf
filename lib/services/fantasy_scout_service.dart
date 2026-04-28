import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FantasyScoutDetail {
  final double totalScore;
  final int goals;
  final int assists;
  final int yellows;
  final int reds;
  final int goalsConceded;
  
  FantasyScoutDetail({
    required this.totalScore,
    this.goals = 0,
    this.assists = 0,
    this.yellows = 0,
    this.reds = 0,
    this.goalsConceded = 0,
  });

  bool get hasStats => (goals + assists + yellows + reds + goalsConceded) > 0;
}

class FantasyScoutService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🚀 OTIMIZAÇÃO FINOPS: O app agora apenas escuta o documento consolidado pelo Servidor
  Stream<Map<String, FantasyScoutDetail>> streamLiveScores(String seasonId, int round) {
    if (seasonId.isEmpty) return Stream.value({});

    return _firestore
        .collection('championships')
        .doc(seasonId)
        .collection('fantasy_live')
        .doc('round_$round')
        .snapshots()
        .map((snapshot) {
      
      if (!snapshot.exists || snapshot.data() == null) return {};

      final data = snapshot.data()!;
      final scoresMap = data['scores'] as Map<String, dynamic>? ?? {};

      final Map<String, FantasyScoutDetail> result = {};

      scoresMap.forEach((pid, pData) {
        final stats = pData as Map<String, dynamic>;
        result[pid] = FantasyScoutDetail(
          totalScore: (stats['totalScore'] ?? 0).toDouble(),
          goals: (stats['goals'] ?? 0).toInt(),
          assists: (stats['assists'] ?? 0).toInt(),
          yellows: (stats['yellows'] ?? 0).toInt(),
          reds: (stats['reds'] ?? 0).toInt(),
          goalsConceded: (stats['goals_conceded'] ?? 0).toInt(),
        );
      });

      return result;
    });
  }
}