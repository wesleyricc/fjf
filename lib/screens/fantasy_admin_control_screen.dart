import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/fantasy_service.dart';
import '../services/fantasy_admin_service.dart';
import '../services/championship_service.dart'; // Importante para pegar a temporada ativa

class FantasyAdminControlScreen extends StatefulWidget {
  const FantasyAdminControlScreen({super.key});

  @override
  State<FantasyAdminControlScreen> createState() => _FantasyAdminControlScreenState();
}

class _FantasyAdminControlScreenState extends State<FantasyAdminControlScreen> {
  final FantasyAdminService _adminService = FantasyAdminService();
  
  bool _isLoading = false;
  String _log = "";
  
  late TextEditingController _seasonController;
  final TextEditingController _roundController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _seasonController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AUTOMATIZAÇÃO: Busca a temporada ativa no serviço de campeonato
    // Isso evita o risco de usar "2026" chumbado se estivermos em "2027_fjf"
    final currentSeasonId = Provider.of<ChampionshipService>(context).currentSeasonId;
    
    // Só preenche se o campo estiver vazio (para não sobrescrever edições do usuário)
    if (_seasonController.text.isEmpty && currentSeasonId.isNotEmpty) {
      _seasonController.text = currentSeasonId;
    }
  }

  @override
  void dispose() {
    _seasonController.dispose();
    _roundController.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _log = "$message\n\n$_log";
    });
  }

  // --- AÇÕES DO SISTEMA ---

  Future<void> _toggleMarket(FantasyService service, bool open, int round) async {
    setState(() => _isLoading = true);
    try {
      await service.setMarketStatus(isOpen: open, newRound: round);
      _addLog(open 
        ? "Mercado ABERTO para a rodada $round." 
        : "Mercado FECHADO na rodada $round.");
    } catch (e) {
      _addLog("Erro ao alterar mercado: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _processRoundClosing(BuildContext context, int currentRound) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Processar Rodada #$currentRound"),
        content: const Text(
          "Isso irá:\n"
          "1. Ler scouts da rodada.\n"
          "2. Calcular valorização.\n"
          "3. Atualizar times e patrimônio.\n\n"
          "Confirma?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              _executeCloseRound(currentRound);
            },
            child: const Text("PROCESSAR AGORA"),
          ),
        ],
      ),
    );
  }

  Future<void> _executeCloseRound(int round) async {
    setState(() => _isLoading = true);
    try {
      _addLog("Iniciando fechamento da Rodada $round...");
      String seasonId = _seasonController.text.trim(); // Usa o ID carregado automaticamente
      
      if (seasonId.isEmpty) {
         _addLog("ERRO: ID da temporada não identificado.");
         return;
      }

      String result = await _adminService.closeRoundFullRoutine(seasonId, round);
      _addLog(result);
    } catch (e) {
      _addLog("Erro Crítico: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _executeSyncAthletes(FantasyService service) async {
    final seasonId = _seasonController.text.trim();
    if (seasonId.isEmpty) {
      _addLog("ERRO: Campo Temporada vazio.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      _addLog("Sincronizando atletas da temporada $seasonId...");
      final res = await service.populateMarketFromSeason(seasonId);
      _addLog("Resultado Sync: $res");
    } catch (e) {
      _addLog("Erro no Sync: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _executeReprocessHistory() async {
    if (_roundController.text.isEmpty) {
      _addLog("ERRO: Informe a rodada FINAL no campo acima.");
      return;
    }
    
    final seasonId = _seasonController.text.trim();
    if (seasonId.isEmpty) {
      _addLog("ERRO: ID da temporada vazio.");
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ RECONSTRUÇÃO TOTAL"),
        content: Text(
          "Esta ação irá ignorar os dados atuais e RECALCULAR TUDO do zero, da Rodada 1 até a rodada informada.\n\n"
          "Temporada Alvo: $seasonId\n\n"
          "Ela usará os SCOUTS das partidas como única fonte da verdade.\n\n"
          "Isso pode demorar alguns segundos. Continuar?"
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("SIM, RECALCULAR", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      int maxRound = int.parse(_roundController.text);
      _addLog("Iniciando RECONSTRUÇÃO (R1 -> R$maxRound) na temporada $seasonId...");
      
      String result = await _adminService.reprocessFullHistory(seasonId, maxRound);
      
      _addLog(result);
    } catch (e) {
      _addLog("Erro: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fantasyService = Provider.of<FantasyService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Painel Admin Fantasy"),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: fantasyService.streamMarketStatus(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data ?? {'is_open': true, 'current_round': 1};
          final bool isOpen = data['is_open'] ?? true;
          final int currentRound = data['current_round'] ?? 1;

          if (_roundController.text.isEmpty) {
            _roundController.text = currentRound.toString();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(isOpen, currentRound),

                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        const Text("Configuração da Operação", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _seasonController,
                                decoration: const InputDecoration(
                                  labelText: "Temporada ID (Ativa)", 
                                  border: OutlineInputBorder(),
                                  helperText: "Carregado automaticamente"
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _roundController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Rodada Alvo", 
                                  border: OutlineInputBorder(),
                                  helperText: "Rodada foco"
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                const Text("Rotina Padrão", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),

                if (isOpen)
                  _buildActionTile(
                    icon: Icons.lock,
                    color: Colors.orange,
                    title: "Fechar Mercado",
                    subtitle: "Bloqueia escalações.",
                    onTap: () => _toggleMarket(fantasyService, false, currentRound),
                  ),

                if (!isOpen)
                  _buildActionTile(
                    icon: Icons.calculate,
                    color: Colors.blue,
                    title: "Processar Fechamento",
                    subtitle: "Calcula rodada atual.",
                    onTap: () => _processRoundClosing(context, currentRound),
                  ),

                if (!isOpen)
                  _buildActionTile(
                    icon: Icons.lock_open,
                    color: Colors.green,
                    title: "Reabrir Mercado (Próxima)",
                    subtitle: "Inicia R${currentRound + 1}.",
                    onTap: () => _toggleMarket(fantasyService, true, currentRound + 1),
                  ),
                  
                const Divider(height: 30),
                const Text("Setup & Manutenção", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                
                 _buildActionTile(
                    icon: Icons.cloud_download,
                    color: Colors.purple,
                    title: "Sincronizar Atletas",
                    subtitle: "Importa novos jogadores da temporada selecionada acima.",
                    onTap: () => _executeSyncAthletes(fantasyService),
                  ),

                const SizedBox(height: 10),
                _buildActionTile(
                  icon: Icons.history_edu,
                  color: Colors.red,
                  title: "Reprocessar Tudo (Baseado em Scouts)",
                  subtitle: "Recalcula histórico, preços e times do zero.",
                  onTap: _executeReprocessHistory,
                ),

                const SizedBox(height: 20),
                const Text("Log:", style: TextStyle(fontWeight: FontWeight.bold)),
                Container(
                  height: 150,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade400)
                  ),
                  child: SingleChildScrollView(child: Text(_log)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(bool isOpen, int round) {
    return Card(
      color: isOpen ? Colors.green[50] : Colors.red[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(isOpen ? Icons.check_circle : Icons.remove_circle, 
                  color: isOpen ? Colors.green : Colors.red, size: 30),
                const SizedBox(width: 10),
                Text(
                  isOpen ? "MERCADO ABERTO" : "MERCADO FECHADO",
                  style: TextStyle(
                    fontSize: 22, 
                    fontWeight: FontWeight.bold,
                    color: isOpen ? Colors.green[800] : Colors.red[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text("Rodada Atual: #$round", style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon, 
    required Color color, 
    required String title, 
    required String subtitle, 
    required VoidCallback onTap
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: _isLoading ? null : onTap,
      ),
    );
  }
}