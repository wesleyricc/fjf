import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // 1. O usuário entrou no Fantasy com sucesso
  static Future<void> logFantasyAccess(String userId) async {
    try {
      await _analytics.logEvent(
        name: 'fantasy_entered',
        parameters: {'user_id': userId},
      );
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  // 2. O usuário salvou uma escalação
  static Future<void> logLineupSaved(double teamValue, bool hasCaptain) async {
    try {
      await _analytics.logEvent(
        name: 'fantasy_lineup_saved',
        parameters: {
          'team_value': teamValue,
          'has_captain': hasCaptain ? 1 : 0, // 1 = Sim, 0 = Não
        },
      );
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  // 3. O usuário tentou gerar um PIX (Funil de Vendas)
  static Future<void> logPhotoPackCheckout(int photoCount, double totalValue) async {
    try {
      await _analytics.logEvent(
        name: 'checkout_initiated', // Evento padrão do Google para E-commerce
        parameters: {
          'item_count': photoCount,
          'value': totalValue,
          'currency': 'BRL',
        },
      );
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  // 4. O usuário brincou no simulador de classificação
  static Future<void> logSimulatorUsed() async {
    try {
      await _analytics.logEvent(name: 'standings_simulator_used');
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }
}