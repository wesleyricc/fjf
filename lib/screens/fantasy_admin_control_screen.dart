import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/fantasy_service.dart';
import '../services/fantasy_admin_service.dart';

class FantasyAdminControlScreen extends StatefulWidget {
  const FantasyAdminControlScreen({super.key});

  @override
  State<FantasyAdminControlScreen> createState() => _FantasyAdminControlScreenState();
}

class _FantasyAdminControlScreenState extends State<FantasyAdminControlScreen> {
  bool _isLoading = false;

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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. STATUS ATUAL
              _buildStatusCard(isOpen, currentRound),

              const SizedBox(height: 20),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text("Controles de Rodada", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              ),

              // 2. BOTÃO: FECHAR MERCADO (Para iniciar os jogos)
              if (isOpen)
                _buildActionTile(
                  icon: Icons.lock,
                  color: Colors.orange,
                  title: "Fechar Mercado",
                  subtitle: "Bloqueia escalações. Use antes do primeiro jogo.",
                  onTap: () => _toggleMarket(fantasyService, false, currentRound),
                ),

              // 3. BOTÃO: PROCESSAR PONTOS (Fim da Rodada)
              if (!isOpen)
                _buildActionTile(
                  icon: Icons.calculate,
                  color: Colors.blue,
                  title: "Processar Fechamento",
                  subtitle: "Calcula valorização e consolida pontos nos times.",
                  onTap: () => _processRoundClosing(context, currentRound),
                ),

              // 4. BOTÃO: REABRIR MERCADO (Próxima Rodada)
              if (!isOpen)
                _buildActionTile(
                  icon: Icons.lock_open,
                  color: Colors.green,
                  title: "Reabrir Mercado (Rodada ${currentRound + 1})",
                  subtitle: "Inicia a próxima rodada com novos preços.",
                  onTap: () => _toggleMarket(fantasyService, true, currentRound + 1),
                ),
                
              const Divider(),
              
               // 5. FERRAMENTAS EXTRAS
               _buildActionTile(
                  icon: Icons.cloud_sync,
                  color: Colors.grey,
                  title: "Sincronizar Atletas",
                  subtitle: "Importa novos jogadores/técnicos do campeonato.",
                  onTap: () async {
                     final res = await fantasyService.populateMarketFromSeason('2025_fjf'); // ID da sua season
                     if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res)));
                  },
                ),
            ],
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
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: _isLoading ? null : onTap,
      ),
    );
  }

  // --- AÇÕES ---

  Future<void> _toggleMarket(FantasyService service, bool open, int round) async {
    setState(() => _isLoading = true);
    await service.setMarketStatus(isOpen: open, newRound: round);
    setState(() => _isLoading = false);
  }

  Future<void> _processRoundClosing(BuildContext context, int currentRound) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Processar Rodada #$currentRound"),
        content: const Text(
          "Isso irá:\n"
          "1. Calcular valorização baseada na última parcial.\n"
          "2. Somar os pontos aos times dos usuários.\n"
          "3. Atualizar o patrimônio de todos.\n\n"
          "Tem certeza que os jogos acabaram e os scouts estão corretos?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () async {
              Navigator.pop(ctx);
              _executeProcess(context, currentRound);
            },
            child: const Text("Processar"),
          ),
        ],
      ),
    );
  }

  Future<void> _executeProcess(BuildContext context, int round) async {
    setState(() => _isLoading = true);
    
    // Chama o serviço de Admin que criamos antes
    final adminService = FantasyAdminService();
    // Ajuste o ID da temporada conforme necessário
    final result = await adminService.closeRoundFullRoutine("2025_fjf", round);

    setState(() => _isLoading = false);

    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Resultado"),
          content: Text(result),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
        ),
      );
    }
  }
}