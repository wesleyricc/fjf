import 'dart:convert';
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

class _MemoryDocsDataCacheEntry {
  final List<Map<String, dynamic>> docs;
  final DateTime expiresAt;

  _MemoryDocsDataCacheEntry(this.docs, this.expiresAt);
}

class _MemoryDocDataCacheEntry {
  final Map<String, dynamic>? data;
  final DateTime expiresAt;

  _MemoryDocDataCacheEntry(this.data, this.expiresAt);
}

class FirestoreCacheService {
  // ⚡ FinOps & Performance: Camada de cache em memória RAM (acesso imediato de 0ms, imune a limitações de disco do WebKit/iOS)
  static final Map<String, _MemoryQueryCacheEntry> _queryMemoryCache = {};
  static final Map<String, _MemoryDocCacheEntry> _docMemoryCache = {};
  static final Map<String, _MemoryDocsDataCacheEntry> _docsDataMemoryCache = {};
  static final Map<String, _MemoryDocDataCacheEntry> _docDataMemoryCache = {};

  /// Serializa estruturas do Firestore (incluindo Timestamp) para JSON seguro no localStorage (Web PWA).
  static dynamic _encodeFirestoreValue(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Timestamp) {
      return {'__fs_ts__': value.millisecondsSinceEpoch};
    }
    if (value is DateTime) {
      return {'__fs_ts__': value.millisecondsSinceEpoch};
    }
    if (value is List) {
      return value.map(_encodeFirestoreValue).toList();
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _encodeFirestoreValue(v)));
    }
    return value.toString();
  }

  /// Desserializa estruturas do JSON de volta para tipos nativos do Firestore (ex: Timestamp).
  static dynamic _decodeFirestoreValue(dynamic value) {
    if (value is List) {
      return value.map(_decodeFirestoreValue).toList();
    }
    if (value is Map) {
      if (value.length == 1 && value.containsKey('__fs_ts__')) {
        final ms = value['__fs_ts__'];
        if (ms is int) {
          return Timestamp.fromMillisecondsSinceEpoch(ms);
        }
      }
      return value.map<String, dynamic>(
        (k, v) => MapEntry(k.toString(), _decodeFirestoreValue(v)),
      );
    }
    return value;
  }

  /// ⚡ FinOps PWA: Obtém uma lista de documentos (cada item contém '_docId' + campos) com persistência
  /// real em SharedPreferences (localStorage no Web), evitando leituras no Firestore ao dar F5 ou reabrir o PWA.
  static Future<List<Map<String, dynamic>>> getDocsDataWithCache({
    required Query query,
    required String cacheKey,
    required Duration ttl,
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();

    // 1. Consulta em memória RAM (0 ms)
    if (!forceRefresh) {
      final mem = _docsDataMemoryCache[cacheKey];
      if (mem != null && now.isBefore(mem.expiresAt)) {
        return mem.docs;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final tsKey = 'firestore_cache_timestamp_$cacheKey';
    final payloadKey = 'firestore_cache_payload_$cacheKey';
    final lastFetchMs = prefs.getInt(tsKey);

    final bool isTtlValid = !forceRefresh &&
        lastFetchMs != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastFetchMs)) <= ttl;

    // 2. Se o TTL for válido, tenta recuperar do SharedPreferences (funciona 100% no Web PWA mesmo com persistenceEnabled: false)
    if (isTtlValid) {
      final rawJson = prefs.getString(payloadKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawJson) as List<dynamic>;
          final docs = decoded
              .map((item) => Map<String, dynamic>.from(_decodeFirestoreValue(item) as Map))
              .toList();
          final remainingTtl = ttl - now.difference(DateTime.fromMillisecondsSinceEpoch(lastFetchMs));
          _docsDataMemoryCache[cacheKey] = _MemoryDocsDataCacheEntry(
            docs,
            now.add(remainingTtl.isNegative ? Duration.zero : remainingTtl),
          );
          return docs;
        } catch (_) {
          // Se falhar o parse do cache local, segue para busca no Firestore
        }
      }
    }

    // 3. Busca via getWithCache (que aproveita Source.cache no mobile ou busca no servidor)
    final snapshot = await getWithCache(
      query: query,
      cacheKey: cacheKey,
      ttl: ttl,
      forceRefresh: forceRefresh,
    );

    final docs = snapshot.docs.map((doc) {
      final map = Map<String, dynamic>.from((doc.data() as Map<String, dynamic>?) ?? {});
      map['_docId'] = doc.id;
      return map;
    }).toList();

    _docsDataMemoryCache[cacheKey] = _MemoryDocsDataCacheEntry(docs, now.add(ttl));

    // Salva payload JSON compactado no localStorage / SharedPreferences (protegido contra limite de cota do Safari)
    try {
      final encoded = jsonEncode(_encodeFirestoreValue(docs));
      if (encoded.length < 450000) {
        await prefs.setString(payloadKey, encoded);
        await prefs.setInt(tsKey, now.millisecondsSinceEpoch);
      }
    } catch (_) {}

    return docs;
  }

  /// ⚡ FinOps PWA: Obtém os dados de um único documento com persistência real em SharedPreferences (localStorage no Web).
  static Future<Map<String, dynamic>?> getDocDataWithCache({
    required DocumentReference docRef,
    required String cacheKey,
    required Duration ttl,
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();

    // 1. Consulta em memória RAM (0 ms)
    if (!forceRefresh) {
      final mem = _docDataMemoryCache[cacheKey];
      if (mem != null && now.isBefore(mem.expiresAt)) {
        return mem.data;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final tsKey = 'firestore_cache_timestamp_$cacheKey';
    final payloadKey = 'firestore_cache_payload_$cacheKey';
    final lastFetchMs = prefs.getInt(tsKey);

    final bool isTtlValid = !forceRefresh &&
        lastFetchMs != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastFetchMs)) <= ttl;

    if (isTtlValid) {
      final rawJson = prefs.getString(payloadKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        try {
          final decoded = _decodeFirestoreValue(jsonDecode(rawJson));
          if (decoded is Map) {
            final data = Map<String, dynamic>.from(decoded);
            final remainingTtl = ttl - now.difference(DateTime.fromMillisecondsSinceEpoch(lastFetchMs));
            _docDataMemoryCache[cacheKey] = _MemoryDocDataCacheEntry(
              data,
              now.add(remainingTtl.isNegative ? Duration.zero : remainingTtl),
            );
            return data;
          }
        } catch (_) {}
      }
    }

    final doc = await getDocumentWithCache(
      docRef: docRef,
      cacheKey: cacheKey,
      ttl: ttl,
      forceRefresh: forceRefresh,
    );

    if (!doc.exists || doc.data() == null) {
      return null;
    }

    final data = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
    data['_docId'] = doc.id;
    _docDataMemoryCache[cacheKey] = _MemoryDocDataCacheEntry(data, now.add(ttl));

    try {
      final encoded = jsonEncode(_encodeFirestoreValue(data));
      if (encoded.length < 250000) {
        await prefs.setString(payloadKey, encoded);
        await prefs.setInt(tsKey, now.millisecondsSinceEpoch);
      }
    } catch (_) {}

    return data;
  }

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

    QuerySnapshot? snapshot;

    // Se estiver no Web/iOS PWA, Source.cache não é suportado porque persistenceEnabled é false
    if (!kIsWeb && !shouldFetchFromServer) {
      try {
        final localSnap = await query.get(const GetOptions(source: Source.cache));
        if (localSnap.docs.isNotEmpty) {
          snapshot = localSnap;
        }
      } catch (_) {
        // Cache em disco indisponível ou ainda não sincronizado -> buscará do servidor
      }
    }

    // Se não encontrou no cache local ou se precisava buscar do servidor
    if (snapshot == null) {
      try {
        snapshot = await query.get(const GetOptions(source: Source.serverAndCache));
        await prefs.setInt(prefsKey, now.millisecondsSinceEpoch);
      } catch (e) {
        // Se a chamada de rede falhar (ex: modo offline), tenta o cache local como último recurso (no Mobile)
        if (!kIsWeb) {
          try {
            snapshot = await query.get(const GetOptions(source: Source.cache));
          } catch (_) {
            rethrow;
          }
        } else {
          rethrow;
        }
      }
    }

    // Salva em memória RAM para os próximos acessos
    _queryMemoryCache[cacheKey] = _MemoryQueryCacheEntry(snapshot, now.add(ttl));
    return snapshot;
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

    DocumentSnapshot? snapshot;

    // Se estiver no Web/iOS PWA, Source.cache não é suportado porque persistenceEnabled é false
    if (!kIsWeb && !shouldFetchFromServer) {
      try {
        final localSnap = await docRef.get(const GetOptions(source: Source.cache));
        if (localSnap.exists) {
          snapshot = localSnap;
        }
      } catch (_) {
        // Cache em disco indisponível ou ainda não sincronizado -> buscará do servidor
      }
    }

    // Se não encontrou no cache local ou se precisava buscar do servidor
    if (snapshot == null) {
      try {
        snapshot = await docRef.get(const GetOptions(source: Source.serverAndCache));
        await prefs.setInt(prefsKey, now.millisecondsSinceEpoch);
      } catch (e) {
        // Se a chamada de rede falhar (ex: modo offline), tenta o cache local como último recurso (no Mobile)
        if (!kIsWeb) {
          try {
            snapshot = await docRef.get(const GetOptions(source: Source.cache));
          } catch (_) {
            rethrow;
          }
        } else {
          rethrow;
        }
      }
    }

    // Salva em memória RAM para os próximos acessos
    _docMemoryCache[cacheKey] = _MemoryDocCacheEntry(snapshot, now.add(ttl));
    return snapshot;
  }

  /// Limpa o Timestamp e a memória de um cache específico.
  static Future<void> invalidateCache(String cacheKey) async {
    _queryMemoryCache.remove(cacheKey);
    _docMemoryCache.remove(cacheKey);
    _docsDataMemoryCache.remove(cacheKey);
    _docDataMemoryCache.remove(cacheKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('firestore_cache_timestamp_$cacheKey');
    await prefs.remove('firestore_cache_payload_$cacheKey');
  }

  /// Limpa todo o cache em memória RAM da sessão.
  static void clearMemoryCache() {
    _queryMemoryCache.clear();
    _docMemoryCache.clear();
    _docsDataMemoryCache.clear();
    _docDataMemoryCache.clear();
  }
}
