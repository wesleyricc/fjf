import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/team_model.dart';
import '../../models/portal_substitution_model.dart';
import '../../services/championship_service.dart';
import '../../services/portal_substitution_service.dart';
import '../../theme/app_theme.dart';

class PortalSubstitutionTab extends StatefulWidget {
  final String? teamId;
  final bool isPresident;
  final bool isAdmin;

  const PortalSubstitutionTab({
    super.key,
    this.teamId,
    this.isPresident = false,
    this.isAdmin = false,
  });

  @override
  State<PortalSubstitutionTab> createState() => _PortalSubstitutionTabState();
}

class _PortalSubstitutionTabState extends State<PortalSubstitutionTab> {
  final PortalSubstitutionService _subService = PortalSubstitutionService();
  String? _selectedTeamId;
  Timer? _tickerTimer;
  DateTime _currentTickTime = DateTime.now();
  String _filter = 'all'; // 'all', 'on_court', 'pending', 'completed'
  String _searchQuery = '';
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _selectedTeamId = widget.teamId;

    // Timer periódico de 1 segundo para atualizar o cronômetro ao vivo na tela
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTickTime = DateTime.now();
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initTeamData();
    });
  }

  @override
  void didUpdateWidget(covariant PortalSubstitutionTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.teamId != oldWidget.teamId) {
      setState(() {
        _selectedTeamId = widget.teamId;
      });
      _initTeamData();
    }
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

  Future<void> _initTeamData() async {
    final champService = Provider.of<ChampionshipService>(context, listen: false);

    // Se o usuário não tiver time fixo (Admin), seleciona o primeiro time da lista
    if (_selectedTeamId == null || _selectedTeamId!.isEmpty) {
      if (champService.teams.isNotEmpty) {
        setState(() {
          _selectedTeamId = champService.teams.first.id;
        });
      }
    }

    if (_selectedTeamId != null && _selectedTeamId!.isNotEmpty) {
      await _syncRoster(silent: true);
    }
  }

  Future<void> _syncRoster({bool silent = false}) async {
    if (_selectedTeamId == null || _selectedTeamId!.isEmpty) return;
    if (!silent) setState(() => _isSyncing = true);

    final champService = Provider.of<ChampionshipService>(context, listen: false);
    final roster = await champService.fetchRoster(_selectedTeamId!, force: true);
    
    Team? currentTeam;
    try {
      currentTeam = champService.teams.firstWhere((t) => t.id == _selectedTeamId);
    } catch (_) {}

    final teamName = currentTeam?.name ?? 'Equipe';

    await _subService.syncRosterWithSession(
      teamId: _selectedTeamId!,
      teamName: teamName,
      roster: roster,
    );

    if (mounted && !silent) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Elenco sincronizado com sucesso!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final champService = Provider.of<ChampionshipService>(context);
    final rawTeams = champService.teams;

    // Deduplica equipes por ID único para evitar erros de DropdownMenuItem repetido
    final uniqueTeamsMap = <String, Team>{};
    for (var t in rawTeams) {
      if (t.id.isNotEmpty) uniqueTeamsMap[t.id] = t;
    }
    final cleanTeams = uniqueTeamsMap.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Determina se pode trocar de time (apenas administradores sem time fixo ou com flag isAdmin)
    final canSwitchTeam = widget.isAdmin || (widget.teamId == null || widget.teamId!.isEmpty);

    // Identifica o time ativo com garantia estrita
    String? currentTeamId;
    if (_selectedTeamId != null && cleanTeams.any((t) => t.id == _selectedTeamId)) {
      currentTeamId = _selectedTeamId;
    } else if (widget.teamId != null && cleanTeams.any((t) => t.id == widget.teamId)) {
      currentTeamId = widget.teamId;
    } else if (cleanTeams.isNotEmpty) {
      currentTeamId = cleanTeams.first.id;
    } else {
      currentTeamId = widget.teamId;
    }

    if (_selectedTeamId != currentTeamId && currentTeamId != null) {
      _selectedTeamId = currentTeamId;
    }

    Team? activeTeam;
    if (currentTeamId != null && cleanTeams.isNotEmpty) {
      try {
        activeTeam = cleanTeams.firstWhere((t) => t.id == currentTeamId);
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          // Header com informações do time e controles
          _buildTopBar(activeTeam, cleanTeams, canSwitchTeam, currentTeamId),

          // Conteúdo principal via StreamBuilder
          Expanded(
            child: currentTeamId == null || currentTeamId.isEmpty
                ? const Center(child: Text('Nenhuma equipe disponível no momento.'))
                : StreamBuilder<TeamSubstitutionSession?>(
                    stream: _subService.streamSession(currentTeamId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final session = snapshot.data;
                      if (session == null || session.playerStates.isEmpty) {
                        return _buildEmptyState();
                      }

                      return _buildSessionContent(session);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.swap_horiz, color: Colors.white),
        label: const Text(
          'Registrar Substituição',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        onPressed: () => _openSubstitutionModal(null),
      ),
    );
  }

  Widget _buildTopBar(
    Team? activeTeam,
    List<Team> cleanTeams,
    bool canSwitchTeam,
    String? currentTeamId,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (activeTeam != null && activeTeam.shieldUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    activeTeam.shieldUrl,
                    width: 38,
                    height: 38,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.shield, size: 36),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: canSwitchTeam && cleanTeams.isNotEmpty
                    ? InkWell(
                        onTap: () => _openTeamSelectionSheet(cleanTeams),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      activeTeam?.name ?? 'Selecionar Equipe',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: AppTheme.secondaryColor,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const Text(
                                      'Toque para trocar de equipe',
                                      style: TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, color: AppTheme.primaryColor),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activeTeam?.name ?? 'Minha Equipe',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppTheme.secondaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Regulamento: 5 min diretos obrigatórios',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              IconButton(
                icon: _isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, color: Colors.grey),
                tooltip: 'Sincronizar Elenco',
                onPressed: _isSyncing ? null : () => _syncRoster(),
              ),
              IconButton(
                icon: const Icon(Icons.assignment, color: Colors.grey),
                tooltip: 'Relatório da Partida',
                onPressed: () => _openReportModal(),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.grey),
                onSelected: (value) {
                  if (value == 'reset') {
                    _confirmResetSession();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'reset',
                    child: Row(
                      children: [
                        Icon(Icons.restart_alt, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text('Nova Partida / Resetar', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openTeamSelectionSheet(List<Team> teams) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (modalCtx, setSheetState) {
            final filtered = query.isEmpty
                ? teams
                : teams
                    .where((t) => t.name.toLowerCase().contains(query.toLowerCase()))
                    .toList();

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.85,
              minChildSize: 0.4,
              builder: (context, scrollController) {
                return Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Selecionar Equipe',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Buscar equipe...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onChanged: (val) {
                          setSheetState(() => query = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final team = filtered[index];
                            final isSelected = team.id == _selectedTeamId;

                            return ListTile(
                              leading: team.shieldUrl.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.network(
                                        team.shieldUrl,
                                        width: 32,
                                        height: 32,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.shield, size: 28),
                                      ),
                                    )
                                  : const Icon(Icons.shield, size: 28),
                              title: Text(
                                team.name,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? AppTheme.primaryColor : Colors.black87,
                                ),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle, color: AppTheme.primaryColor)
                                  : null,
                              onTap: () {
                                Navigator.pop(ctx);
                                setState(() {
                                  _selectedTeamId = team.id;
                                });
                                _syncRoster();
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Nenhum atleta sincronizado ainda',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Toque no botão abaixo para carregar todos os atletas da sua equipe e iniciar o controle dos 5 minutos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _syncRoster(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.sync, color: Colors.white),
              label: const Text(
                'Carregar Elenco',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionContent(TeamSubstitutionSession session) {
    final allStates = session.playerStates.values.toList();

    // Ordenação: 1º Em quadra, 2º Não cumpriram os 5 min, 3º Cumpriram os 5 min
    allStates.sort((a, b) {
      if (a.isOnCourt && !b.isOnCourt) return -1;
      if (!a.isOnCourt && b.isOnCourt) return 1;

      final aSatisfied = a.isRuleSatisfied(now: _currentTickTime);
      final bSatisfied = b.isRuleSatisfied(now: _currentTickTime);

      if (!aSatisfied && bSatisfied) return -1;
      if (aSatisfied && !bSatisfied) return 1;

      return a.playerName.toLowerCase().compareTo(b.playerName.toLowerCase());
    });

    // Filtros
    final filteredStates = allStates.where((p) {
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchName = p.playerName.toLowerCase().contains(query);
        final matchNum = p.jerseyNumber?.toString().contains(query) ?? false;
        if (!matchName && !matchNum) return false;
      }

      if (_filter == 'on_court') return p.isOnCourt;
      if (_filter == 'pending') return !p.isRuleSatisfied(now: _currentTickTime);
      if (_filter == 'completed') return p.isRuleSatisfied(now: _currentTickTime);
      return true;
    }).toList();

    return Column(
      children: [
        // Cards de métricas rápidas no topo
        _buildSummaryCards(session),

        // Barra de busca e filtros
        _buildFiltersRow(session),

        // Lista de Atletas
        Expanded(
          child: filteredStates.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum atleta encontrado no filtro selecionado.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: filteredStates.length,
                  itemBuilder: (context, index) {
                    final player = filteredStates[index];
                    return _buildPlayerCard(player, allStates);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(TeamSubstitutionSession session) {
    final total = session.totalPlayers;
    final onCourt = session.playersOnCourtCount;
    final completed = session.ruleSatisfiedCount;
    final pending = session.pendingPlayersCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _buildMiniStatCard(
            title: 'Em Quadra',
            count: onCourt,
            color: Colors.blue,
            icon: Icons.sports_handball,
          ),
          const SizedBox(width: 8),
          _buildMiniStatCard(
            title: '5 min OK',
            count: completed,
            color: Colors.green,
            icon: Icons.check_circle_outline,
          ),
          const SizedBox(width: 8),
          _buildMiniStatCard(
            title: 'Falta Jogar',
            count: pending,
            color: Colors.orange,
            icon: Icons.hourglass_top,
          ),
          const SizedBox(width: 8),
          _buildMiniStatCard(
            title: 'Total',
            count: total,
            color: Colors.grey.shade700,
            icon: Icons.people_outline,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersRow(TeamSubstitutionSession session) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Campo de busca rápida
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: const InputDecoration(
                hintText: 'Buscar atleta por nome ou número...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Chips de filtro
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('all', 'Todos (${session.totalPlayers})'),
                const SizedBox(width: 6),
                _buildFilterChip('on_court', '🟢 Em Quadra (${session.playersOnCourtCount})'),
                const SizedBox(width: 6),
                _buildFilterChip('pending', '⏳ Precisam Entrar (${session.pendingPlayersCount})'),
                const SizedBox(width: 6),
                _buildFilterChip('completed', '✅ 5 Min OK (${session.ruleSatisfiedCount})'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _filter == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : Colors.grey.shade800,
        ),
      ),
      selected: isSelected,
      selectedColor: AppTheme.primaryColor,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
        ),
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() => _filter = key);
        }
      },
    );
  }

  Widget _buildPlayerCard(
    PlayerSubstitutionState player,
    List<PlayerSubstitutionState> allPlayers,
  ) {
    final isOnCourt = player.isOnCourt;
    final currentElapsed = player.getCurrentStintElapsedSeconds(now: _currentTickTime);
    final effectiveContinuous = player.getEffectiveContinuousSeconds(now: _currentTickTime);
    final isSatisfied = player.isRuleSatisfied(now: _currentTickTime);
    final progress = player.getProgressTowards5Min(now: _currentTickTime);

    // Destaque visual caso atinja os 5 minutos enquanto está em quadra
    final isCelebrating5Min = isOnCourt && currentElapsed >= 300;

    return Card(
      elevation: isOnCourt ? 3 : 1,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isCelebrating5Min
              ? Colors.green.shade400
              : isOnCourt
                  ? AppTheme.primaryColor.withValues(alpha: 0.6)
                  : isSatisfied
                      ? Colors.green.shade200
                      : Colors.grey.shade200,
          width: isOnCourt ? 2 : 1,
        ),
      ),
      color: isCelebrating5Min
          ? Colors.green.shade50.withValues(alpha: 0.5)
          : isOnCourt
              ? Colors.blue.shade50.withValues(alpha: 0.3)
              : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar / Foto do Atleta com número da camisa
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: player.photoUrl.isNotEmpty
                          ? NetworkImage(player.photoUrl)
                          : null,
                      child: player.photoUrl.isEmpty
                          ? Text(
                              player.playerName.isNotEmpty
                                  ? player.playerName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondaryColor,
                              ),
                            )
                          : null,
                    ),
                    if (player.jerseyNumber != null)
                      Positioned(
                        bottom: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Text(
                            '#${player.jerseyNumber}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // Nome e Informações do Atleta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.playerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppTheme.secondaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (player.position != null && player.position!.isNotEmpty) ...[
                            Text(
                              player.position!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const Text(' • ', style: TextStyle(color: Colors.grey)),
                          ],
                          Text(
                            isOnCourt ? 'Em Quadra' : 'No Banco',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isOnCourt ? Colors.blue.shade700 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // CRONÔMETRO AO LADO DOS DADOS DO ATLETA
                _buildStopwatchBox(
                  isOnCourt: isOnCourt,
                  currentElapsed: currentElapsed,
                  effectiveContinuous: effectiveContinuous,
                  isSatisfied: isSatisfied,
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Barra de Progresso dos 5 Minutos Obrigatórios
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isSatisfied ? Icons.check_circle : Icons.timer,
                          size: 14,
                          color: isSatisfied ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isSatisfied
                              ? 'Regulamento 5 min Cumprido! (${_formatDuration(effectiveContinuous)})'
                              : isOnCourt
                                  ? 'Faltam ${_formatDuration((300 - currentElapsed).clamp(0, 300))} para cumprir a regra'
                                  : effectiveContinuous > 0
                                      ? 'Jogou ${_formatDuration(effectiveContinuous)} diretos (Precisa de 5:00 diretos)'
                                      : 'Ainda não jogou (Precisa cumprir 5 min diretos)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSatisfied
                                ? Colors.green.shade800
                                : isOnCourt
                                    ? Colors.blue.shade900
                                    : Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSatisfied ? Colors.green : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isSatisfied ? Colors.green : (isOnCourt ? AppTheme.primaryColor : Colors.orange),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Linha de Ações (Entrar, Sair, Ajustar Tempo)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Indicador de Total de passagens
                if (player.stints.isNotEmpty) ...[
                  Text(
                    '${player.stints.length} passagem(ns) • Total: ${_formatDuration(player.getEffectiveTotalSeconds(now: _currentTickTime))}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  const Spacer(),
                ] else ...[
                  const Spacer(),
                ],

                // Botão Ajustar Tempo
                IconButton(
                  icon: const Icon(Icons.tune, size: 18, color: Colors.grey),
                  tooltip: 'Ajustar Minutos',
                  onPressed: () => _openAdjustTimeModal(player),
                  visualDensity: VisualDensity.compact,
                ),

                const SizedBox(width: 4),

                // Botão Principal (Entrar ou Sair)
                if (!isOnCourt)
                  ElevatedButton.icon(
                    onPressed: () => _openSubstitutionModal(player),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.login, size: 16),
                    label: const Text(
                      'Entrar em Quadra',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () => _confirmPlayerExit(player),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSatisfied ? Colors.blue.shade600 : Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.logout, size: 16),
                    label: Text(
                      isSatisfied ? 'Registrar Saída' : 'Substituir / Banco',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Caixa com o cronômetro digital em destaque ao lado dos dados do atleta
  Widget _buildStopwatchBox({
    required bool isOnCourt,
    required int currentElapsed,
    required int effectiveContinuous,
    required bool isSatisfied,
  }) {
    final displayTime = isOnCourt
        ? _formatDuration(currentElapsed)
        : _formatDuration(effectiveContinuous);

    Color bgColor;
    Color textColor;
    Color borderColor;

    if (isOnCourt) {
      if (currentElapsed >= 300) {
        bgColor = Colors.green.shade600;
        textColor = Colors.white;
        borderColor = Colors.green.shade800;
      } else {
        bgColor = AppTheme.primaryColor;
        textColor = Colors.white;
        borderColor = AppTheme.secondaryColor;
      }
    } else {
      if (isSatisfied) {
        bgColor = Colors.green.shade50;
        textColor = Colors.green.shade800;
        borderColor = Colors.green.shade300;
      } else {
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade700;
        borderColor = Colors.grey.shade300;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: isOnCourt
            ? [
                BoxShadow(
                  color: (currentElapsed >= 300 ? Colors.green : AppTheme.primaryColor)
                      .withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isOnCourt) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                displayTime,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: textColor,
                ),
              ),
            ],
          ),
          Text(
            isOnCourt
                ? (currentElapsed >= 300 ? '5 MIN OK! ✅' : 'EM QUADRA')
                : (isSatisfied ? 'CUMPRIDO' : 'BANCO'),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: textColor.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 🚀 MODAIS DE OPERAÇÃO
  // ===========================================================================

  /// Modal para registrar entrada do atleta, informando o tempo de entrada
  Future<void> _openSubstitutionModal(PlayerSubstitutionState? targetPlayer) async {
    if (_selectedTeamId == null) return;

    final session = await _subService.getSession(_selectedTeamId!);
    if (session == null) return;

    final availablePlayers = session.playerStates.values.toList();
    final benchPlayers = availablePlayers.where((p) => !p.isOnCourt).toList();
    final onCourtPlayers = availablePlayers.where((p) => p.isOnCourt).toList();

    if (benchPlayers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Todos os atletas já estão em quadra.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final uniqueBench = <String, PlayerSubstitutionState>{};
    for (var p in benchPlayers) {
      if (p.playerId.isNotEmpty) uniqueBench[p.playerId] = p;
    }
    final cleanBenchPlayers = uniqueBench.values.toList()
      ..sort((a, b) => a.playerName.toLowerCase().compareTo(b.playerName.toLowerCase()));

    if (cleanBenchPlayers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Todos os atletas já estão em quadra.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final uniqueOnCourt = <String, PlayerSubstitutionState>{};
    for (var p in onCourtPlayers) {
      if (p.playerId.isNotEmpty) uniqueOnCourt[p.playerId] = p;
    }
    final cleanOnCourtPlayers = uniqueOnCourt.values.toList()
      ..sort((a, b) => a.playerName.toLowerCase().compareTo(b.playerName.toLowerCase()));

    PlayerSubstitutionState selectedPlayerIn = (targetPlayer != null && cleanBenchPlayers.any((p) => p.playerId == targetPlayer.playerId))
        ? targetPlayer
        : cleanBenchPlayers.first;
    String? selectedPlayerOutId;

    // Controle de tempo de entrada informado
    int entryOffsetSeconds = 0;
    final minutesController = TextEditingController(text: '0');
    final secondsController = TextEditingController(text: '0');

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.swap_horiz, color: AppTheme.primaryColor),
                            SizedBox(width: 8),
                            Text(
                              'Entrada de Atleta',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),

                    // 1. Quem entra
                    const Text(
                      'Atleta que está entrando:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () {
                        showModalBottomSheet(
                          context: ctx,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          builder: (subCtx) {
                            return Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Selecione o atleta que vai entrar:',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  const Divider(),
                                  Expanded(
                                    child: ListView.separated(
                                      itemCount: cleanBenchPlayers.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (context, idx) {
                                        final p = cleanBenchPlayers[idx];
                                        final isSel = p.playerId == selectedPlayerIn.playerId;
                                        final isSat = p.isRuleSatisfied(now: _currentTickTime);

                                        return ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: Colors.grey.shade200,
                                            backgroundImage: p.photoUrl.isNotEmpty ? NetworkImage(p.photoUrl) : null,
                                            child: p.photoUrl.isEmpty
                                                ? Text(p.playerName.isNotEmpty ? p.playerName[0].toUpperCase() : '?',
                                                    style: const TextStyle(fontWeight: FontWeight.bold))
                                                : null,
                                          ),
                                          title: Text(
                                            '${p.jerseyNumber != null ? '#${p.jerseyNumber} ' : ''}${p.playerName}',
                                            style: TextStyle(
                                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                              color: isSel ? AppTheme.primaryColor : Colors.black87,
                                            ),
                                          ),
                                          subtitle: Text(
                                            isSat ? '5 min cumpridos ✅' : 'Falta cumprir ⏳',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isSat ? Colors.green : Colors.orange,
                                            ),
                                          ),
                                          trailing: isSel ? const Icon(Icons.check_circle, color: AppTheme.primaryColor) : null,
                                          onTap: () {
                                            Navigator.pop(subCtx);
                                            setModalState(() {
                                              selectedPlayerIn = p;
                                            });
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage: selectedPlayerIn.photoUrl.isNotEmpty ? NetworkImage(selectedPlayerIn.photoUrl) : null,
                              child: selectedPlayerIn.photoUrl.isEmpty
                                  ? Text(selectedPlayerIn.playerName.isNotEmpty ? selectedPlayerIn.playerName[0].toUpperCase() : '?',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${selectedPlayerIn.jerseyNumber != null ? '#${selectedPlayerIn.jerseyNumber} ' : ''}${selectedPlayerIn.playerName}${selectedPlayerIn.isRuleSatisfied(now: _currentTickTime) ? ' (5 min OK ✅)' : ' (Falta jogar ⏳)'}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: AppTheme.primaryColor),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 2. Quem sai (Opcional - substituição clássica)
                    const Text(
                      'Atleta que está saindo (opcional):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () {
                        showModalBottomSheet(
                          context: ctx,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          builder: (subCtx) {
                            return Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Selecione quem está saindo:',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  const Divider(),
                                  ListTile(
                                    leading: const Icon(Icons.person_add_disabled, color: Colors.grey),
                                    title: const Text('Nenhum (Entrada direta)'),
                                    trailing: selectedPlayerOutId == null ? const Icon(Icons.check_circle, color: AppTheme.primaryColor) : null,
                                    onTap: () {
                                      Navigator.pop(subCtx);
                                      setModalState(() {
                                        selectedPlayerOutId = null;
                                      });
                                    },
                                  ),
                                  const Divider(height: 1),
                                  Expanded(
                                    child: ListView.separated(
                                      itemCount: cleanOnCourtPlayers.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (context, idx) {
                                        final p = cleanOnCourtPlayers[idx];
                                        final isSel = p.playerId == selectedPlayerOutId;
                                        final elapsed = p.getCurrentStintElapsedSeconds(now: _currentTickTime);
                                        final isSat = elapsed >= 300;

                                        return ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: Colors.grey.shade200,
                                            backgroundImage: p.photoUrl.isNotEmpty ? NetworkImage(p.photoUrl) : null,
                                            child: p.photoUrl.isEmpty
                                                ? Text(p.playerName.isNotEmpty ? p.playerName[0].toUpperCase() : '?',
                                                    style: const TextStyle(fontWeight: FontWeight.bold))
                                                : null,
                                          ),
                                          title: Text(
                                            '${p.jerseyNumber != null ? '#${p.jerseyNumber} ' : ''}${p.playerName}',
                                            style: TextStyle(
                                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                              color: isSel ? AppTheme.primaryColor : Colors.black87,
                                            ),
                                          ),
                                          subtitle: Text(
                                            'Tempo em quadra: ${_formatDuration(elapsed)} ${isSat ? '(5 min OK ✅)' : '(Abaixo de 5 min ⚠️)'}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isSat ? Colors.green : Colors.orange,
                                            ),
                                          ),
                                          trailing: isSel ? const Icon(Icons.check_circle, color: AppTheme.primaryColor) : null,
                                          onTap: () {
                                            Navigator.pop(subCtx);
                                            setModalState(() {
                                              selectedPlayerOutId = p.playerId;
                                            });
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selectedPlayerOutId == null ? Icons.person_add_disabled : Icons.person_remove,
                              size: 20,
                              color: selectedPlayerOutId == null ? Colors.grey : Colors.orange.shade800,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selectedPlayerOutId == null
                                    ? 'Nenhum (Entrada direta)'
                                    : () {
                                        try {
                                          final out = cleanOnCourtPlayers.firstWhere((p) => p.playerId == selectedPlayerOutId);
                                          final elapsed = out.getCurrentStintElapsedSeconds(now: _currentTickTime);
                                          final sat = elapsed >= 300;
                                          return '${out.jerseyNumber != null ? '#${out.jerseyNumber} ' : ''}${out.playerName} (${_formatDuration(elapsed)} ${sat ? '✅' : '⚠️'})';
                                        } catch (_) {
                                          return 'Nenhum (Entrada direta)';
                                        }
                                      }(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: selectedPlayerOutId == null ? FontWeight.normal : FontWeight.bold,
                                  color: selectedPlayerOutId == null ? Colors.grey.shade700 : AppTheme.secondaryColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: AppTheme.primaryColor),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 3. Tempo em que ele entrou
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tempo que ele entrou:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          entryOffsetSeconds == 0
                              ? 'Entrou agora (00:00)'
                              : 'Entrou há ${_formatDuration(entryOffsetSeconds)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: entryOffsetSeconds == 0 ? Colors.green : AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Se o atleta entrou agora, mantenha 00:00. Caso já esteja em quadra há algum tempo, informe os minutos para o cronômetro iniciar a partir desse valor.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),

                    // Atalhos rápidos
                    Wrap(
                      spacing: 6,
                      children: [
                        ActionChip(
                          label: const Text('Agora (00:00)', style: TextStyle(fontSize: 11)),
                          backgroundColor: entryOffsetSeconds == 0 ? Colors.green.shade100 : null,
                          onPressed: () {
                            setModalState(() {
                              entryOffsetSeconds = 0;
                              minutesController.text = '0';
                              secondsController.text = '0';
                            });
                          },
                        ),
                        ActionChip(
                          label: const Text('Há 1 min', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setModalState(() {
                              entryOffsetSeconds = 60;
                              minutesController.text = '1';
                              secondsController.text = '0';
                            });
                          },
                        ),
                        ActionChip(
                          label: const Text('Há 2 min', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setModalState(() {
                              entryOffsetSeconds = 120;
                              minutesController.text = '2';
                              secondsController.text = '0';
                            });
                          },
                        ),
                        ActionChip(
                          label: const Text('Há 3 min', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setModalState(() {
                              entryOffsetSeconds = 180;
                              minutesController.text = '3';
                              secondsController.text = '0';
                            });
                          },
                        ),
                        ActionChip(
                          label: const Text('Há 5 min', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setModalState(() {
                              entryOffsetSeconds = 300;
                              minutesController.text = '5';
                              secondsController.text = '0';
                            });
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Campos de digitação precisa de minutos e segundos
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minutesController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Minutos decorridos',
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (val) {
                              final m = int.tryParse(val) ?? 0;
                              final s = int.tryParse(secondsController.text) ?? 0;
                              setModalState(() {
                                entryOffsetSeconds = (m * 60) + s;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: secondsController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Segundos',
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (val) {
                              final m = int.tryParse(minutesController.text) ?? 0;
                              final s = int.tryParse(val) ?? 0;
                              setModalState(() {
                                entryOffsetSeconds = (m * 60) + s;
                              });
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Botão Salvar Substituição
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: const Text(
                          'Salvar Entrada e Iniciar Cronômetro',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _subService.recordPlayerEntry(
                            teamId: _selectedTeamId!,
                            playerId: selectedPlayerIn.playerId,
                            initialOffsetSeconds: entryOffsetSeconds,
                            playerOutId: selectedPlayerOutId,
                          );

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${selectedPlayerIn.playerName} entrou em quadra! Cronômetro iniciado.',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Diálogo de confirmação de saída do atleta (com alerta se saiu antes de 5 min)
  Future<void> _confirmPlayerExit(PlayerSubstitutionState player) async {
    final elapsed = player.getCurrentStintElapsedSeconds(now: _currentTickTime);
    final isSatisfied = elapsed >= 300;

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                isSatisfied ? Icons.check_circle : Icons.warning_amber_rounded,
                color: isSatisfied ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(isSatisfied ? 'Registrar Saída' : 'Atenção: Regra 5 Min!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Atleta: ${player.playerName}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Tempo em quadra nesta passagem: ${_formatDuration(elapsed)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isSatisfied ? Colors.green.shade800 : Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 12),
              if (!isSatisfied) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    'O regulamento exige 5 minutos contínuos.\nSe sair agora com ${_formatDuration(elapsed)}, este atleta ainda precisará cumprir 5 minutos diretos em outra entrada.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Text('Deseja confirmar a saída deste atleta para o banco?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar (Manter em Quadra)'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isSatisfied ? Colors.green : Colors.orange.shade800,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar Saída', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (shouldExit == true && _selectedTeamId != null) {
      await _subService.recordPlayerExit(
        teamId: _selectedTeamId!,
        playerId: player.playerId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saída de ${player.playerName} registrada (${_formatDuration(elapsed)}).',
            ),
            backgroundColor: isSatisfied ? Colors.green : Colors.orange,
          ),
        );
      }
    }
  }

  /// Diálogo para ajustar manualmente os minutos do atleta (correções)
  Future<void> _openAdjustTimeModal(PlayerSubstitutionState player) async {
    final controller = TextEditingController(text: '60');
    bool isAdding = true;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Ajustar Tempo - ${player.playerName}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Adicione ou remova segundos para corrigir o tempo do atleta.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('+ Adicionar'),
                        selected: isAdding,
                        selectedColor: Colors.green,
                        labelStyle: TextStyle(
                          color: isAdding ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (val) => setDialogState(() => isAdding = true),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('- Subtrair'),
                        selected: !isAdding,
                        selectedColor: Colors.red,
                        labelStyle: TextStyle(
                          color: !isAdding ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (val) => setDialogState(() => isAdding = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Segundos (ex: 60 = 1 min, 120 = 2 min)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final sec = int.tryParse(controller.text) ?? 0;
                    final delta = isAdding ? sec : -sec;
                    Navigator.pop(ctx);

                    if (_selectedTeamId != null) {
                      await _subService.adjustPlayerTime(
                        teamId: _selectedTeamId!,
                        playerId: player.playerId,
                        additionalSeconds: delta,
                      );
                    }
                  },
                  child: const Text('Salvar Ajuste'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Diálogo com o relatório completo da partida para conferência e cópia para WhatsApp
  Future<void> _openReportModal() async {
    if (_selectedTeamId == null) return;
    final session = await _subService.getSession(_selectedTeamId!);
    if (session == null) return;

    final players = session.playerStates.values.toList()
      ..sort((a, b) => a.playerName.compareTo(b.playerName));

    final satisfiedList = players.where((p) => p.isRuleSatisfied(now: _currentTickTime)).toList();
    final pendingList = players.where((p) => !p.isRuleSatisfied(now: _currentTickTime)).toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Relatório de Substituições (5 Min)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Resumo em texto rápido
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text('Equipe: ${session.teamName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('OK: ${satisfiedList.length}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        Text('Pendentes: ${pendingList.length}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        if (pendingList.isNotEmpty) ...[
                          const Text(
                            '⚠️ PENDENTES (Ainda precisam dos 5 min diretos):',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                          ),
                          const SizedBox(height: 6),
                          ...pendingList.map((p) {
                            final continuous = p.getEffectiveContinuousSeconds(now: _currentTickTime);
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.hourglass_bottom, color: Colors.orange),
                              title: Text('${p.jerseyNumber != null ? '#${p.jerseyNumber} ' : ''}${p.playerName}'),
                              subtitle: Text(p.isOnCourt
                                  ? 'Em quadra agora (${_formatDuration(p.getCurrentStintElapsedSeconds(now: _currentTickTime))})'
                                  : 'Maior passagem direta: ${_formatDuration(continuous)}'),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('Falta cumprir', style: TextStyle(fontSize: 10, color: Colors.orange)),
                              ),
                            );
                          }),
                          const SizedBox(height: 16),
                        ],

                        const Text(
                          '✅ CUMPRIRAM A REGRA DOS 5 MINUTOS:',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                        const SizedBox(height: 6),
                        ...satisfiedList.map((p) {
                          final continuous = p.getEffectiveContinuousSeconds(now: _currentTickTime);
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.check_circle, color: Colors.green),
                            title: Text('${p.jerseyNumber != null ? '#${p.jerseyNumber} ' : ''}${p.playerName}'),
                            subtitle: Text('Tempo contínuo registrado: ${_formatDuration(continuous)}'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Apto / OK', style: TextStyle(fontSize: 10, color: Colors.green)),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Botão de Copiar Relatório
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.copy, color: Colors.white),
                      label: const Text(
                        'Copiar Resumo para WhatsApp',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        final buffer = StringBuffer();
                        buffer.writeln('📋 *CONTROLE DE SUBSTITUIÇÕES - REGRA 5 MINUTOS*');
                        buffer.writeln('Equipe: ${session.teamName}');
                        buffer.writeln('Data: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}');
                        buffer.writeln('\n✅ *ATLETAS COM 5 MIN CUMPRIDOS:*');
                        for (var p in satisfiedList) {
                          buffer.writeln('• ${p.playerName} (${_formatDuration(p.getEffectiveContinuousSeconds(now: _currentTickTime))})');
                        }
                        if (pendingList.isNotEmpty) {
                          buffer.writeln('\n⚠️ *ATLETAS PENDENTES (FALTA JOGAR 5 MIN):*');
                          for (var p in pendingList) {
                            buffer.writeln('• ${p.playerName} (${_formatDuration(p.getEffectiveContinuousSeconds(now: _currentTickTime))})');
                          }
                        }
                        Clipboard.setData(ClipboardData(text: buffer.toString()));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Relatório copiado para a área de transferência!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Diálogo para resetar a partida
  Future<void> _confirmResetSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.restart_alt, color: Colors.red),
              SizedBox(width: 8),
              Text('Nova Partida / Resetar'),
            ],
          ),
          content: const Text(
            'Tem certeza que deseja zerar os cronômetros e histórico de substituições?\nEssa ação é recomendada apenas ao iniciar um novo jogo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Zerar e Iniciar Nova', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirm == true && _selectedTeamId != null) {
      if (!mounted) return;
      final champService = Provider.of<ChampionshipService>(context, listen: false);
      final roster = champService.getCachedRoster(_selectedTeamId!);
      Team? team;
      try {
        team = champService.teams.firstWhere((t) => t.id == _selectedTeamId);
      } catch (_) {}

      await _subService.resetSession(
        teamId: _selectedTeamId!,
        teamName: team?.name ?? 'Equipe',
        roster: roster,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sessão resetada para nova partida!'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }
  }
}
