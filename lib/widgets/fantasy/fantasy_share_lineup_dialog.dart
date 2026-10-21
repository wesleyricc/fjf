import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/fantasy_models.dart';
import '../../services/analytics_service.dart';
import '../../viewmodels/fantasy_lineup_viewmodel.dart';
import '../ui/optimized_network_image.dart';
import '../team_logo_widget.dart';

class FantasyShareLineupDialog extends StatefulWidget {
  final FantasyLineupViewModel vm;
  final String teamName;
  final String ownerName;

  const FantasyShareLineupDialog({
    super.key,
    required this.vm,
    required this.teamName,
    required this.ownerName,
  });

  static Future<void> show(
    BuildContext context, {
    required FantasyLineupViewModel vm,
    required String teamName,
    required String ownerName,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => FantasyShareLineupDialog(
        vm: vm,
        teamName: teamName,
        ownerName: ownerName,
      ),
    );
  }

  @override
  State<FantasyShareLineupDialog> createState() =>
      _FantasyShareLineupDialogState();
}

class _FantasyShareLineupDialogState extends State<FantasyShareLineupDialog> {
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isSharing = false;

  Future<void> _shareCard() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    HapticFeedback.mediumImpact();

    try {
      final Uint8List? imageBytes = await _screenshotController.capture(
        pixelRatio: 3.0,
      );

      if (imageBytes != null && mounted) {
        AnalyticsService.logShare(
            'fantasy_lineup_card', widget.vm.userId ?? '');
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                imageBytes,
                mimeType: 'image/png',
                name: 'escalacao_rodada_${widget.vm.currentRound}.png',
              ),
            ],
            text:
                'Confira a minha escalação do time ${widget.teamName} para a Rodada ${widget.vm.currentRound} no Fantasy Cartola FJF! ⚽🔥 #CartolaFJF',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao compartilhar imagem: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final bench = vm.bench.values.toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Área compacta e moderna capturada pelo ScreenshotController
            Screenshot(
              controller: _screenshotController,
              child: Container(
                width: 350,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0F172A), // Slate 900
                      Color(0xFF064E3B), // Emerald 900
                      Color(0xFF022C22), // Emerald 950
                    ],
                  ),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    )
                  ],
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Cabeçalho Compacto & Moderno
                    Row(
                      children: [
                        TeamLogoWidget(
                          logoUrl: vm.team?.customLogoUrl,
                          shieldType: vm.team?.shieldType ?? '1',
                          radius: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.teamName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                "Técnico: ${widget.ownerName}",
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.4),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                "RODADA ${vm.currentRound}",
                                style: const TextStyle(
                                  color: Color(0xFF34D399),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "C\$ ${vm.lineupPrice.toStringAsFixed(2)}",
                              style: const TextStyle(
                                color: Colors.amberAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "VALOR DO TIME",
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 7,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Quadra Tática de Futsal com Linhas Oficiais
                    Container(
                      height: 350,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF064E3B), // Emerald 900
                            Color(
                                0xFF047857), // Emerald 700 (iluminação central da quadra)
                            Color(0xFF064E3B), // Emerald 900
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Stack(
                          children: [
                            // Desenho das Linhas Oficiais da Quadra de Futsal
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _MiniPitchPainter(),
                              ),
                            ),

                            // Pivô (Slot 5) - Topo Centro (Área Ofensiva)
                            Positioned(
                              top: 30,
                              left: 0,
                              right: 0,
                              child: Center(
                                child:
                                    _buildPitchToken(vm.lineup[5], 'Pivô', vm),
                              ),
                            ),

                            // Alas (Slots 3 e 4) - Linha Lateral / Meio de Campo Ofensivo
                            Positioned(
                              top: 120,
                              left: 14,
                              child: _buildPitchToken(vm.lineup[3], 'Ala', vm),
                            ),
                            Positioned(
                              top: 120,
                              right: 14,
                              child: _buildPitchToken(vm.lineup[4], 'Ala', vm),
                            ),

                            // Fixo (Slot 2) - Centro Defesa (Abaixo do Círculo Central)
                            Positioned(
                              top: 200,
                              left: 0,
                              right: 0,
                              child: Center(
                                child:
                                    _buildPitchToken(vm.lineup[2], 'Fixo', vm),
                              ),
                            ),

                            // Goleiro (Slot 1) - Centralizado na Meta
                            Positioned(
                              bottom: 10,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: _buildPitchToken(
                                    vm.lineup[1], 'Goleiro', vm),
                              ),
                            ),

                            // Técnico (Slot 6) - Canto Direito (Área Técnica na Linha de Fundo)
                            Positioned(
                              bottom: 10,
                              right: 8,
                              child: _buildPitchToken(
                                vm.lineup[6],
                                'Técnico',
                                vm,
                                isCoach: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Banco de Reservas (Faixa Compacta e Completa de Todos os Suplentes)
                    if (bench.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.event_seat,
                                    size: 11, color: Colors.purpleAccent),
                                const SizedBox(width: 4),
                                Text(
                                  "BANCO DE RESERVAS (${bench.length})",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: bench.map((p) {
                                final bool isLuxury =
                                    vm.luxuryReserveId == p.playerId;
                                return Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 2),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 2, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isLuxury
                                          ? const Color(0xFF1E293B)
                                          : Colors.white
                                              .withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isLuxury
                                            ? Colors.amberAccent
                                            : Colors.white12,
                                        width: isLuxury ? 1.2 : 0.6,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 3, vertical: 0.5),
                                          decoration: BoxDecoration(
                                            color: isLuxury
                                                ? Colors.amber
                                                    .withValues(alpha: 0.3)
                                                : Colors.white12,
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: Text(
                                            p.position.length > 3
                                                ? p.position
                                                    .substring(0, 3)
                                                    .toUpperCase()
                                                : p.position.toUpperCase(),
                                            style: TextStyle(
                                              color: isLuxury
                                                  ? Colors.amberAccent
                                                  : Colors.white70,
                                              fontSize: 7.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            ClipOval(
                                              child: OptimizedNetworkImage(
                                                imageUrl: p.photoUrl,
                                                width: 22,
                                                height: 22,
                                                fit: BoxFit.cover,
                                                memCacheWidth: 44,
                                                memCacheHeight: 44,
                                                alignment: Alignment.topCenter,
                                              ),
                                            ),
                                            if (isLuxury)
                                              Positioned(
                                                top: -3,
                                                right: -3,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(1.5),
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: Colors.amber,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                      Icons.diamond,
                                                      size: 7,
                                                      color: Colors.black87),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          p.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 7.5,
                                            fontWeight: FontWeight.w600,
                                            height: 1.1,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Rodapé Sutil
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset('assets/logo_fjf_fantasy.webp', height: 14),
                        const SizedBox(width: 6),
                        Text(
                          "FANTASY CARTOLA FJF • acefjf.web.app",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Botões de Ação
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Fechar",
                      style: TextStyle(color: Colors.white70)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isSharing ? null : _shareCard,
                  icon: _isSharing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.share, size: 18),
                  label: Text(_isSharing ? "Gerando..." : "Compartilhar"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPitchToken(
      FantasyPlayer? player, String position, FantasyLineupViewModel vm,
      {bool isCoach = false}) {
    if (player == null) {
      return SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCoach
                    ? Colors.amber.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.15),
                border: Border.all(
                  color: isCoach
                      ? Colors.amber.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Icon(
                isCoach ? Icons.psychology : Icons.person_outline,
                color: isCoach ? Colors.amberAccent : Colors.white54,
                size: 18,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              position,
              style: TextStyle(
                color: isCoach ? Colors.amberAccent : Colors.white54,
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    final bool isCaptain = vm.captainId == player.playerId;

    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: isCaptain
                        ? const Color(0xFFF59E0B) // Gold
                        : (isCoach ? const Color(0xFF38BDF8) : Colors.white),
                    width: isCaptain || isCoach ? 2 : 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isCaptain
                          ? Colors.amber.withValues(alpha: 0.4)
                          : Colors.black26,
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: OptimizedNetworkImage(
                    imageUrl: player.photoUrl,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    memCacheWidth: 72,
                    memCacheHeight: 72,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
              if (isCaptain)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      "C",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                )
              else if (isCoach)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0284C7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.psychology,
                      color: Colors.white,
                      size: 8,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
            decoration: BoxDecoration(
              color: isCoach
                  ? const Color(0xFF0F172A).withValues(alpha: 0.95)
                  : Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(4),
              border: isCoach
                  ? Border.all(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                      width: 0.8,
                    )
                  : null,
            ),
            child: Text(
              player.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                height: 1.15,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    const double pad = 4.0;
    // Retângulo limite da quadra
    final courtRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2),
      const Radius.circular(8),
    );
    canvas.drawRRect(courtRect, linePaint);

    // Linha do meio de campo
    final double midY = size.height * 0.49;
    canvas.drawLine(
        Offset(pad, midY), Offset(size.width - pad, midY), linePaint);

    // Círculo central com ponto
    canvas.drawCircle(Offset(size.width / 2, midY), 30, linePaint);
    canvas.drawCircle(Offset(size.width / 2, midY), 2.2, dotPaint);

    // Área do ataque (semicírculo superior no pivô)
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width / 2, pad),
        width: size.width * 0.54,
        height: size.height * 0.28,
      ),
      0,
      3.14159,
      false,
      linePaint,
    );

    // Área da defesa (semicírculo inferior no goleiro)
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height - pad),
        width: size.width * 0.54,
        height: size.height * 0.28,
      ),
      3.14159,
      3.14159,
      false,
      linePaint,
    );

    // Marca do tiro livre / pênalti (6m)
    canvas.drawCircle(
        Offset(size.width / 2, size.height * 0.18), 2.0, dotPaint);
    canvas.drawCircle(
        Offset(size.width / 2, size.height * 0.82), 2.0, dotPaint);

    // Marca do tiro livre de 10m (segundo pênalti futsal)
    canvas.drawCircle(
        Offset(size.width / 2, size.height * 0.32), 1.8, dotPaint);
    canvas.drawCircle(
        Offset(size.width / 2, size.height * 0.68), 1.8, dotPaint);

    // Escanteios nos 4 cantos da quadra
    const double cornerR = 7.0;
    canvas.drawArc(
        Rect.fromCircle(center: const Offset(pad, pad), radius: cornerR),
        0,
        1.5708,
        false,
        linePaint);
    canvas.drawArc(
        Rect.fromCircle(center: Offset(size.width - pad, pad), radius: cornerR),
        1.5708,
        1.5708,
        false,
        linePaint);
    canvas.drawArc(
        Rect.fromCircle(
            center: Offset(pad, size.height - pad), radius: cornerR),
        4.71239,
        1.5708,
        false,
        linePaint);
    canvas.drawArc(
        Rect.fromCircle(
            center: Offset(size.width - pad, size.height - pad),
            radius: cornerR),
        3.14159,
        1.5708,
        false,
        linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
