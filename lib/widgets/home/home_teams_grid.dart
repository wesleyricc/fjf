import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../services/championship_service.dart';
import '../../viewmodels/sponsor_viewmodel.dart';
import '../ui/custom_empty_state.dart';
import '../ui/shimmer_effect.dart';
import '../../screens/championship/team_detail_screen.dart';

class SponsorGridCard extends StatelessWidget {
  final String _partnerContactUrl = "https://wa.me/5548996381626?text=Ol%C3%A1,%20gostaria%20de%20ser%20parceiro%20do%20aplicativo%20da%20FJF.";

  const SponsorGridCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SponsorViewModel>(builder: (context, sponsorVm, _) {
      final sponsors = sponsorVm.sponsors.where((s) {
        return s['location'] == 'grid_teams' && s['isActive'] == true;
      }).toList();

      if (sponsors.isNotEmpty) {
        final data = sponsors.first;

        return InkWell(
          onTap: () async {
            final url = data['targetUrl'];
            if (url != null && url.isNotEmpty) {
              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC5A814), width: 1.5)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: data['imageUrl'] ?? '',
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => _buildDefaultCard(),
              ),
            ),
          ),
        );
      }
      return _buildDefaultCard();
    });
  }

  Widget _buildDefaultCard() {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(_partnerContactUrl), mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF002776), Color(0xFF001133)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC5A814), width: 1.5)),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(Icons.all_inclusive, size: 100, color: Colors.white.withOpacity(0.05)),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFC5A814).withOpacity(0.2),
                        shape: BoxShape.circle),
                    child: const Icon(FontAwesomeIcons.handshake, color: Color(0xFFC5A814), size: 24),
                  ),
                  const SizedBox(height: 8),
                  const Text("SEJA PARCEIRO",
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          color: Color(0xFFC5A814),
                          letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  const Text("Anuncie aqui", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.white70)),
                ],
              ),
            ),
          ],
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
              childAspectRatio: 0.85,
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

        final bool insertSponsor = (teams.length == 8);
        final int itemCount = insertSponsor ? 9 : teams.length;

        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.85,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (insertSponsor && index == 4) {
                return const SponsorGridCard();
              }

              final int teamIndex = (insertSponsor && index > 4) ? index - 1 : index;
              final team = teams[teamIndex];

              return InkWell(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team))),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC5A814), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
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
                          child: CachedNetworkImage(
                            imageUrl: team.shieldUrl,
                            fit: BoxFit.contain,
                            placeholder: (_, __) => Container(color: Colors.grey.shade50),
                            errorWidget: (_, __, ___) => const Icon(Icons.shield_outlined, color: Colors.grey),
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
        border: Border.all(color: const Color(0xFFC5A814), width: 1.5),
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
