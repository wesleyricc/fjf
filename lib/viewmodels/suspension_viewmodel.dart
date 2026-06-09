import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SuspensionViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<DocumentSnapshot> _suspensions = [];
  bool _isLoading = false;

  List<DocumentSnapshot> get suspensions => _suspensions;
  bool get isLoading => _isLoading;

  // 🚨 LAZY LOADING: Poupa centenas de leituras no Splash Screen global
  Future<void> loadSuspensions(String seasonId, {bool force = false}) async {
    if (seasonId.isEmpty) return;
    if (!force && _suspensions.isNotEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('disciplinary_log')
          .orderBy('timestamp', descending: true)
          .get();

      _suspensions = snapshot.docs;
    } catch (e) {
      debugPrint("Erro ao carregar suspensões: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}