import 'package:cloud_firestore/cloud_firestore.dart';

class DisciplinaryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference _getDisciplinaryLogRef(String seasonId) {
    return _firestore.collection('championships').doc(seasonId).collection('disciplinary_log');
  }

  // --- Métodos Transacionais (Usados pelo MatchService) ---

  void recordDisciplinaryLog(
    Transaction transaction,
    String seasonId,
    String matchId,
    String playerId,
    Map<String, dynamic> playerData,
    String matchLabel,
    String reason,
  ) {
    // ID único (por partida/jogador) evita duplicidade
    final logRef = _getDisciplinaryLogRef(seasonId).doc("${matchId}_$playerId");

    final logData = {
      'playerId': playerId,
      'playerName': playerData['name'] ?? 'Desconhecido',
      'teamId': playerData['team_id'] ?? '',
      'teamName': playerData['team_name'] ?? '',
      'teamLogoUrl': playerData['team_shield_url'] ?? '',
      'playerPhotoUrl': playerData['photo_url'] ?? '',
      'is_staff': playerData['is_staff'] ?? false,
      'matchId_occurred': matchId,
      'match_description': matchLabel,
      'reason': reason,
      'timestamp': FieldValue.serverTimestamp(),
      'return_date': null,
    };

    transaction.set(logRef, logData);
  }

  void removeDisciplinaryLog(
    Transaction transaction,
    String seasonId,
    String matchId,
    String playerId,
  ) {
    final logRef = _getDisciplinaryLogRef(seasonId).doc("${matchId}_$playerId");
    transaction.delete(logRef);
  }
}