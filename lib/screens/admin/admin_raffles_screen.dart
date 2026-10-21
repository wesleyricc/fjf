import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/team_model.dart';
import '../../models/player_model.dart';
import '../../services/championship_service.dart';
import '../../services/raffle_service.dart';
import '../../widgets/team_logo_widget.dart';
import '../../widgets/celebration_particles_widget.dart';

class AdminRafflesScreen extends StatefulWidget {
  const AdminRafflesScreen({super.key});

  @override
  State<AdminRafflesScreen> createState() => _AdminRafflesScreenState();
}

class _AdminRafflesScreenState extends State<AdminRafflesScreen>
    with SingleTickerProviderStateMixin {
  final RaffleService _raffleService = RaffleService();

  // Estados de dados
  bool _isLoading = true;
  String _selectedSeasonId = '';
  String _selectedSeasonName = '';
  List<Map<String, dynamic>> _seasons = [];
  List<Team> _teams = [];
  Set<String> _selectedTeamIds = {};
  List<Player> _athletes = [];

  List<Team> get _participatingTeams =>
      _teams.where((t) => _selectedTeamIds.contains(t.id)).toList();


  // Configurações do Sorteio
  RaffleMode _currentMode = RaffleMode.team;
  bool _excludeStaff = true;
  bool _activeOnly = true;
  bool _enableSuspense = true;

  // Time opcional pré-selecionado para o Modo 3 (Time + Atleta)
  Team? _preselectedTeamForMode3;

  // Estado da Animação / Roleta
  bool _isRolling = false;
  Timer? _rouletteTimer;
  int _rouletteCounter = 0;
  String _tickerTeamName = '';
  String _tickerAthleteName = '';
  String? _tickerTeamLogo;
  String? _tickerAthletePhoto;

  // Resultado
  RaffleResult? _currentResult;
  bool _showCelebration = false;

  // Histórico da sessão
  final List<RaffleResult> _sessionHistory = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initData());
  }

  @override
  void dispose() {
    _rouletteTimer?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // 🔄 CARREGAMENTO DE DADOS
  // ===========================================================================

  Future<void> _initData() async {
    setState(() => _isLoading = true);

    final champService = Provider.of<ChampionshipService>(context, listen: false);

    // 1. Temporadas
    List<Map<String, dynamic>> seasons = champService.availableSeasons;
    if (seasons.isEmpty) {
      seasons = await _raffleService.fetchSeasons();
    }
    _seasons = seasons;

    // 2. Temporada inicial (atual do app ou a primeira ativa)
    String initialSeasonId = champService.currentSeasonId;
    if (initialSeasonId.isEmpty && _seasons.isNotEmpty) {
      final active = _seasons.firstWhere(
        (s) => s['isActive'] == true,
        orElse: () => _seasons.first,
      );
      initialSeasonId = active['id'] ?? '';
    }

    _selectedSeasonId = initialSeasonId;
    _updateSelectedSeasonName();

    await _loadSeasonData(_selectedSeasonId);
  }

  void _updateSelectedSeasonName() {
    final s = _seasons.firstWhere(
      (item) => item['id'] == _selectedSeasonId,
      orElse: () => {'name': _selectedSeasonId},
    );
    _selectedSeasonName = s['name']?.toString() ?? _selectedSeasonId;
  }

  Future<void> _loadSeasonData(String seasonId) async {
    if (seasonId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final teams = await _raffleService.fetchTeams(seasonId);
      final athletes = await _raffleService.fetchAthletes(
        seasonId,
        activeOnly: _activeOnly,
        excludeStaff: _excludeStaff,
      );

      if (mounted) {
        setState(() {
          _teams = teams;
          _selectedTeamIds = teams.map((t) => t.id).toSet();
          _athletes = athletes;
          _preselectedTeamForMode3 = null;
          _isLoading = false;
        });

        // Pré-carrega as imagens dos times na memória para exibição imediata
        for (final team in teams) {
          if (team.shieldUrl.isNotEmpty && mounted) {
            precacheImage(NetworkImage(team.shieldUrl), context)
                .catchError((_) {});
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados da temporada: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ===========================================================================
  // 🎲 EXECUÇÃO DO SORTEIO
  // ===========================================================================

  Future<void> _executeDraw() async {
    if (_isRolling) return;

    // Validações de pool
    if (_currentMode == RaffleMode.team) {
      if (_teams.isEmpty) {
        _showEmptyPoolAlert('Nenhuma equipe cadastrada para a temporada selecionada.');
        return;
      }
      if (_participatingTeams.isEmpty) {
        _showEmptyPoolAlert('Nenhuma equipe selecionada para participar do sorteio. Por favor, defina as equipes participantes.');
        return;
      }
    }

    if (_currentMode == RaffleMode.athlete && _athletes.isEmpty) {
      _showEmptyPoolAlert('Nenhum atleta cadastrado com os filtros ativos para esta temporada.');
      return;
    }

    if (_currentMode == RaffleMode.teamAndAthlete && _teams.isEmpty) {
      _showEmptyPoolAlert('Nenhuma equipe disponível para sortear.');
      return;
    }

    // Se suspense estiver ativado, roda a roleta por 2.2 segundos
    if (_enableSuspense) {
      await _runRouletteSuspense();
    }

    // Calcula o sorteado final
    RaffleResult? result;

    switch (_currentMode) {
      case RaffleMode.team:
        final team = _raffleService.drawRandomTeam(_participatingTeams);
        if (team != null) {
          result = RaffleResult(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            mode: _currentMode,
            seasonId: _selectedSeasonId,
            seasonName: _selectedSeasonName,
            team: team,
            drawnAt: DateTime.now(),
          );
        }
        break;

      case RaffleMode.athlete:
        final athlete = _raffleService.drawRandomAthlete(_athletes);
        if (athlete != null) {
          result = RaffleResult(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            mode: _currentMode,
            seasonId: _selectedSeasonId,
            seasonName: _selectedSeasonName,
            athlete: athlete,
            drawnAt: DateTime.now(),
          );
        }
        break;

      case RaffleMode.teamAndAthlete:
        final pair = _raffleService.drawRandomTeamAndAthlete(
          teams: _participatingTeams.isNotEmpty ? _participatingTeams : _teams,
          athletes: _athletes,
          preselectedTeam: _preselectedTeamForMode3,
        );

        if (pair.team != null) {
          result = RaffleResult(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            mode: _currentMode,
            seasonId: _selectedSeasonId,
            seasonName: _selectedSeasonName,
            team: pair.team,
            athlete: pair.athlete,
            drawnAt: DateTime.now(),
          );
        }
        break;
    }

    if (result != null && mounted) {
      HapticFeedback.heavyImpact();
      setState(() {
        _currentResult = result;
        _sessionHistory.insert(0, result!);
        _showCelebration = true;
      });
    }
  }

  Future<void> _runRouletteSuspense() async {
    final completer = Completer<void>();
    _rouletteCounter = 0;
    setState(() {
      _isRolling = true;
      _showCelebration = false;
    });

    const totalSteps = 24;
    const initialIntervalMs = 50;
    int currentInterval = initialIntervalMs;

    void tick() {
      if (!mounted || !_isRolling) {
        if (!completer.isCompleted) completer.complete();
        return;
      }

      _rouletteCounter++;

      // Atualiza os valores do ticker com itens aleatórios
      setState(() {
        final teamsPool =
            _participatingTeams.isNotEmpty ? _participatingTeams : _teams;
        if (teamsPool.isNotEmpty) {
          final t = _raffleService.drawRandomTeam(teamsPool);
          _tickerTeamName = t?.name ?? '';
          _tickerTeamLogo = t?.shieldUrl;
        }
        if (_athletes.isNotEmpty) {
          final a = _raffleService.drawRandomAthlete(_athletes);
          _tickerAthleteName = a?.name ?? '';
          _tickerAthletePhoto = a?.photoUrl;
        }
      });

      HapticFeedback.selectionClick();

      if (_rouletteCounter >= totalSteps) {
        setState(() => _isRolling = false);
        if (!completer.isCompleted) completer.complete();
      } else {
        // Desaceleração progressiva (easing out)
        if (_rouletteCounter > 15) {
          currentInterval += 25;
        } else if (_rouletteCounter > 8) {
          currentInterval += 10;
        }
        _rouletteTimer = Timer(Duration(milliseconds: currentInterval), tick);
      }
    }

    _rouletteTimer = Timer(Duration(milliseconds: currentInterval), tick);
    return completer.future;
  }

  void _skipRoulette() {
    _rouletteTimer?.cancel();
    if (mounted) {
      setState(() => _isRolling = false);
    }
  }

  void _showEmptyPoolAlert(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('Sem Dados'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 📋 AÇÕES DO RESULTADO (COPIAR E COMPARTILHAR)
  // ===========================================================================

  Future<void> _copyResult(RaffleResult result) async {
    await Clipboard.setData(ClipboardData(text: result.summaryText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resultado copiado para a área de transferência! 📋'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _shareResult(RaffleResult result) async {
    try {
      await Share.share(
        result.summaryText,
        subject: 'Resultado do Sorteio FJF - ${result.seasonName}',
      );
    } catch (e) {
      debugPrint('Erro ao compartilhar resultado: $e');
    }
  }

  // ===========================================================================
  // 🎨 CONSTRUÇÃO DA TELA (BUILD)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Sorteios da Temporada',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar dados',
            onPressed: () => _loadSeasonData(_selectedSeasonId),
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _sessionHistory.isNotEmpty,
              label: Text('${_sessionHistory.length}'),
              child: const Icon(Icons.history),
            ),
            tooltip: 'Histórico da sessão',
            onPressed: _showHistoryModal,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Carregando equipes e atletas da temporada...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. BARRA DE SELEÇÃO DA TEMPORADA E CONTADORES
                  _buildSeasonSelectorCard(),
                  const SizedBox(height: 16),

                  // 2. SELETOR DE MODALIDADE (AS 3 OPÇÕES SOLICITADAS)
                  _buildModeSelector(),
                  const SizedBox(height: 16),

                  // 3. PAINEL DE CONFIGURAÇÕES / FILTROS
                  _buildFiltersCard(),
                  const SizedBox(height: 20),

                  // 4. PALCO DO SORTEIO (RESULTADO OU ROLETADOR)
                  CelebrationParticlesWidget(
                    isPlaying: _showCelebration,
                    child: _isRolling
                        ? _buildRouletteCard()
                        : _currentResult != null
                            ? _buildWinnerCard(_currentResult!)
                            : _buildReadyToDrawCard(),
                  ),

                  const SizedBox(height: 24),

                  // 5. BOTÃO PRINCIPAL DE AÇÃO
                  _buildMainActionButton(),

                  const SizedBox(height: 32),

                  // 6. HISTÓRICO RÁPIDO DA SESSÃO
                  if (_sessionHistory.isNotEmpty) _buildRecentHistorySection(),
                ],
              ),
            ),
    );
  }

  // ===========================================================================
  // 🧩 WIDGETS AUXILIARES
  // ===========================================================================

  Widget _buildSeasonSelectorCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: Colors.amber[800], size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Temporada do Sorteio',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _seasons.any((s) => s['id'] == _selectedSeasonId)
                  ? _selectedSeasonId
                  : (_seasons.isNotEmpty ? _seasons.first['id'] : null),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              items: _seasons.map((s) {
                final bool isActive = s['isActive'] == true;
                return DropdownMenuItem<String>(
                  value: s['id'],
                  child: Row(
                    children: [
                      Text(
                        s['name'] ?? s['id'],
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Ativa',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
              onChanged: (newSeasonId) {
                if (newSeasonId != null && newSeasonId != _selectedSeasonId) {
                  setState(() {
                    _selectedSeasonId = newSeasonId;
                    _updateSelectedSeasonName();
                    _currentResult = null;
                  });
                  _loadSeasonData(newSeasonId);
                }
              },
            ),
            const SizedBox(height: 12),
            // Contadores rápidos de disponibilidade
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildInfoBadge(
                  icon: Icons.shield,
                  color: Colors.blue,
                  label: _selectedTeamIds.length == _teams.length
                      ? '${_teams.length} Equipes cadastradas'
                      : '${_selectedTeamIds.length}/${_teams.length} Equipes no sorteio',
                ),
                _buildInfoBadge(
                  icon: Icons.person,
                  color: Colors.teal,
                  label: '${_athletes.length} Atletas aptos',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBadge({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'OPÇÕES DE SORTEIO',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              _buildModeOptionTile(
                mode: RaffleMode.team,
                icon: Icons.shield,
                iconColor: Colors.blue,
                title: 'Sortear 1 Time',
                subtitle: _selectedTeamIds.length == _teams.length
                    ? 'Sorteia aleatoriamente uma equipe participante'
                    : 'Sorteia entre as ${_selectedTeamIds.length} equipes selecionadas',
              ),
              const Divider(height: 1, indent: 56),
              _buildModeOptionTile(
                mode: RaffleMode.athlete,
                icon: Icons.person,
                iconColor: Colors.teal,
                title: 'Sortear 1 Atleta',
                subtitle: 'Sorteia um atleta entre todas as equipes da temporada',
              ),
              const Divider(height: 1, indent: 56),
              _buildModeOptionTile(
                mode: RaffleMode.teamAndAthlete,
                icon: Icons.groups,
                iconColor: Colors.deepPurple,
                title: 'Sortear 1 Time e um Atleta',
                subtitle: 'Sorteia a equipe e, em seguida, um atleta dessa equipe',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeOptionTile({
    required RaffleMode mode,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    final bool isSelected = _currentMode == mode;
    return InkWell(
      onTap: () {
        if (_isRolling) return;
        setState(() {
          _currentMode = mode;
          _currentResult = null;
          _showCelebration = false;
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? iconColor.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? iconColor : iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isSelected ? iconColor : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Radio<RaffleMode>(
              value: mode,
              groupValue: _currentMode,
              activeColor: iconColor,
              onChanged: _isRolling
                  ? null
                  : (val) {
                      if (val != null) {
                        setState(() {
                          _currentMode = val;
                          _currentResult = null;
                          _showCelebration = false;
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 16, color: Colors.blueGrey.shade700),
                const SizedBox(width: 6),
                Text(
                  'Ajustes do Sorteio',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Animação de Suspense (Roleta)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Gera efeito de roleta antes de revelar',
                  style: TextStyle(fontSize: 11)),
              value: _enableSuspense,
              activeColor: Colors.deepPurple,
              onChanged: _isRolling
                  ? null
                  : (v) => setState(() => _enableSuspense = v),
            ),
            if (_currentMode != RaffleMode.team) ...[
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Excluir Comissão Técnica',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: const Text('Considera apenas jogadores de linha e goleiros',
                    style: TextStyle(fontSize: 11)),
                value: _excludeStaff,
                activeColor: Colors.teal,
                onChanged: _isRolling
                    ? null
                    : (v) {
                        setState(() => _excludeStaff = v);
                        _loadSeasonData(_selectedSeasonId);
                      },
              ),
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Apenas Atletas Ativos',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: const Text('Ignora atletas inativos no elenco',
                    style: TextStyle(fontSize: 11)),
                value: _activeOnly,
                activeColor: Colors.blue,
                onChanged: _isRolling
                    ? null
                    : (v) {
                        setState(() => _activeOnly = v);
                        _loadSeasonData(_selectedSeasonId);
                      },
              ),
            ],
            // Opção extra para Modo 1 (e Modo 3 sem time fixo): definir equipes participantes
            if (_currentMode == RaffleMode.team || _currentMode == RaffleMode.teamAndAthlete) ...[
              const Divider(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield, size: 18, color: Colors.blue),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Equipes no Sorteio',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _selectedTeamIds.length == _teams.length
                              ? 'Todas as ${_teams.length} equipes participando'
                              : '${_selectedTeamIds.length} de ${_teams.length} equipes selecionadas',
                          style: TextStyle(
                            fontSize: 11,
                            color: _selectedTeamIds.isEmpty
                                ? Colors.red
                                : (_selectedTeamIds.length == _teams.length
                                    ? Colors.grey.shade600
                                    : Colors.blue.shade700),
                            fontWeight: _selectedTeamIds.length != _teams.length
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _teams.isEmpty || _isRolling
                        ? null
                        : _showSelectTeamsDialog,
                    icon: const Icon(Icons.checklist, size: 16),
                    label: const Text('Definir Equipes'),
                  ),
                ],
              ),
              if (_teams.isNotEmpty && _selectedTeamIds.length < _teams.length) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ..._participatingTeams.take(5).map((team) => Chip(
                          avatar: TeamLogoWidget(logoUrl: team.shieldUrl, radius: 10),
                          label: Text(
                            team.shortName.isNotEmpty ? team.shortName : team.name,
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: Colors.blue.shade50,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        )),
                    if (_participatingTeams.length > 5)
                      Chip(
                        label: Text(
                          '+${_participatingTeams.length - 5}',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: Colors.blue.shade50,
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.restart_alt, size: 14, color: Colors.blue),
                      label: const Text(
                        'Restaurar Todas',
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.blue.shade200),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: _isRolling
                          ? null
                          : () {
                              setState(() {
                                _selectedTeamIds = _teams.map((t) => t.id).toSet();
                              });
                            },
                    ),
                  ],
                ),
              ],
            ],
            // Opção extra para Modo 3: fixar time manualmente se desejar
            if (_currentMode == RaffleMode.teamAndAthlete) ...[
              const Divider(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Equipe Alvo (Opcional)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _preselectedTeamForMode3 == null
                              ? 'Aleatória (sorteará o time primeiro)'
                              : 'Fixado em: ${_preselectedTeamForMode3!.name}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  if (_preselectedTeamForMode3 != null)
                    TextButton(
                      onPressed: () =>
                          setState(() => _preselectedTeamForMode3 = null),
                      child: const Text('Resetar', style: TextStyle(fontSize: 12)),
                    )
                  else
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      onPressed: _showPickTeamDialog,
                      child: const Text('Escolher Time'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showPickTeamDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fixar Equipe Específica'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _teams.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, idx) {
              final team = _teams[idx];
              return ListTile(
                leading: TeamLogoWidget(logoUrl: team.shieldUrl, radius: 18),
                title: Text(team.name, style: const TextStyle(fontSize: 14)),
                onTap: () {
                  setState(() => _preselectedTeamForMode3 = team);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  void _showSelectTeamsDialog() {
    final tempSelected = Set<String>.from(_selectedTeamIds);
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredTeams = _teams.where((team) {
              if (searchQuery.trim().isEmpty) return true;
              final q = searchQuery.toLowerCase().trim();
              return team.name.toLowerCase().contains(q) ||
                  team.shortName.toLowerCase().contains(q);
            }).toList();

            final int totalSelected = tempSelected.length;
            final bool allSelected =
                tempSelected.length == _teams.length && _teams.isNotEmpty;

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Cabeçalho
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.shield,
                                color: Colors.blue.shade700, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Definir Equipes no Sorteio',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '$totalSelected de ${_teams.length} equipes selecionadas',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: totalSelected == 0
                                        ? Colors.red
                                        : Colors.grey.shade600,
                                    fontWeight: totalSelected == 0
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Fechar',
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Campo de busca
                      if (_teams.length > 5) ...[
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'Buscar equipe por nome...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          onChanged: (val) {
                            setModalState(() {
                              searchQuery = val;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Botões rápidos: Marcar todas / Desmarcar todas
                      Row(
                        children: [
                          TextButton.icon(
                            icon: Icon(
                              allSelected ? Icons.deselect : Icons.select_all,
                              size: 16,
                            ),
                            label: Text(
                              allSelected
                                  ? 'Desmarcar Todas'
                                  : 'Selecionar Todas',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () {
                              setModalState(() {
                                if (allSelected) {
                                  tempSelected.clear();
                                } else {
                                  tempSelected.clear();
                                  tempSelected.addAll(_teams.map((t) => t.id));
                                }
                              });
                            },
                          ),
                          const Spacer(),
                          if (totalSelected == 0)
                            const Text(
                              'Nenhum time marcado',
                              style: TextStyle(fontSize: 11, color: Colors.red),
                            ),
                        ],
                      ),
                      const Divider(height: 8),

                      // Lista com checkboxes
                      Flexible(
                        child: filteredTeams.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(24.0),
                                child: Center(
                                  child: Text('Nenhuma equipe encontrada.'),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filteredTeams.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final team = filteredTeams[index];
                                  final isChecked =
                                      tempSelected.contains(team.id);

                                  return CheckboxListTile(
                                    value: isChecked,
                                    activeColor: Colors.blue.shade700,
                                    dense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                    secondary: TeamLogoWidget(
                                      logoUrl: team.shieldUrl,
                                      radius: 18,
                                    ),
                                    title: Text(
                                      team.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isChecked
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: team.shortName.isNotEmpty
                                        ? Text(
                                            team.shortName,
                                            style: const TextStyle(
                                                fontSize: 12),
                                          )
                                        : null,
                                    onChanged: (bool? val) {
                                      setModalState(() {
                                        if (val == true) {
                                          tempSelected.add(team.id);
                                        } else {
                                          tempSelected.remove(team.id);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // Botões de confirmação
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: totalSelected == 0
                                ? null
                                : () {
                                    setState(() {
                                      _selectedTeamIds = tempSelected;
                                    });
                                    Navigator.pop(ctx);
                                  },
                            child: Text(
                              'Confirmar ($totalSelected)',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // 🎰 ROLETADOR / SUSPENSE EM ANDAMENTO
  // ===========================================================================

  Widget _buildRouletteCard() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.deepPurple, width: 2),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Colors.deepPurple.shade900,
              Colors.deepPurple.shade700,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.amber,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'SORTEANDO...',
                      style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _skipRoulette,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Pular', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Ícone animado
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.amber, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: _currentMode == RaffleMode.team
                    ? TeamLogoWidget(logoUrl: _tickerTeamLogo, radius: 36)
                    : _tickerAthletePhoto != null &&
                            _tickerAthletePhoto!.isNotEmpty
                        ? ClipOval(
                            child: kIsWeb
                                ? Image.network(
                                    _tickerAthletePhoto!,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.person,
                                      color: Colors.grey,
                                      size: 40,
                                    ),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: _tickerAthletePhoto!,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const Icon(
                                      Icons.person,
                                      color: Colors.grey,
                                      size: 40,
                                    ),
                                  ),
                          )
                        : const Icon(Icons.casino, color: Colors.amber, size: 40),
              ),
            ),
            const SizedBox(height: 16),

            // Nome girando
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 60),
              child: Text(
                _currentMode == RaffleMode.team
                    ? (_tickerTeamName.isNotEmpty
                        ? _tickerTeamName
                        : 'Buscando equipe...')
                    : (_tickerAthleteName.isNotEmpty
                        ? _tickerAthleteName
                        : 'Buscando atleta...'),
                key: ValueKey('$_tickerTeamName-$_tickerAthleteName'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Aguarde a desaceleração da roleta...',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 🏆 TELA DE RESULTADO / VENCEDOR
  // ===========================================================================

  Widget _buildWinnerCard(RaffleResult result) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFFFD700), width: 2.5),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF2A1110), Color(0xFF4A1A18)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            // Faixa comemorativa dourada
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(17),
                  topRight: Radius.circular(17),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.emoji_events, color: Colors.black87, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'VENCEDOR DO SORTEIO',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  // Conteúdo de acordo com a modalidade
                  if (result.mode == RaffleMode.team)
                    _buildTeamWinnerContent(result.team!)
                  else if (result.mode == RaffleMode.athlete)
                    _buildAthleteWinnerContent(result.athlete!)
                  else
                    _buildTeamAndAthleteWinnerContent(
                        result.team, result.athlete),

                  const SizedBox(height: 20),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 14),

                  // Barra de ações do resultado
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withOpacity(0.12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => _copyResult(result),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copiar'),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withOpacity(0.12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => _shareResult(result),
                        icon: const Icon(Icons.share, size: 16),
                        label: const Text('Compartilhar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamWinnerContent(Team team) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: const Color(0xFFFFD700), width: 3.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.4),
                blurRadius: 18,
                spreadRadius: 4,
              ),
            ],
          ),
          child: TeamLogoWidget(logoUrl: team.shieldUrl, radius: 48),
        ),
        const SizedBox(height: 16),
        Text(
          team.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (team.shortName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              team.shortName,
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          _selectedTeamIds.length < _teams.length
              ? 'Sorteada entre as ${_selectedTeamIds.length} equipes selecionadas ($_selectedSeasonName)'
              : 'Equipe sorteada na temporada $_selectedSeasonName',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildAthleteWinnerContent(Player athlete) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFFFFD700).withOpacity(0.8), width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.3),
                    blurRadius: 16,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: ClipOval(
                child: athlete.photoUrl.isNotEmpty
                    ? (kIsWeb
                        ? Image.network(
                            athlete.photoUrl,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 90,
                              height: 90,
                              color: Colors.white24,
                              child: const Icon(Icons.person,
                                  size: 50, color: Colors.white),
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: athlete.photoUrl,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 90,
                              height: 90,
                              color: Colors.white24,
                              child: const Icon(Icons.person,
                                  size: 50, color: Colors.white),
                            ),
                          ))
                    : Container(
                        width: 90,
                        height: 90,
                        color: Colors.white24,
                        child: const Icon(Icons.person,
                            size: 50, color: Colors.white),
                      ),
              ),
            ),
            if (athlete.jerseyNumber != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.brown.shade900, width: 1.5),
                ),
                child: Text(
                  '#${athlete.jerseyNumber}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Colors.brown.shade900,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          athlete.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        if (athlete.position != null && athlete.position!.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              athlete.position!,
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        const SizedBox(height: 10),
        if (athlete.teamName.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (athlete.teamShieldUrl.isNotEmpty) ...[
                TeamLogoWidget(logoUrl: athlete.teamShieldUrl, radius: 12),
                const SizedBox(width: 6),
              ],
              Text(
                athlete.teamName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildTeamAndAthleteWinnerContent(Team? team, Player? athlete) {
    return Column(
      children: [
        // 1. Time Sorteado
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              TeamLogoWidget(logoUrl: team?.shieldUrl, radius: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EQUIPE SORTEADA',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      team?.name ?? 'Equipe não identificada',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),
        const Icon(Icons.arrow_downward, color: Color(0xFFFFD700), size: 20),
        const SizedBox(height: 14),

        // 2. Atleta Sorteado daquela Equipe
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              ClipOval(
                child: (athlete?.photoUrl.isNotEmpty ?? false)
                    ? (kIsWeb
                        ? Image.network(
                            athlete!.photoUrl,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 52,
                              height: 52,
                              color: Colors.white24,
                              child:
                                  const Icon(Icons.person, color: Colors.white),
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: athlete!.photoUrl,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 52,
                              height: 52,
                              color: Colors.white24,
                              child:
                                  const Icon(Icons.person, color: Colors.white),
                            ),
                          ))
                    : Container(
                        width: 52,
                        height: 52,
                        color: Colors.white24,
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ATLETA DA EQUIPE',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      athlete != null
                          ? '${athlete.jerseyNumber != null ? '#${athlete.jerseyNumber} ' : ''}${athlete.name}'
                          : 'Nenhum atleta ativo encontrado para este time',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (athlete?.position != null &&
                        athlete!.position!.isNotEmpty)
                      Text(
                        athlete.position!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 🏁 CARD DE ESPERA (PRONTO PARA SORTEAR)
  // ===========================================================================

  Widget _buildReadyToDrawCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.amber.shade200, width: 2),
              ),
              child: Icon(
                Icons.casino,
                size: 48,
                color: Colors.amber.shade800,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _currentMode.description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pressione o botão abaixo para sortear de forma 100% aleatória e auditada.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            if (_currentMode == RaffleMode.team) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _selectedTeamIds.isEmpty
                      ? Colors.red.shade50
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedTeamIds.isEmpty
                        ? Colors.red.shade200
                        : Colors.blue.shade200,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _selectedTeamIds.isEmpty
                          ? Icons.warning_amber
                          : Icons.shield,
                      size: 16,
                      color: _selectedTeamIds.isEmpty
                          ? Colors.red
                          : Colors.blue.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _selectedTeamIds.length == _teams.length
                          ? 'Participando: Todas as ${_teams.length} equipes'
                          : 'Participando: ${_selectedTeamIds.length} de ${_teams.length} equipes selecionadas',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _selectedTeamIds.isEmpty
                            ? Colors.red.shade800
                            : Colors.blue.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 🔘 BOTÃO PRINCIPAL DE AÇÃO
  // ===========================================================================

  Widget _buildMainActionButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFC25F22), // Laranja Fogo FJF
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      onPressed: _isRolling ? null : _executeDraw,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _currentResult != null ? Icons.replay : Icons.casino,
            size: 24,
          ),
          const SizedBox(width: 10),
          Text(
            _currentResult != null ? 'SORTEAR NOVAMENTE' : 'REALIZAR SORTEIO',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 📜 SEÇÃO E MODAL DE HISTÓRICO
  // ===========================================================================

  Widget _buildRecentHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'HISTÓRICO DESTA SESSÃO',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
                letterSpacing: 1.0,
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() => _sessionHistory.clear());
              },
              child: const Text('Limpar', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        Card(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _sessionHistory.length > 5 ? 5 : _sessionHistory.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
            itemBuilder: (ctx, idx) {
              final item = _sessionHistory[idx];
              return _buildHistoryListTile(item);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryListTile(RaffleResult item) {
    String title = '';
    String? subtitle;
    Widget leadingWidget;

    switch (item.mode) {
      case RaffleMode.team:
        title = item.team?.name ?? 'Time';
        subtitle = 'Sorteio de Equipe';
        leadingWidget =
            TeamLogoWidget(logoUrl: item.team?.shieldUrl, radius: 18);
        break;
      case RaffleMode.athlete:
        title = item.athlete?.name ?? 'Atleta';
        subtitle = item.athlete?.teamName;
        leadingWidget = const CircleAvatar(
          backgroundColor: Colors.teal,
          radius: 18,
          child: Icon(Icons.person, color: Colors.white, size: 20),
        );
        break;
      case RaffleMode.teamAndAthlete:
        title = '${item.team?.name} -> ${item.athlete?.name}';
        subtitle = 'Time + Atleta';
        leadingWidget =
            TeamLogoWidget(logoUrl: item.team?.shieldUrl, radius: 18);
        break;
    }

    return ListTile(
      leading: leadingWidget,
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 12))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copiar',
            onPressed: () => _copyResult(item),
          ),
          IconButton(
            icon: const Icon(Icons.share, size: 18),
            tooltip: 'Compartilhar',
            onPressed: () => _shareResult(item),
          ),
        ],
      ),
      onTap: () {
        setState(() {
          _currentResult = item;
          _showCelebration = false;
        });
      },
    );
  }

  void _showHistoryModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Histórico Completo da Sessão',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (_sessionHistory.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setState(() => _sessionHistory.clear());
                          setModalState(() {});
                          Navigator.pop(context);
                        },
                        child: const Text('Limpar Tudo'),
                      ),
                  ],
                ),
                const Divider(),
                if (_sessionHistory.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Nenhum sorteio realizado ainda nesta sessão.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: _sessionHistory.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 56),
                      itemBuilder: (context, idx) {
                        return _buildHistoryListTile(_sessionHistory[idx]);
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
