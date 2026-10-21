import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryQueryCacheEntry {
  final QuerySnapshot snapshot;
  final DateTime expiresAt;

  _MemoryQueryCacheEntry(this.snapshot, this.expiresAt);
}

class _MemoryDocCacheEntry {
  final DocumentSnapshot snapshot;
  final DateTime expiresAt;

  _MemoryDocCacheEntry(this.snapshot, this.expiresAt);
}

class FirestoreCacheService {
  // ⚡ FinOps & Performance: Camada de cache em memória RAM (acesso imediato de 0ms, imune a limitações de disco do WebKit/iOS)
  static final Map<String, _MemoryQueryCacheEntry> _queryMemoryCache = {};
  static final Map<String, _MemoryDocCacheEntry> _docMemoryCache = {};

  /// Obtém dados do Firestore usando uma estratégia híbrida baseada em TTL (Time to Live).
  /// 1. Consulta RAM primeiro (0 ms).
  /// 2. Se expirado ou forceRefresh, busca do servidor/cache e renova RAM + SharedPreferences.
  static Future<QuerySnapshot> getWithCache({
    required Query query,
    required String cacheKey,
    required Duration ttl,
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();

    // ⚡ 1. Consulta em memória RAM
    if (!forceRefresh) {
      final mem = _queryMemoryCache[cacheKey];
      if (mem != null && now.isBefore(mem.expiresAt)) {
        return mem.snapshot;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final prefsKey = 'firestore_cache_timestamp_$cacheKey';
    final lastFetchMs = prefs.getInt(prefsKey);

    bool shouldFetchFromServer = forceRefresh;

    if (!shouldFetchFromServer) {
      if (lastFetchMs == null) {
        shouldFetchFromServer = true;
      } else {
        final lastFetchTime = DateTime.fromMillisecondsSinceEpoch(lastFetchMs);
        if (now.difference(lastFetchTime) > ttl) {
          shouldFetchFromServer = true;
        }
      }
    }

    try {
      final QuerySnapshot snapshot;
      if (shouldFetchFromServer) {
        snapshot = await query.get(const GetOptions(source: Source.serverAndCache));
        await prefs.setInt(prefsKey, now.millisecondsSinceEpoch);
      } else {
        // Tenta buscar do cache local (se persistência estiver ativa)
        final localSnap = await query.get(const GetOptions(source: Source.cache));
        if (localSnap.docs.isEmpty) {
          snapshot = await query.get(const GetOptions(source: Source.serverAndCache));
          await prefs.setInt(prefsKey, now.millisecondsSinceEpoch);
        } else {
          snapshot = localSnap;
        }
      }

      // Salva em memória RAM para os próximos acessos
      _queryMemoryCache[cacheKey] = _MemoryQueryCacheEntry(snapshot, now.add(ttl));
      return snapshot;
    } catch (e) {
      debugPrint('FirestoreCacheService: Fallback para Cache após erro: $e');
      final fallback = await query.get(const GetOptions(source: Source.cache));
      _queryMemoryCache[cacheKey] = _MemoryQueryCacheEntry(fallback, now.add(ttl));
      return fallback;
    }
  }

  /// Para uso quando buscamos apenas UM Documento (DocumentReference em vez de Query).
  static Future<DocumentSnapshot> getDocumentWithCache({
    required DocumentReference docRef,
    required String cacheKey,
    required Duration ttl,
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();

    // ⚡ 1. Consulta em memória RAM
    if (!forceRefresh) {
      final mem = _docMemoryCache[cacheKey];
      if (mem != null && now.isBefore(mem.expiresAt)) {
        return mem.snapshot;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final prefsKey = 'firestore_cache_timestamp_$cacheKey';
    final lastFetchMs = prefs.getInt(prefsKey);

    bool shouldFetchFromServer = forceRefresh;

    if (!shouldFetchFromServer) {
      if (lastFetchMs == null) {
        shouldFetchFromServer = true;
      } else {
        final lastFetchTime = DateTime.fromMillisecondsSinceEpoch(lastFetchMs);
        if (now.difference(lastFetchTime) > ttl) {
          shouldFetchFromServer = true;
        }
      }
    }

    try {
      final DocumentSnapshot snapshot;
      if (shouldFetchFromServer) {
        snapshot = await docRef.get(const GetOptions(source: Source.serverAndCache));
        await prefs.setInt(prefsKey, now.millisecondsSinceEpoch);
      } else {
        final localSnap = await docRef.get(const GetOptions(source: Source.cache));
        if (!localSnap.exists) {
          snapshot = await docRef.get(const GetOptions(source: Source.serverAndCache));
          await prefs.setInt(prefsKey, now.millisecondsSinceEpoch);
        } else {
          snapshot = localSnap;
        }
      }

      // Salva em memória RAM para os próximos acessos
      _docMemoryCache[cacheKey] = _MemoryDocCacheEntry(snapshot, now.add(ttl));
      return snapshot;
    } catch (e) {
      debugPrint('FirestoreCacheService (Doc): Fallback para Cache após erro: $e');
      final fallback = await docRef.get(const GetOptions(source: Source.cache));
      _docMemoryCache[cacheKey] = _MemoryDocCacheEntry(fallback, now.add(ttl));
      return fallback;
    }
  }

  /// Limpa o Timestamp e a memória de um cache específico.
  static Future<void> invalidateCache(String cacheKey) async {
    _queryMemoryCache.remove(cacheKey);
    _docMemoryCache.remove(cacheKey);
    final prefs = await SharedPreferences.getInstance();
    final prefsKey = 'firestore_cache_timestamp_$cacheKey';
    await prefs.remove(prefsKey);
  }

  /// Limpa todo o cache em memória RAM da sessão.
  static void clearMemoryCache() {
    _queryMemoryCache.clear();
    _docMemoryCache.clear();
  }
}
