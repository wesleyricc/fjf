import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../viewmodels/admin_bolao_viewmodel.dart';
import 'admin_bolao_modals.dart';

class AdminBolaoMiniBoloesTab extends StatelessWidget {
  const AdminBolaoMiniBoloesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<AdminBolaoViewModel>(context);

    Future<void> _deleteMiniBolao(String id, String title) async {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Excluir Mini Bolão?"),
          content: Text("Tem certeza que deseja apagar a sala '$title'?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Excluir", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await viewModel.deleteMiniLeague(id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sala excluída com sucesso."), backgroundColor: Colors.red));
        }
      }
    }

    Widget _buildMiniBoloesList() {
      return StreamBuilder<QuerySnapshot>(
        stream: viewModel.streamMiniLeagues(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(padding: EdgeInsets.all(16.0), child: Center(child: CircularProgressIndicator()));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Padding(padding: EdgeInsets.all(16.0), child: Center(child: Text("Nenhum Mini Bolão criado ainda.", style: TextStyle(color: Colors.grey))));
          }

          return Container(
            constraints: const BoxConstraints(maxHeight: 350), 
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final title = data['title'] ?? 'Sem Título';
                final fee = data['entry_fee'] ?? 0;
                final adminFee = data['admin_fee_percentage'] ?? 0.0;
                final participantsCount = data['participants_count'] ?? 0;
                final prizePool = data['prize_pool'] ?? 0.0;
                final isActive = data['is_active'] ?? false;
                final isFinished = data['status'] == 'finished'; 

                final Timestamp? deadlineTs = data['deadline'] as Timestamp?;
                final String deadlineStr = deadlineTs != null 
                    ? DateFormat('dd/MM/yyyy HH:mm').format(deadlineTs.toDate()) 
                    : "Sem Prazo";

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: Icon(isFinished ? Icons.emoji_events : Icons.rocket_launch, color: isFinished ? Colors.amber : (isActive ? Colors.green : Colors.grey), size: 30),
                    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(
                      isFinished 
                        ? "SALA ENCERRADA - RANKING GERADO" 
                        : "R\$ $fee Entrada | Taxa App: $adminFee%\n$participantsCount Jogadores | Prêmio: R\$ $prizePool\n⏳ Encerra: $deadlineStr", 
                      style: TextStyle(fontSize: 12, color: isFinished ? Colors.orange : Colors.grey)
                    ),
                    isThreeLine: !isFinished,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: isActive,
                          activeColor: Colors.green,
                          onChanged: (val) {
                            viewModel.toggleMiniLeagueStatus(doc.id, val);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => AdminBolaoModals.showEditMiniBolaoModal(context, doc),
                        ),
                        IconButton(
                          icon: const Icon(Icons.flag, color: Colors.orange),
                          tooltip: "Gerenciar / Encerrar",
                          onPressed: () => AdminBolaoModals.showControlMiniBolaoModal(context, doc),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: "Excluir",
                          onPressed: () => _deleteMiniBolao(doc.id, title),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    }

    return ExpansionTile(
      title: const Text("🎯 Mini Bolões (Tiro Curto)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
      leading: const Icon(Icons.rocket_launch, color: Colors.blue),
      backgroundColor: Colors.blue.shade50,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.all(12)),
              onPressed: viewModel.isLoading ? null : () => AdminBolaoModals.showCreateMiniBolaoModal(context),
              icon: const Icon(Icons.add_circle),
              label: const Text("CRIAR NOVA SALA DE MINI BOLÃO", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        _buildMiniBoloesList(),
        const SizedBox(height: 8),
      ],
    );
  }
}
