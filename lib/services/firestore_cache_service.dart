import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirestoreCacheService {
  /// Obtém dados do Firestore usando uma estratégia híbrida baseada em TTL (Time to Live).
  /// Se [forceRefresh] for verdadeiro ou o TTL expirar, faz um fetch no servidor e renova o timestamp.
  /// Caso contrário, tenta recuperar exclusivamente do cache em disco/memória para economizar leituras (FinOps).
  static Future<QuerySnapshot> getWithCache({
    required Query query,
    required String cacheKey,
    required Duration ttl,
    bool forceRefresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final prefsKey = 'firestore_cache_timestamp_$cacheKey';
    final lastFetchMs = prefs.getInt(prefsKey);

    final now = DateTime.now();
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
      if (shouldFetchFromServer) {
        // Busca do servidor e do cache (padrão Firebase que salva no disco local)
        final snapshot = await query.get(const GetOptions(source: Source.serverAndCache));
        // Renova o timestamp após sucesso
        await prefs.setInt(prefsKey, now.millisecondsSinceEpoch);
        return snapshot;
      } else {
        // Tenta buscar ESTRITAMENTE do cache local para custo zero
        final snapshot = await query.get(const GetOptions(source: Source.cache));
        
        // Se o cache estiver completamente vazio (ex: app recém instalado), contorna buscando no servidor.
        if (snapshot.docs.isEmpty) {
          final fallbackSnap = await query.get(const GetOptions(source: Source.serverAndCache));
          await prefs.setInt(prefsKey, now.millisecondsSinceEpoch);
          return fallbackSnap;
        }
        
        return snapshot;
      }
    } catch (e) {
      // Se a chamada do servidor falhar por estar offline ou falha no cache
      // faz um fallback seguro buscando do cache, caso haja.
      print('FirestoreCacheService: Fallback para Cache após erro: $e');
      return await query.get(const GetOptions(source: Source.cache));
    }
  }

  /// Para uso quando buscamos apenas UM Documento (DocumentReference em vez de Query).
  static Future<DocumentSnapshot> getDocumentWithCache({
    required DocumentReference docRef,
    required String cacheKey,
    required Duration ttl,
    bool forceRefresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final prefsKey = 'firestore_cache_timestamp_$cacheKey';
    final lastFetchMs = prefs.getInt(prefsKey);

    final now = DateTime.now();
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
      if (shouldFetchFromServer) {
        final snapshot = await docRef.get(const GetOptions(source: Source.serverAndCache));
        await prefs.setInt(prefsKey, now.millisecondsSinceEpoch);
        return snapshot;
      } else {
        final snapshot = await docRef.get(const GetOptions(source: Source.cache));
        if (!snapshot.exists) {
          final fallbackSnap = await docRef.get(const GetOptions(source: Source.serverAndCache));
          await prefs.setInt(prefsKey, now.millisecondsSinceEpoch);
          return fallbackSnap;
        }
        return snapshot;
      }
    } catch (e) {
      print('FirestoreCacheService (Doc): Fallback para Cache após erro: $e');
      return await docRef.get(const GetOptions(source: Source.cache));
    }
  }

  /// Limpa o Timestamp de um cache específico, forçando a atualização na próxima leitura.
  static Future<void> invalidateCache(String cacheKey) async {
    final prefs = await SharedPreferences.getInstance();
    final prefsKey = 'firestore_cache_timestamp_$cacheKey';
    await prefs.remove(prefsKey);
  }
}
