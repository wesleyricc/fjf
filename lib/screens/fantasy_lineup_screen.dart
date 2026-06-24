import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/custom_cache_manager.dart';
import '../services/fantasy_auth_service.dart';
import '../services/championship_service.dart';
import '../models/fantasy_models.dart';
import '../services/fantasy_scout_service.dart';
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../viewmodels/fantasy_lineup_viewmodel.dart'; 
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
    // 🚨 Analytics: Acesso à prancheta de escalação
    AnalyticsService.logCustomScreenView('Fantasy_Lineup_Screen');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<FantasyAuthService>(context, listen: false);
      final champ = Provider.of<ChampionshipService>(context, listen: false);
      
      if (auth.user != null) {
        Provider.of<FantasyLineupViewModel>(context, listen: false)
            .init(auth.user!.uid, champ.currentSeasonId);
      }
    });
  }

  Future<void> _openMarketForSlot(FantasyLineupViewModel vm, int slotIndex, String position) async {
    if (!vm.isMarketOpen) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mercado Fechado!")));
      return;
    }

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

  // 🚨 ATUALIZADO: Widget auxiliar para desenhar as parciais dentro do ExpansionTile
  Widget _buildLiveScouts(FantasyScoutDetail? scouts, bool isCaptain) {
    if (scouts == null || !scouts.hasStats) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text("Nenhum scout registrado na rodada.", style: TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }

    List<Widget> badges = [];

    void addBadge(String label, int count, Color color) {
      if (count > 0) {
        badges.add(Container(
          margin: const EdgeInsets.only(right: 6, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Text("${count}x $label", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ));
      }
    }

    // Inserção dos badges (Cartola Style)
    addBadge("G", scouts.goals, Colors.green);
    addBadge("A", scouts.assists, Colors.blue);
    addBadge("SG", scouts.cleanSheets, Colors.teal);
    addBadge("PD", scouts.penaltiesSaved, Colors.orange);
    addBadge("FT", scouts.shotsOnPost, Colors.brown);
    addBadge("CA", scouts.yellows, Colors.amber.shade800);
    addBadge("PP", scouts.penaltiesMissed, Colors.deepPurple);
    addBadge("CV", scouts.reds, Colors.red);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text("Scouts da Rodada:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 6),
        Wrap(children: badges),
        if (isCaptain)
          const Padding(
            padding: EdgeInsets.only(top: 4.0),
            child: Text("* Pontuação a dobrar pelo Capitão.", style: TextStyle(fontSize: 10, color: Colors.orange, fontStyle: FontStyle.italic)),
          )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FantasyLineupViewModel>(
      builder: (context, vm, child) {
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
                const Text("Escalação"),
                Text(
                  vm.isMarketOpen 
                      ? "Escalando Rodada ${vm.currentRound}" 
                      : "Parciais da Rodada ${vm.currentRound}",
                  style: TextStyle(
                    fontSize: 12, 
                    color: vm.isMarketOpen ? Colors.greenAccent : Colors.orangeAccent,
                    fontWeight: FontWeight.bold
                  ),
                ),
              ],
            ),
            actions: [
              if (vm.isMarketOpen)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: vm.isSaving 
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.cloud_done, color: Colors.greenAccent, size: 20),
                  ),
                ),
              if (vm.isMarketOpen)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: "Limpar Time",
                  onPressed: vm.lineup.isNotEmpty ? vm.sellAll : null
                ),
            ],
          ),
          body: Column(
            children: [
              _buildFinancialHeader(vm, totalLiveScore),
              
              if (vm.isMarketOpen && vm.lineup.length < 6)
                _buildWarningBanner("Seu time está incompleto! Escale os 6 integrantes para pontuar.", Icons.warning_amber_rounded, Colors.orange),
              if (vm.isMarketOpen && vm.lineup.isNotEmpty && vm.captainId == null)
                _buildWarningBanner("Você não definiu um Capitão! Clique na estrela do jogador para dobrar os pontos.", Icons.star_border, Colors.blue),

              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: vm.slotsConfig.length,
                  itemBuilder: (ctx, i) {
                    final config = vm.slotsConfig[i];
                    final int slotIndex = config['index'];
                    final String posLabel = config['pos'];
                    IconData icon = Icons.person;
                    
                    if(posLabel == 'Goleiro') icon = Icons.sports_handball;
                    else if(posLabel == 'Fixo') icon = Icons.shield;
                    else if(posLabel == 'Ala') icon = Icons.flash_on;
                    else if(posLabel == 'Pivô') icon = Icons.sports_soccer;

                    final player = vm.lineup[slotIndex];

                    if (player == null) {
                      return _buildEmptySlotCard(vm, slotIndex, posLabel, icon);
                    } else {
                      double displayScore = (!vm.isMarketOpen) 
                          ? (vm.liveScores[player.playerId]?.totalScore ?? 0.0) 
                          : player.lastScore;

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

  Widget _buildWarningBanner(String text, IconData icon, MaterialColor color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.shade50,
      child: Row(
        children: [
          Icon(icon, color: color.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color.shade800, fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildFinancialHeader(FantasyLineupViewModel vm, double liveScore) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
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
    
    final double lastScore = player.lastScore;
    final double priceChange = player.lastPriceChange;
    final double average = player.averageScore;

    final Color apprecColor = priceChange >= 0 ? Colors.green : Colors.red;
    final String apprecIcon = priceChange >= 0 ? "▲" : "▼";

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: isCaptain ? const BorderSide(color: Colors.orange, width: 2) : BorderSide.none),
      elevation: 2,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: CircleAvatar(
            backgroundImage: player.photoUrl.isNotEmpty 
                ? CachedNetworkImageProvider(
                    player.photoUrl, 
                    cacheManager: PlayerCacheManager.instance,
                    maxWidth: 150, 
                    maxHeight: 150
                  ) 
                : null, 
            child: player.photoUrl.isEmpty ? const Icon(Icons.person) : null
          ),
          title: Row(children: [
              Text(player.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              if (isCaptain) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)), child: const Text("C", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))
          ]),
          subtitle: Row(children: [
              if (vm.isMarketOpen) Text("C\$ ${player.currentPrice.toStringAsFixed(2)}", style: const TextStyle(color: Colors.grey)),
              if (!vm.isMarketOpen) Text("Parcial: ${score.toStringAsFixed(2)}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ]),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: Colors.grey[50],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                       const Text("Última Pontuação"),
                       Text(lastScore.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                       const Text("Média"),
                       Text(average.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                       const Text("Valorização"),
                       Text("$apprecIcon ${priceChange.toStringAsFixed(2)}", style: TextStyle(color: apprecColor, fontWeight: FontWeight.bold)),
                  ]),
                  
                  // 🚨 NOVA ÁREA: DETALHES DE SCOUTS AO VIVO NO CARD
                  if (!vm.isMarketOpen) ...[
                    const Divider(),
                    _buildLiveScouts(vm.liveScores[player.playerId], isCaptain),
                  ],

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