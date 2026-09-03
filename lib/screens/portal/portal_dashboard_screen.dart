import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/portal_auth_service.dart';
import '../../theme/app_theme.dart';
import 'portal_home_tab.dart';
import 'portal_agenda_tab.dart';
import 'portal_financial_tab.dart';
import 'portal_admin_tab.dart';
import '../../services/championship_service.dart';

class PortalDashboardScreen extends StatefulWidget {
  const PortalDashboardScreen({super.key});

  @override
  State<PortalDashboardScreen> createState() => _PortalDashboardScreenState();
}

class _PortalDashboardScreenState extends State<PortalDashboardScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChampionshipService>(context, listen: false).fetchStaticData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<PortalAuthService>(context);
    final user = authService.currentPortalUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isGlobalAdmin = user.role == 'admin' || user.role == 'staff';
    final isPresident = user.role == 'president';
    final hasAdminAccess = isGlobalAdmin || isPresident;

    final List<Widget> tabs = [
      PortalHomeTab(onNavigate: (index) => setState(() => _currentIndex = index)),
      const PortalAgendaTab(),
      const PortalFinancialTab(),
      if (hasAdminAccess) PortalAdminTab(isPresident: isPresident, teamId: user.teamId),
    ];

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.brazilGradient,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Portal do Atleta', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Bem-vindo(a) ${user.name.split(' ').first}', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 1,
        actions: [
          if (hasAdminAccess)
            IconButton(
              icon: const Icon(Icons.transfer_within_a_station, color: Colors.white),
              tooltip: 'Mercado de Atletas',
              onPressed: () {
                Navigator.of(context).pushNamed('/free-agents-market');
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: () async {
              await authService.logout();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/portal');
              }
            },
          )
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: tabs[_currentIndex],
      ),
      bottomNavigationBar: _buildBottomNavBar(context, hasAdminAccess, isPresident),
    );
  }

  Widget _buildBottomNavBar(BuildContext context, bool hasAdminAccess, bool isPresident) {
    return Container(
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
              _buildBottomNavItem(context, Icons.home, "Início", index: 0),
              _buildBottomNavItem(context, Icons.calendar_month, "Agenda", index: 1),
              _buildBottomNavItem(context, Icons.account_balance_wallet, "Financeiro", index: 2),
              if (hasAdminAccess) _buildBottomNavItem(context, isPresident ? Icons.shield : Icons.admin_panel_settings, isPresident ? "Meu Time" : "Admin", index: 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(BuildContext context, IconData icon, String label, {required int index}) {
    final isActive = _currentIndex == index;
    final color = isActive ? Theme.of(context).primaryColor : Colors.grey.shade600;
    
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
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
}
