import 'package:flutter/material.dart';
import '../../services/championship_service.dart';
import '../../services/analytics_service.dart';
import '../../services/voting_service.dart';
import '../../models/poll_model.dart';
import '../../theme/app_theme.dart';
import 'package:FJF_App/screens/bolao/mini_bolao_home_screen.dart';
import 'home_section_header.dart';
import 'home_modals.dart';

class HomeSuperAppGrid extends StatelessWidget {
  final ChampionshipService service;
  const HomeSuperAppGrid({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Poll>>(
        stream: service.currentSeasonId.isNotEmpty
            ? VotingService().streamActivePolls(service.currentSeasonId)
            : Stream.value([]),
        builder: (context, pollSnapshot) {
          final activePolls = pollSnapshot.data ?? [];

          List<Widget> items = [];

          if (service.isFantasyEnabled) {
            items.add(SuperAppGridItem(
              title: "Cartola FJF",
              imageAsset: 'assets/logo_fjf_fantasy.webp',
              color: const Color(0xFF2A1110),
              isFeatured: true,
              badgeText: "NOVO",
              onTap: () {
                AnalyticsService.logCustomScreenView('Home_Click_Fantasy');
                Navigator.pushNamed(context, '/fantasy-home');
              },
            ));
          }

          if (service.isBolaoEnabled) {
            items.add(SuperAppGridItem(
              title: "Bolão FJF - Copa do Mundo 2026",
              icon: Icons.public,
              color: const Color(0xFF009C3B),
              onTap: () {
                AnalyticsService.logCustomScreenView('Home_Click_Bolao_VIP');
                Navigator.pushNamed(context, '/wordcup-pool');
              },
            ));
          }

          if (service.isMiniBolaoEnabled) {
            items.add(SuperAppGridItem(
              title: "Mini Bolão FJF",
              icon: Icons.rocket_launch,
              color: Colors.deepOrange.shade600,
              onTap: () {
                AnalyticsService.logCustomScreenView('Home_Click_Mini_Bolao');
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MiniBolaoHomeScreen()));
              },
            ));
          }

          if (service.isPhotoStoreEnabled) {
            items.add(SuperAppGridItem(
              title: "Fotos",
              icon: Icons.camera_enhance,
              color: const Color(0xFF32BCAD),
              onTap: () {
                AnalyticsService.logCustomScreenView('Home_Click_Photo_Store');
                Navigator.pushNamed(context, '/photo-sales');
              },
            ));
          }

          if (activePolls.isNotEmpty) {
            items.add(SuperAppGridItem(
              title: "Votações",
              icon: Icons.how_to_vote,
              color: const Color(0xFFC25F22),
              badgeCount: activePolls.length,
              onTap: () {
                if (activePolls.length == 1) {
                  Navigator.pushNamed(context, '/voting',
                          arguments: activePolls.first)
                      .then((_) {});
                } else {
                  HomeModals.showVotingBottomSheet(
                      context, activePolls, service.currentSeasonId);
                }
              },
            ));
          }

          if (items.isEmpty) return const SizedBox();

          Widget gridLayout;
          int itemsPerRow = items.length <= 4 ? 4 : 3;
          List<Widget> rows = [];

          for (int i = 0; i < items.length; i += itemsPerRow) {
            List<Widget> rowItems = [];
            for (int j = 0; j < itemsPerRow; j++) {
              if (i + j < items.length) {
                rowItems.add(Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: items[i + j],
                  ),
                ));
              }
            }
            rows.add(Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rowItems));
            if (i + itemsPerRow < items.length)
              rows.add(const SizedBox(height: 16));
          }

          gridLayout = Column(children: rows);

          return Column(
            children: [
              HomeSectionHeader(
                  title: "Central FJF",
                  icon: Icons.apps,
                  color: AppTheme.primaryColor),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(12)),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 3))
                  ],
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: gridLayout,
              ),
            ],
          );
        });
  }
}

class SuperAppGridItem extends StatefulWidget {
  final String title;
  final IconData? icon;
  final String? imageAsset;
  final Color color;
  final VoidCallback onTap;
  final int badgeCount;
  final String? badgeText;
  final bool isFeatured;

  const SuperAppGridItem({
    super.key,
    required this.title,
    this.icon,
    this.imageAsset,
    required this.color,
    required this.onTap,
    this.badgeCount = 0,
    this.badgeText,
    this.isFeatured = false,
  }) : assert(icon != null || imageAsset != null,
            'Either icon or imageAsset must be provided');

  @override
  State<SuperAppGridItem> createState() => _SuperAppGridItemState();
}

class _SuperAppGridItemState extends State<SuperAppGridItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final hslColor = HSLColor.fromColor(widget.color);
    final lighterColor = hslColor
        .withLightness((hslColor.lightness + 0.15).clamp(0.0, 1.0))
        .toColor();

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: double.infinity,
                  height: 74,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: widget.isFeatured
                          ? const [Color(0xFFFF6D00), Color(0xFF250C0B)]
                          : [lighterColor, widget.color],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: widget.isFeatured
                        ? Border.all(color: const Color(0xFFFFB300), width: 1.8)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: widget.isFeatured
                            ? const Color(0xFFFF6D00).withOpacity(0.55)
                            : widget.color.withOpacity(0.4),
                        blurRadius: widget.isFeatured ? 14 : 10,
                        spreadRadius: widget.isFeatured ? 1.5 : 0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: widget.imageAsset != null
                      ? Padding(
                          padding: EdgeInsets.all(widget.isFeatured ? 2.0 : 7.0),
                          child: Transform.scale(
                            scale: widget.isFeatured ? 1.25 : 1.0,
                            child: Image.asset(
                              widget.imageAsset!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        )
                      : Icon(widget.icon, color: Colors.white, size: 32),
                ),
                if (widget.badgeCount > 0)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        widget.badgeCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (widget.badgeText != null)
                  Positioned(
                    top: -8,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD54F), Color(0xFFFF6D00)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt, size: 9, color: Colors.black87),
                          const SizedBox(width: 1),
                          Text(
                            widget.badgeText!,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: widget.isFeatured ? FontWeight.w900 : FontWeight.w700,
                color: widget.isFeatured ? const Color(0xFFD84315) : Colors.black87,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
