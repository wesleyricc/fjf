import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/bolao_admin_service.dart';

class AdminBolaoViewModel extends ChangeNotifier {
  final BolaoAdminService _service = BolaoAdminService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isPredictionsOpen = false;
  bool get isPredictionsOpen => _isPredictionsOpen;

  AdminBolaoViewModel() {
    _init();
  }

  Future<void> _init() async {
    _setLoading(true);
    _isPredictionsOpen = await _service.getPredictionsStatus();
    _setLoading(false);
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  Future<void> togglePredictionsStatus(bool isOpen) async {
    _setLoading(true);
    try {
      await _service.togglePredictionsStatus(isOpen);
      _isPredictionsOpen = isOpen;
    } catch (e) {
      debugPrint("Erro ao alternar status: $e");
    } finally {
      _setLoading(false);
    }
  }

  Future<void> seedMatches() async {
    _setLoading(true);
    try {
      await _service.seedMatches();
    } catch (e) {
      debugPrint("Erro ao semear jogos: $e");
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deleteMiniLeague(String id) async {
    _setLoading(true);
    try {
      await _service.deleteMiniLeague(id);
    } catch (e) {
      debugPrint("Erro ao deletar mini liga: $e");
    } finally {
      _setLoading(false);
    }
  }

  Future<void> toggleMiniLeagueStatus(String id, bool isActive) async {
    try {
      await _service.toggleMiniLeagueStatus(id, isActive);
    } catch (e) {
      debugPrint("Erro ao alternar status mini liga: $e");
    }
  }

  Stream<QuerySnapshot> streamMiniLeagues() {
    return _service.streamMiniLeagues();
  }

  Stream<QuerySnapshot> streamMatches() {
    return _service.streamMatches();
  }

  Future<void> updateMatchScore(String matchId, int homeScore, int awayScore, String status, {bool extraTime = false, bool penalties = false}) async {
    _setLoading(true);
    try {
      await _service.updateMatchScore(matchId, homeScore, awayScore, status, extraTime: extraTime, penalties: penalties);
    } catch (e) {
      debugPrint("Erro ao atualizar placar: $e");
    } finally {
      _setLoading(false);
    }
  }
}
