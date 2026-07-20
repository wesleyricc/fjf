import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/bolao_seed_data.dart'; // Assumindo que este existe

class BolaoAdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ---------------------------------------------------------
  // CONFIGURAÇÕES GLOBAIS DO BOLÃO
  // ---------------------------------------------------------

  Future<bool> getPredictionsStatus() async {
    final doc = await _firestore.collection('bolao_config').doc('settings').get();
    if (doc.exists && doc.data()!['is_predictions_open'] != null) {
      return doc.data()!['is_predictions_open'] as bool;
    }
    return false;
  }

  Future<void> togglePredictionsStatus(bool isOpen) async {
    await _firestore.collection('bolao_config').doc('settings').set({
      'is_predictions_open': isOpen,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---------------------------------------------------------
  // GERENCIAMENTO DE PARTIDAS
  // ---------------------------------------------------------

  Future<void> seedMatches() async {
    final batch = _firestore.batch();
    for (var matchMap in bolaoSeedMatches) {
      final docRef = _firestore.collection('bolao_matches').doc(matchMap['id']);
      final matchDate = DateTime.parse(matchMap['date']);
      final data = Map<String, dynamic>.from(matchMap);
      data['date'] = Timestamp.fromDate(matchDate); 
      batch.set(docRef, data, SetOptions(merge: true)); 
    }
    await batch.commit();
  }

  Future<void> updateMatchScore(String matchId, int homeScore, int awayScore, String matchStatus, {bool extraTime = false, bool penalties = false}) async {
    await _firestore.collection('bolao_matches').doc(matchId).update({
      'score_home': homeScore,
      'score_away': awayScore,
      'status': matchStatus,
      'extra_time': extraTime,
      'penalties': penalties,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> streamMatches() {
    return _firestore.collection('bolao_matches').orderBy('date').snapshots();
  }

  // ---------------------------------------------------------
  // MINI LIGAS
  // ---------------------------------------------------------

  Stream<QuerySnapshot> streamMiniLeagues() {
    return _firestore.collection('bolao_mini_leagues').orderBy('created_at', descending: true).snapshots();
  }

  Future<void> createMiniLeague(Map<String, dynamic> data) async {
    await _firestore.collection('bolao_mini_leagues').add(data);
  }

  Future<void> updateMiniLeague(String id, Map<String, dynamic> data) async {
    await _firestore.collection('bolao_mini_leagues').doc(id).update(data);
  }

  Future<void> deleteMiniLeague(String id) async {
    await _firestore.collection('bolao_mini_leagues').doc(id).delete();
  }

  Future<void> toggleMiniLeagueStatus(String id, bool isActive) async {
    await _firestore.collection('bolao_mini_leagues').doc(id).update({'is_active': isActive});
  }
}
