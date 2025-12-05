import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminService {
  // --- CONFIGURAÇÕES GLOBAIS (Valores em Cache na Memória) ---
  // Mantemos static para não quebrar as referências atuais na UI (ex: AdminService.pendingYellowCards)
  // No futuro, podemos migrar isso para um Provider reativo.
  
  static String defaultPhase = 'first';
  static String defaultStage = '1';

  static int pendingYellowCards = 2;
  static int suspensionYellowCards = 3;
  static bool suspensionOnRed = true;
  static bool resetYellowsOnSuspension = true;
  static bool resetYellowsOnRed = false;

  static String semifinalTiebreaker = 'extra_time_penalties';
  static String thirdPlaceTiebreaker = 'penalties';
  static String finalTiebreaker = 'extra_time_penalties';
  
  static List<String> tiebreakerOrder = [
    'head_to_head', 'disciplinary_points', 'wins', 'goal_difference', 'goals_against', 'draw_sort',
  ];

  // --- HELPER DE ROTEAMENTO PADRONIZADO ---
  static DocumentReference _getConfigDocRef(String seasonId, String docId) {
    // REMOVIDO: Verificação de LEGACY_ID.
    // Agora aponta sempre para a estrutura de temporada.
    return FirebaseFirestore.instance
        .collection('championships')
        .doc(seasonId)
        .collection('settings')
        .doc(docId);
  }

  // --- CARREGAMENTO UNIFICADO ---
  static Future<void> loadAllRules(String seasonId) async {
    debugPrint("🔄 [AdminService] Carregando regras para temporada: $seasonId");
    
    // Carrega tudo em paralelo para ser mais rápido
    await Future.wait([
      loadAppSettings(seasonId),
      loadDisciplinaryRules(seasonId),
      loadPlayoffRules(seasonId),
      loadTiebreakerOrder(seasonId),
    ]);
  }

  static Future<void> loadAppSettings(String seasonId) async {
    try {
      final doc = await _getConfigDocRef(seasonId, 'app_settings').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        
        defaultPhase = data['default_phase'] ?? 'first';
        // Fallback para 'default_fixtures_round' para manter compatibilidade com nomes antigos de campo se houver
        defaultStage = data['default_stage'] ?? (data['default_fixtures_round']?.toString() ?? '1');
        
        if (data.containsKey('default_fixtures_round') && !data.containsKey('default_phase')) {
          defaultPhase = 'first';
          defaultStage = data['default_fixtures_round'].toString();
        }
      } else {
        // Se não existir configuração, mantém os padrões (Reset)
        defaultPhase = 'first';
        defaultStage = '1';
      }
    } catch (e) { 
      debugPrint("Erro config app_settings: $e"); 
    }
  }

  static Future<void> loadDisciplinaryRules(String seasonId) async {
     try {
      final doc = await _getConfigDocRef(seasonId, 'disciplinary_rules').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        pendingYellowCards = data['pending_yellow_cards'] ?? 2;
        suspensionYellowCards = data['suspension_yellow_cards'] ?? 3;
        suspensionOnRed = data['suspension_on_red'] ?? true;
        resetYellowsOnSuspension = data['reset_yellows_on_suspension'] ?? true;
        resetYellowsOnRed = data['reset_yellows_on_red'] ?? false;
      } else {
        // Padrões FJF se não houver config salva
        pendingYellowCards = 2;
        suspensionYellowCards = 3;
        suspensionOnRed = true;
        resetYellowsOnSuspension = true;
        resetYellowsOnRed = false;
      }
    } catch (e) { 
      debugPrint("Erro config disciplinary: $e"); 
    }
  }

  static Future<void> loadPlayoffRules(String seasonId) async {
     try {
      final doc = await _getConfigDocRef(seasonId, 'playoff_rules').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        semifinalTiebreaker = data['semifinal_tiebreaker'] ?? 'extra_time_penalties';
        thirdPlaceTiebreaker = data['third_place_tiebreaker'] ?? 'penalties';
        finalTiebreaker = data['final_tiebreaker'] ?? 'extra_time_penalties';
      } else {
        semifinalTiebreaker = 'extra_time_penalties';
        thirdPlaceTiebreaker = 'penalties';
        finalTiebreaker = 'extra_time_penalties';
      }
    } catch (e) { 
      debugPrint("Erro config playoff: $e"); 
    }
  }
  
  static Future<void> loadTiebreakerOrder(String seasonId) async {
     try {
      final doc = await _getConfigDocRef(seasonId, 'tiebreaker_rules').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['order'] != null) {
          tiebreakerOrder = List<String>.from(data['order']);
        }
      } else {
        // Ordem padrão se não houver config
        tiebreakerOrder = [
          'head_to_head', 'disciplinary_points', 'wins', 'goal_difference', 'goals_against', 'draw_sort',
        ];
      }
    } catch (e) { 
      debugPrint("Erro config tiebreaker: $e"); 
    }
  }
}