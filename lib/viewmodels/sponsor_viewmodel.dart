import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../services/firestore_cache_service.dart';

class SponsorViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<Map<String, dynamic>> _sponsors = [];
  List<Map<String, dynamic>> get sponsors => _sponsors;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  final Set<String> _cachedDiskUrls = {};
  final Set<String> _precachedMemoryUrls = {};

  SponsorViewModel() {
    loadSponsors();
  }

  /// ⚡ FinOps PWA: Substitui listener .snapshots() permanente por leitura com cache persistente (TTL: 30 min),
  /// eliminando conexões WebSocket ociosas e leituras repetidas a cada reload do PWA.
  Future<void> loadSponsors({bool forceRefresh = false}) async {
    try {
      final query = _firestore
          .collection('sponsors')
          .where('isActive', isEqualTo: true)
          .orderBy('order');

      final docs = await FirestoreCacheService.getDocsDataWithCache(
        query: query,
        cacheKey: 'active_sponsors_list',
        ttl: const Duration(minutes: 30),
        forceRefresh: forceRefresh,
      );

      _sponsors = docs;
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();

      _warmupDiskCache();
    } catch (e) {
      debugPrint("Erro ao carregar patrocinadores: $e");
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Baixa as imagens dos patrocinadores para o cache de disco em background
  /// Sem decodificar em bitmap na RAM (100% seguro para memória no iOS)
  void _warmupDiskCache() {
    if (kIsWeb) return;
    for (final sponsor in _sponsors) {
      final url = (sponsor['imageUrl']?.toString() ?? '').trim();
      if (url.isNotEmpty && !_cachedDiskUrls.contains(url)) {
        _cachedDiskUrls.add(url);
        DefaultCacheManager().downloadFile(url).catchError((err) {
          debugPrint("Falha silenciosa ao pré-aquecer banner em disco: $err");
          return null as dynamic;
        });
      }
    }
  }

  /// Pré-carrega em memória (ImageCache) os banners prioritários com restrição
  /// de resolução (maxWidth: 600) para garantir abertura instantânea sem OOM no iOS Safari.
  void precachePriorityBanners(BuildContext context) {
    if (_sponsors.isEmpty) return;

    for (final sponsor in _sponsors.take(6)) {
      final url = ((sponsor['imageUrl'] ??
              sponsor['image_url'] ??
              sponsor['bannerUrl'] ??
              '')
          .toString())
          .trim();
      if (url.isNotEmpty && !_precachedMemoryUrls.contains(url)) {
        _precachedMemoryUrls.add(url);
        try {
          if (kIsWeb) {
            precacheImage(
              ResizeImage(NetworkImage(url), width: 600),
              context,
            ).catchError((_) {});
          } else {
            precacheImage(
              CachedNetworkImageProvider(url, maxWidth: 600),
              context,
            ).catchError((_) {});
          }
        } catch (_) {}
      }
    }
  }
}
