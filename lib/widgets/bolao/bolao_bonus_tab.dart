import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/bolao_models.dart';
import '../../services/bolao_service.dart';
import '../../utils/bolao_constants.dart';

class BolaoBonusTab extends StatefulWidget {
  final String userId;
  final BolaoUser? currentUser;
  final VoidCallback onRequireProfile;

  const BolaoBonusTab({
    super.key,
    required this.userId,
    required this.currentUser,
    required this.onRequireProfile,
  });

  @override
  State<BolaoBonusTab> createState() => _BolaoBonusTabState();
}

class _BolaoBonusTabState extends State<BolaoBonusTab> {
  Future<void> _saveBonusPrediction(String field, String? value) async {
    if (value == null) return;
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('submitBolaoBonus');
      await callable.call({'field': field, 'teamName': value});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Bônus salvo com sucesso! 🏆"), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erro: O prazo encerrou!"), backgroundColor: Colors.red)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deadline = DateTime.utc(2026, 6, 18, 2, 59, 59); 
    final bool isTimeOver = DateTime.now().toUtc().isAfter(deadline);
    final bool isBonusLocked = isTimeOver; 

    final List<String> availableTeams = BolaoConstants.teamsFlagsMap.keys.toList()..sort();
    final List<String> seededTeams = ['Alemanha', 'Argentina', 'Bélgica', 'Brasil', 'Canadá', 'Espanha', 'Estados Unidos', 'França', 'Holanda', 'Inglaterra', 'México', 'Portugal'];

    return StreamBuilder<List<BolaoUser>>(
      stream: BolaoService().streamLeaderboard(),
      builder: (context, snapshot) {
        final allUsers = snapshot.data ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isBonusLocked ? Colors.red.shade50 : Colors.amber.shade50, 
                borderRadius: BorderRadius.circular(12), 
                border: Border.all(color: isBonusLocked ? Colors.red.shade200 : Colors.amber.shade300)
              ),
              child: Text(
                isBonusLocked ? "🔒 Opções Extras Trancadas Definitivamente!" : "Atenção: Estes palpites trancam no dia 17/06/2026 às 23h59. Pense bem!", 
                style: TextStyle(color: isBonusLocked ? Colors.red[800] : Colors.orange[800], fontWeight: FontWeight.bold), 
                textAlign: TextAlign.center
              ),
            ),
            const SizedBox(height: 20),

            _buildBonusDropdown(
              title: "O Grande Campeão (20 pts)", description: "Qual seleção irá levantar a taça e sagrar-se campeã do mundo?", icon: Icons.emoji_events,
              currentValue: widget.currentUser?.champion, isLocked: isBonusLocked, availableTeams: availableTeams, 
              onChanged: (val) => _saveBonusPrediction('bonus_champion', val),
              bonusKey: 'bonus_champion', allUsers: allUsers,
            ),
            const SizedBox(height: 12),
            _buildBonusDropdown(
              title: "O Vice-Campeão (10 pts)", description: "Qual seleção chegará à Grande Final, mas irá perder o título?", icon: Icons.looks_two,
              currentValue: widget.currentUser?.runnerUp, isLocked: isBonusLocked, availableTeams: availableTeams, 
              onChanged: (val) => _saveBonusPrediction('bonus_runner_up', val),
              bonusKey: 'bonus_runner_up', allUsers: allUsers,
            ),
            const SizedBox(height: 12),
            _buildBonusDropdown(
              title: "Melhor Ataque (10 pts)", description: "A seleção que marcar o maior número de gols no total da Copa.", icon: Icons.sports_soccer,
              currentValue: widget.currentUser?.bestOffense, isLocked: isBonusLocked, availableTeams: availableTeams, 
              onChanged: (val) => _saveBonusPrediction('bonus_best_offense', val),
              bonusKey: 'bonus_best_offense', allUsers: allUsers,
            ),
            const SizedBox(height: 12),
            _buildBonusDropdown(
              title: "A Pior Defesa (10 pts)", description: "O 'Saco de Pancadas'. A seleção que sofrer o maior número de gols.", icon: Icons.shield,
              currentValue: widget.currentUser?.worstDefense, isLocked: isBonusLocked, availableTeams: availableTeams, 
              onChanged: (val) => _saveBonusPrediction('bonus_worst_defense', val),
              bonusKey: 'bonus_worst_defense', allUsers: allUsers,
            ),
            const SizedBox(height: 12),
            _buildBonusDropdown(
              title: "A Grande Decepção (10 pts)", description: "O Fiasco. A primeira seleção 'Cabeça de Chave' a ser eliminada do torneio.", icon: Icons.trending_down,
              currentValue: widget.currentUser?.disappointment, isLocked: isBonusLocked, availableTeams: seededTeams, 
              onChanged: (val) => _saveBonusPrediction('bonus_disappointment', val),
              bonusKey: 'bonus_disappointment', allUsers: allUsers,
            ),
            const SizedBox(height: 30),
          ],
        );
      }
    );
  }

  Widget _buildBonusDropdown({
    required String title, required String description, required IconData icon, required String? currentValue,
    required bool isLocked, required List<String> availableTeams, required Function(String?) onChanged,
    required String bonusKey, required List<BolaoUser> allUsers,
  }) {
    final bool isProfileIncomplete = widget.currentUser == null || !widget.currentUser!.isProfileComplete;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, color: Colors.amber.shade700, size: 24), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
            const SizedBox(height: 6),
            Text(description, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 16),
            
            GestureDetector(
              onTap: () {
                if (isProfileIncomplete && !isLocked) {
                  widget.onRequireProfile();
                }
              },
              child: AbsorbPointer(
                absorbing: isProfileIncomplete,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: availableTeams.contains(currentValue) ? currentValue : null,
                  disabledHint: currentValue != null
                      ? Row(children: [Text(BolaoConstants.teamsFlagsMap[currentValue] ?? '❓', style: const TextStyle(fontSize: 20)), const SizedBox(width: 8), Expanded(child: Text(currentValue, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis))])
                      : const Text("Bloqueado (Sem Palpite)", style: TextStyle(color: Colors.red)),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: isLocked,
                    fillColor: Colors.grey.shade100,
                  ),
                  items: isLocked ? null : availableTeams.map((team) {
                          return DropdownMenuItem(value: team, child: Row(children: [Text(BolaoConstants.teamsFlagsMap[team] ?? '❓', style: const TextStyle(fontSize: 20)), const SizedBox(width: 12), Expanded(child: Text(team, overflow: TextOverflow.ellipsis))]));
                        }).toList(),
                  onChanged: isLocked ? null : onChanged,
                ),
              ),
            ),
            
            if (isLocked && allUsers.isNotEmpty)
               _buildBonusThermometer(bonusKey, allUsers),
          ],
        ),
      ),
    );
  }

  Widget _buildBonusThermometer(String bonusKey, List<BolaoUser> allUsers) {
    Map<String, int> counts = {};
    int totalVotes = 0;

    for (var u in allUsers) {
      String? choice;
      if (bonusKey == 'bonus_champion') choice = u.champion;
      else if (bonusKey == 'bonus_runner_up') choice = u.runnerUp;
      else if (bonusKey == 'bonus_best_offense') choice = u.bestOffense;
      else if (bonusKey == 'bonus_worst_defense') choice = u.worstDefense;
      else if (bonusKey == 'bonus_disappointment') choice = u.disappointment;

      if (choice != null && choice.isNotEmpty) {
        counts[choice] = (counts[choice] ?? 0) + 1;
        totalVotes++;
      }
    }

    if (totalVotes == 0) return const SizedBox.shrink();

    var sortedEntries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    List<Widget> bars = [];
    
    for (int i = 0; i < sortedEntries.length; i++) {
      if (i >= 3 && sortedEntries.length > 4) {
        int outrosCount = 0;
        for (int j = i; j < sortedEntries.length; j++) {
          outrosCount += sortedEntries[j].value;
        }
        double percent = outrosCount / totalVotes;
        bars.add(_buildThermometerBar("🌍 Outros", percent, outrosCount));
        break;
      } else {
        String teamName = sortedEntries[i].key;
        int count = sortedEntries[i].value;
        double percent = count / totalVotes;
        String flag = BolaoConstants.teamsFlagsMap[teamName] ?? '❓';
        bars.add(_buildThermometerBar("$flag $teamName", percent, count));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Row(
          children: [
            const Icon(Icons.query_stats, color: Colors.indigo, size: 16),
            const SizedBox(width: 6),
            const Text("Termômetro da Galera", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
            const Spacer(),
            Text("$totalVotes votos", style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 10),
        ...bars,
      ],
    );
  }

  Widget _buildThermometerBar(String label, double percent, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
              Text("${(percent * 100).toStringAsFixed(1)}%", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.grey.shade200,
              color: Colors.indigo.shade400,
              minHeight: 6,
            ),
          )
        ],
      ),
    );
  }
}
