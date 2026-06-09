import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SponsorViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<Map<String, dynamic>> _sponsors = [];
  List<Map<String, dynamic>> get sponsors => _sponsors;

  StreamSubscription? _sub;

  SponsorViewModel() {
    _listenSponsors();
  }

  void _listenSponsors() {
    _sub = _firestore
        .collection('sponsors')
        .where('isActive', isEqualTo: true)
        .orderBy('order')
        .snapshots()
        .listen((snapshot) {
      _sponsors = snapshot.docs.map((d) => d.data()).toList();
      notifyListeners();
    }, onError: (e) {
      debugPrint("Erro ao carregar patrocinadores: $e");
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}