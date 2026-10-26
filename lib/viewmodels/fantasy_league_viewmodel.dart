import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../models/fantasy_league_model.dart';
import '../models/fantasy_models.dart';
import '../services/fantasy_league_service.dart';

class FantasyLeagueViewModel extends ChangeNotifier {
  final FantasyLeagueService _leagueService = FantasyLeagueService();
  
  String? _userId;
  bool _isLoading = false;
  String? _errorMessage;
  List<FantasyLeague> _myLeagues = [];
  List<FantasyLeague> _sponsoredLeagues = [];
  StreamSubscription? _leaguesSub;
  StreamSubscription? _sponsoredLeaguesSub;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get userId => _userId;
  List<FantasyLeague> get myLeagues => _myLeagues;
  List<FantasyLeague> get sponsoredLeagues => _sponsoredLeagues;

  void init(String userId) {
    _userId = userId;
    _leaguesSub?.cancel();
    _sponsoredLeaguesSub?.cancel();
    
    // Fica escutando as ligas em tempo real
    _leaguesSub = _leagueService.streamMyLeagues(userId).listen((leagues) {
      _myLeagues = leagues;
      notifyListeners();
    }, onError: (error) {
      debugPrint("Erro ao escutar ligas: $error");
    });

    _sponsoredLeaguesSub = _leagueService.streamSponsoredLeagues().listen((leagues) {
      _sponsoredLeagues = leagues;
      notifyListeners();
    }, onError: (error) {
      debugPrint("Erro ao escutar ligas patrocinadas: $error");
    });
  }

  Future<String?> createLeague(String name, {String type = 'classic', int? maxTeams}) async {
    if (_userId == null || name.trim().isEmpty) return null;
    
    _setLoading(true);
    try {
      final inviteCode = await _leagueService.createLeague(name, _userId!, type: type, maxTeams: maxTeams);
      _setLoading(false);
      return inviteCode;
    } catch (e) {
      _errorMessage = "Erro ao criar liga: $e";
      _setLoading(false);
      return null;
    }
  }

  Future<bool> generateBracket(FantasyLeague league) async {
    _setLoading(true);
    try {
      final res = await _leagueService.generateBracket(league);
      if (res != "Sucesso") {
        _errorMessage = res;
        _setLoading(false);
        return false;
      }
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = "Erro ao gerar chaves: $e";
      _setLoading(false);
      return false;
    }
  }

  Stream<List<KnockoutMatch>> streamKnockoutMatches(String leagueId) {
    return _leagueService.streamKnockoutMatches(leagueId);
  }

  Future<bool> joinLeague(String code) async {
    if (_userId == null || code.trim().isEmpty) return false;

    _setLoading(true);
    try {
      final error = await _leagueService.joinLeague(code, _userId!);
      if (error != null) {
        _errorMessage = error;
        _setLoading(false);
        return false;
      }
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = "Erro ao entrar na liga: $e";
      _setLoading(false);
      return false;
    }
  }

  Future<bool> joinSponsoredLeague(String leagueId) async {
    if (_userId == null || leagueId.isEmpty) return false;

    _setLoading(true);
    try {
      final error = await _leagueService.joinSponsoredLeague(leagueId, _userId!);
      if (error != null) {
        _errorMessage = error;
        _setLoading(false);
        return false;
      }
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = "Erro ao entrar na liga patrocinada: $e";
      _setLoading(false);
      return false;
    }
  }

  Future<bool> leaveLeague(String leagueId) async {
    if (_userId == null || leagueId.isEmpty) return false;

    _setLoading(true);
    try {
      final error = await _leagueService.leaveLeague(leagueId, _userId!);
      if (error != null) {
        _errorMessage = error;
        _setLoading(false);
        return false;
      }
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = "Erro ao sair da liga: $e";
      _setLoading(false);
      return false;
    }
  }

  // =================================================================
  // GERENCIAMENTO DA LIGA (DONO)
  // =================================================================

  Stream<FantasyLeague> streamLeague(String leagueId) {
    return _leagueService.streamLeague(leagueId);
  }

  Future<List<FantasyTeam>> getMembersTeams(List<String> memberIds) {
    return _leagueService.getLeagueMembersTeams(memberIds);
  }

  Future<bool> updateLeagueInfo(
    String leagueId, {
    required String newName,
    XFile? newImageFile,
    bool removeImage = false,
  }) async {
    if (_userId == null) return false;
    _setLoading(true);

    try {
      String? uploadedImageUrl;
      if (newImageFile != null) {
        uploadedImageUrl = await _leagueService.uploadLeagueImage(leagueId, newImageFile);
        if (uploadedImageUrl == null) {
          _errorMessage = "Falha ao enviar imagem da liga.";
          _setLoading(false);
          return false;
        }
      }

      final error = await _leagueService.updateLeagueInfo(
        leagueId,
        _userId!,
        newName: newName,
        newImageUrl: uploadedImageUrl,
        removeImage: removeImage,
      );

      if (error != null) {
        _errorMessage = error;
        _setLoading(false);
        return false;
      }

      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = "Erro ao salvar liga: $e";
      _setLoading(false);
      return false;
    }
  }

  Future<bool> removeMember(String leagueId, String memberId) async {
    _setLoading(true);
    try {
      final error = await _leagueService.removeMemberFromLeague(leagueId, memberId);
      if (error != null) {
        _errorMessage = error;
        _setLoading(false);
        return false;
      }
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = "Erro ao remover participante: $e";
      _setLoading(false);
      return false;
    }
  }

  Future<bool> transferOwnership(String leagueId, String newOwnerId) async {
    if (_userId == null) return false;
    _setLoading(true);
    try {
      final error = await _leagueService.transferLeagueOwnership(leagueId, _userId!, newOwnerId);
      if (error != null) {
        _errorMessage = error;
        _setLoading(false);
        return false;
      }
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = "Erro ao transferir administração: $e";
      _setLoading(false);
      return false;
    }
  }

  Future<bool> deleteLeague(String leagueId) async {
    if (_userId == null) return false;
    _setLoading(true);
    try {
      final error = await _leagueService.deleteLeague(leagueId, _userId!);
      if (error != null) {
        _errorMessage = error;
        _setLoading(false);
        return false;
      }
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = "Erro ao excluir liga: $e";
      _setLoading(false);
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _leaguesSub?.cancel();
    _sponsoredLeaguesSub?.cancel();
    super.dispose();
  }
}