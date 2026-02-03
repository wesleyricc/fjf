import 'package:flutter/material.dart';
import '../models/fantasy_models.dart';

class FantasyPitchWidget extends StatelessWidget {
  final Map<int, FantasyPlayer?> lineup; // Mapa de Posição -> Jogador
  final Function(int slotIndex, String position) onSlotTap;
  final Function(int slotIndex) onRemovePlayer;
  final String? captainId;
  final Function(String playerId) onSetCaptain;

  const FantasyPitchWidget({
    super.key,
    required this.lineup,
    required this.onSlotTap,
    required this.onRemovePlayer,
    required this.captainId,
    required this.onSetCaptain,
  });

  @override
  Widget build(BuildContext context) {
    // Cores de quadra de futsal (Azul ou Madeira/Amarelo, ou Verde mesmo)
    // Vamos usar um Azul moderno para diferenciar do campo de grama
    final Color courtColor = Colors.blue[800]!; 
    final Color courtLines = Colors.white54;

    return Container(
      decoration: BoxDecoration(
        color: courtColor,
        border: Border.all(color: Colors.white, width: 4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          // --- DESENHO DA QUADRA (Simplificado) ---
          // Linha central
          Center(child: Container(height: 2, color: courtLines)), 
          // Círculo central
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: courtLines, width: 2),
              ),
            ),
          ),
          // Áreas (Goleiro)
          Positioned(
            top: 0, left: 100, right: 100,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: courtLines, width: 2),
                  left: BorderSide(color: courtLines, width: 2),
                  right: BorderSide(color: courtLines, width: 2),
                ),
              ),
            ),
          ),

          // --- FORMAÇÃO FUTSAL (1-1-2-1 ou Losango) ---
          
          // 1. Goleiro (Lá no fundo)
          _buildPlayerNode(context, slotIndex: 1, positionLabel: 'Goleiro', top: 0.88, left: 0.40),

          // 2. Fixo (Defesa Central)
          _buildPlayerNode(context, slotIndex: 2, positionLabel: 'Fixo', top: 0.65, left: 0.40),

          // 3. Alas (Abertos e um pouco avançados em relação ao fixo)
          _buildPlayerNode(context, slotIndex: 3, positionLabel: 'Ala', top: 0.45, left: 0.08), // Ala Esquerda
          _buildPlayerNode(context, slotIndex: 4, positionLabel: 'Ala', top: 0.45, left: 0.72), // Ala Direita

          // 4. Pivô (Lá na frente)
          _buildPlayerNode(context, slotIndex: 5, positionLabel: 'Pivô', top: 0.15, left: 0.40),

          // 5. Técnico (Fora da quadra, canto inferior direito)
          _buildPlayerNode(context, slotIndex: 6, positionLabel: 'Técnico', top: 0.90, left: 0.80, isCoach: true),
        ],
      ),
    );
  }

  Widget _buildPlayerNode(
    BuildContext context, {
    required int slotIndex,
    required String positionLabel,
    required double top,
    required double left,
    bool isCoach = false,
  }) {
    final player = lineup[slotIndex];
    final bool isEmpty = player == null;
    final bool isCaptain = !isEmpty && player.playerId == captainId;

    return Positioned(
      top: MediaQuery.of(context).size.height * 0.65 * top,
      left: MediaQuery.of(context).size.width * left,
      child: GestureDetector(
        onTap: () {
          if (isEmpty) {
            onSlotTap(slotIndex, positionLabel);
          } else {
            _showPlayerOptions(context, player, slotIndex);
          }
        },
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 50, // Um pouco maior pois são menos jogadores
                  height: 50,
                  decoration: BoxDecoration(
                    color: isEmpty ? Colors.white.withOpacity(0.3) : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCaptain ? Colors.orangeAccent : Colors.white, 
                      width: isCaptain ? 3 : 2
                    ),
                    image: (!isEmpty && player.photoUrl.isNotEmpty)
                        ? DecorationImage(image: NetworkImage(player.photoUrl), fit: BoxFit.cover)
                        : null,
                  ),
                  child: isEmpty
                      ? const Icon(Icons.add, color: Colors.white)
                      : null,
                ),
                if (isCaptain)
                  Positioned(
                    bottom: -5,
                    right: -5,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: const Text("C", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  Text(
                    isEmpty ? positionLabel : _getShortName(player.name),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isEmpty)
                  Text(
                    "C\$ ${player.currentPrice.toStringAsFixed(1)}",
                    style: TextStyle(color: Colors.greenAccent[100], fontSize: 9),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  String _getShortName(String fullName) {
    final parts = fullName.split(' ');
    if (parts.length > 1) return "${parts[0]} ${parts[1][0]}.";
    return parts[0];
  }

  void _showPlayerOptions(BuildContext context, FantasyPlayer player, int slotIndex) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Wrap(
          children: [
            ListTile(
              leading: CircleAvatar(backgroundImage: NetworkImage(player.photoUrl)),
              title: Text(player.name),
              subtitle: Text("${player.position} - ${player.teamId}"),
            ),
            const Divider(),
            if (!['Técnico'].contains(player.position))
              ListTile(
                leading: const Icon(Icons.star, color: Colors.orange),
                title: const Text("Tornar Capitão"),
                onTap: () {
                  onSetCaptain(player.playerId);
                  Navigator.pop(ctx);
                },
              ),
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.blue),
              title: const Text("Substituir"),
              onTap: () {
                Navigator.pop(ctx);
                onSlotTap(slotIndex, player.position);
              },
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle, color: Colors.red),
              title: const Text("Vender Jogador"),
              onTap: () {
                onRemovePlayer(slotIndex);
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }
}