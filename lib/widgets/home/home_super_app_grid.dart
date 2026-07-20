import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/championship_service.dart';
import '../../services/analytics_service.dart';
import '../../services/voting_service.dart';
import '../../services/bolao_service.dart';
import '../../models/poll_model.dart';
import '../../theme/app_theme.dart';
import 'package:FJF_App/screens/bolao/mini_bolao_home_screen.dart';
import 'home_section_header.dart';
import 'home_modals.dart';

class HomeSuperAppGrid extends StatelessWidget {
  final ChampionshipService service;
  const HomeSuperAppGrid({super.key, required this.service});

Widget buildSuperAppGridItem({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                height: 70,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withOpacity(0.5), width: 1.5),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              if (badgeCount > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badgeCount.toString(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

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
            items.add(buildSuperAppGridItem(
              context: context,
              title: "Fantasy",
              icon: Icons.sports_soccer,
              color: const Color(0xFF002776),
              onTap: () {
                AnalyticsService.logCustomScreenView('Home_Click_Fantasy');
                Navigator.pushNamed(context, '/fantasy-home');
              },
            ));
          }

          if (service.isBolaoEnabled) {
            items.add(buildSuperAppGridItem(
              context: context,
              title: "Bolão FJF - Copa do Mundo 2026",
              icon: FontAwesomeIcons.earthAmericas,
              color: const Color(0xFF009C3B),
              onTap: () {
                AnalyticsService.logCustomScreenView('Home_Click_Bolao_VIP');
                Navigator.pushNamed(context, '/wordcup-pool');
              },
            ));
          }

          if (service.isMiniBolaoEnabled) {
            items.add(buildSuperAppGridItem(
              context: context,
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
            items.add(buildSuperAppGridItem(
              context: context,
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
            items.add(buildSuperAppGridItem(
              context: context,
              title: "Votações",
              icon: Icons.how_to_vote,
              color: const Color(0xFFC5A814),
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
          if (items.length <= 4) {
            gridLayout = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: items
                  .map((item) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: item,
                        ),
                      ))
                  .toList(),
            );
          } else {
            // Ex: se houver 5 cards, divide 3 em cima e 2 embaixo
            List<Widget> firstRow = items
                .sublist(0, 3)
                .map((item) => Expanded(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: item)))
                .toList();
            List<Widget> secondRow = items
                .sublist(3)
                .map((item) => Expanded(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: item)))
                .toList();

            gridLayout = Column(
              children: [
                Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: firstRow),
                const SizedBox(height: 16),
                Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: secondRow),
              ],
            );
          }

          return Column(
            children: [
              HomeSectionHeader(title: "Central FJF", icon: Icons.apps, color: AppTheme.primaryColor),
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
