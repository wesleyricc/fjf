import 'package:flutter/material.dart';
import '../../../viewmodels/admin_bolao_viewmodel.dart';
import 'package:provider/provider.dart';

class AdminBolaoSettingsTab extends StatelessWidget {
  const AdminBolaoSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Escuta o ViewModel inteiro, ou o Provider
    final viewModel = Provider.of<AdminBolaoViewModel>(context);

    Future<void> _confirmTogglePredictions(bool newValue) async {
      final String acao = newValue ? "ABRIR" : "FECHAR";
      final Color corBotao = newValue ? Colors.green : Colors.red;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: corBotao, size: 28),
              const SizedBox(width: 8),
              Text("$acao Mercado?"),
            ],
          ),
          content: Text("Tem certeza que deseja $acao o mercado de palpites para todos os usuários do Bolão?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: corBotao, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text("Sim, $acao"),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await viewModel.togglePredictionsStatus(newValue);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(newValue ? "🔓 Palpites ABERTOS!" : "🔒 Palpites BLOQUEADOS!"), 
            backgroundColor: newValue ? Colors.green : Colors.red
          ));
        }
      }
    }

    Future<void> _seedMatches() async {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.sync_problem, color: Colors.red, size: 28),
              const SizedBox(width: 8),
              Text("Regerar Jogos?"),
            ],
          ),
          content: const Text(
            "Tem certeza que deseja forçar a atualização dos 104 jogos?\n\n"
            "Esta ação aplicará as configurações padrão para os times, mas NÃO apagará os placares de jogos encerrados, pois o sistema de mesclagem (merge) de segurança está ativado."
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Sim, Regerar / Atualizar"),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      try {
        await viewModel.seedMatches();
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tabela de 104 jogos sincronizada com segurança! ⚽"), backgroundColor: Colors.green));
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
      }
    }

    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.blueGrey[50],
      child: Column(
        children: [
          SwitchListTile(
            title: const Text("Status de Palpites (Geral)", style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(viewModel.isPredictionsOpen ? "MERCADO ABERTO" : "MERCADO FECHADO"),
            value: viewModel.isPredictionsOpen,
            activeColor: Colors.green,
            onChanged: viewModel.isLoading ? null : _confirmTogglePredictions,
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: viewModel.isLoading ? null : _seedMatches,
            icon: const Icon(Icons.download),
            label: viewModel.isLoading 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("REGERAR / ATUALIZAR JOGOS (104 partidas)"),
          ),
        ],
      ),
    );
  }
}
