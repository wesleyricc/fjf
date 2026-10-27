import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/fantasy_models.dart';
import '../../services/fantasy_admin_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/team_logo_widget.dart';

class TeamLineupEntry {
  final FantasyTeam team;
  final bool isStarter;
  final bool isBench;
  final bool isCaptain;
  double currentBalance;
  double currentTeamValue;

  TeamLineupEntry({
    required this.team,
    required this.isStarter,
    required this.isBench,
    required this.isCaptain,
    required this.currentBalance,
    required this.currentTeamValue,
  });
}

class AdminFantasyPlayerLineupsScreen extends StatefulWidget {
  final int initialRound;

  const AdminFantasyPlayerLineupsScreen({
    super.key,
    required this.initialRound,
  });

  @override
  State<AdminFantasyPlayerLineupsScreen> createState() =>
      _AdminFantasyPlayerLineupsScreenState();
}

class _AdminFantasyPlayerLineupsScreenState
    extends State<AdminFantasyPlayerLineupsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FantasyAdminService _adminService = FantasyAdminService();

  // Estados de controle
  bool _isLoadingInitial = true;
  bool _isLoadingTeams = false;
  String? _errorMessage;

  int _selectedRound = 0; // 0 = Rodada Ativa / Mercado Atual; >0 = Rodada de Histórico
  int _dbRound = 1;
  bool _isMarketOpen = true;

  List<FantasyPlayer> _allPlayers = [];
  FantasyPlayer? _selectedPlayer;

  List<FantasyTeam> _allTeams = [];
  List<TeamLineupEntry> _teamsWithPlayer = [];
  List<TeamLineupEntry> _filteredTeamsWithPlayer = [];

  // Cache de histórico por rodada: round -> { teamId: historyData }
  final Map<int, Map<String, Map<String, dynamic>>> _roundHistoriesCache = {};

  final TextEditingController _teamSearchController = TextEditingController();
  String _teamRoleFilter = 'all'; // 'all', 'starters', 'bench', 'captains'

  @override
  void initState() {
    super.initState();
    _selectedRound = widget.initialRound > 0 ? widget.initialRound : 0;
    _teamSearchController.addListener(_onTeamSearchChanged);
    _loadInitialData();
  }

  @override
  void dispose() {
    _teamSearchController.dispose();
    super.dispose();
  }

  void _onTeamSearchChanged() {
    _applyTeamFilter();
  }

  void _applyTeamFilter() {
    final query = _teamSearchController.text.trim().toLowerCase();
    setState(() {
      _filteredTeamsWithPlayer = _teamsWithPlayer.where((entry) {
        final matchesText = query.isEmpty ||
            entry.team.teamName.toLowerCase().contains(query) ||
            entry.team.ownerName.toLowerCase().contains(query);

        bool matchesRole = true;
        if (_teamRoleFilter == 'starters') {
          matchesRole = entry.isStarter;
        } else if (_teamRoleFilter == 'bench') {
          matchesRole = entry.isBench;
        } else if (_teamRoleFilter == 'captains') {
          matchesRole = entry.isCaptain;
        }

        return matchesText && matchesRole;
      }).toList();
    });
  }

  // --- CARREGAMENTO INICIAL ---
  Future<void> _loadInitialData() async {
    setState(() {
      _isLoadingInitial = true;
      _errorMessage = null;
    });

    try {
      // 1. Status do Mercado
      final statusDoc =
          await _firestore.collection('fantasy_config').doc('status').get();
      if (statusDoc.exists) {
        final data = statusDoc.data()!;
        _isMarketOpen = data['is_open'] ?? true;
        _dbRound = data['current_round'] ?? 1;
        if (_selectedRound == 0 && !_isMarketOpen) {
          _selectedRound = _dbRound;
        }
      }

      // 2. Todos os atletas do mercado
      final playersSnap =
          await _firestore.collection('fantasy_market_players').get();
      _allPlayers = playersSnap.docs
          .map((doc) => FantasyPlayer.fromFirestore(doc))
          .toList();
      _allPlayers.sort((a, b) => a.name.compareTo(b.name));

      // 3. Todos os times cadastrados
      final teamsSnap = await _firestore.collection('fantasy_teams').get();
      _allTeams =
          teamsSnap.docs.map((doc) => FantasyTeam.fromFirestore(doc)).toList();

      setState(() {
        _isLoadingInitial = false;
      });

      if (_selectedPlayer != null) {
        await _findTeamsWithSelectedPlayer();
      }
    } catch (e) {
      debugPrint("Erro ao carregar dados iniciais: $e");
      setState(() {
        _errorMessage = "Erro ao carregar dados do Fantasy: $e";
        _isLoadingInitial = false;
      });
    }
  }

  // --- LOCALIZA TIMES QUE ESCALARAM O ATLETA ---
  Future<void> _findTeamsWithSelectedPlayer() async {
    if (_selectedPlayer == null) {
      setState(() {
        _teamsWithPlayer = [];
        _filteredTeamsWithPlayer = [];
      });
      return;
    }

    setState(() {
      _isLoadingTeams = true;
    });

    try {
      final pid = _selectedPlayer!.playerId;
      final List<TeamLineupEntry> results = [];

      if (_selectedRound == 0) {
        // Escalação Ativa / Mercado Atual
        for (var team in _allTeams) {
          final isStarter = team.lineupPlayerIds.contains(pid);
          final isBench = team.benchPlayerIds.contains(pid);
          final isCaptain = team.captainId == pid;

          if (isStarter || isBench) {
            results.add(TeamLineupEntry(
              team: team,
              isStarter: isStarter,
              isBench: isBench,
              isCaptain: isCaptain,
              currentBalance: team.currentBalance,
              currentTeamValue: team.teamValue,
            ));
          }
        }
      } else {
        // Rodada Histórica
        if (!_roundHistoriesCache.containsKey(_selectedRound)) {
          final Map<String, Map<String, dynamic>> histMap = {};
          final List<Future<void>> tasks = [];

          for (var team in _allTeams) {
            tasks.add(() async {
              try {
                final hDoc = await _firestore
                    .collection('fantasy_teams')
                    .doc(team.id)
                    .collection('history')
                    .doc(_selectedRound.toString())
                    .get();
                if (hDoc.exists && hDoc.data() != null) {
                  histMap[team.id] = hDoc.data()!;
                }
              } catch (_) {}
            }());
          }
          await Future.wait(tasks);
          _roundHistoriesCache[_selectedRound] = histMap;
        }

        final roundHistMap = _roundHistoriesCache[_selectedRound]!;

        for (var team in _allTeams) {
          final hist = roundHistMap[team.id];
          if (hist == null) continue;

          final originalLineup = List<String>.from(hist['lineup_snapshot'] ?? []);
          final finalLineup = List<String>.from(hist['final_lineup'] ?? []);
          final captainId = hist['captain_id']?.toString() ??
              hist['original_captain_id']?.toString();

          final isOriginalStarter = originalLineup.contains(pid);
          final isFinalStarter = finalLineup.contains(pid);
          final isCaptain = captainId == pid;

          if (isOriginalStarter || isFinalStarter) {
            results.add(TeamLineupEntry(
              team: team,
              isStarter: true,
              isBench: false,
              isCaptain: isCaptain,
              currentBalance: team.currentBalance,
              currentTeamValue: team.teamValue,
            ));
          }
        }
      }

      results.sort((a, b) {
        if (a.isCaptain && !b.isCaptain) return -1;
        if (!a.isCaptain && b.isCaptain) return 1;
        if (a.isStarter && !b.isStarter) return -1;
        if (!a.isStarter && b.isStarter) return 1;
        return a.team.teamName.compareTo(b.team.teamName);
      });

      setState(() {
        _teamsWithPlayer = results;
        _isLoadingTeams = false;
      });
      _applyTeamFilter();
    } catch (e) {
      debugPrint("Erro ao buscar times do atleta: $e");
      setState(() {
        _isLoadingTeams = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao buscar times: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- MODAL: AJUSTAR MOEDAS INDIVIDUALMENTE ---
  Future<void> _showCoinAdjustmentDialog(TeamLineupEntry entry) async {
    final team = entry.team;
    final coinsController = TextEditingController(text: '1.00');
    final reasonController = TextEditingController(
      text: _selectedPlayer != null
          ? "Correção de valorização: ${_selectedPlayer!.name} (${_selectedRound == 0 ? 'Rodada Atual' : 'Rodada $_selectedRound'})"
          : "Correção de valorização de scout",
    );
    bool updateHistory = _selectedRound > 0;
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final double coins = double.tryParse(coinsController.text.replaceAll(',', '.')) ?? 0.0;
            final double newBalance = entry.currentBalance + coins;
            final double newPatrimony = entry.currentTeamValue + coins;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.amber.shade100,
                    child: Icon(Icons.monetization_on, color: Colors.amber.shade800),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Compensar Moedas",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Informações do Time
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          TeamLogoWidget(
                            logoUrl: team.customLogoUrl,
                            shieldType: team.shieldType,
                            radius: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  team.teamName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                Text(
                                  "Cartoleiro: ${team.ownerName}",
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Situação Financeira Atual
                    Row(
                      children: [
                        Expanded(
                          child: _buildMiniStat(
                            "Saldo Atual",
                            "C\$ ${entry.currentBalance.toStringAsFixed(2)}",
                            Colors.blue.shade700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMiniStat(
                            "Patrimônio Atual",
                            "C\$ ${entry.currentTeamValue.toStringAsFixed(2)}",
                            Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Valor a Adicionar
                    const Text(
                      "Quantidade de Moedas a Adicionar (C\$):",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: coinsController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^-?[0-9]*[.,]?[0-9]*')),
                      ],
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.paid, color: Colors.amber),
                        hintText: "Ex: 1.50 ou 2.00",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),

                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [0.50, 1.00, 1.50, 2.00, 3.00, 5.00].map((val) {
                        return ActionChip(
                          label: Text("+C\$ ${val.toStringAsFixed(2)}", style: const TextStyle(fontSize: 12)),
                          backgroundColor: Colors.amber.shade50,
                          side: BorderSide(color: Colors.amber.shade400),
                          onPressed: () {
                            setDialogState(() {
                              coinsController.text = val.toStringAsFixed(2);
                            });
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      "Motivo / Justificativa:",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: reasonController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: "Ex: Correção de scout na Rodada X",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),

                    if (_selectedRound > 0) ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          "Atualizar Histórico da Rodada $_selectedRound?",
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          "Ajusta também os campos patrimony e variation no histórico da rodada.",
                          style: TextStyle(fontSize: 11),
                        ),
                        value: updateHistory,
                        onChanged: (v) => setDialogState(() => updateHistory = v),
                      ),
                    ],

                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Prévia pós-compensação:",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Novo Saldo: C\$ ${newBalance.toStringAsFixed(2)}",
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                              Text("Novo Patrimônio: C\$ ${newPatrimony.toStringAsFixed(2)}",
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final double? amount =
                              double.tryParse(coinsController.text.replaceAll(',', '.'));
                          if (amount == null || amount == 0) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Informe uma quantidade válida de moedas.")),
                              );
                            }
                            return;
                          }

                          final messenger = ScaffoldMessenger.of(context);
                          setDialogState(() => isSaving = true);

                          try {
                            final authService =
                                Provider.of<AuthService>(context, listen: false);
                            final adminEmail = authService.adminEmail;

                            await _adminService.adjustTeamCoins(
                              teamId: team.id,
                              coinsAmount: amount,
                              reason: reasonController.text.trim(),
                              playerId: _selectedPlayer?.playerId,
                              playerName: _selectedPlayer?.name,
                              round: _selectedRound > 0 ? _selectedRound : _dbRound,
                              updateHistory: updateHistory,
                              adminEmail: adminEmail,
                            );

                            setState(() {
                              entry.currentBalance = double.parse(
                                  (entry.currentBalance + amount).toStringAsFixed(2));
                              entry.currentTeamValue = double.parse(
                                  (entry.currentTeamValue + amount).toStringAsFixed(2));
                            });

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  "Sucesso! C\$ ${amount.toStringAsFixed(2)} adicionados ao time ${team.teamName}!",
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            messenger.showSnackBar(
                              SnackBar(content: Text("Erro ao ajustar moedas: $e"), backgroundColor: Colors.red),
                            );
                          }
                        },
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: Text(isSaving ? "Salvando..." : "Confirmar"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- MODAL: AJUSTAR MOEDAS EM LOTE ---
  Future<void> _showBatchAdjustmentDialog() async {
    if (_teamsWithPlayer.isEmpty) return;

    final coinsController = TextEditingController(text: '1.00');
    final reasonController = TextEditingController(
      text: _selectedPlayer != null
          ? "Compensação de valorização em lote: ${_selectedPlayer!.name} (${_selectedRound == 0 ? 'Rodada Atual' : 'Rodada $_selectedRound'})"
          : "Compensação de valorização em lote",
    );
    String targetScope = 'starters_and_captains';
    bool updateHistory = _selectedRound > 0;
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final List<TeamLineupEntry> targetTeams = targetScope == 'all'
                ? _teamsWithPlayer
                : _teamsWithPlayer.where((e) => e.isStarter || e.isCaptain).toList();

            final double coins = double.tryParse(coinsController.text.replaceAll(',', '.')) ?? 0.0;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.purple.shade100,
                    child: Icon(Icons.playlist_add_check, color: Colors.purple.shade800),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Compensar em Lote",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: Text(
                        "Esta ação adicionará o mesmo valor de moedas para múltiplas equipes que escalaram ${_selectedPlayer?.name ?? 'o atleta'}.",
                        style: TextStyle(color: Colors.purple.shade900, fontSize: 13),
                      ),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      "Aplicar para quais equipes?",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        targetScope == 'starters_and_captains'
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: Colors.purple.shade700,
                      ),
                      title: Text(
                        "Apenas Titulares e Capitães (${_teamsWithPlayer.where((e) => e.isStarter || e.isCaptain).length} times)",
                        style: const TextStyle(fontSize: 13),
                      ),
                      onTap: () => setDialogState(() => targetScope = 'starters_and_captains'),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        targetScope == 'all'
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: Colors.purple.shade700,
                      ),
                      title: Text(
                        "Todos os times listados (${_teamsWithPlayer.length} times)",
                        style: const TextStyle(fontSize: 13),
                      ),
                      onTap: () => setDialogState(() => targetScope = 'all'),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      "Quantidade de Moedas por Time (C\$):",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: coinsController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^-?[0-9]*[.,]?[0-9]*')),
                      ],
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.paid, color: Colors.amber),
                        hintText: "Ex: 1.50",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),

                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [0.50, 1.00, 1.50, 2.00, 3.00, 5.00].map((val) {
                        return ActionChip(
                          label: Text("+C\$ ${val.toStringAsFixed(2)}", style: const TextStyle(fontSize: 12)),
                          backgroundColor: Colors.amber.shade50,
                          side: BorderSide(color: Colors.amber.shade400),
                          onPressed: () {
                            setDialogState(() {
                              coinsController.text = val.toStringAsFixed(2);
                            });
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      "Motivo / Justificativa:",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: reasonController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: "Ex: Correção de valorização do atleta na Rodada X",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),

                    if (_selectedRound > 0) ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          "Atualizar Histórico da Rodada $_selectedRound?",
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        value: updateHistory,
                        onChanged: (v) => setDialogState(() => updateHistory = v),
                      ),
                    ],

                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Text(
                        "Resumo: Serão adicionados C\$ ${coins.toStringAsFixed(2)} para cada um dos ${targetTeams.length} times selecionados.",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final double? amount =
                              double.tryParse(coinsController.text.replaceAll(',', '.'));
                          if (amount == null || amount == 0) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Informe uma quantidade válida de moedas.")),
                              );
                            }
                            return;
                          }

                          if (targetTeams.isEmpty) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Nenhuma equipe encontrada no escopo selecionado.")),
                              );
                            }
                            return;
                          }

                          final messenger = ScaffoldMessenger.of(context);
                          setDialogState(() => isSaving = true);

                          try {
                            final authService =
                                Provider.of<AuthService>(context, listen: false);
                            final adminEmail = authService.adminEmail;
                            final teamIds = targetTeams.map((e) => e.team.id).toList();

                            final int updated = await _adminService.batchAdjustTeamsCoins(
                              teamIds: teamIds,
                              coinsAmount: amount,
                              reason: reasonController.text.trim(),
                              playerId: _selectedPlayer?.playerId,
                              playerName: _selectedPlayer?.name,
                              round: _selectedRound > 0 ? _selectedRound : _dbRound,
                              updateHistory: updateHistory,
                              adminEmail: adminEmail,
                            );

                            setState(() {
                              for (var entry in targetTeams) {
                                entry.currentBalance = double.parse(
                                    (entry.currentBalance + amount).toStringAsFixed(2));
                                entry.currentTeamValue = double.parse(
                                    (entry.currentTeamValue + amount).toStringAsFixed(2));
                              }
                            });

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  "Sucesso! $updated times atualizados com +C\$ ${amount.toStringAsFixed(2)} cada!",
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            messenger.showSnackBar(
                              SnackBar(content: Text("Erro na compensação em lote: $e"), backgroundColor: Colors.red),
                            );
                          }
                        },
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.done_all),
                  label: Text(isSaving ? "Processando..." : "Aplicar em Lote"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- SELETOR DE ATLETA (BOTTOM SHEET) ---
  void _openPlayerPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            String sheetSearch = '';
            List<FantasyPlayer> sheetFiltered = _allPlayers;

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    "Selecione o Atleta",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Buscar atleta por nome ou posição...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (val) {
                      setSheetState(() {
                        sheetSearch = val.trim().toLowerCase();
                        if (sheetSearch.isEmpty) {
                          sheetFiltered = _allPlayers;
                        } else {
                          sheetFiltered = _allPlayers.where((p) {
                            return p.name.toLowerCase().contains(sheetSearch) ||
                                p.position.toLowerCase().contains(sheetSearch);
                          }).toList();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: sheetFiltered.isEmpty
                        ? const Center(child: Text("Nenhum atleta encontrado."))
                        : ListView.separated(
                            itemCount: sheetFiltered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final player = sheetFiltered[index];
                              final isSelected = _selectedPlayer?.playerId == player.playerId;

                              return ListTile(
                                selected: isSelected,
                                selectedTileColor: Colors.amber.shade50,
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage: player.photoUrl.isNotEmpty
                                      ? CachedNetworkImageProvider(player.photoUrl)
                                      : null,
                                  child: player.photoUrl.isEmpty
                                      ? const Icon(Icons.person, color: Colors.grey)
                                      : null,
                                ),
                                title: Text(
                                  player.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blue.shade200),
                                      ),
                                      child: Text(
                                        player.position.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "C\$ ${player.currentPrice.toStringAsFixed(2)}",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle, color: Colors.green)
                                    : const Icon(Icons.chevron_right, color: Colors.grey),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    _selectedPlayer = player;
                                  });
                                  _findTeamsWithSelectedPlayer();
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
  }

  // --- WIDGET PRINCIPAL ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Compensação de Moedas"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Atualizar Dados",
            onPressed: () {
              _loadInitialData();
            },
          ),
        ],
      ),
      body: _isLoadingInitial
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadInitialData,
                          child: const Text("Tentar Novamente"),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    _buildHeaderCard(),
                    Expanded(
                      child: _selectedPlayer == null
                          ? _buildEmptyAthleteState()
                          : _isLoadingTeams
                              ? const Center(child: CircularProgressIndicator())
                              : _buildTeamsList(),
                    ),
                  ],
                ),
    );
  }

  // --- CABEÇALHO ---
  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month, color: Colors.blueGrey, size: 20),
              const SizedBox(width: 8),
              const Text("Rodada de Análise:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _selectedRound,
                      items: [
                        DropdownMenuItem<int>(
                          value: 0,
                          child: Text(
                            "Escalação Ativa (Mercado Atual)",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        for (int r = 1; r <= _dbRound; r++)
                          DropdownMenuItem<int>(
                            value: r,
                            child: Text(
                              "Rodada $r (Histórico)",
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                      onChanged: (newRound) {
                        if (newRound != null && newRound != _selectedRound) {
                          setState(() {
                            _selectedRound = newRound;
                          });
                          _findTeamsWithSelectedPlayer();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (_selectedPlayer == null)
            ElevatedButton.icon(
              onPressed: _openPlayerPicker,
              icon: const Icon(Icons.person_search),
              label: const Text("Selecionar Atleta para Consultar"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            )
          else
            _buildSelectedPlayerCard(),
        ],
      ),
    );
  }

  // --- CARD DO ATLETA SELECIONADO ---
  Widget _buildSelectedPlayerCard() {
    final player = _selectedPlayer!;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade400, width: 1.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            backgroundImage: player.photoUrl.isNotEmpty
                ? CachedNetworkImageProvider(player.photoUrl)
                : null,
            child: player.photoUrl.isEmpty
                ? const Icon(Icons.person, size: 28, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.shade700),
                      ),
                      child: Text(
                        player.position.toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Preço: C\$ ${player.currentPrice.toStringAsFixed(2)}",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Var: ${player.lastPriceChange >= 0 ? '+' : ''}${player.lastPriceChange.toStringAsFixed(2)}",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: player.lastPriceChange >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.sync_alt, color: Colors.blueGrey),
            tooltip: "Trocar Atleta",
            onPressed: _openPlayerPicker,
          ),
        ],
      ),
    );
  }

  // --- ESTADO SEM ATLETA SELECIONADO ---
  Widget _buildEmptyAthleteState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_soccer, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              "Nenhum atleta selecionado",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              "Clique no botão acima para pesquisar um jogador e visualizar em quais times ele foi escalado nesta rodada.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  // --- LISTA DE TIMES ---
  Widget _buildTeamsList() {
    if (_teamsWithPlayer.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.group_off, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                "Nenhum time escalou ${_selectedPlayer?.name ?? 'este atleta'}",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _selectedRound == 0
                    ? "O atleta não está presente na escalação ativa de nenhuma equipe no mercado atual."
                    : "O atleta não foi escalado por nenhuma equipe na Rodada $_selectedRound.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final startersCount = _teamsWithPlayer.where((e) => e.isStarter).length;
    final benchCount = _teamsWithPlayer.where((e) => e.isBench).length;
    final captainsCount = _teamsWithPlayer.where((e) => e.isCaptain).length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.grey.shade50,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${_teamsWithPlayer.length} equipes escalaram este atleta",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "$startersCount Titulares  •  $benchCount Reservas  •  $captainsCount Capitães",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _showBatchAdjustmentDialog,
                    icon: const Icon(Icons.playlist_add_check, size: 18),
                    label: const Text("Ajustar em Lote", style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _teamSearchController,
                      decoration: InputDecoration(
                        hintText: "Buscar por time ou cartoleiro...",
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _teamRoleFilter,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text("Todos")),
                      DropdownMenuItem(value: 'starters', child: Text("Titulares")),
                      DropdownMenuItem(value: 'bench', child: Text("Reservas")),
                      DropdownMenuItem(value: 'captains', child: Text("Capitães")),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _teamRoleFilter = val;
                        });
                        _applyTeamFilter();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        Expanded(
          child: _filteredTeamsWithPlayer.isEmpty
              ? const Center(child: Text("Nenhuma equipe coincide com a busca."))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _filteredTeamsWithPlayer.length,
                  itemBuilder: (context, index) {
                    final entry = _filteredTeamsWithPlayer[index];
                    return _buildTeamCard(entry);
                  },
                ),
        ),
      ],
    );
  }

  // --- CARD DE CADA TIME ---
  Widget _buildTeamCard(TeamLineupEntry entry) {
    final team = entry.team;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showCoinAdjustmentDialog(entry),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              TeamLogoWidget(
                logoUrl: team.customLogoUrl,
                shieldType: team.shieldType,
                radius: 24,
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            team.teamName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (entry.isCaptain)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber.shade800),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: 12, color: Colors.amber.shade900),
                                const SizedBox(width: 2),
                                Text(
                                  "CAPITÃO",
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                ),
                              ],
                            ),
                          )
                        else if (entry.isStarter)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.green.shade700),
                            ),
                            child: Text(
                              "TITULAR",
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                            ),
                          )
                        else if (entry.isBench)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blue.shade600),
                            ),
                            child: Text(
                              "RESERVA",
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 2),

                    Text(
                      "Cartoleiro: ${team.ownerName}",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),

                    const SizedBox(height: 6),

                    Row(
                      children: [
                        Text(
                          "Saldo: C\$ ${entry.currentBalance.toStringAsFixed(2)}",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "Patrimônio: C\$ ${entry.currentTeamValue.toStringAsFixed(2)}",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              IconButton(
                icon: const Icon(Icons.monetization_on, color: Colors.amber),
                tooltip: "Adicionar Moedas",
                onPressed: () => _showCoinAdjustmentDialog(entry),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
