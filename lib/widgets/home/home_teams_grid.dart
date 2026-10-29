import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';

import '../../services/championship_service.dart';
import '../ui/custom_empty_state.dart';
import '../ui/shimmer_effect.dart';
import '../ui/optimized_network_image.dart';
import '../../screens/championship/team_detail_screen.dart';
import '../sponsor_banner_rotator.dart';

class SponsorGridCard extends StatelessWidget {
  const SponsorGridCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFC25F22), width: 1.5)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: const SponsorBannerRotator(
          location: 'grid_teams',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class HomeTeamsGrid extends StatelessWidget {
  final bool isCacheResolved; 
  const HomeTeamsGrid({super.key, required this.isCacheResolved});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChampionshipService>(
      builder: (context, service, _) {
        if (service.isLoading && service.teams.isEmpty && !isCacheResolved) {
          return SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.95,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildSkeletonItem(),
              childCount: 6,
            ),
          );
        }

        final teams = service.teams;

        if (teams.isEmpty) {
          return SliverToBoxAdapter(
              child: CustomEmptyState(
            icon: Icons.groups_outlined,
            title: "Sem Equipes",
            message: "As equipes desta temporada ainda estão sendo cadastradas.",
            buttonText: "Atualizar",
            onButtonPressed: () => service.fetchStaticData(forceRefresh: true),
          ));
        }

        const bool insertSponsor = true;
        final int itemCount = teams.length + 1;

        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.95,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (insertSponsor && index == 4) {
                return const SponsorGridCard();
              }

              final int teamIndex = (insertSponsor && index > 4) ? index - 1 : index;
              if (teamIndex >= teams.length) return const SizedBox.shrink();
              final team = teams[teamIndex];

              return RepaintBoundary(
                child: InkWell(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team))),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.yellowColor, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: OptimizedNetworkImage(
                              imageUrl: team.shieldUrl,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              memCacheWidth: 160,
                              memCacheHeight: 160,
                              fallbackIcon: Icons.shield_outlined,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                          child: Text(
                            team.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            childCount: itemCount,
          ),
        );
      },
    );
  }

  Widget _buildSkeletonItem() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.yellowColor, width: 1.5),
      ),
      padding: const EdgeInsets.all(12),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(child: ShimmerEffect.circular(size: 60)),
          SizedBox(height: 10),
          ShimmerEffect.rectangular(height: 10, width: 60),
        ],
      ),
    );
  }
}
