import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../../theme/app_theme.dart';
import '../styled_sponsor_banner.dart';

class FantasyBottomNavBar extends StatelessWidget {
  final String currentRoute;
  final bool showSponsor;

  const FantasyBottomNavBar({
    super.key,
    required this.currentRoute,
    this.showSponsor = true,
  });

  void _navigate(BuildContext context, String routeName) {
    if (currentRoute == routeName) return;

    if (routeName == '/fantasy-home') {
      Navigator.popUntil(context,
          (route) => route.settings.name == '/fantasy-home' || route.isFirst);
      return;
    }

    final isMainTab = [
      '/fantasy-lineup',
      '/fantasy-market',
      '/fantasy-rankings',
      '/fantasy-leagues',
    ].contains(routeName);

    if (currentRoute == '/fantasy-home') {
      Navigator.pushNamed(context, routeName);
    } else if (isMainTab) {
      Navigator.pushReplacementNamed(context, routeName);
    } else {
      Navigator.pushNamed(context, routeName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool shouldShowSponsor =
        showSponsor && currentRoute != '/fantasy-lineup' && currentRoute != '/fantasy-market';

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 40 ||
            (MediaQuery.maybeSizeOf(context)?.height ?? 0) < 60) {
          return const SizedBox.shrink();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (shouldShowSponsor) const StyledSponsorBanner(location: 'fantasy'),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildBottomNavItem(context, Icons.home, "Início",
                          isActive: currentRoute == '/fantasy-home',
                          onTap: () => _navigate(context, '/fantasy-home')),
                      _buildBottomNavItem(context, Icons.shield, "Escalar",
                          isActive: currentRoute == '/fantasy-lineup',
                          onTap: () => _navigate(context, '/fantasy-lineup')),
                      _buildBottomNavItem(context, Icons.shopping_cart, "Mercado",
                          isActive: currentRoute == '/fantasy-market',
                          onTap: () => _navigate(context, '/fantasy-market')),
                      _buildBottomNavItem(context, Icons.groups, "Ranking",
                          isActive: currentRoute == '/fantasy-rankings',
                          onTap: () => _navigate(context, '/fantasy-rankings')),
                      _buildBottomNavItem(context, Icons.emoji_events, "Ligas",
                          isActive: currentRoute == '/fantasy-leagues',
                          onTap: () => _navigate(context, '/fantasy-leagues')),
                      _buildBottomNavItem(context, Icons.menu, "Menu",
                          onTap: () => _showMenuBottomSheet(context)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomNavItem(BuildContext context, IconData icon, String label,
      {bool isActive = false, required VoidCallback onTap}) {
    final color =
        isActive ? Theme.of(context).primaryColor : Colors.grey.shade600;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight:
                        isActive ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  void _showMenuBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PointerInterceptor(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.5,
          decoration: const BoxDecoration(
            color: Color(0xFFF0F2F5),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/logo_fjf_fantasy.webp', height: 28),
                    const SizedBox(width: 8),
                    const Text("Menu Cartola FJF",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Column(
                    children: [
                      _buildQuickAccessGrid(ctx),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemedSectionHeader(
      BuildContext context, String title, IconData icon) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 16, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        image: AppTheme.headerImage,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, -2))
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildQuickAccessGrid(BuildContext context) {
    return Column(
      children: [
        _buildThemedSectionHeader(context, "Mais Opções", Icons.dashboard),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(12)),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))
            ],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 10,
            childAspectRatio: 0.85,
            children: [
              _buildGridItem(context, Icons.military_tech, "Top 5",
                  '/fantasy-top-players', Colors.amber.shade800),
              _buildGridItem(context, Icons.analytics, "Scouts",
                  '/fantasy-scouts', Colors.indigoAccent),
              _buildGridItem(context, Icons.history, "Histórico",
                  '/fantasy-history', Colors.teal),
              _buildGridItem(context, Icons.fact_check_outlined, "Revisão",
                  '/fantasy-scout-review', Colors.deepPurpleAccent),
              _buildGridItem(context, Icons.menu_book, "Regras",
                  '/fantasy-rules', Colors.blueGrey),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridItem(BuildContext context, IconData icon, String label,
      String route, Color color) {
    return InkWell(
      onTap: () {
        Navigator.pop(context); // Fecha o modal
        _navigate(context, route);
      },
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
        ],
      ),
    );
  }
}
