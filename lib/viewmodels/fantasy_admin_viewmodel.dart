import 'package:flutter/material.dart';
import '../services/fantasy_service.dart';
import '../services/fantasy_admin_service.dart';

class FantasyAdminViewModel extends ChangeNotifier {
  final FantasyService _fantasyService = FantasyService();
  final FantasyAdminService _fantasyAdminService = FantasyAdminService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<String> syncMarket(String seasonId) async {
    _setLoading(true);
    try {
      final result = await _fantasyService.populateMarketFromSeason(seasonId);
      return result;
    } catch (e) {
      return "Erro: $e";
    } finally {
      _setLoading(false);
    }
  }

  Future<String> reprocessHistory(String seasonId, int maxRound) async {
    _setLoading(true);
    try {
      final result = await _fantasyAdminService.reprocessFullHistory(seasonId, maxRound);
      return result;
    } catch (e) {
      return "Erro: $e";
    } finally {
      _setLoading(false);
    }
  }

  Future<String> toggleMarket(bool isOpenNow, int targetRound) async {
    final nextStatus = !isOpenNow;
    _setLoading(true);
    try {
      await _fantasyService.setMarketStatus(nextStatus, targetRound);
      return "Mercado ${nextStatus ? 'ABERTO' : 'FECHADO'} com sucesso!";
    } catch (e) {
      return "Erro: $e";
    } finally {
      _setLoading(false);
    }
  }

  Future<String> processRound(String seasonId, int round) async {
    _setLoading(true);
    try {
      final result = await _fantasyService.processRoundCloud(seasonId, round);
      return result;
    } catch (e) {
      return "Erro fatal: $e";
    } finally {
      _setLoading(false);
    }
  }
}
