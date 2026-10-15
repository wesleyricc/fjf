import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/fantasy_models.dart';
import '../../models/fantasy_scout_appeal_model.dart';
import '../../models/match_model.dart';
import '../../services/championship_service.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/fantasy_scout_appeal_service.dart';
import '../../services/fantasy_service.dart';
import '../../services/match_service.dart';
import '../../widgets/fantasy/fantasy_bottom_nav_bar.dart';
import '../../widgets/ui/optimized_network_image.dart';

class FantasyScoutReviewScreen extends StatefulWidget {
  const FantasyScoutReviewScreen({super.key});

  @override
  State<FantasyScoutReviewScreen> createState() =>
      _FantasyScoutReviewScreenState();
}

class _FantasyScoutReviewScreenState extends State<FantasyScoutReviewScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  final FantasyScoutAppealService _appealService = FantasyScoutAppealService();
  final MatchService _matchService = MatchService();

  // Estado do formulário
  int _selectedRound = 1;
  int _maxRound = 10;
  bool _isLoadingInitialData = true;
  bool _isSubmitting = false;
  String _userTeamName = 'Meu Time';

  List<MatchModel> _roundMatches = [];
  MatchModel? _selectedMatch;

  List<FantasyPlayer> _allMarketPlayers = [];
  List<FantasyPlayer> _filteredPlayers = [];
  FantasyPlayer? _selectedPlayer;

  String _selectedPeriod = '2º Tempo';
  final TextEditingController _minuteController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _videoUrlController = TextEditingController();

  String _selectedScoutType = 'Finalização na Trave';
  String _selectedActionType = 'Adicionar scout não computado';

  final List<String> _scoutTypes = [
    'Finalização na Trave',
    'Gol',
    'Assistência',
    'Defesa Difícil',
    'Pênalti Defendido',
    'Jogo Sem Sofrer Gol (SG)',
    'Cartão Amarelo',
    'Cartão Vermelho',
    'Pênalti Perdido',
    'Falta/Tiro Livre Perdido',
    'Gol Contra',
    'Craque da Partida',
    'Outro Lance',
  ];

  final List<String> _actionTypes = [
    'Adicionar scout não computado',
    'Remover scout computado indevidamente',
    'Corrigir o atleta autor do lance',
  ];

  final List<String> _periods = [
    '1º Tempo',
    '2º Tempo',
    'Prorrogação',
    'Pênaltis',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _minuteController.dispose();
    _descriptionController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final champService =
        Provider.of<ChampionshipService>(context, listen: false);
    final fantasyService = Provider.of<FantasyService>(context, listen: false);
    final authService = Provider.of<FantasyAuthService>(context, listen: false);

    try {
      final status = await fantasyService.streamMarketStatus().first;
      _selectedRound = (status['current_round'] as num?)?.toInt() ?? 1;
      _maxRound = _selectedRound > 1 ? _selectedRound : 10;

      // Carrega o time do usuário logado
      final user = authService.user;
      if (user != null) {
        try {
          final teamDoc = await FirebaseFirestore.instance
              .collection('fantasy_teams')
              .doc(user.uid)
              .get();
          if (teamDoc.exists && teamDoc.data() != null) {
            _userTeamName = teamDoc.data()!['team_name'] ?? 'Meu Time';
          }
        } catch (_) {}
      }

      // Carrega os jogadores de mercado
      _allMarketPlayers = await fantasyService.getAllPlayers();

      // Carrega partidas da rodada selecionada
      await _loadMatchesForRound(_selectedRound, champService.currentSeasonId);
    } catch (e) {
      debugPrint("Erro ao carregar dados iniciais de revisão: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingInitialData = false);
      }
    }
  }

  Future<void> _loadMatchesForRound(int round, String seasonId) async {
    if (seasonId.isEmpty) return;

    try {
      final matchesStream =
          _matchService.streamMatches(seasonId, round: round);
      final matches = await matchesStream.first;

      if (mounted) {
        setState(() {
          _roundMatches = matches;
          _selectedMatch = matches.isNotEmpty ? matches.first : null;
          _updateFilteredPlayers();
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar partidas da rodada $round: $e");
    }
  }

  String _getPlayerTeamName(FantasyPlayer player) {
    if (_selectedMatch != null) {
      if (player.teamId == _selectedMatch!.homeTeamId) {
        return _selectedMatch!.homeTeamName;
      }
      if (player.teamId == _selectedMatch!.awayTeamId) {
        return _selectedMatch!.awayTeamName;
      }
    }
    return player.position;
  }

  void _updateFilteredPlayers() {
    if (_selectedMatch == null || _allMarketPlayers.isEmpty) {
      _filteredPlayers = List.from(_allMarketPlayers);
      return;
    }

    final homeId = _selectedMatch!.homeTeamId;
    final awayId = _selectedMatch!.awayTeamId;

    // Filtra jogadores que pertencem aos times do jogo
    final matchPlayers = _allMarketPlayers
        .where((p) => p.teamId == homeId || p.teamId == awayId)
        .toList();

    setState(() {
      _filteredPlayers =
          matchPlayers.isNotEmpty ? matchPlayers : _allMarketPlayers;
      if (_selectedPlayer != null &&
          !_filteredPlayers.any((p) => p.playerId == _selectedPlayer!.playerId)) {
        _selectedPlayer = null;
      }
    });
  }

  Future<void> _submitAppeal() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Por favor, selecione o atleta envolvido no lance."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final champService =
        Provider.of<ChampionshipService>(context, listen: false);
    final user = authService.user;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Faça login para enviar uma contestação."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String matchLabel = _selectedMatch != null
          ? "${_selectedMatch!.homeTeamName} vs ${_selectedMatch!.awayTeamName}"
          : "Partida Rodada $_selectedRound";

      final appeal = FantasyScoutAppeal(
        id: '',
        userId: user.uid,
        userName: user.displayName ?? 'Cartoleiro',
        userTeamName: _userTeamName,
        seasonId: champService.currentSeasonId,
        round: _selectedRound,
        matchId: _selectedMatch?.id ?? '',
        matchLabel: matchLabel,
        period: _selectedPeriod,
        minute: _minuteController.text.trim(),
        playerId: _selectedPlayer!.playerId,
        playerName: _selectedPlayer!.name,
        playerTeamName: _getPlayerTeamName(_selectedPlayer!),
        scoutType: _selectedScoutType,
        actionType: _selectedActionType,
        description: _descriptionController.text.trim(),
        videoUrl: _videoUrlController.text.trim().isNotEmpty
            ? _videoUrlController.text.trim()
            : null,
        createdAt: DateTime.now(),
      );

      await _appealService.submitAppeal(appeal);

      if (mounted) {
        _minuteController.clear();
        _descriptionController.clear();
        _videoUrlController.clear();

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 8),
                Text("Solicitação Enviada!"),
              ],
            ),
            content: const Text(
              "Sua solicitação de revisão de scout foi enviada com sucesso para a comissão de auditoria.\n\n"
              "Você pode acompanhar o parecer e resposta da nossa equipe na aba 'Minhas Solicitações'.",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _tabController.animateTo(1); // Vai para "Minhas Solicitações"
                },
                child: const Text("OK, Entendido"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao enviar solicitação: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Revisão de Scouts"),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.add_circle_outline), text: "Nova Solicitação"),
            Tab(icon: Icon(Icons.history_edu), text: "Minhas Solicitações"),
          ],
        ),
      ),
      bottomNavigationBar:
          const FantasyBottomNavBar(currentRoute: '/fantasy-scouts'),
      body: _isLoadingInitialData
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFormTab(),
                _buildMyRequestsTab(),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // ABA 1: FORMULÁRIO DE NOVA SOLICITAÇÃO
  // ---------------------------------------------------------------------------
  Widget _buildFormTab() {
    final champService = Provider.of<ChampionshipService>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Informativo
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade800, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Transparência & Fair Play",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Notou algum lance (ex: finalização na trave, defesa difícil, assistência) que não foi marcado ou computado errado? "
                          "Informe o tempo do jogo e o lance abaixo. Nossa equipe analisará a súmula e gravação!",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade900,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Rodada
            const Text(
              "1. Rodada",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              value: _selectedRound,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              items: List.generate(_maxRound, (index) => index + 1)
                  .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text("Rodada $r"),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedRound = val);
                  _loadMatchesForRound(val, champService.currentSeasonId);
                }
              },
            ),

            const SizedBox(height: 16),

            // Partida
            const Text(
              "2. Partida / Jogo",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            if (_roundMatches.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Text(
                  "Nenhuma partida cadastrada nesta rodada.",
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
              )
            else
              DropdownButtonFormField<MatchModel>(
                value: _selectedMatch,
                isExpanded: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: _roundMatches.map((m) {
                  return DropdownMenuItem<MatchModel>(
                    value: m,
                    child: Text(
                      "${m.homeTeamName} vs ${m.awayTeamName}",
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedMatch = val;
                    _updateFilteredPlayers();
                  });
                },
              ),

            const SizedBox(height: 16),

            // Tempo do Jogo
            const Text(
              "3. Tempo e Minuto do Jogo",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    value: _selectedPeriod,
                    decoration: InputDecoration(
                      labelText: "Período",
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: _periods
                        .map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedPeriod = val);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _minuteController,
                    decoration: InputDecoration(
                      labelText: "Minuto / Tempo",
                      hintText: "Ex: 14' (ou 12:30)",
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return "Informe o minuto";
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Atleta Envolvido
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "4. Atleta Envolvido",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (_selectedMatch != null &&
                    _filteredPlayers.length < _allMarketPlayers.length)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _filteredPlayers = List.from(_allMarketPlayers);
                      });
                    },
                    child: const Text("Mostrar todos os atletas", style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<FantasyPlayer>(
              value: _selectedPlayer,
              isExpanded: true,
              hint: const Text("Selecione o jogador"),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              items: _filteredPlayers.map((p) {
                return DropdownMenuItem<FantasyPlayer>(
                  value: p,
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: p.photoUrl.isNotEmpty
                            ? OptimizedNetworkImage(
                                imageUrl: p.photoUrl,
                                width: 24,
                                height: 24,
                                fit: BoxFit.cover,
                                fallbackIcon: Icons.person,
                              )
                            : const Icon(Icons.person, size: 14),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "${p.name} (${p.position})",
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        _getPlayerTeamName(p),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                setState(() => _selectedPlayer = val);
              },
              validator: (val) =>
                  val == null ? "Selecione o atleta envolvido" : null,
            ),

            const SizedBox(height: 16),

            // Scout Contestador e Ação
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "5. Tipo de Scout",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _selectedScoutType,
                        isExpanded: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        items: _scoutTypes
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedScoutType = val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "6. Ação Solicitada",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _selectedActionType,
                        isExpanded: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        items: _actionTypes
                            .map((a) => DropdownMenuItem(
                                  value: a,
                                  child: Text(a, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedActionType = val);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Descrição Detalhada
            const Text(
              "7. Descrição do Lance",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText:
                    "Descreva o lance com o máximo de detalhes possível:\n"
                    "Ex: Aos 14 minutos do 2º tempo, o atleta chutou rasteiro da ala esquerda, a bola desviou na trave antes de sair pela linha de fundo, porém não foi computado o scout de Finalização na Trave.",
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(14),
              ),
              validator: (val) {
                if (val == null || val.trim().length < 10) {
                  return "Por favor, detalhe o lance com pelo menos 10 caracteres.";
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Link do Vídeo (Opcional)
            const Text(
              "8. Link de Vídeo / Transmissão (Opcional)",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _videoUrlController,
              decoration: InputDecoration(
                hintText: "Ex: https://youtube.com/live/... ou link do Instagram",
                prefixIcon: const Icon(Icons.link),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),

            const SizedBox(height: 24),

            // Botão Enviar
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitAppeal,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _isSubmitting ? "Enviando..." : "Enviar Contestação para Análise",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ABA 2: MINHAS SOLICITAÇÕES
  // ---------------------------------------------------------------------------
  Widget _buildMyRequestsTab() {
    final authService = Provider.of<FantasyAuthService>(context);
    final user = authService.user;

    if (user == null) {
      return const Center(child: Text("Faça login para visualizar suas solicitações."));
    }

    return StreamBuilder<List<FantasyScoutAppeal>>(
      stream: _appealService.streamUserAppeals(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text("Erro ao carregar solicitações: ${snapshot.error}"));
        }

        final appeals = snapshot.data ?? [];

        if (appeals.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_edu, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text(
                    "Nenhuma solicitação enviada",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Quando você contestar algum scout, o status e o parecer da nossa comissão técnica aparecerão aqui.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () => _tabController.animateTo(0),
                    icon: const Icon(Icons.add),
                    label: const Text("Criar Nova Solicitação"),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: appeals.length,
          itemBuilder: (context, index) {
            final item = appeals[index];
            return _buildAppealCard(item);
          },
        );
      },
    );
  }

  Widget _buildAppealCard(FantasyScoutAppeal appeal) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: appeal.statusColor.withValues(alpha: 0.3), width: 1.2),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho: Status + Data
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: appeal.statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: appeal.statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(appeal.statusIcon, size: 14, color: appeal.statusColor),
                      const SizedBox(width: 5),
                      Text(
                        appeal.statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: appeal.statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  dateFormat.format(appeal.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Jogo e Rodada
            Row(
              children: [
                const Icon(Icons.sports_soccer, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "${appeal.matchLabel} • Rodada ${appeal.round}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // Atleta e Lance
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        "${appeal.playerName} (${appeal.playerTeamName})",
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        "${appeal.period} • Minuto: ${appeal.minute}",
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.fact_check, size: 16, color: Colors.deepPurple),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "${appeal.actionType}: ${appeal.scoutType}",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Descrição do Usuário
            const Text(
              "Descrição do lance:",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 2),
            Text(
              appeal.description,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.3),
            ),

            if (appeal.videoUrl != null && appeal.videoUrl!.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final uri = Uri.tryParse(appeal.videoUrl!);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Row(
                  children: [
                    const Icon(Icons.play_circle_fill, size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "Abrir vídeo / transmissão informada",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade800,
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // PARECER DA COMISSÃO (Se já avaliada)
            if (appeal.adminFeedback != null && appeal.adminFeedback!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: appeal.status == 'approved'
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: appeal.status == 'approved'
                        ? Colors.green.shade300
                        : Colors.red.shade300,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          appeal.status == 'approved'
                              ? Icons.verified_user
                              : Icons.gavel,
                          size: 16,
                          color: appeal.statusColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Parecer da Comissão Técnica FJF:",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: appeal.statusColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appeal.adminFeedback!,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade900, height: 1.3),
                    ),
                    if (appeal.reviewedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        "Avaliado em ${dateFormat.format(appeal.reviewedAt!)}${appeal.reviewedBy != null ? ' por ${appeal.reviewedBy}' : ''}",
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
