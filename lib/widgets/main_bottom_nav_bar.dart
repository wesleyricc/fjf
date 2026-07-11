import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../services/auth_service.dart';
import '../services/championship_service.dart';
import '../services/fantasy_service.dart';
import '../services/voting_service.dart';
import '../services/analytics_service.dart';
import '../models/poll_model.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../screens/mini_bolao_home_screen.dart';

class MainBottomNavBar extends StatelessWidget {
  final String currentRoute;

  const MainBottomNavBar({super.key, required this.currentRoute});

  void _navigate(BuildContext context, String routeName) {
    if (currentRoute == routeName) return;

    if (routeName == '/') {
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }

    final isMainTab = ['/fixtures', '/standings', '/season-summary', '/teams'].contains(routeName);

    if (currentRoute == '/') {
      Navigator.pushNamed(context, routeName);
    } else if (isMainTab) {
      Navigator.pushReplacementNamed(context, routeName);
    } else {
      Navigator.pushNamed(context, routeName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SponsorBannerRotator(location: 'footer_home'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildBottomNavItem(context, Icons.home, "Início", isActive: currentRoute == '/', onTap: () => _navigate(context, '/')),
                  _buildBottomNavItem(context, Icons.calendar_month, "Jogos", isActive: currentRoute == '/fixtures', onTap: () => _navigate(context, '/fixtures')),
                  _buildBottomNavItem(context, Icons.leaderboard, "Tabela", isActive: currentRoute == '/standings', onTap: () => _navigate(context, '/standings')),
                  _buildBottomNavItem(context, Icons.emoji_events, "Resumo", isActive: currentRoute == '/season-summary', onTap: () => _navigate(context, '/season-summary')),
                  _buildBottomNavItem(context, Icons.menu, "Menu", onTap: () => _showMenuBottomSheet(context)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavItem(BuildContext context, IconData icon, String label, {bool isActive = false, required VoidCallback onTap}) {
    final color = isActive ? Theme.of(context).primaryColor : Colors.grey.shade600;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
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
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
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
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text("Menu Principal", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 30),
                child: Column(
                  children: [
                    _buildQuickAccessGrid(ctx),
                    const SizedBox(height: 16),
                    _buildStatisticsSection(ctx),
                    const SizedBox(height: 16),
                    _buildMarketSection(ctx),
                    const SizedBox(height: 16),
                    _buildInstitutionalSection(ctx),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemedSectionHeader(BuildContext context, String title, IconData icon) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 16, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFC5A814), Color(0xFF00873E)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
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
        _buildThemedSectionHeader(context, "Menu Principal", Icons.dashboard),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 10,
            childAspectRatio: 0.8,
            children: [
              _buildGridItem(context, Icons.calendar_month, "Jogos", '/fixtures', Colors.blue),
              _buildGridItem(context, Icons.leaderboard, "Tabela", '/standings', Colors.green),
              _buildGridItem(context, Icons.shield, "Equipes", '/teams', Colors.orange),
              _buildGridItem(context, Icons.emoji_events, "Resumo", '/season-summary', Colors.purple),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridItem(BuildContext context, IconData icon, String label, String route, Color color) {
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
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsSection(BuildContext context) {
    return Column(
      children: [
        _buildThemedSectionHeader(context, "Dados & Estatísticas", Icons.query_stats),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              _buildListTile(context, Icons.query_stats, "Estatísticas de Equipes", '/team-stats'),
              const Divider(height: 1),
              _buildListTile(context, Icons.person_search, "Estatísticas de Atletas", '/player-stats'),
              const Divider(height: 1),
              _buildListTile(context, Icons.history_toggle_off, "Suspensões", '/suspension-history'),
              const Divider(height: 1),
              _buildListTile(context, Icons.compare_arrows, "Comparador de Atletas", '/player-comparison'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMarketSection(BuildContext context) {
    return Column(
      children: [
        _buildThemedSectionHeader(context, "Seja um Atleta FJF", Icons.assignment_ind),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.blue.shade900, Colors.blue.shade700]),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
            border: Border.all(color: const Color(0xFFC5A814)),
          ),
          child: Column(
            children: [
              _buildListTile(context, Icons.assignment_ind, "Inscrição no Mercado", '/free-agents-registration', isDark: true),
              Divider(height: 1, color: Colors.white.withOpacity(0.2)),
              _buildListTile(context, Icons.transfer_within_a_station, "Mercado de Atletas", '/free-agents-market', isDark: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInstitutionalSection(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        return Column(
          children: [
            _buildThemedSectionHeader(context, "Institucional & Conta", Icons.business),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  _buildListTile(context, Icons.history_edu, "Nossa História", '/about-history'),
                  const Divider(height: 1),
                  _buildListTile(context, Icons.groups_2, "Diretoria", '/about-board'),
                  const Divider(height: 1),
                  _buildListTile(context, Icons.bug_report_outlined, "Reportar Erro", '/report-bug'),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(authService.isAdmin ? Icons.admin_panel_settings : Icons.settings_outlined, color: authService.isAdmin ? Colors.green : Colors.grey),
                    title: Text(authService.isAdmin ? 'Painel Admin' : 'Acesso Restrito', style: TextStyle(color: authService.isAdmin ? Colors.green[700] : Colors.grey[700], fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    onTap: () async {
                      Navigator.pop(context); // Fecha o modal
                      if (authService.isAdmin) {
                        Navigator.of(context).pushNamed('/admin-menu');
                      } else {
                        final String? error = await authService.signInWithGoogle();
                        if (error != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                        } else if (authService.isAdmin && context.mounted) {
                          Navigator.of(context).pushNamed('/admin-menu');
                        } else if (authService.isPresident && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bem-vindo, Presidente! Acesso ao Mercado liberado.")));
                        }
                      }
                    },
                  ),
                  if (authService.isAuthenticated) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text('Sair', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                      onTap: () async {
                        Navigator.pop(context); // Fecha o modal
                        await authService.logout();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      }
    );
  }

  Widget _buildListTile(BuildContext context, IconData icon, String title, String route, {bool isDark = false}) {
    return ListTile(
      leading: Icon(icon, color: isDark ? Colors.white : Theme.of(context).primaryColor),
      title: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 14)),
      trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.white70 : Colors.grey),
      onTap: () {
        Navigator.pop(context); // Fecha o modal
        _navigate(context, route);
      },
    );
  }
}
