import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/fantasy_auth_service.dart';
import '../services/championship_service.dart';
import '../models/fantasy_models.dart';
import '../viewmodels/fantasy_lineup_viewmodel.dart'; // <--- Import ViewModel
import 'fantasy_market_screen.dart'; 

class FantasyLineupScreen extends StatefulWidget {
  const FantasyLineupScreen({super.key});

  @override
  State<FantasyLineupScreen> createState() => _FantasyLineupScreenState();
}

class _FantasyLineupScreenState extends State<FantasyLineupScreen> {
  
  @override
  void initState() {
    super.initState();
    // Inicializa o ViewModel
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<FantasyAuthService>(context, listen: false);
      final champ = Provider.of<ChampionshipService>(context, listen: false);
      
      if (auth.user != null) {
        Provider.of<FantasyLineupViewModel>(context, listen: false)
            .init(auth.user!.uid, champ.currentSeasonId);
      }
    });
  }

  // Helper para abrir o mercado (Isso é UI logic, pode ficar na View)
  Future<void> _openMarketForSlot(FantasyLineupViewModel vm, int slotIndex, String position) async {
    if (!vm.isMarketOpen) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mercado Fechado!")));
      return;
    }

    // Calcula orçamento para este slot específico
    double budget = vm.currentBalance;
    if (vm.lineup.containsKey(slotIndex)) {
      budget += vm.lineup[slotIndex]!.currentPrice;
    }

    final selectedPlayer = await Navigator.push<FantasyPlayer>(
      context,
      MaterialPageRoute(
        builder: (ctx) => FantasyMarketScreen(
          isSelectionMode: true,
          requiredPosition: position,
          maxBudget: budget,
        ),
      ),
    );

    if (selectedPlayer != null) {
      vm.addPlayer(slotIndex, selectedPlayer);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FantasyLineupViewModel>(
      builder: (context, vm, child) {
        // Feedback de Erro/Sucesso via SnackBar
        if (vm.errorMessage != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.errorMessage!), backgroundColor: Colors.red));
            vm.clearMessages();
          });
        }
        if (vm.successMessage != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.successMessage!), backgroundColor: Colors.green));
            vm.clearMessages();
          });
        }

        if (vm.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        // Cálculo da Parcial Total (Apenas para exibição)
        double totalLiveScore = 0.0;
        if (!vm.isMarketOpen) {
           for (var p in vm.lineup.values) {
              double s = vm.liveScores[p.playerId]?.totalScore ?? 0.0;
              if (vm.captainId == p.playerId) s *= 2;
              totalLiveScore += s;
           }
        }

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: Column(
              children: [
                const Text("Escalar Time"),
                Text(
                  vm.isMarketOpen 
                      ? "Mercado ABERTO (Rodada ${vm.currentRound})" 
                      : "Mercado FECHADO (Parciais R${vm.currentRound})",
                  style: TextStyle(fontSize: 12, color: vm.isMarketOpen ? Colors.greenAccent : Colors.orangeAccent),
                ),
              ],
            ),
            actions: [
              if (vm.isMarketOpen) ...[
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: "Limpar Time",
                  onPressed: vm.lineup.isNotEmpty ? vm.sellAll : null
                ),
                IconButton(
                  icon: const Icon(Icons.save),
                  tooltip: "Salvar Escalação",
                  onPressed: () => vm.saveLineup(Provider.of<FantasyAuthService>(context, listen: false).user!.uid)
                ),
              ]
            ],
          ),
          body: Column(
            children: [
              _buildFinancialHeader(vm, totalLiveScore),
              
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: vm.slotsConfig.length,
                  itemBuilder: (ctx, i) {
                    final config = vm.slotsConfig[i];
                    final int slotIndex = config['index'];
                    final String posLabel = config['pos'];
                    // Ícone fixo para simplificar (ou mapeie do int se preferir)
                    IconData icon = Icons.person;
                    if(posLabel == 'Goleiro') icon = Icons.sports_handball;
                    else if(posLabel == 'Fixo') icon = Icons.shield;
                    else if(posLabel == 'Ala') icon = Icons.flash_on;
                    else if(posLabel == 'Pivô') icon = Icons.sports_soccer;

                    final player = vm.lineup[slotIndex];

                    if (player == null) {
                      return _buildEmptySlotCard(vm, slotIndex, posLabel, icon);
                    } else {
                      // Se fechado, mostra parcial. Se aberto, mostra lastScore.
                      double displayScore = 0.0;
                      if (!vm.isMarketOpen) {
                        displayScore = vm.liveScores[player.playerId]?.totalScore ?? 0.0;
                      } else {
                        displayScore = player.lastScore;
                      }

                      return _buildPlayerCard(vm, slotIndex, player, displayScore);
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFinancialHeader(FantasyLineupViewModel vm, double liveScore) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildInfoItem("Patrimônio", vm.totalPatrimony, Colors.black87),

          vm.isMarketOpen 
            ? _buildInfoItem("Disponível", vm.currentBalance, vm.currentBalance < 0 ? Colors.red : Colors.green[700]!)
            : _buildInfoItem("Parcial", liveScore, liveScore >= 0 ? Colors.green : Colors.red, isLive: true),

          Column(
            children: [
              Text("${vm.lineup.length}/6", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: vm.lineup.length == 6 ? Colors.green : Colors.orange)),
              const Text("Escalados", style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, double value, Color color, {bool isLive = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isLive ? value.toStringAsFixed(2) : "C\$ ${value.toStringAsFixed(2)}",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)
        ),
        Row(children: [
            if (isLive) const Icon(Icons.circle, size: 8, color: Colors.redAccent),
            if (isLive) const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ],
    );
  }

  Widget _buildEmptySlotCard(FantasyLineupViewModel vm, int slotIndex, String label, IconData icon) {
    if (!vm.isMarketOpen) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: Colors.grey[200],
        child: ListTile(
          leading: Icon(icon, color: Colors.grey),
          title: Text("Vazio ($label)", style: const TextStyle(color: Colors.grey)),
          trailing: const Icon(Icons.lock, color: Colors.grey),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        onTap: () => _openMarketForSlot(vm, slotIndex, label),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Row(
            children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle), child: Icon(icon, color: Colors.grey[400])),
              const SizedBox(width: 16),
              Text("Adicionar $label", style: TextStyle(fontSize: 16, color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
              const Spacer(),
              const Icon(Icons.add_circle_outline, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerCard(FantasyLineupViewModel vm, int slotIndex, FantasyPlayer player, double score) {
    final bool isCaptain = vm.captainId == player.playerId;
    
    // Ajuste visual para parcial (Se capitão, mostra x2)
    final double displayValue = (!vm.isMarketOpen && isCaptain) ? score * 2 : score;

    final Color apprecColor = player.lastPriceChange >= 0 ? Colors.green : Colors.red;
    final String apprecIcon = player.lastPriceChange >= 0 ? "▲" : "▼";

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: isCaptain ? const BorderSide(color: Colors.orange, width: 2) : BorderSide.none),
      elevation: 2,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: CircleAvatar(backgroundImage: player.photoUrl.isNotEmpty ? NetworkImage(player.photoUrl) : null, child: player.photoUrl.isEmpty ? const Icon(Icons.person) : null),
          title: Row(children: [
              Text(player.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              if (isCaptain) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)), child: const Text("C", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))
          ]),
          subtitle: Row(children: [
              if (vm.isMarketOpen) Text("C\$ ${player.currentPrice.toStringAsFixed(2)}", style: const TextStyle(color: Colors.grey)),
              if (!vm.isMarketOpen) Text("Parcial: ${displayValue.toStringAsFixed(2)}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ]),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: Colors.grey[50],
              child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                       const Text("Última Pontuação"),
                       Text(player.lastScore.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                       const Text("Média"),
                       Text(player.averageScore.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                       const Text("Valorização"),
                       Text("$apprecIcon ${player.lastPriceChange.toStringAsFixed(2)}", style: TextStyle(color: apprecColor)),
                  ]),
                  if (vm.isMarketOpen) ...[
                    const Divider(),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        if (player.position != 'Técnico')
                          TextButton.icon(
                            icon: Icon(Icons.star, color: isCaptain ? Colors.grey : Colors.orange),
                            label: Text(isCaptain ? "Remover Capitão" : "Tornar Capitão"),
                            onPressed: () => vm.setCaptain(player.playerId),
                          ),
                        TextButton.icon(
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text("Vender"),
                          onPressed: () => vm.removePlayer(slotIndex),
                        )
                    ]),
                  ]
              ]),
            )
          ],
        ),
      ),
    );
  }
}