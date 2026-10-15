import 'package:flutter/foundation.dart';
import '../models/fantasy_audit_models.dart';
import '../services/fantasy_audit_service.dart';

enum AuditSortField {
  expectedScore,
  deltaLive,
  deltaFinal,
  name,
  position,
}

class FantasyAuditViewModel extends ChangeNotifier {
  final FantasyAuditService _service = FantasyAuditService();

  String _seasonId = '';
  int _selectedRound = 1;

  bool _isLoading = false;
  bool _isRunningAudit = false;
  String? _errorMessage;
  String? _successMessage;

  FantasyAuditSummary? _summary;
  List<FantasyAuditPlayer> _players = [];
  List<FantasyAuditMatch> _matches = [];
  List<FantasyAuditTeam> _teams = [];

  // Filtros
  String _selectedPosition = 'Todas';
  String _selectedTeam = 'Todos';
  bool _onlyDiscrepancies = false;
  String _searchQuery = '';
  AuditSortField _sortField = AuditSortField.deltaLive;
  bool _sortAscending = false;

  // Getters
  String get seasonId => _seasonId;
  int get selectedRound => _selectedRound;
  bool get isLoading => _isLoading;
  bool get isRunningAudit => _isRunningAudit;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  FantasyAuditSummary? get summary => _summary;
  List<FantasyAuditPlayer> get players => _players;
  List<FantasyAuditMatch> get matches => _matches;
  List<FantasyAuditTeam> get teams => _teams;

  String get selectedPosition => _selectedPosition;
  String get selectedTeam => _selectedTeam;
  bool get onlyDiscrepancies => _onlyDiscrepancies;
  String get searchQuery => _searchQuery;
  AuditSortField get sortField => _sortField;
  bool get sortAscending => _sortAscending;

  List<String> get availablePositions => ['Todas', 'Goleiro', 'Fixo', 'Ala', 'Pivô', 'Técnico'];
  
  List<String> get availableTeams {
    final set = <String>{'Todos'};
    for (var p in _players) {
      if (p.teamId.isNotEmpty) set.add(p.teamId);
    }
    return set.toList();
  }

  void init(String seasonId, int initialRound) {
    _seasonId = seasonId;
    _selectedRound = initialRound;
    loadAuditData(seasonId, initialRound);
  }

  void setRound(int round) {
    if (_selectedRound != round) {
      _selectedRound = round;
      loadAuditData(_seasonId, round);
    }
  }

  Future<void> loadAuditData(String seasonId, int round) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _summary = await _service.getAuditSummary(seasonId, round);
      if (_summary != null) {
        _players = await _service.getAuditedPlayers(seasonId, round);
        _matches = await _service.getAuditedMatches(seasonId, round);
        _teams = await _service.getAuditedTeams(seasonId, round);
      } else {
        _players = [];
        _matches = [];
        _teams = [];
      }
    } catch (e) {
      _errorMessage = "Erro ao carregar dados da auditoria: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> triggerAudit() async {
    if (_seasonId.isEmpty || _selectedRound < 1) return false;

    _isRunningAudit = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final error = await _service.runAudit(
        seasonId: _seasonId,
        round: _selectedRound,
        includeTeams: true,
      );

      if (error != null) {
        _errorMessage = error;
        _isRunningAudit = false;
        notifyListeners();
        return false;
      }

      _successMessage = "Auditoria da Rodada $_selectedRound executada com sucesso!";
      await loadAuditData(_seasonId, _selectedRound);
      _isRunningAudit = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = "Falha ao rodar auditoria: $e";
      _isRunningAudit = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> syncLiveScores() async {
    if (_seasonId.isEmpty || _selectedRound < 1) return false;

    _isRunningAudit = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final error = await _service.syncAuditToLive(
        seasonId: _seasonId,
        round: _selectedRound,
      );

      if (error != null) {
        _errorMessage = error;
        _isRunningAudit = false;
        notifyListeners();
        return false;
      }

      _successMessage = "Scouts Ao Vivo sincronizados com sucesso!";
      await loadAuditData(_seasonId, _selectedRound);
      _isRunningAudit = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = "Falha ao sincronizar scouts: $e";
      _isRunningAudit = false;
      notifyListeners();
      return false;
    }
  }

  // Métodos de Filtro
  void setPositionFilter(String pos) {
    _selectedPosition = pos;
    notifyListeners();
  }

  void setTeamFilter(String team) {
    _selectedTeam = team;
    notifyListeners();
  }

  void setOnlyDiscrepancies(bool value) {
    _onlyDiscrepancies = value;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query.trim().toLowerCase();
    notifyListeners();
  }

  void setSorting(AuditSortField field) {
    if (_sortField == field) {
      _sortAscending = !_sortAscending;
    } else {
      _sortField = field;
      _sortAscending = false;
    }
    notifyListeners();
  }

  void clearFilters() {
    _selectedPosition = 'Todas';
    _selectedTeam = 'Todos';
    _onlyDiscrepancies = false;
    _searchQuery = '';
    _sortField = AuditSortField.deltaLive;
    _sortAscending = false;
    notifyListeners();
  }

  List<FantasyAuditPlayer> get filteredPlayers {
    List<FantasyAuditPlayer> list = _players.where((p) {
      if (_onlyDiscrepancies && !p.hasDiscrepancy) return false;
      if (_selectedPosition != 'Todas' && p.position != _selectedPosition) return false;
      if (_selectedTeam != 'Todos' && p.teamId != _selectedTeam) return false;
      if (_searchQuery.isNotEmpty && !p.name.toLowerCase().contains(_searchQuery)) return false;
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp = 0;
      switch (_sortField) {
        case AuditSortField.expectedScore:
          cmp = a.expectedScore.compareTo(b.expectedScore);
          break;
        case AuditSortField.deltaLive:
          cmp = a.deltaLive.abs().compareTo(b.deltaLive.abs());
          break;
        case AuditSortField.deltaFinal:
          final dA = a.deltaFinal?.abs() ?? 0.0;
          final dB = b.deltaFinal?.abs() ?? 0.0;
          cmp = dA.compareTo(dB);
          break;
        case AuditSortField.name:
          cmp = a.name.compareTo(b.name);
          break;
        case AuditSortField.position:
          cmp = a.position.compareTo(b.position);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });

    return list;
  }

  List<FantasyAuditTeam> get filteredTeams {
    return _teams.where((t) {
      if (_onlyDiscrepancies && !t.hasDiscrepancy) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return t.teamName.toLowerCase().contains(q) || t.ownerName.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  String exportPlayersCsv() {
    final buffer = StringBuffer();
    buffer.writeln("ID,Nome,Posicao,Time,Jogou,Gols,Assists,CA,CV,SG,MOTM,Esperado,AoVivo,DeltaAoVivo,Fechamento,DeltaFechamento,PrecoEsperado,Divergencia,Flags");
    for (var p in filteredPlayers) {
      buffer.writeln(
        '"${p.playerId}","${p.name}","${p.position}","${p.teamId}",${p.played},'
        '${p.scouts['goals'] ?? 0},${p.scouts['assists'] ?? 0},${p.scouts['yellows'] ?? 0},${p.scouts['reds'] ?? 0},'
        '${p.scouts['clean_sheets'] ?? 0},${p.scouts['motm'] ?? 0},'
        '${p.expectedScore},${p.publishedLiveScore},${p.deltaLive},'
        '${p.publishedFinalScore ?? ""},${p.deltaFinal ?? ""},'
        '${p.priceExpectedNew},${p.hasDiscrepancy},"${p.flags.join("; ")}"'
      );
    }
    return buffer.toString();
  }
}
