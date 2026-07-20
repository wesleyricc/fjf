import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/fantasy_league_model.dart';
import '../../services/fantasy_admin_service.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/fantasy_service.dart';
import '../../services/championship_service.dart';
import '../../utils/app_feedback.dart';
import '../admin/admin_fantasy_status_screen.dart';
import '../../viewmodels/fantasy_admin_viewmodel.dart';
import 'admin_sponsored_leagues_screen.dart';

class FantasyAdminControlScreen extends StatefulWidget {
  const FantasyAdminControlScreen({super.key});

  @override
  State<FantasyAdminControlScreen> createState() =>
      _FantasyAdminControlScreenState();
}

class _FantasyAdminControlScreenState extends State<FantasyAdminControlScreen> {
  final FantasyAdminViewModel _viewModel = FantasyAdminViewModel();
  final TextEditingController _roundController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Carrega a rodada atual do banco ao abrir a tela
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stream = Provider.of<FantasyService>(context, listen: false)
          .streamMarketStatus();
      stream.first.then((data) {
        if (mounted) {
          setState(() {
            _roundController.text = (data['current_round'] ?? 1).toString();
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _roundController.dispose();
    super.dispose();
  }

  // --- MÉTODOS DE AÇÃO ---

  Future<void> _syncMarket() async {
    final confirm = await _showConfirmDialog(
        "Sincronizar Mercado",
        "Isso importará jogadores novos da temporada oficial para o Fantasy.\n\n"
            "Preços e pontos de jogadores já existentes NÃO serão alterados.");
    if (!confirm) return;

    final seasonId = Provider.of<ChampionshipService>(context, listen: false)
        .currentSeasonId;
    final result = await _viewModel.syncMarket(seasonId);
    if (mounted) _showFeedback(result, isError: result.contains("Erro"));
  }

  Future<void> _reprocessHistory(int maxRound) async {
    final confirm = await _showConfirmDialog(
        "Reprocessar Todo o Campeonato",
        "⚠️ ZONA DE PERIGO ⚠️\n\n"
            "Isso vai apagar a pontuação atual e recalcular TUDO desde a Rodada 1 até a Rodada $maxRound usando os scouts atualizados das súmulas.\n\n"
            "O patrimônio livre dos usuários que já venderam jogadores na rodada atual não pode ser desfeito. Tem certeza absoluta?");
    if (!confirm) return;

    final seasonId = Provider.of<ChampionshipService>(context, listen: false)
        .currentSeasonId;
    final result = await _viewModel.reprocessHistory(seasonId, maxRound);
    if (mounted) _showFeedback(result, isError: result.contains("Erro"));
  }

  Future<void> _toggleMarket(bool isOpenNow, int currentRound) async {
    final nextStatus = !isOpenNow;
    final actionLabel = nextStatus ? "ABRIR" : "FECHAR";
    final targetRound = int.tryParse(_roundController.text) ?? currentRound;

    final confirm = await _showConfirmDialog(
        "$actionLabel Mercado",
        "Você está prestes a $actionLabel o mercado para a Rodada $targetRound.\n\n"
            "${nextStatus ? 'Os usuários poderão escalar times.' : 'As escalações serão bloqueadas.'}");
    if (!confirm) return;

    final result = await _viewModel.toggleMarket(isOpenNow, targetRound);
    if (mounted) _showFeedback(result, isError: result.contains("Erro"));
  }

  Future<void> _processRound(int round) async {
    final confirm = await _showConfirmDialog(
        "Processar Rodada $round",
        "⚠️ ATENÇÃO: AÇÃO IRREVERSÍVEL\n\n"
            "Isso enviará o comando para a NUVEM (Cloud Functions) para:\n"
            "1. Calcular pontuação de todos os jogadores (Scouts da rodada $round).\n"
            "2. Calcular valorização/desvalorização (Cartoletas).\n"
            "3. Atualizar o patrimônio de TODOS os times.\n\n"
            "Certifique-se de que TODOS os jogos da rodada foram finalizados e os scouts lançados.");
    if (!confirm) return;

    final seasonId = Provider.of<ChampionshipService>(context, listen: false)
        .currentSeasonId;
    final result = await _viewModel.processRound(seasonId, round);
    if (mounted) _showFeedback(result, isError: result.contains("Erro"));
  }

  // --- HELPERS VISUAIS ---

  Future<bool> _showConfirmDialog(String title, String content) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title,
                style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold)),
            content: Text(content),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancelar")),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white),
                  child: const Text("Confirmar")),
            ],
          ),
        ) ??
        false;
  }

  void _showFeedback(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : Colors.green,
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Painel Admin Fantasy")),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: Provider.of<FantasyService>(context).streamMarketStatus(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(child: Text("Erro: ${snapshot.error}"));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final data = snapshot.data!;
          final bool isOpen = data['is_open'] ?? true;
          final int dbRound = data['current_round'] ?? 1;

          return ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. STATUS ATUAL
                    _buildStatusCard(isOpen, dbRound),

                    const SizedBox(height: 24),

                    // 2. CONTROLE DA RODADA (INPUT)
                    const Text("Configuração da Rodada",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _roundController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: "Número da Rodada",
                        hintText: "Ex: $dbRound",
                        border: const OutlineInputBorder(),
                        helperText:
                            "Define qual rodada será processada ou aberta.",
                        prefixIcon: const Icon(Icons.numbers),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // --- NOVO: GERENCIAMENTO DE STATUS ---
                    const Text("Mercado & Jogadores",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const AdminFantasyStatusScreen()));
                      },
                      icon: const Icon(Icons.manage_accounts),
                      label: const Text("Gerenciar Status dos Atletas"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 12),

                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSponsoredLeaguesScreen()));
                      },
                      icon: const Icon(Icons.star),
                      label: const Text("Gerenciar Ligas Patrocinadas"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: Colors.amber.shade600,
                        foregroundColor: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // 3. GAME LOOP (Ciclo do Jogo)
                    const Text("Ciclo do Jogo (Game Loop)",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),

                    _buildStepCard(
                      step: "1",
                      title: "FECHAR MERCADO",
                      subtitle: "Bloqueia escalações. Faça antes do 1º jogo.",
                      icon: Icons.lock,
                      color: Colors.redAccent,
                      isAvailable: isOpen && !_viewModel.isLoading,
                      onTap: () => _toggleMarket(isOpen,
                          int.tryParse(_roundController.text) ?? dbRound),
                    ),

                    // PASSO 2: PROCESSAR
                    _buildStepCard(
                      step: "2",
                      title: "PROCESSAR RODADA (NUVEM)",
                      subtitle:
                          "Calcula pontos e cartoletas via Cloud Functions.",
                      icon: Icons.cloud_sync,
                      color: Colors.purple,
                      isAvailable: !isOpen &&
                          !_viewModel.isLoading, // Só processa se fechado
                      onTap: () => _processRound(
                          int.tryParse(_roundController.text) ?? dbRound),
                    ),

                    // PASSO 3: REABRIR
                    _buildStepCard(
                      step: "3",
                      title: "REABRIR MERCADO",
                      subtitle: "Prepara para a próxima rodada.",
                      icon: Icons.lock_open,
                      color: Colors.green,
                      isAvailable: !isOpen && !_viewModel.isLoading,
                      onTap: () {
                        // Sugere incrementar rodada ao reabrir
                        final currentVal =
                            int.tryParse(_roundController.text) ?? dbRound;
                        _roundController.text = (currentVal + 1).toString();
                        _toggleMarket(isOpen, currentVal + 1);
                      },
                    ),

                    const Divider(height: 40),

                    // 4. MANUTENÇÃO
                    const Text("Manutenção",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _viewModel.isLoading ? null : _syncMarket,
                      icon: const Icon(Icons.sync),
                      label: const Text(
                          "Sincronizar Jogadores (Season -> Fantasy)"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Theme.of(context).primaryColor),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // BOTÃO DE REPROCESSAMENTO
                    OutlinedButton.icon(
                      onPressed: _viewModel.isLoading
                          ? null
                          : () {
                              final targetRound =
                                  int.tryParse(_roundController.text) ??
                                      dbRound;
                              _reprocessHistory(targetRound);
                            },
                      icon: const Icon(Icons.warning_amber_rounded),
                      label: const Text("Reprocessar Histórico Completo"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(bool isOpen, int round) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isOpen ? Colors.green[50] : Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Icon(isOpen ? Icons.check_circle : Icons.do_not_disturb_on,
                size: 40, color: isOpen ? Colors.green : Colors.red),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOpen ? "MERCADO ABERTO" : "MERCADO FECHADO",
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: isOpen ? Colors.green[800] : Colors.red[800]),
                  ),
                  Text("Rodada Atual: $round",
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required String step,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isAvailable,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: isAvailable ? 2 : 0,
      color: isAvailable ? Colors.white : Colors.grey[200],
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isAvailable ? color : Colors.grey[400],
          child: Text(step,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isAvailable ? Colors.black87 : Colors.grey[600])),
        subtitle: Text(subtitle,
            style: TextStyle(
                fontSize: 12,
                color: isAvailable ? Colors.black54 : Colors.grey[500])),
        trailing: Icon(icon, color: isAvailable ? color : Colors.grey[400]),
        enabled: isAvailable,
        onTap: isAvailable ? onTap : null,
      ),
    );
  }
}
