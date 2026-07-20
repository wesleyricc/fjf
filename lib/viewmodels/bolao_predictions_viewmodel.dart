import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/bolao_service.dart';
import '../models/bolao_models.dart';

class BolaoPredictionsViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final BolaoService _bolaoService = BolaoService();

  Stream<DocumentSnapshot> streamSettings() {
    return _firestore.collection('bolao_config').doc('settings').snapshots();
  }

  Stream<BolaoUser?> streamBolaoUser(String userId) {
    return _bolaoService.streamBolaoUser(userId);
  }

  Future<List<BolaoMatch>> getMatches({bool forceRefresh = false}) {
    return _bolaoService.getMatches(forceRefresh: forceRefresh);
  }

  Future<List<BolaoPrediction>> getMyPredictions(String userId,
      {bool forceRefresh = false}) {
    return _bolaoService.getMyPredictions(userId, forceRefresh: forceRefresh);
  }

  void savePrediction(
      String userId, String matchId, int homeScore, int awayScore) {
    _bolaoService.savePrediction(userId, matchId, homeScore, awayScore);
  }

  Future<void> saveFullUserProfile(String userId, String name, String cpf,
      String phone, String? photoUrl) async {
    await _bolaoService.saveFullUserProfile(userId, name, cpf, phone, photoUrl);
  }
}
