import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NewsViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _news = [];
  bool _isLoading = false;

  List<Map<String, dynamic>> get news => _news;
  bool get isLoading => _isLoading;

  // 🚨 LAZY LOADING: Só faz a query se a lista estiver vazia ou for um force refresh
  Future<void> loadNews(String seasonId, {bool force = false}) async {
    if (seasonId.isEmpty) return;
    if (!force && _news.isNotEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('news')
          .where('isActive', isEqualTo: true)
          .orderBy('order', descending: true)
          .limit(10)
          .get();

      _news = snapshot.docs.map((d) => d.data()).toList();
    } catch (e) {
      debugPrint("Erro ao carregar notícias: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}