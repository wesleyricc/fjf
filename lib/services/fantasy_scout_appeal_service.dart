import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/fantasy_scout_appeal_model.dart';

class FantasyScoutAppealService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _appealsRef =>
      _firestore.collection('fantasy_scout_appeals');

  /// Envia uma nova solicitação de revisão de scout
  Future<String> submitAppeal(FantasyScoutAppeal appeal) async {
    try {
      final docRef = await _appealsRef.add(appeal.toMap());
      return docRef.id;
    } catch (e) {
      debugPrint("❌ Erro ao enviar solicitação de revisão: $e");
      rethrow;
    }
  }

  /// Escuta as solicitações feitas por um usuário específico
  Stream<List<FantasyScoutAppeal>> streamUserAppeals(String userId,
      {String? seasonId}) {
    Query query = _appealsRef.where('user_id', isEqualTo: userId);

    if (seasonId != null && seasonId.isNotEmpty) {
      query = query.where('season_id', isEqualTo: seasonId);
    }

    return query.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => FantasyScoutAppeal.fromFirestore(doc))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Escuta todas as solicitações (para painel de administração)
  Stream<List<FantasyScoutAppeal>> streamAllAppeals(
      {String? seasonId, String? statusFilter}) {
    Query query = _appealsRef;

    if (seasonId != null && seasonId.isNotEmpty) {
      query = query.where('season_id', isEqualTo: seasonId);
    }

    if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'all') {
      query = query.where('status', isEqualTo: statusFilter);
    }

    return query.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => FantasyScoutAppeal.fromFirestore(doc))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Escuta a contagem de contestações pendentes
  Stream<int> streamPendingCount({String? seasonId}) {
    Query query = _appealsRef.where('status', isEqualTo: 'pending');
    if (seasonId != null && seasonId.isNotEmpty) {
      query = query.where('season_id', isEqualTo: seasonId);
    }

    return query.snapshots().map((snapshot) => snapshot.docs.length);
  }

  /// Atualiza o parecer/julgamento de uma contestação
  Future<void> reviewAppeal({
    required String appealId,
    required String status,
    required String adminFeedback,
    required String reviewedBy,
  }) async {
    try {
      await _appealsRef.doc(appealId).update({
        'status': status,
        'admin_feedback': adminFeedback,
        'reviewed_by': reviewedBy,
        'reviewed_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("❌ Erro ao revisar solicitação: $e");
      rethrow;
    }
  }

  /// Exclui uma solicitação (se necessário)
  Future<void> deleteAppeal(String appealId) async {
    try {
      await _appealsRef.doc(appealId).delete();
    } catch (e) {
      debugPrint("❌ Erro ao excluir solicitação: $e");
      rethrow;
    }
  }
}
