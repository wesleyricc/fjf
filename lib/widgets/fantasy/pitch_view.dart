import 'package:flutter/material.dart';
import '../../models/fantasy_models.dart';
import '../../services/fantasy_scout_service.dart';
import '../ui/optimized_network_image.dart';

class PitchView extends StatelessWidget {
  final Map<int, FantasyPlayer> lineup;
  final Map<String, FantasyScoutDetail> liveScores;
  final bool isMarketOpen;
  final String? captainId;
  final Function(int, String) onEmptySlotTap;
  final Function(FantasyPlayer) onPlayerTap;

  const PitchView({
    Key? key,
    required this.lineup,
    required this.liveScores,
    required this.isMarketOpen,
    required this.captainId,
    required this.onEmptySlotTap,
    required this.onPlayerTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double pitchWidth = screenWidth - 32;
    if (pitchWidth > 500) pitchWidth = 500;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          // A Quadra de Futsal
          Container(
            height: 540,
            width: pitchWidth,
            decoration: BoxDecoration(
              color: Colors.green.shade800,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                    color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
              ],
            ),
            child: Stack(
              children: [
                // Linhas da quadra
                _buildPitchLines(pitchWidth),

                // Jogadores
                // Pivô (5)
                Positioned(
                  top: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildSlot(5, 'Pivô'),
                  ),
                ),

                // Alas (3 e 4)
                Positioned(
                  top: 170,
                  left: 20,
                  child: _buildSlot(3, 'Ala'),
                ),
                Positioned(
                  top: 170,
                  right: 20,
                  child: _buildSlot(4, 'Ala'),
                ),

                // Fixo (2)
                Positioned(
                  top: 290,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildSlot(2, 'Fixo'),
                  ),
                ),

                // Goleiro (1)
                Positioned(
                  bottom: 15,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildSlot(1, 'Goleiro'),
                  ),
                ),

                // Técnico (6)
                Positioned(
                  bottom: 15,
                  right: 10,
                  child: _buildSlot(6, 'Técnico', isCoach: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPitchLines(double width) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(width, 540),
        painter: PitchPainter(),
      ),
    );
  }

  Widget _buildSlot(int slotIndex, String position, {bool isCoach = false}) {
    final player = lineup[slotIndex];

    if (player == null) {
      return GestureDetector(
        onTap: () => onEmptySlotTap(slotIndex, position),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.white, width: 1, style: BorderStyle.solid),
              ),
              child: Icon(isCoach ? Icons.psychology : Icons.add,
                  color: Colors.white),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isCoach ? Colors.blue.shade700 : Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isCoach)
                    const Icon(Icons.psychology, color: Colors.white, size: 10),
                  if (isCoach) const SizedBox(width: 2),
                  Text(
                    position.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            )
          ],
        ),
      );
    }

    final isCap = captainId == player.playerId;
    final double displayScore = !isMarketOpen
        ? (liveScores[player.playerId]?.totalScore ?? 0.0)
        : player.lastScore;

    return GestureDetector(
      onTap: () => onPlayerTap(player),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isCap ? Colors.orange : Colors.white, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: OptimizedNetworkImage(
                    imageUrl: player.photoUrl,
                    width: 56,
                    height: 70,
                    memCacheWidth: 120,
                    memCacheHeight: 150,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
              if (isCap)
                Positioned(
                  top: -5,
                  right: -5,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Colors.orange, shape: BoxShape.circle),
                    child: const Text("C",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              Positioned(
                top: -5,
                left: -5,
                child: _buildStatusIcon(player.status),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isCoach ? Colors.blue.shade700 : Colors.black87,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCoach)
                  const Icon(Icons.psychology, color: Colors.white, size: 10),
                if (isCoach) const SizedBox(width: 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 60),
                  child: Text(
                    _shortenName(player.name),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: isMarketOpen
                  ? Colors.blue.shade100
                  : (displayScore >= 0
                      ? Colors.green.shade100
                      : Colors.red.shade100),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isMarketOpen
                  ? "C\$ ${player.currentPrice.toStringAsFixed(2)}"
                  : displayScore.toStringAsFixed(2),
              style: TextStyle(
                color: isMarketOpen
                    ? Colors.blue.shade800
                    : (displayScore >= 0
                        ? Colors.green.shade800
                        : Colors.red.shade800),
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
    );
  }

  String _shortenName(String name) {
    List<String> parts = name.split(' ');
    if (parts.length > 1) {
      if (parts[0].length <= 3) return "${parts[0]} ${parts[1]}";
      return parts[0];
    }
    return name;
  }

  Widget _buildStatusIcon(String status) {
    Color color;
    IconData icon;
    switch (status.toLowerCase()) {
      case 'injured':
        color = Colors.red;
        icon = Icons.local_hospital;
        break;
      case 'suspended':
        color = Colors.red;
        icon = Icons.block;
        break;
      case 'doubt':
      case 'doubtful':
        color = Colors.orange;
        icon = Icons.help_outline;
        break;
      case 'probable':
      default:
        color = Colors.green;
        icon = Icons.check;
        break;
    }
    
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 10, color: Colors.white),
    );
  }
}

class PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Meio de campo
    canvas.drawLine(
        Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 40, paint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 2,
        paint..style = PaintingStyle.fill);

    // Área superior (Pivô ataca)
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(size.width / 2, 0),
          width: size.width * 0.6,
          height: 150),
      0,
      3.14,
      false,
      paint..style = PaintingStyle.stroke,
    );

    // Área inferior (Goleiro defende)
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(size.width / 2, size.height),
          width: size.width * 0.6,
          height: 150),
      3.14,
      3.14,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
