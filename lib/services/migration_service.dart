import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class MigrationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> migrateLegacyTo2025() async {
    try {
      const String newSeasonId = '2025_fjf';
      debugPrint("🚀 [MIGRAÇÃO] Iniciando processo...");

      // 1. Criar Temporada
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

      // --- ETAPA 1: MIGRAR TIMES E SEUS LOGS DE PONTOS ---
      debugPrint("⏳ [MIGRAÇÃO] Processando Times e Logs de Pontos...");
      
      final legacyTeams = await _firestore.collection('teams').get();
      
      for (var doc in legacyTeams.docs) {
        final data = doc.data();
        
        // A. Diretório Global
        final dirRef = _firestore.collection('teams_directory').doc(doc.id);
        batch.set(dirRef, {
          'name': data['name'],
          'short_name': data['short_name'],
          'shield_url': data['shield_url'],
          'championship_history': data['championship_history'] ?? [],
        });

        // B. Participação na Temporada
        final partRef = seasonRef.collection('teams_participation').doc(doc.id);
        batch.set(partRef, data);

        // C. (NOVO) MIGRAR SUB-COLEÇÃO 'extra_points_log'
        // O Firestore não move subcoleções sozinho. Temos que fazer manualmente.
        final legacyLogs = await doc.reference.collection('extra_points_log').get();
        for (var logDoc in legacyLogs.docs) {
           final newLogRef = partRef.collection('extra_points_log').doc(logDoc.id);
           batch.set(newLogRef, logDoc.data());
           batch.delete(logDoc.reference); // Deleta o log antigo
           batchCount++;
        }

        // D. Deleta o time da Raiz
        batch.delete(doc.reference);
        batchCount++;
        
        // Safety check para o limite do Batch (500 operações)
        if (batchCount >= 400) {
          await batch.commit();
          batch = _firestore.batch();
          batchCount = 0;
        }
      }
      if (batchCount > 0) {
        await batch.commit();
        batch = _firestore.batch(); // Reinicia para próximas etapas
        batchCount = 0;
      }
      debugPrint("✅ [MIGRAÇÃO] Times e Sub-logs migrados.");

      // --- ETAPA 2: MIGRAR JOGOS ---
      debugPrint("⏳ [MIGRAÇÃO] Processando Jogos...");
      final legacyMatches = await _firestore.collection('matches').get();
      for (var doc in legacyMatches.docs) {
        final newMatchRef = seasonRef.collection('matches').doc(doc.id);
        batch.set(newMatchRef, doc.data());
        batch.delete(doc.reference);
        batchCount++;
        if (batchCount >= 400) { await batch.commit(); batch = _firestore.batch(); batchCount = 0; }
      }
      if (batchCount > 0) { await batch.commit(); batch = _firestore.batch(); batchCount = 0; }

      // --- ETAPA 3: MIGRAR LOG DE SUSPENSÃO ---
      debugPrint("⏳ [MIGRAÇÃO] Processando Logs de Suspensão...");
      final legacySuspension = await _firestore.collection('suspension_log').get();
      for (var doc in legacySuspension.docs) {
        final newLogRef = seasonRef.collection('disciplinary_log').doc(doc.id);
        batch.set(newLogRef, doc.data());
        batch.delete(doc.reference);
        batchCount++;
        if (batchCount >= 400) { await batch.commit(); batch = _firestore.batch(); batchCount = 0; }
      }
      if (batchCount > 0) { await batch.commit(); batch = _firestore.batch(); batchCount = 0; }

      // --- ETAPA 4: MIGRAR JOGADORES (STATS) ---
      debugPrint("⏳ [MIGRAÇÃO] Processando Stats de Jogadores...");
      final legacyPlayers = await _firestore.collection('players').get();
      for (var doc in legacyPlayers.docs) {
        // Cria Stats na Temporada 2025
        final seasonStatsRef = seasonRef.collection('player_stats').doc(doc.id);
        batch.set(seasonStatsRef, doc.data());
        // NOTA: NÃO deletamos da raiz (Global Directory)
        batchCount++;
        if (batchCount >= 400) { await batch.commit(); batch = _firestore.batch(); batchCount = 0; }
      }
      if (batchCount > 0) { await batch.commit(); batch = _firestore.batch(); batchCount = 0; }

      // --- ETAPA 5: CONFIGURAÇÕES ---
      debugPrint("⏳ [MIGRAÇÃO] Processando Configurações...");
      final configDocs = ['app_settings', 'disciplinary_rules', 'playoff_rules', 'tiebreaker_rules'];
      for (String docId in configDocs) {
        final docSnap = await _firestore.collection('config').doc(docId).get();
        if (docSnap.exists) {
          final targetRef = seasonRef.collection('settings').doc(docId);
          batch.set(targetRef, docSnap.data()!);
        }
      }
      if (batchCount > 0) { await batch.commit(); batch = _firestore.batch(); batchCount = 0; }

      // --- ETAPA 6: MIGRAR NOTÍCIAS ---
      debugPrint("⏳ [MIGRAÇÃO] Processando Notícias...");
      final legacyNews = await _firestore.collection('media_feed').get();
      for (var doc in legacyNews.docs) {
        final newNewsRef = seasonRef.collection('news').doc(doc.id);
        batch.set(newNewsRef, doc.data());
        batch.delete(doc.reference);
        batchCount++;
        if (batchCount >= 400) { await batch.commit(); batch = _firestore.batch(); batchCount = 0; }
      }
      
      await batch.commit(); // Commit final
      debugPrint("✅ [MIGRAÇÃO] Processo Concluído!");

      return "Sucesso";
    } catch (e) {
      debugPrint("❌ [MIGRAÇÃO] ERRO CRÍTICO: $e");
      return "Erro: $e";
    }
  }
}