import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class MigrationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- MIGRAR REFERÊNCIAS DE STORAGE (URLS) ---
  Future<String> migrateStorageUrls(String seasonId) async {
    WriteBatch batch = _firestore.batch();
    int count = 0;

    debugPrint("🚀 [STORAGE MIGRAÇÃO] Iniciando conversão de URLs com Tokens...");

    // Função interna auxiliar para processar documentos
    Future<int> processDocs(Query query, List<String> fields, int currentCount, WriteBatch currentBatch) async {
      final snap = await query.get();
      int localCount = currentCount;
      WriteBatch localBatch = currentBatch;

      for (var doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        bool changed = false;
        Map<String, dynamic> updates = {};

        for (String field in fields) {
          final String? valorAtual = data[field]?.toString();
          
          if (valorAtual != null && valorAtual.isNotEmpty) {
            // Verifica se é uma URL antiga que precisa ser migrada e limpa
            if (valorAtual.contains('fjfapp.firebasestorage.app') || 
                valorAtual.contains('acefjf.firebasestorage.app') ||
                valorAtual.contains('firebasestorage.googleapis.com')) {
              
              String novaUrl = _atualizarUrlStorage(valorAtual);
              
              if (novaUrl != valorAtual) {
                updates[field] = novaUrl;
                changed = true;
              }
            }
          }
        }

        if (changed) {
          localBatch.update(doc.reference, updates);
          localCount++;
          
          // Comita a cada 450 para não estourar o limite do Firestore
          if (localCount >= 450) {
            await localBatch.commit();
            localBatch = _firestore.batch();
            localCount = 0;
            debugPrint("♻️ Batch intermediário comitado.");
          }
        }
      }
      return localCount; // Retorna o contador residual
    }

    try {
      // 1. Coleções Globais
      count = await processDocs(_firestore.collection('teams_directory'), ['shield_url'], count, batch);
      count = await processDocs(_firestore.collection('players'), ['photo_url', 'team_shield_url'], count, batch);
      count = await processDocs(_firestore.collection('photo_albums'), ['coverUrl'], count, batch);
      count = await processDocs(_firestore.collection('photo_sales'), ['original_url', 'preview_url'], count, batch);
      count = await processDocs(_firestore.collection('fantasy_teams'), ['custom_logo_url'], count, batch);
      count = await processDocs(_firestore.collection('fantasy_market_players'), ['team_shield_url', 'photo_url'], count, batch);
      count = await processDocs(_firestore.collection('sponsors'), ['imageUrl', 'targetUrl'], count, batch);

      // 2. Coleções da Temporada
      final seasonRef = _firestore.collection('championships').doc(seasonId);
      count = await processDocs(seasonRef.collection('teams_participation'), ['shield_url'], count, batch);
      count = await processDocs(seasonRef.collection('player_stats'), ['photo_url', 'team_shield_url'], count, batch);
      count = await processDocs(seasonRef.collection('news'), ['imageUrl'], count, batch);
      count = await processDocs(seasonRef.collection('matches'), ['team_home_shield', 'team_away_shield', 'sumula_url'], count, batch);
      count = await processDocs(seasonRef.collection('disciplinary_log'), ['teamLogoUrl', 'playerPhotoUrl'], count, batch);
      count = await processDocs(seasonRef.collection('settings'), ['regulation_pdf_url'], count, batch);

      // Comita o restante do batch que ficou na memória
      await batch.commit();
      return "Sucesso: URLs do Storage migradas e convertidas para formato público.";
    } catch (e) {
      return "Erro na migração: $e";
    }
  }

  // --- MIGRAÇÃO DE BANCO LEGADO (MANTIDO INTACTO) ---
  Future<String> migrateLegacyTo2025() async {
    try {
      const String newSeasonId = '2025_fjf';
      debugPrint("🚀 [MIGRAÇÃO] Iniciando processo para $newSeasonId...");

      // 1. Criar Temporada se não existir
      final seasonRef = _firestore.collection('championships').doc(newSeasonId);
      final seasonDoc = await seasonRef.get();
      
      if (!seasonDoc.exists) {
        await seasonRef.set({
          'year': 2025,
          'name': 'FJF 2025',
          'honoree': 'Taça Mary Neusa Espíndola Bif',
          'is_active': true,
          'status': 'open',
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      WriteBatch batch = _firestore.batch();
      int batchCount = 0;

      // Helper para comitar se o batch encher (Limite do Firestore é 500 operações por Batch)
      Future<void> commitIfNeeded() async {
        if (batchCount >= 400) {
          await batch.commit();
          batch = _firestore.batch();
          batchCount = 0;
          debugPrint("♻️ [MIGRAÇÃO] Batch intermediário processado.");
        }
      }

      // --- PASSO 0: CACHE DE JOGADORES ---
      debugPrint("⏳ [MIGRAÇÃO] Pré-carregando cache de jogadores...");
      final allPlayersSnap = await _firestore.collection('players').get();
      final Map<String, Map<String, dynamic>> playerCache = {};
      for (var doc in allPlayersSnap.docs) {
        playerCache[doc.id] = doc.data();
      }

      // --- ETAPA 1: TIMES (Global + Temporada) ---
      debugPrint("⏳ [MIGRAÇÃO] 1/6 - Times...");
      final legacyTeams = await _firestore.collection('teams').get();
      
      for (var doc in legacyTeams.docs) {
        final data = doc.data();
        
        final dirRef = _firestore.collection('teams_directory').doc(doc.id);
        batch.set(dirRef, {
          'name': data['name'] ?? 'Time Desconhecido',
          'short_name': data['short_name'] ?? '',
          'shield_url': data['shield_url'] ?? '',
          'championship_history': data['championship_history'] ?? [],
        });
        batchCount++;

        final partRef = seasonRef.collection('teams_participation').doc(doc.id);
        
        // 🚨 NOVO: LIMPEZA DE DESTINO (Apaga histórico de punições/bônus de testes anteriores)
        final destExtraPoints = await partRef.collection('extra_points_log').get();
        for (var lixoDoc in destExtraPoints.docs) {
          batch.delete(lixoDoc.reference);
          batchCount++;
        }

        // Salva os dados do time
        batch.set(partRef, data);
        batchCount++;

        // Migra o log original da raiz
        final legacyLogs = await doc.reference.collection('extra_points_log').get();
        for (var logDoc in legacyLogs.docs) {
           final newLogRef = partRef.collection('extra_points_log').doc(logDoc.id);
           batch.set(newLogRef, logDoc.data());
           batch.delete(logDoc.reference); 
           batchCount += 2;
           await commitIfNeeded();
        }

        batch.delete(doc.reference);
        batchCount++;
        await commitIfNeeded();
      }

      // --- ETAPA 2: JOGOS + GERAÇÃO DE TIMELINE ---
      debugPrint("⏳ [MIGRAÇÃO] 2/6 - Jogos e Geração de Timeline...");
      final legacyMatches = await _firestore.collection('matches').get();
      
      for (var doc in legacyMatches.docs) {
        final matchData = doc.data();
        final newMatchRef = seasonRef.collection('matches').doc(doc.id);
        
        // 🚨 NOVO: LIMPEZA DE DESTINO (Mata os fantasmas de migrações anteriores)
        final destinationTimeline = await newMatchRef.collection('timeline').get();
        for (var lixoDoc in destinationTimeline.docs) {
          batch.delete(lixoDoc.reference);
          batchCount++;
        }

        // Salva os metadados do jogo
        batch.set(newMatchRef, matchData);
        batchCount++;

        // 1. Buscamos a timeline antiga PRIMEIRO na raiz
        final legacyTimeline = await doc.reference.collection('timeline').get();

        // 2. Se a partida JÁ TEM eventos na timeline, apenas copiamos (EVITA DUPLICAR)
        if (legacyTimeline.docs.isNotEmpty) {
          for (var eventDoc in legacyTimeline.docs) {
            final newEventRef = newMatchRef.collection('timeline').doc(eventDoc.id);
            batch.set(newEventRef, eventDoc.data());
            batch.delete(eventDoc.reference); // Limpa da raiz
            batchCount += 2;
          }
        } 
        // 3. Se a partida NÃO TEM timeline (jogos bem antigos), criamos uma sintética do pStats
        else if (matchData.containsKey('stats_applied') && matchData['stats_applied']?['player_stats'] != null) {
          final pStats = matchData['stats_applied']['player_stats'];
          
          void generateEvents(Map<String, dynamic>? sourceMap, String eventType) {
            if (sourceMap == null) return;
            
            sourceMap.forEach((playerId, count) {
              final int qtd = (count is int) ? count : 0;
              if (qtd <= 0) return;

              final pData = playerCache[playerId];
              final String pName = pData?['name'] ?? 'Desconhecido';
              final String pTeamId = pData?['team_id'] ?? '';

              for (int i = 0; i < qtd; i++) {
                final eventRef = newMatchRef.collection('timeline').doc(); 
                
                batch.set(eventRef, {
                  'type': eventType, 
                  'playerId': playerId,
                  'playerName': pName,
                  'teamId': pTeamId,
                  'minute': 0, 
                  'period': '1T',
                  'timestamp': matchData['datetime'] ?? FieldValue.serverTimestamp(), 
                  'concededByPlayerId': null 
                });
                batchCount++;
              }
            });
          }

          generateEvents(pStats['goals'] as Map<String, dynamic>?, 'goal');
          generateEvents(pStats['yellows'] as Map<String, dynamic>?, 'yellowCard');
          generateEvents(pStats['reds'] as Map<String, dynamic>?, 'redCard');
        }

        // Apaga o jogo antigo da raiz
        batch.delete(doc.reference);
        batchCount++;
        await commitIfNeeded();
      }

      // --- ETAPA 3: SUSPENSÕES ---
      debugPrint("⏳ [MIGRAÇÃO] 3/6 - Histórico Disciplinar...");
      final legacySuspension = await _firestore.collection('suspension_log').get();
      for (var doc in legacySuspension.docs) {
        final newLogRef = seasonRef.collection('disciplinary_log').doc(doc.id);
        batch.set(newLogRef, doc.data());
        batch.delete(doc.reference);
        batchCount += 2;
        await commitIfNeeded();
      }

      // --- ETAPA 4: JOGADORES (Vínculo) ---
      debugPrint("⏳ [MIGRAÇÃO] 4/6 - Stats de Jogadores...");
      final legacyPlayers = await _firestore.collection('players').get();
      for (var doc in legacyPlayers.docs) {
        final seasonStatsRef = seasonRef.collection('player_stats').doc(doc.id);
        batch.set(seasonStatsRef, doc.data());
        batchCount++;
        await commitIfNeeded();
      }

      // --- ETAPA 5: CONFIGURAÇÕES ---
      debugPrint("⏳ [MIGRAÇÃO] 5/6 - Configurações...");
      final configDocs = ['app_settings', 'disciplinary_rules', 'playoff_rules', 'tiebreaker_rules', 'settings'];
      for (String docId in configDocs) {
        final docRef = _firestore.collection('config').doc(docId);
        final docSnap = await docRef.get();
        if (docSnap.exists) {
          final targetRef = seasonRef.collection('settings').doc(docId);
          batch.set(targetRef, docSnap.data()!);
          batch.delete(docRef); 
          batchCount += 2;
          await commitIfNeeded();
        }
      }

      // --- ETAPA 6: NOTÍCIAS ---
      debugPrint("⏳ [MIGRAÇÃO] 6/6 - Notícias...");
      final legacyNews = await _firestore.collection('media_feed').get();
      for (var doc in legacyNews.docs) {
        final newNewsRef = seasonRef.collection('news').doc(doc.id);
        batch.set(newNewsRef, doc.data());
        batch.delete(doc.reference);
        batchCount += 2;
        await commitIfNeeded();
      }
      
      await batch.commit(); 
      debugPrint("✅ [MIGRAÇÃO] SUCESSO TOTAL! Banco legado migrado para a temporada 2025_fjf.");

      return "Sucesso";
    } catch (e, stack) {
      debugPrint("❌ [MIGRAÇÃO] ERRO CRÍTICO: $e\n$stack");
      return "Erro: $e";
    }
  }

  // =========================================================================
  // FUNÇÃO AUXILIAR: Decodificador e Limpador de URLs do Firebase Storage
  // =========================================================================
  String _atualizarUrlStorage(String urlAntiga) {
    if (urlAntiga.isEmpty) return urlAntiga;
    
    const String newBucket = 'acefjf-us-storage';

    // Se já está no formato correto (Google Cloud Storage público) não faz nada
    if (urlAntiga.contains('storage.googleapis.com/$newBucket')) {
      return urlAntiga;
    }

    try {
      // 1. É uma URL gerada pelo Firebase Storage (contém /o/) e tem token?
      if (urlAntiga.contains('/o/')) {
        String parteDoCaminho = urlAntiga.split('/o/')[1];
        
        // Remove os parâmetros de query e o token (tudo a partir do '?')
        if (parteDoCaminho.contains('?')) {
          parteDoCaminho = parteDoCaminho.split('?')[0];
        }
        
        // Decodifica os caracteres da web (exemplo: "%2F" volta a ser "/")
        String caminhoLimpo = Uri.decodeComponent(parteDoCaminho);
        
        // Retorna a URL pública, limpa e apontando para o seu bucket gratuito
        return 'https://storage.googleapis.com/$newBucket/$caminhoLimpo';
      } 
      // 2. Fallback: Se for uma URL que apenas contém o nome do bucket, mas sem a estrutura padrão
      else if (urlAntiga.contains('fjfapp.firebasestorage.app') || urlAntiga.contains('acefjf.firebasestorage.app')) {
         String temp = urlAntiga.replaceAll('fjfapp.firebasestorage.app', newBucket);
         return temp.replaceAll('acefjf.firebasestorage.app', newBucket);
      }
    } catch (e) {
      debugPrint('Erro ao converter URL: $e');
    }

    return urlAntiga;
  }
}