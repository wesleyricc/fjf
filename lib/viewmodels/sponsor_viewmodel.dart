import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();

      _warmupDiskCache();
    }, onError: (e) {
      debugPrint("Erro ao carregar patrocinadores: $e");
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();
    });
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
  /// de resolução (maxWidth: 800) para garantir abertura instantânea sem OOM no iOS.
  void precachePriorityBanners(BuildContext context) {
    if (_sponsors.isEmpty) return;

    for (final sponsor in _sponsors.take(8)) {
      final url = (sponsor['imageUrl']?.toString() ?? '').trim();
      if (url.isNotEmpty && !_precachedMemoryUrls.contains(url)) {
        _precachedMemoryUrls.add(url);
        try {
          precacheImage(
            CachedNetworkImageProvider(url, maxWidth: 800),
            context,
          );
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}