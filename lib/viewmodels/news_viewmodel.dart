import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_cache_service.dart';

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
      final query = _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('news')
          .where('isActive', isEqualTo: true)
          .orderBy('order', descending: true)
          .limit(10);
          
      final snapshot = await FirestoreCacheService.getWithCache(
        query: query,
        cacheKey: 'news_',
        ttl: const Duration(hours: 1),
        forceRefresh: force,
      );

      _news = snapshot.docs.map((d) => d.data() as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint("Erro ao carregar notícias: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}