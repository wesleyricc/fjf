import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // ==========================================================
  // 1. PROPRIEDADES DO USUÁRIO (AUDIÊNCIAS)
  // ==========================================================
  static Future<void> setUserProperties({
    required String userId,
    required String role, // Ex: 'admin', 'president', 'user'
  }) async {
    try {
      await _analytics.setUserId(id: userId);
      await _analytics.setUserProperty(name: 'user_role', value: role);
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  static Future<void> setFantasyPlayerTag(bool hasTeam) async {
    try {
      await _analytics.setUserProperty(name: 'play_fantasy', value: hasTeam.toString());
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  // ==========================================================
  // 2. RASTREAMENTO DE TELAS CONTEXTUAIS (PROFUNDIDADE)
  // ==========================================================
  static Future<void> logCustomScreenView(String screenName, {Map<String, Object>? parameters}) async {
    try {
      await _analytics.logEvent(
        name: 'screen_view',
        parameters: {
          'firebase_screen': screenName,
          ...?parameters,
        },
      );
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  // Usar quando o usuário abre o perfil de um Time, Jogador ou Jogo específico
  static Future<void> logViewItem({
    required String contentType, // Ex: 'player', 'team', 'match'
    required String itemId,
    required String itemName,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'view_item',
        parameters: {
          'content_type': contentType,
          'item_id': itemId,
          'item_name': itemName,
        },
      );
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  // ==========================================================
  // 3. PUBLICIDADE (IMPRESSÕES E CLIQUES)
  // ==========================================================
  static Future<void> logAdImpression(String sponsorName, String location) async {
    try {
      await _analytics.logEvent(
        name: 'ad_impression',
        parameters: {
          'ad_source': sponsorName,
          'ad_slot': location,
        },
      );
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  static Future<void> logAdClick(String sponsorName, String location, String url) async {
    try {
      await _analytics.logEvent(
        name: 'ad_click',
        parameters: {
          'ad_source': sponsorName,
          'ad_slot': location,
          'url': url,
        },
      );
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  // ==========================================================
  // 4. FUNIL DE E-COMMERCE E BOLÃO (CONVERSÃO)
  // ==========================================================
  static Future<void> logBeginCheckout({
    required String type, // 'photo_pack', 'mini_bolao', 'bolao_copa'
    required int itemCount,
    required double totalValue,
    String? itemName,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'begin_checkout',
        parameters: {
          'content_type': type,
          'item_count': itemCount,
          'value': totalValue,
          'currency': 'BRL',
          if (itemName != null) 'item_name': itemName,
        },
      );
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  static Future<void> logPurchase({
    required String type,
    required String transactionId,
    required double value,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'purchase',
        parameters: {
          'content_type': type,
          'transaction_id': transactionId,
          'value': value,
          'currency': 'BRL',
        },
      );
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  // ==========================================================
  // 5. ENGAJAMENTO (FANTASY E CHAT)
  // ==========================================================
  static Future<void> logFantasyAccess(String userId) async {
    try {
      await _analytics.logEvent(name: 'fantasy_entered', parameters: {'user_id': userId});
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  static Future<void> logLineupSaved(double teamValue, bool hasCaptain) async {
    try {
      await _analytics.logEvent(
        name: 'fantasy_lineup_saved',
        parameters: {'team_value': teamValue, 'has_captain': hasCaptain ? 1 : 0},
      );
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  static Future<void> logChatMessageSent(String matchId) async {
    try {
      await _analytics.logEvent(name: 'chat_message_sent', parameters: {'match_id': matchId});
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }

  static Future<void> logShare(String contentType, String contentId) async {
    try {
      await _analytics.logEvent(
        name: 'share',
        parameters: {'content_type': contentType, 'item_id': contentId},
      );
    } catch (e) { debugPrint("Analytics Error: $e"); }
  }
}