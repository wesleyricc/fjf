import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MiniBolaoHomeViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  Stream<Map<String, dynamic>?> streamUser(String userId) {
    if (userId.isEmpty) return Stream.value(null);
    return _firestore
        .collection('mini_bolao_users')
        .doc(userId)
        .snapshots()
        .map((s) => s.data());
  }

  Future<void> saveUserProfile(String userId, String name, String cpf, String phone, String? photoUrl) async {
    _setLoading(true);
    try {
      final payload = {
        'name': name,
        'cpf': cpf,
        'phone': phone,
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (photoUrl != null) {
        payload['photo_url'] = photoUrl;
      }
      await _firestore.collection('mini_bolao_users').doc(userId).set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Erro ao salvar perfil: $e");
    } finally {
      _setLoading(false);
    }
  }

  Stream<QuerySnapshot> streamMiniLeagues() {
    return _firestore.collection('bolao_mini_leagues').orderBy('created_at', descending: true).snapshots();
  }

  Stream<DocumentSnapshot> streamPaymentOrder(String paymentId) {
    return _firestore.collection('orders').doc(paymentId).snapshots();
  }

  Future<QuerySnapshot> getLeagueParticipants(String leagueId) {
    return _firestore.collection('bolao_mini_leagues').doc(leagueId).collection('participants').get();
  }

  Future<DocumentSnapshot> getUser(String userId) {
    return _firestore.collection('mini_bolao_users').doc(userId).get();
  }
}
