import 'dart:io';
void main() {
  final file = File(r'c:\Users\Wesley Ricardo\Documents\Projetos\fjf\lib\screens\fantasy\fantasy_lineup_screen.dart');
  var content = file.readAsStringSync();
  
  // Add import
  content = content.replaceFirst(
      "import '../../widgets/fantasy/pitch_view.dart';", 
      "import '../../widgets/fantasy/pitch_view.dart';\nimport '../../widgets/fantasy/fantasy_player_details_modal.dart';");

  // Add isBench parameter to _showPlayerActionSheet
  content = content.replaceFirst(
      "void _showPlayerActionSheet(\n      FantasyLineupViewModel vm, FantasyPlayer player, int slotIndex) {",
      "void _showPlayerActionSheet(FantasyLineupViewModel vm, FantasyPlayer player, int slotIndex, {bool isBench = false}) {"
  );

  // Replace _showPlayerActionSheet body
  final startIndex = content.indexOf('  void _showPlayerActionSheet(');
  final endIndex = content.indexOf('class WarningBanner extends StatelessWidget {');
  
  if (startIndex != -1 && endIndex != -1) {
    final replacement = '''
  void _showPlayerActionSheet(FantasyLineupViewModel vm, FantasyPlayer player, int slotIndex, {bool isBench = false}) {
    final championshipService = Provider.of<ChampionshipService>(context, listen: false);
    final matches = championshipService.matches;
    String? nextOpponentShieldUrl;
    for (var m in matches) {
      if (m.status == 'pending' && (m.homeTeamId == player.teamId || m.awayTeamId == player.teamId)) {
        nextOpponentShieldUrl = m.homeTeamId == player.teamId ? m.awayTeamShield : m.homeTeamShield;
        break;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))
      ),
      builder: (ctx) {
        return ChangeNotifierProvider.value(
          value: vm,
          child: Consumer<FantasyLineupViewModel>(
            builder: (ctx, vm, _) {
              final bool isCaptain = vm.captainId == player.playerId;
              final bool isLuxury = vm.luxuryReserveId == player.playerId;
              
              return FantasyPlayerDetailsModal(
                player: player,
                nextOpponentShieldUrl: nextOpponentShieldUrl,
                extraContent: Column(
                  children: [
                    if (!vm.isMarketOpen)
                      LiveScoutsWidget(
                        scouts: vm.liveScores[player.playerId],
                        isCaptain: isCaptain,
                        isMarketOpen: vm.isMarketOpen,
                        position: player.position
                      ),
                  ]
                ),
                actionButton: vm.isMarketOpen
                  ? Row(
                      children: [
                        if (!isBench && player.position != 'Técnico')
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: Icon(Icons.star, color: isCaptain ? Colors.grey : Colors.orange),
                              label: Text(isCaptain ? "Remover Capitão" : "Capitão", style: const TextStyle(fontSize: 12)),
                              onPressed: () {
                                vm.setCaptain(player.playerId);
                                Navigator.pop(ctx);
                              },
                            ),
                          ),
                        if (isBench && player.position != 'Técnico')
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: Icon(Icons.diamond, color: isLuxury ? Colors.grey : Colors.amber),
                              label: Text(isLuxury ? "Remover R. Luxo" : "Reserva", style: const TextStyle(fontSize: 12)),
                              onPressed: () {
                                vm.setLuxuryReserve(player.playerId);
                                Navigator.pop(ctx);
                              },
                            ),
                          ),
                        if (player.position != 'Técnico')
                          const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.sell, color: Colors.red),
                            label: const Text("Vender", style: TextStyle(color: Colors.red, fontSize: 12)),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                            onPressed: () {
                              if (isBench) {
                                vm.removeBenchPlayer(slotIndex);
                              } else {
                                vm.removePlayer(slotIndex);
                              }
                              Navigator.pop(ctx);
                            },
                          ),
                        ),
                      ],
                    )
                  : null,
              );
            }
          ),
        );
      }
    );
  }
}

''';
    content = content.replaceRange(startIndex, endIndex, replacement);
  }

  // Find PlayerCard call for bench and replace it with a simple Card that opens modal
  final benchCallStart = content.indexOf('return PlayerCard(', content.indexOf('vm.benchSlotsConfig.map'));
  final benchCallEnd = content.indexOf(');', benchCallStart) + 2;
  
  if (benchCallStart != -1) {
    final replacement = '''
                          final bool isCaptain = vm.captainId == player.playerId;
                          final bool isLuxury = vm.luxuryReserveId == player.playerId;
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: isLuxury ? const BorderSide(color: Colors.amber, width: 2) : BorderSide.none,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: player.photoUrl.isNotEmpty ? NetworkImage(player.photoUrl) : null,
                                child: player.photoUrl.isEmpty ? const Icon(Icons.person) : null,
                              ),
                              title: Text(player.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("\ \• C\$ \"),
                              trailing: isLuxury ? const Icon(Icons.diamond, color: Colors.amber) : null,
                              onTap: () => _showPlayerActionSheet(vm, player, slotIndex, isBench: true),
                            ),
                          );
''';
    content = content.replaceRange(benchCallStart, benchCallEnd, replacement);
  }

  file.writeAsStringSync(content);
  print("Done lineup screen.");
}
