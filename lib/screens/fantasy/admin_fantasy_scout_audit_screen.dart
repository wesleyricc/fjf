import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/fantasy_audit_models.dart';
import '../../services/auth_service.dart';
import '../../services/championship_service.dart';
import '../../services/fantasy_service.dart';
import '../../utils/app_feedback.dart';
import '../../utils/custom_cache_manager.dart';
import '../../viewmodels/fantasy_audit_viewmodel.dart';

class AdminFantasyScoutAuditScreen extends StatefulWidget {
  const AdminFantasyScoutAuditScreen({super.key});

  @override
  State<AdminFantasyScoutAuditScreen> createState() =>
      _AdminFantasyScoutAuditScreenState();
}

class _AdminFantasyScoutAuditScreenState
    extends State<AdminFantasyScoutAuditScreen>
    with SingleTickerProviderStateMixin {
  late final FantasyAuditViewModel _viewModel;
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  String _currentSeasonId = '';
  int _currentRound = 1;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _viewModel = FantasyAuditViewModel();
    _tabController = TabController(length: 4, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initScreen();
    });
  }

  void _initScreen() async {
    final champService =
        Provider.of<ChampionshipService>(context, listen: false);
    _currentSeasonId = champService.currentSeasonId;

    try {
      final statusStream =
          Provider.of<FantasyService>(context, listen: false).streamMarketStatus();
      final statusData = await statusStream.first;
      _currentRound = (statusData['current_round'] ?? 1).toInt();
    } catch (_) {
      _currentRound = 1;
    }

    if (mounted) {
      _viewModel.init(_currentSeasonId, _currentRound);
      setState(() => _initialized = true);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final isAdmin = authService.isAdmin;

    // Proteção de acesso estrita: apenas admin_users
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Acesso Restrito"),
          backgroundColor: Colors.red.shade900,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gpp_bad, size: 72, color: Colors.red.shade400),
                const SizedBox(height: 16),
                const Text(
                  "Acesso Não Autorizado",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "A Central de Auditoria de Scouts é confidencial e restrita exclusivamente aos administradores da Federação.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text("Voltar"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ChangeNotifierProvider<FantasyAuditViewModel>.value(
      value: _viewModel,
      child: Consumer<FantasyAuditViewModel>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            appBar: _buildAppBar(vm),
            body: !_initialized
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      _buildRoundSelectorBar(vm),
                      _buildTabBar(),
                      Expanded(
                        child: vm.isLoading
                            ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text(
                                      "Carregando dados da auditoria...",
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ],
                                ),
                              )
                            : TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildOverviewTab(vm),
                                  _buildPlayersTab(vm),
                                  _buildMatchesTab(vm),
                                  _buildTeamsTab(vm),
                                ],
                              ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(FantasyAuditViewModel vm) {
    return AppBar(
      backgroundColor: const Color(0xFF1E293B),
      elevation: 2,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.teal.shade900.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.tealAccent.shade400, width: 1),
            ),
            child: const Icon(Icons.fact_check, color: Colors.tealAccent, size: 20),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Central de Auditoria",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                "Validação de Scouts & Pontuações",
                style: TextStyle(fontSize: 11, color: Colors.tealAccent),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: "Recarregar Relatório",
          icon: const Icon(Icons.refresh, color: Colors.white70),
          onPressed: vm.isLoading || vm.isRunningAudit
              ? null
              : () => vm.loadAuditData(vm.seasonId, vm.selectedRound),
        ),
        IconButton(
          tooltip: "Copiar CSV de Atletas",
          icon: const Icon(Icons.file_download_outlined, color: Colors.tealAccent),
          onPressed: vm.summary == null ? null : () => _exportCsv(vm),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildRoundSelectorBar(FantasyAuditViewModel vm) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(
          bottom: BorderSide(color: Color(0xFF334155), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, color: Colors.tealAccent, size: 18),
          const SizedBox(width: 8),
          const Text(
            "Rodada:",
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: vm.selectedRound,
            dropdownColor: const Color(0xFF1E293B),
            style: const TextStyle(
                color: Colors.tealAccent, fontWeight: FontWeight.bold),
            underline: Container(height: 1, color: Colors.tealAccent),
            items: List.generate(30, (i) => i + 1).map((r) {
              return DropdownMenuItem<int>(
                value: r,
                child: Text("Rodada $r", style: const TextStyle(color: Colors.white)),
              );
            }).toList(),
            onChanged: vm.isLoading || vm.isRunningAudit
                ? null
                : (val) {
                    if (val != null) vm.setRound(val);
                  },
          ),
          const Spacer(),
          if (vm.summary != null && vm.summary!.playersWithDiscrepancies > 0) ...[
            ElevatedButton.icon(
              onPressed: vm.isRunningAudit ? null : () => _confirmSyncLiveScores(vm),
              icon: const Icon(Icons.sync, size: 16),
              label: const Text(
                "Sincronizar Ao Vivo",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 8),
          ],
          ElevatedButton.icon(
            onPressed: vm.isRunningAudit ? null : () => _confirmRunAudit(vm),
            icon: vm.isRunningAudit
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow, size: 18),
            label: Text(
              vm.isRunningAudit ? "Auditando..." : "Rodar Auditoria",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF1E293B),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: Colors.tealAccent,
        labelColor: Colors.tealAccent,
        unselectedLabelColor: Colors.white60,
        indicatorWeight: 3,
        tabs: const [
          Tab(
            icon: Icon(Icons.dashboard_outlined, size: 20),
            text: "Visão Geral",
          ),
          Tab(
            icon: Icon(Icons.sports_soccer, size: 20),
            text: "Atletas & Scouts",
          ),
          Tab(
            icon: Icon(Icons.event_note, size: 20),
            text: "Partidas & Súmulas",
          ),
          Tab(
            icon: Icon(Icons.groups, size: 20),
            text: "Times dos Usuários",
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: VISÃO GERAL (OVERVIEW)
  // ==========================================
  Widget _buildOverviewTab(FantasyAuditViewModel vm) {
    final summary = vm.summary;

    if (summary == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 64, color: Colors.teal.shade200.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                "Nenhum relatório de auditoria gerado para a Rodada ${vm.selectedRound}.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                "Clique em 'Rodar Auditoria' para validar todos os scouts, presenças em súmulas e pontuações de forma isolada.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _confirmRunAudit(vm),
                icon: const Icon(Icons.play_arrow),
                label: Text("Auditar Rodada ${vm.selectedRound} Agora"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final hasDiscrepancy = summary.playersWithDiscrepancies > 0 ||
        summary.teamsWithDiscrepancies > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner de Status Principal
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hasDiscrepancy
                  ? Colors.amber.shade900.withValues(alpha: 0.2)
                  : Colors.teal.shade900.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasDiscrepancy
                    ? Colors.amber.shade600
                    : Colors.tealAccent.shade400,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasDiscrepancy ? Icons.warning_amber : Icons.verified,
                  color: hasDiscrepancy
                      ? Colors.amberAccent
                      : Colors.tealAccent,
                  size: 36,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasDiscrepancy
                            ? "DIVERGÊNCIAS DETECTADAS NA RODADA ${summary.round}"
                            : "RODADA ${summary.round} 100% CONCILIADA",
                        style: TextStyle(
                          color: hasDiscrepancy
                              ? Colors.amberAccent
                              : Colors.tealAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Executado em: ${summary.runAt != null ? _formatDateTime(summary.runAt!) : 'Recente'} por ${summary.runBy}",
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (hasDiscrepancy) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: vm.isRunningAudit ? null : () => _confirmSyncLiveScores(vm),
              icon: const Icon(Icons.sync, size: 20),
              label: Text(
                "Sincronizar Scouts no Ao Vivo (${summary.playersWithDiscrepancies} divergências)",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Cards de KPIs
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: "Atletas Auditados",
                  value: "${summary.totalPlayersAudited}",
                  subvalue: "${summary.playersWithDiscrepancies} com divergência",
                  isAlert: summary.playersWithDiscrepancies > 0,
                  icon: Icons.person_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: "Times dos Usuários",
                  value: "${summary.totalTeamsAudited}",
                  subvalue: "${summary.teamsWithDiscrepancies} com divergência",
                  isAlert: summary.teamsWithDiscrepancies > 0,
                  icon: Icons.groups_outlined,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: "Maior Diferença (Delta)",
                  value: "${summary.maxPlayerDelta.toStringAsFixed(2)} pts",
                  subvalue: summary.maxPlayerDelta > 0.05
                      ? "Atenção necessária"
                      : "Diferença desprezível",
                  isAlert: summary.maxPlayerDelta > 0.05,
                  icon: Icons.difference_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: "Partidas Analisadas",
                  value: "${summary.matchesFinished} / ${summary.totalMatches}",
                  subvalue: summary.liveIsFinal
                      ? "Rodada Oficialmente Fechada"
                      : "Rodada em Andamento (Ao Vivo)",
                  isAlert: false,
                  icon: Icons.sports,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Card de Regras Aplicadas
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.rule, color: Colors.tealAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Regras Críticas Auditadas",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildRuleItem(
                  icon: Icons.shield_outlined,
                  title: "Clean Sheet (SG) Restrito por Súmula",
                  description:
                      "Goleiro e Fixo só recebem bônus de SG se tiverem presença confirmada na súmula da partida ('lineup_played').",
                ),
                _buildRuleItem(
                  icon: Icons.sports_score,
                  title: "Média do Técnico Fidedigna",
                  description:
                      "A nota do técnico é a média aritmética calculada exclusivamente com base nos atletas da equipe que de fato jogaram.",
                ),
                _buildRuleItem(
                  icon: Icons.monetization_on_outlined,
                  title: "Auditoria de Cartoletas / Variação de Preço",
                  description:
                      "A variação de preço esperada pela fórmula oficial do Fantasy é comparada com o valor gravado.",
                ),
                _buildRuleItem(
                  icon: Icons.compare_arrows,
                  title: "Isolamento Total",
                  description:
                      "Esta rotina apenas lê os dados das súmulas e grava este relatório, sem modificar pontuações em produção.",
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Botão Grande de Reauditoria
          OutlinedButton.icon(
            onPressed: vm.isRunningAudit ? null : () => _confirmRunAudit(vm),
            icon: const Icon(Icons.refresh),
            label: Text("Reexecutar Auditoria da Rodada ${summary.round}"),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.tealAccent,
              side: const BorderSide(color: Colors.tealAccent),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subvalue,
    required bool isAlert,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isAlert ? Colors.red.shade400 : const Color(0xFF334155),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: isAlert ? Colors.redAccent : Colors.tealAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isAlert ? Colors.redAccent : Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subvalue,
            style: TextStyle(
              fontSize: 11,
              color: isAlert ? Colors.red.shade200 : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.tealAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: ATLETAS & SCOUTS
  // ==========================================
  Widget _buildPlayersTab(FantasyAuditViewModel vm) {
    final players = vm.filteredPlayers;

    return Column(
      children: [
        // Barra de Ferramentas / Filtros
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF1E293B),
          child: Column(
            children: [
              // Linha 1: Busca e Toggle de Discrepâncias
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: "Buscar atleta por nome...",
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                        prefixIcon: const Icon(Icons.search, color: Colors.white60, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  vm.setSearchQuery('');
                                },
                              )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) => vm.setSearchQuery(val),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(
                      "Só Divergências (${vm.players.where((p) => p.hasDiscrepancy).length})",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: vm.onlyDiscrepancies ? Colors.white : Colors.amberAccent,
                      ),
                    ),
                    selected: vm.onlyDiscrepancies,
                    selectedColor: Colors.amber.shade800,
                    backgroundColor: const Color(0xFF0F172A),
                    side: BorderSide(
                      color: vm.onlyDiscrepancies
                          ? Colors.amberAccent
                          : Colors.amber.shade700,
                    ),
                    onSelected: (val) => vm.setOnlyDiscrepancies(val),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Linha 2: Chips de Posição & Ordenação
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...vm.availablePositions.map((pos) {
                      final isSelected = vm.selectedPosition == pos;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(pos, style: const TextStyle(fontSize: 11)),
                          selected: isSelected,
                          selectedColor: Colors.teal.shade800,
                          backgroundColor: const Color(0xFF0F172A),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.tealAccent : Colors.white70,
                          ),
                          side: BorderSide(
                            color: isSelected ? Colors.tealAccent : Colors.transparent,
                          ),
                          onSelected: (_) => vm.setPositionFilter(pos),
                        ),
                      );
                    }),
                    const SizedBox(width: 8),
                    // Dropdown de Ordenação
                    PopupMenuButton<AuditSortField>(
                      tooltip: "Ordenar por",
                      color: const Color(0xFF1E293B),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sort, color: Colors.tealAccent, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              _sortLabel(vm.sortField),
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: AuditSortField.deltaLive,
                          child: Text("Maior Divergência Ao Vivo",
                              style: TextStyle(color: Colors.white)),
                        ),
                        const PopupMenuItem(
                          value: AuditSortField.expectedScore,
                          child: Text("Pontuação Esperada",
                              style: TextStyle(color: Colors.white)),
                        ),
                        const PopupMenuItem(
                          value: AuditSortField.name,
                          child: Text("Nome do Jogador",
                              style: TextStyle(color: Colors.white)),
                        ),
                        const PopupMenuItem(
                          value: AuditSortField.position,
                          child: Text("Posição",
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                      onSelected: (field) => vm.setSorting(field),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Contador de resultados
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: const Color(0xFF0F172A),
          child: Row(
            children: [
              Text(
                "Exibindo ${players.length} de ${vm.players.length} atletas",
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const Spacer(),
              if (vm.onlyDiscrepancies ||
                  vm.selectedPosition != 'Todas' ||
                  vm.searchQuery.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    vm.clearFilters();
                  },
                  child: const Text(
                    "Limpar filtros",
                    style: TextStyle(color: Colors.tealAccent, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),

        // Lista de Jogadores
        Expanded(
          child: players.isEmpty
              ? const Center(
                  child: Text(
                    "Nenhum atleta corresponde aos filtros selecionados.",
                    style: TextStyle(color: Colors.white60),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: players.length,
                  itemBuilder: (ctx, idx) => _buildPlayerCard(players[idx]),
                ),
        ),
      ],
    );
  }

  Widget _buildPlayerCard(FantasyAuditPlayer player) {
    final hasDiscrepancy = player.hasDiscrepancy;

    return Card(
      color: const Color(0xFF1E293B),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: hasDiscrepancy ? Colors.amber.shade700 : const Color(0xFF334155),
          width: hasDiscrepancy ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showPlayerDetailsSheet(player),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho: Foto, Nome, Posição, Presença e Flags
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPlayerAvatar(player),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade900,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                player.position,
                                style: const TextStyle(
                                    color: Colors.tealAccent, fontSize: 10),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              player.teamId.isNotEmpty ? player.teamId : "Sem time",
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 11),
                            ),
                            const SizedBox(width: 8),
                            // Indicador de Presença em Súmula
                            Icon(
                              player.played
                                  ? Icons.check_circle
                                  : Icons.remove_circle_outline,
                              size: 13,
                              color: player.played
                                  ? Colors.greenAccent
                                  : Colors.white30,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              player.played ? "Jogou" : "Não jogou",
                              style: TextStyle(
                                fontSize: 10,
                                color: player.played
                                    ? Colors.greenAccent
                                    : Colors.white38,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Pontuação Esperada em Grande Destaque
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        "ESPERADO",
                        style: TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        player.expectedScore.toStringAsFixed(2),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Barra de Scouts Sumarizados Sensível à Posição (Goleiro vs Linha)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: player.position == 'Goleiro'
                      ? [
                          _buildScoutMiniStat("SG", player.scouts['clean_sheets'] ?? 0),
                          _buildScoutMiniStat("DD", player.scouts['difficult_saves'] ?? 0),
                          _buildScoutMiniStat("DP", player.scouts['penalties_saved'] ?? 0),
                          _buildScoutMiniStat("G", player.scouts['goals'] ?? 0),
                          _buildScoutMiniStat("CA", player.scouts['yellows'] ?? 0),
                          _buildScoutMiniStat("CV", player.scouts['reds'] ?? 0),
                          _buildScoutMiniStat("MOTM", player.scouts['motm'] ?? 0),
                        ]
                      : [
                          _buildScoutMiniStat("G", player.scouts['goals'] ?? 0),
                          _buildScoutMiniStat("A", player.scouts['assists'] ?? 0),
                          _buildScoutMiniStat("FT", player.scouts['shots_on_post'] ?? 0),
                          if (player.position == 'Fixo')
                            _buildScoutMiniStat("SG", player.scouts['clean_sheets'] ?? 0),
                          _buildScoutMiniStat("CA", player.scouts['yellows'] ?? 0),
                          _buildScoutMiniStat("CV", player.scouts['reds'] ?? 0),
                          _buildScoutMiniStat("MOTM", player.scouts['motm'] ?? 0),
                        ],
                ),
              ),

              // Chips de Scouts Especiais Adicionais (se houver)
              if ((player.scouts['penalties_missed'] ?? 0) > 0 ||
                  (player.scouts['own_goals'] ?? 0) > 0 ||
                  (player.scouts['direct_free_kicks_missed'] ?? 0) > 0 ||
                  (player.position != 'Goleiro' && (player.scouts['difficult_saves'] ?? 0) > 0)) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if ((player.scouts['penalties_missed'] ?? 0) > 0)
                      _buildSpecialScoutBadge("PP: ${player.scouts['penalties_missed']} (Pênalti Perdido)", Colors.redAccent),
                    if ((player.scouts['own_goals'] ?? 0) > 0)
                      _buildSpecialScoutBadge("GC: ${player.scouts['own_goals']} (Gol Contra)", Colors.redAccent),
                    if ((player.scouts['direct_free_kicks_missed'] ?? 0) > 0)
                      _buildSpecialScoutBadge("FD: ${player.scouts['direct_free_kicks_missed']} (Falta Desperdiçada)", Colors.orangeAccent),
                    if (player.position != 'Goleiro' && (player.scouts['difficult_saves'] ?? 0) > 0)
                      _buildSpecialScoutBadge("DD: ${player.scouts['difficult_saves']} (Defesa Difícil)", Colors.tealAccent),
                  ],
                ),
              ],

              const SizedBox(height: 10),

              // Comparativo de Pontuação: Ao Vivo vs Fechamento vs Delta
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildComparisonColumn(
                    label: "Ao Vivo",
                    value: player.publishedLiveScore.toStringAsFixed(2),
                    delta: player.deltaLive,
                  ),
                  if (player.publishedFinalScore != null)
                    _buildComparisonColumn(
                      label: "Fechamento",
                      value: player.publishedFinalScore!.toStringAsFixed(2),
                      delta: player.deltaFinal ?? 0.0,
                    ),
                  _buildPriceColumn(player),
                  const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
                ],
              ),

              // Badges de Flags de Erro
              if (player.flags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: player.flags.map((flag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.redAccent, width: 0.5),
                      ),
                      child: Text(
                        flag,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerAvatar(FantasyAuditPlayer player) {
    if (player.photoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: player.photoUrl,
          cacheManager: PlayerCacheManager.instance,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: 44,
            height: 44,
            color: const Color(0xFF334155),
            child: const Icon(Icons.person, color: Colors.white30, size: 24),
          ),
          errorWidget: (_, __, ___) => Container(
            width: 44,
            height: 44,
            color: const Color(0xFF334155),
            child: const Icon(Icons.person, color: Colors.white30, size: 24),
          ),
        ),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF334155),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.person, color: Colors.white30, size: 24),
    );
  }

  Widget _buildScoutMiniStat(String label, int value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        Text(
          "$value",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: value > 0 ? Colors.tealAccent : Colors.white60,
          ),
        ),
      ],
    );
  }

  Widget _buildSpecialScoutBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildGridScoutItem(String label, int value, {bool isKey = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isKey
              ? Colors.tealAccent.withValues(alpha: 0.5)
              : (value > 0 ? Colors.teal.shade700 : const Color(0xFF334155)),
          width: isKey ? 1 : 0.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isKey ? Colors.tealAccent : Colors.white70,
              fontSize: 10,
              fontWeight: isKey ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "$value",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: value > 0 ? Colors.tealAccent : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonColumn({
    required String label,
    required String value,
    required double delta,
  }) {
    final hasDelta = delta.abs() > 0.05;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
            ),
            if (hasDelta) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.red.shade900,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  delta > 0
                      ? "+${delta.toStringAsFixed(1)}"
                      : delta.toStringAsFixed(1),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildPriceColumn(FantasyAuditPlayer player) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Preço Esp.",
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
        Text(
          "C\$ ${player.priceExpectedNew.toStringAsFixed(2)}",
          style: const TextStyle(
              color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 3: PARTIDAS & SÚMULAS
  // ==========================================
  Widget _buildMatchesTab(FantasyAuditViewModel vm) {
    final matches = vm.matches;

    if (matches.isEmpty) {
      return const Center(
        child: Text(
          "Nenhuma partida vinculada a esta rodada.",
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: matches.length,
      itemBuilder: (ctx, idx) {
        final match = matches[idx];
        final hasDiscrepancy = match.discrepancies.isNotEmpty;

        return Card(
          color: const Color(0xFF1E293B),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: hasDiscrepancy
                  ? Colors.amber.shade700
                  : const Color(0xFF334155),
              width: hasDiscrepancy ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Linha de Cabeçalho: Status e Label
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      match.matchLabel.isNotEmpty
                          ? match.matchLabel
                          : "Partida #${idx + 1}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: match.status == 'finished'
                            ? Colors.green.shade900
                            : Colors.orange.shade900,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        match.status.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Placar
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        match.homeId,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "${match.scoreHome} x ${match.scoreAway}",
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        match.awayId,
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                const Divider(color: Color(0xFF334155), height: 1),
                const SizedBox(height: 10),

                // Auditoria da Súmula
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMatchStatItem(
                      icon: Icons.checklist_rtl,
                      label: "Presença Súmula",
                      value: "${match.lineupPlayedCount} confirmados",
                    ),
                    _buildMatchStatItem(
                      icon: Icons.timeline,
                      label: "Lances Timeline",
                      value: "${match.timelineEventsCount} eventos",
                    ),
                    _buildMatchStatItem(
                      icon: Icons.shield_outlined,
                      label: "SG",
                      value: match.cleanSheetHome && match.cleanSheetAway
                          ? "Ambos (0x0)"
                          : match.cleanSheetHome
                              ? "Mandante"
                              : match.cleanSheetAway
                                  ? "Visitante"
                                  : "Nenhum",
                    ),
                    if (match.motmId != null)
                      _buildMatchStatItem(
                        icon: Icons.star,
                        label: "MOTM",
                        value: "Eleito",
                      ),
                  ],
                ),

                // Avisos de Discrepância na Partida
                if (match.discrepancies.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amberAccent, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: match.discrepancies.map((d) {
                        return Row(
                          children: [
                            const Icon(Icons.warning, size: 14, color: Colors.amberAccent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                d,
                                style: const TextStyle(
                                    color: Colors.amberAccent, fontSize: 11),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMatchStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 16, color: Colors.tealAccent),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        Text(
          value,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 4: TIMES DOS USUÁRIOS
  // ==========================================
  Widget _buildTeamsTab(FantasyAuditViewModel vm) {
    final teams = vm.filteredTeams;

    if (teams.isEmpty) {
      return const Center(
        child: Text(
          "Nenhum time de usuário encontrado para esta rodada.",
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: teams.length,
      itemBuilder: (ctx, idx) {
        final team = teams[idx];
        final hasDelta = team.delta.abs() > 0.05;

        return Card(
          color: const Color(0xFF1E293B),
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: hasDelta ? Colors.red.shade400 : const Color(0xFF334155),
              width: hasDelta ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.shield, color: Colors.tealAccent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team.teamName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        "${team.ownerName} • ${team.lineupCount} atletas",
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                      if (team.substitutions.isNotEmpty)
                        Text(
                          "${team.substitutions.length} substituição(ões) automática(s)",
                          style: const TextStyle(
                              color: Colors.amberAccent, fontSize: 10),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Text(
                          "Gravado: ${team.publishedPoints.toStringAsFixed(2)}",
                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Text(
                          "Esperado: ",
                          style: TextStyle(color: Colors.tealAccent, fontSize: 11),
                        ),
                        Text(
                          team.expectedPoints.toStringAsFixed(2),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    if (hasDelta) ...[
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          "Delta: ${team.delta.toStringAsFixed(2)} pts",
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // MODAL: DETALHES DO JOGADOR & MEMÓRIA DE CÁLCULO
  // ==========================================
  void _showPlayerDetailsSheet(FantasyAuditPlayer player) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Cabeçalho do Modal
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        _buildPlayerAvatar(player),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                player.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "${player.position} • ${player.teamId} • ${player.played ? 'Confirmado em Súmula' : 'Não Jogou'}",
                                style: TextStyle(
                                  color: player.played
                                      ? Colors.tealAccent
                                      : Colors.amberAccent,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  const Divider(color: Color(0xFF334155), height: 1),

                  // Conteúdo do Modal com Scroll
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Card de Resumo de Pontuação e Deltas
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: player.hasDiscrepancy
                                  ? Colors.amber.shade700
                                  : Colors.teal.shade900,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildSummaryScoreBox(
                                    label: "Esperado (Auditoria)",
                                    value: player.expectedScore.toStringAsFixed(2),
                                    color: Colors.tealAccent,
                                  ),
                                  _buildSummaryScoreBox(
                                    label: "Ao Vivo (Banco)",
                                    value: player.publishedLiveScore.toStringAsFixed(2),
                                    color: Colors.white,
                                  ),
                                  if (player.publishedFinalScore != null)
                                    _buildSummaryScoreBox(
                                      label: "Fechamento (Final)",
                                      value: player.publishedFinalScore!.toStringAsFixed(2),
                                      color: Colors.white70,
                                    ),
                                ],
                              ),
                              if (player.hasDiscrepancy) ...[
                                const SizedBox(height: 10),
                                const Divider(color: Color(0xFF334155)),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.warning,
                                        size: 16, color: Colors.amberAccent),
                                    const SizedBox(width: 6),
                                    Text(
                                      "Divergência detectada no Ao Vivo: Delta = ${player.deltaLive.toStringAsFixed(2)} pts",
                                      style: const TextStyle(
                                          color: Colors.amberAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Se for Técnico: Memória de Cálculo Específica dos Atletas
                        if (player.coachDetails != null) ...[
                          _buildCoachBreakdownSection(player.coachDetails!),
                          const SizedBox(height: 20),
                        ],

                        // Memória de Cálculo / Breakdown
                        const Text(
                          "Memória de Cálculo da Pontuação",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        // Quadro Completo de Todos os Scouts do Fantasy FJF
                        const Text(
                          "Quadro Geral de Scouts (Todos os Critérios)",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: _buildGridScoutItem("Gols (G)", player.scouts['goals'] ?? 0)),
                                  Expanded(child: _buildGridScoutItem("Assistências (A)", player.scouts['assists'] ?? 0)),
                                  Expanded(child: _buildGridScoutItem("Amarelos (CA)", player.scouts['yellows'] ?? 0)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: _buildGridScoutItem("Vermelhos (CV)", player.scouts['reds'] ?? 0)),
                                  Expanded(child: _buildGridScoutItem("Sem Sofrer Gol (SG)", player.scouts['clean_sheets'] ?? 0, isKey: player.position == 'Goleiro' || player.position == 'Fixo')),
                                  Expanded(child: _buildGridScoutItem("Craque (MOTM)", player.scouts['motm'] ?? 0)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: _buildGridScoutItem("Defesa Difícil (DD)", player.scouts['difficult_saves'] ?? 0, isKey: player.position == 'Goleiro')),
                                  Expanded(child: _buildGridScoutItem("Pên. Defendido (DP)", player.scouts['penalties_saved'] ?? 0, isKey: player.position == 'Goleiro')),
                                  Expanded(child: _buildGridScoutItem("Finaliz. Trave (FT)", player.scouts['shots_on_post'] ?? 0)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: _buildGridScoutItem("Pên. Perdido (PP)", player.scouts['penalties_missed'] ?? 0)),
                                  Expanded(child: _buildGridScoutItem("Gol Contra (GC)", player.scouts['own_goals'] ?? 0)),
                                  Expanded(child: _buildGridScoutItem("Falta Perdida (FD)", player.scouts['direct_free_kicks_missed'] ?? 0)),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Memória de Cálculo / Breakdown
                        const Text(
                          "Memória de Cálculo da Pontuação (Pontuadores)",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        if (player.breakdown.isEmpty)
                          const Text(
                            "Nenhum scout pontuador registrado na rodada.",
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          )
                        else
                          ...player.breakdown.map((item) {
                            final rawName = item['label'] ?? item['scout'] ?? '';
                            final scoutLabel = _scoutNamePt(rawName.toString());
                            final count = (item['count'] ?? 0) as num;
                            final weight = (item['ptsPerUnit'] ?? item['weight'] ?? 0.0) as num;
                            final total = (item['subtotal'] ?? item['total'] ?? 0.0) as num;
                            final note = item['note'];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        scoutLabel,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        "$count x ${weight >= 0 ? '+$weight' : '$weight'} pts${note != null ? ' ($note)' : ''}",
                                        style: const TextStyle(
                                            color: Colors.white60, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    total > 0
                                        ? "+${total.toStringAsFixed(2)} pts"
                                        : "${total.toStringAsFixed(2)} pts",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: total >= 0
                                          ? Colors.tealAccent
                                          : Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),

                        const SizedBox(height: 20),

                        // Evidências na Timeline da Súmula
                        const Text(
                          "Evidências Registradas na Súmula (Timeline)",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        if (player.timelineEvidence.isEmpty)
                          const Text(
                            "Nenhum evento registrado na timeline desta partida.",
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          )
                        else
                          ...player.timelineEvidence.map((ev) {
                            final type = ev['type'] ?? '';
                            final minute = ev['minute'] ?? '';
                            final matchId = ev['matchId'] ?? '';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  Icon(_timelineIcon(type),
                                      color: Colors.tealAccent, size: 16),
                                  const SizedBox(width: 10),
                                  Text(
                                    minute.isNotEmpty ? "$minute'" : "—",
                                    style: const TextStyle(
                                        color: Colors.tealAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _scoutNamePt(type),
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12),
                                    ),
                                  ),
                                  Text(
                                    "Jogo: $matchId",
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 10),
                                  ),
                                ],
                              ),
                            );
                          }),

                        const SizedBox(height: 20),

                        // Auditoria de Variação de Preço
                        const Text(
                          "Auditoria de Variação de Preço (Cartoletas)",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              _buildPriceRow(
                                  "Preço Anterior",
                                  "C\$ ${player.priceBefore.toStringAsFixed(2)}"),
                              _buildPriceRow(
                                  "Variação Esperada",
                                  "${player.priceExpectedVariation >= 0 ? '+' : ''}${player.priceExpectedVariation.toStringAsFixed(2)}"),
                              _buildPriceRow(
                                  "Novo Preço Esperado",
                                  "C\$ ${player.priceExpectedNew.toStringAsFixed(2)}",
                                  highlight: true),
                              if (player.publishedPriceChange != null)
                                _buildPriceRow(
                                    "Variação Publicada no Banco",
                                    "${player.publishedPriceChange! >= 0 ? '+' : ''}${player.publishedPriceChange!.toStringAsFixed(2)}"),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildSummaryScoreBox({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCoachBreakdownSection(Map<String, dynamic> coach) {
    final teamCount = coach['teamPlayersCount'] ?? 0;
    final sum = (coach['teamPlayersScoreSum'] ?? 0.0) as num;
    final average = (coach['averageScore'] ?? 0.0) as num;
    final teamPlayers = List<Map<String, dynamic>>.from(coach['teamPlayers'] ?? []);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.person_pin, color: Colors.tealAccent, size: 18),
              SizedBox(width: 8),
              Text(
                "Detalhamento da Média do Técnico",
                style: TextStyle(
                    color: Colors.tealAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Regra: Nota é a média aritmética dos atletas confirmados na súmula da equipe.\n"
            "Cálculo: $sum pts ÷ $teamCount atletas = ${average.toStringAsFixed(2)} pts",
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 10),
          ...teamPlayers.map((tp) {
            final pName = tp['name'] ?? 'Atleta';
            final pScore = (tp['score'] ?? 0.0) as num;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("• $pName",
                      style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  Text("${pScore.toStringAsFixed(2)} pts",
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              color: highlight ? Colors.tealAccent : Colors.white,
              fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // HELPERS DE AÇÃO E FORMATAÇÃO
  // ==========================================
  void _confirmRunAudit(FantasyAuditViewModel vm) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            const Icon(Icons.fact_check, color: Colors.tealAccent),
            const SizedBox(width: 10),
            Text("Auditar Rodada ${vm.selectedRound}"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Esta ação executará uma auditoria completa e independente da Rodada ${vm.selectedRound}.\n\n"
              "• Verificação estrita de presença em súmula ('lineup_played') para SG.\n"
              "• Recálculo exato da média dos técnicos com atletas confirmados.\n"
              "• Auditoria da variação de preço esperada.\n"
              "• Recálculo das pontuações dos times dos usuários.\n\n"
              "⚠️ NENHUM dado de pontuação do fantasy em produção será alterado; o relatório será gerado em ambiente isolado de validação.",
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text("Executar Auditoria"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await vm.triggerAudit();
      if (mounted) {
        if (success) {
          AppFeedback.showSuccess(
            context,
            "Auditoria da Rodada ${vm.selectedRound} concluída com sucesso!",
          );
        } else if (vm.errorMessage != null) {
          AppFeedback.showError(context, vm.errorMessage!);
        }
      }
    }
  }

  void _confirmSyncLiveScores(FantasyAuditViewModel vm) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            const Icon(Icons.sync, color: Colors.amberAccent),
            const SizedBox(width: 10),
            Text("Sincronizar Ao Vivo (R${vm.selectedRound})"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Esta ação aplicará as pontuações auditadas (incluindo Craque do Jogo, SG validado e scouts corrigidos) diretamente no documento 'Ao Vivo' da Rodada ${vm.selectedRound}.\n\n"
              "• Atualiza 'fantasy_live/round_${vm.selectedRound}' com as pontuações e scouts corretos.\n"
              "• Corrige discrepâncias entre o ao vivo e o cálculo oficial da auditoria.\n"
              "• Zera os deltas de divergência na auditoria.\n\n"
              "Deseja prosseguir com a sincronização?",
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
            ),
            child: const Text("Sincronizar Agora"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await vm.syncLiveScores();
      if (mounted) {
        if (success) {
          AppFeedback.showSuccess(
            context,
            vm.successMessage ?? "Scouts Ao Vivo sincronizados com sucesso!",
          );
        } else if (vm.errorMessage != null) {
          AppFeedback.showError(context, vm.errorMessage!);
        }
      }
    }
  }

  void _exportCsv(FantasyAuditViewModel vm) {
    final csv = vm.exportPlayersCsv();
    Clipboard.setData(ClipboardData(text: csv));
    AppFeedback.showSuccess(
      context,
      "CSV copiado para a área de transferência (${vm.filteredPlayers.length} atletas)!",
    );
  }

  String _sortLabel(AuditSortField field) {
    switch (field) {
      case AuditSortField.deltaLive:
        return "Maior Divergência";
      case AuditSortField.expectedScore:
        return "Pontuação";
      case AuditSortField.name:
        return "Nome";
      case AuditSortField.position:
        return "Posição";
      default:
        return "Padrão";
    }
  }

  String _scoutNamePt(String code) {
    switch (code) {
      case 'goals':
      case 'goal':
        return 'Gols (G)';
      case 'assists':
      case 'assist':
        return 'Assistências (A)';
      case 'yellows':
      case 'yellow_card':
      case 'yellowCard':
        return 'Cartão Amarelo (CA)';
      case 'reds':
      case 'red_card':
      case 'redCard':
        return 'Cartão Vermelho (CV)';
      case 'clean_sheets':
      case 'clean_sheet':
      case 'cleanSheet':
        return 'Sem Sofrer Gol (SG)';
      case 'motm':
      case 'man_of_the_match':
        return 'Craque do Jogo (MOTM)';
      case 'difficult_saves':
      case 'difficultSave':
        return 'Defesas Difíceis (DD)';
      case 'penalties_saved':
      case 'penaltySaved':
        return 'Pênaltis Defendidos (DP)';
      case 'penalties_missed':
      case 'penaltyMissed':
        return 'Pênaltis Perdidos (PP)';
      case 'shots_on_post':
      case 'shotOnPost':
        return 'Finalizações na Trave (FT)';
      case 'own_goals':
      case 'ownGoal':
        return 'Gols Contra (GC)';
      case 'direct_free_kicks_missed':
      case 'directFreeKickMissed':
        return 'Faltas Diretas Desperdiçadas (FD)';
      case 'coach_avg':
        return 'Média dos Atletas';
      default:
        return code;
    }
  }

  IconData _timelineIcon(String type) {
    switch (type) {
      case 'goal':
      case 'goals':
        return Icons.sports_soccer;
      case 'assist':
      case 'assists':
        return Icons.handshake;
      case 'yellow_card':
      case 'yellowCard':
      case 'yellows':
        return Icons.warning_amber;
      case 'red_card':
      case 'redCard':
      case 'reds':
        return Icons.cancel;
      case 'difficult_saves':
      case 'difficultSave':
        return Icons.pan_tool_alt;
      case 'penalties_saved':
      case 'penaltySaved':
        return Icons.sports_handball;
      case 'penalties_missed':
      case 'penaltyMissed':
        return Icons.highlight_off;
      case 'shots_on_post':
      case 'shotOnPost':
        return Icons.sports_soccer;
      case 'own_goals':
      case 'ownGoal':
        return Icons.error_outline;
      case 'direct_free_kicks_missed':
      case 'directFreeKickMissed':
        return Icons.replay;
      default:
        return Icons.event;
    }
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return "$d/$m/$y $h:$min";
  }
}
