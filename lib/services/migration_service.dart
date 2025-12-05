import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class MigrationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

      // Helper para comitar se o batch encher
      Future<void> commitIfNeeded() async {
        if (batchCount >= 400) {
          await batch.commit();
          batch = _firestore.batch();
          batchCount = 0;
          debugPrint("♻️ [MIGRAÇÃO] Batch intermediário processado.");
        }
      }

      // --- PASSO 0: CACHE DE JOGADORES (Necessário para gerar Timeline) ---
      // Como os stats antigos só tem ID, precisamos buscar o Nome e TimeID do jogador global
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
        
        // A. CRIA CADASTRO GLOBAL
        final dirRef = _firestore.collection('teams_directory').doc(doc.id);
        batch.set(dirRef, {
          'name': data['name'],
          'short_name': data['short_name'],
          'shield_url': data['shield_url'],
          'championship_history': data['championship_history'] ?? [],
        });

        // B. MOVE DADOS PARA A TEMPORADA
        final partRef = seasonRef.collection('teams_participation').doc(doc.id);
        batch.set(partRef, data);

        // C. MIGRA SUB-COLEÇÃO 'extra_points_log'
        final legacyLogs = await doc.reference.collection('extra_points_log').get();
        for (var logDoc in legacyLogs.docs) {
           final newLogRef = partRef.collection('extra_points_log').doc(logDoc.id);
           batch.set(newLogRef, logDoc.data());
           batch.delete(logDoc.reference); 
           batchCount++;
           await commitIfNeeded();
        }

        // D. Deleta legado
        batch.delete(doc.reference);
        batchCount++;
        await commitIfNeeded();
      }

      // --- ETAPA 2: JOGOS + GERAÇÃO DE TIMELINE (Ajustado) ---
      debugPrint("⏳ [MIGRAÇÃO] 2/6 - Jogos e Geração de Timeline (Minuto 0)...");
      final legacyMatches = await _firestore.collection('matches').get();
      
      for (var doc in legacyMatches.docs) {
        final matchData = doc.data();
        final newMatchRef = seasonRef.collection('matches').doc(doc.id);
        
        // 1. Copia a partida
        batch.set(newMatchRef, matchData);
        
        // 2. GERA TIMELINE SINTÉTICA A PARTIR DOS STATS (Minuto 0)
        if (matchData.containsKey('stats_applied') && matchData['stats_applied']?['player_stats'] != null) {
          final pStats = matchData['stats_applied']['player_stats'];
          
          // Função auxiliar interna para gerar eventos
          void generateEvents(Map<String, dynamic>? sourceMap, String eventType) {
            if (sourceMap == null) return;
            
            sourceMap.forEach((playerId, count) {
              // Garante que é um número e maior que 0
              final int qtd = (count is int) ? count : 0;
              if (qtd <= 0) return;

              // Busca dados do jogador no cache
              final pData = playerCache[playerId];
              final String pName = pData?['name'] ?? 'Desconhecido';
              final String pTeamId = pData?['team_id'] ?? '';

              // Cria N eventos para N gols/cartões
              for (int i = 0; i < qtd; i++) {
                final eventRef = newMatchRef.collection('timeline').doc(); // ID auto-gerado
                
                batch.set(eventRef, {
                  'type': eventType, // goal, yellowCard, redCard
                  'playerId': playerId,
                  'playerName': pName,
                  'teamId': pTeamId,
                  'minute': 0, // <-- REGRA SOLICITADA
                  'period': '1T',
                  'timestamp': matchData['datetime'], // Usa data do jogo para ordenação
                  'concededByPlayerId': null // Não temos como saber quem era o goleiro no legado
                });
                batchCount++;
              }
            });
          }

          // Gera Gols
          generateEvents(pStats['goals'], 'goal');
          // Gera Amarelos
          generateEvents(pStats['yellows'], 'yellowCard');
          // Gera Vermelhos
          generateEvents(pStats['reds'], 'redCard');
          
          // Nota: Não precisamos comitar aqui dentro pois o commitIfNeeded é chamado abaixo
        }

        // Tenta migrar timeline antiga se existir (apenas segurança, caso algum já tenha)
        final legacyTimeline = await doc.reference.collection('timeline').get();
        for (var eventDoc in legacyTimeline.docs) {
          final newEventRef = newMatchRef.collection('timeline').doc(eventDoc.id);
          batch.set(newEventRef, eventDoc.data());
          batch.delete(eventDoc.reference);
          batchCount++;
        }

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
        batchCount++;
        await commitIfNeeded();
      }

      // --- ETAPA 4: JOGADORES (Vínculo) ---
      debugPrint("⏳ [MIGRAÇÃO] 4/6 - Stats de Jogadores...");
      final legacyPlayers = await _firestore.collection('players').get();
      for (var doc in legacyPlayers.docs) {
        final seasonStatsRef = seasonRef.collection('player_stats').doc(doc.id);
        batch.set(seasonStatsRef, doc.data());
        // Não deleta da raiz
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
          batchCount++;
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
        batchCount++;
        await commitIfNeeded();
      }
      
      await batch.commit(); // Commit final
      debugPrint("✅ [MIGRAÇÃO] SUCESSO TOTAL! Banco migrado e Timelines geradas.");

      return "Sucesso";
    } catch (e) {
      debugPrint("❌ [MIGRAÇÃO] ERRO CRÍTICO: $e");
      return "Erro: $e";
    }
  }
}