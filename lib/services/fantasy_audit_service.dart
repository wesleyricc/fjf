import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/fantasy_audit_models.dart';

class FantasyAuditService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  CollectionReference get _auditRef => _firestore.collection('fantasy_audit');

  /// Executa a rotina isolada de auditoria na nuvem via Cloud Function
  Future<String?> runAudit({
    required String seasonId,
    required int round,
    bool includeTeams = true,
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('auditFantasyRound');
      final result = await callable.call(<String, dynamic>{
        'seasonId': seasonId,
        'round': round,
        'includeTeams': includeTeams,
      });

      final data = result.data as Map<dynamic, dynamic>? ?? {};
      if (data['success'] == true) {
        return null; // Sucesso sem erro
      }
      return data['message'] ?? 'Falha ao executar auditoria.';
    } catch (e) {
      debugPrint("Erro ao chamar auditFantasyRound: $e");
      if (e is FirebaseFunctionsException) {
        return "Erro Cloud (${e.code}): ${e.message}";
      }
      return "Erro na execução da auditoria: $e";
    }
  }

  /// Sincroniza os scouts ao vivo com base na auditoria oficial (corrige divergências como MOTM)
  Future<String?> syncAuditToLive({
    required String seasonId,
    required int round,
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('syncAuditToLive');
      final result = await callable.call(<String, dynamic>{
        'seasonId': seasonId,
        'round': round,
      });

      final data = result.data as Map<dynamic, dynamic>? ?? {};
      if (data['success'] == true) {
        return null; // Sucesso sem erro
      }
      return data['message'] ?? 'Falha ao sincronizar scouts.';
    } catch (e) {
      debugPrint("Erro ao chamar syncAuditToLive: $e");
      if (e is FirebaseFunctionsException) {
        return "Erro Cloud (${e.code}): ${e.message}";
      }
      return "Erro na sincronização: $e";
    }
  }

  /// Escuta o documento resumo de auditoria de uma rodada
  Stream<FantasyAuditSummary?> streamAuditSummary(String seasonId, int round) {
    final docId = "${seasonId}_r$round";
    return _auditRef.doc(docId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return FantasyAuditSummary.fromFirestore(doc);
    });
  }

  /// Busca o resumo de auditoria de uma rodada
  Future<FantasyAuditSummary?> getAuditSummary(String seasonId, int round) async {
    try {
      final docId = "${seasonId}_r$round";
      final doc = await _auditRef.doc(docId).get();
      if (!doc.exists) return null;
      return FantasyAuditSummary.fromFirestore(doc);
    } catch (e) {
      debugPrint("Erro ao buscar resumo de auditoria: $e");
      return null;
    }
  }

  /// Busca os jogadores auditados
  Future<List<FantasyAuditPlayer>> getAuditedPlayers(String seasonId, int round) async {
    try {
      final docId = "${seasonId}_r$round";
      final snap = await _auditRef.doc(docId).collection('players').get();
      return snap.docs.map((d) => FantasyAuditPlayer.fromFirestore(d)).toList();
    } catch (e) {
      debugPrint("Erro ao buscar jogadores da auditoria: $e");
      return [];
    }
  }

  /// Busca as partidas auditadas
  Future<List<FantasyAuditMatch>> getAuditedMatches(String seasonId, int round) async {
    try {
      final docId = "${seasonId}_r$round";
      final snap = await _auditRef.doc(docId).collection('matches').get();
      return snap.docs.map((d) => FantasyAuditMatch.fromFirestore(d)).toList();
    } catch (e) {
      debugPrint("Erro ao buscar partidas da auditoria: $e");
      return [];
    }
  }

  /// Busca os times dos usuários auditados
  Future<List<FantasyAuditTeam>> getAuditedTeams(String seasonId, int round) async {
    try {
      final docId = "${seasonId}_r$round";
      final snap = await _auditRef.doc(docId).collection('teams').get();
      return snap.docs.map((d) => FantasyAuditTeam.fromFirestore(d)).toList();
    } catch (e) {
      debugPrint("Erro ao buscar times da auditoria: $e");
      return [];
    }
  }

  /// Lista relatórios de auditoria históricos
  Stream<List<FantasyAuditSummary>> streamAllAudits(String seasonId) {
    return _auditRef
        .where('season_id', isEqualTo: seasonId)
        .orderBy('round', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => FantasyAuditSummary.fromFirestore(d)).toList());
  }
}
