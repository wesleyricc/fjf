import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/portal_auth_service.dart';
import '../../theme/app_theme.dart';
import 'portal_home_tab.dart';
import 'portal_agenda_tab.dart';
import 'portal_financial_tab.dart';
import 'portal_admin_tab.dart';
import 'portal_profile_tab.dart';

class PortalDashboardScreen extends StatefulWidget {
  const PortalDashboardScreen({super.key});

  @override
  State<PortalDashboardScreen> createState() => _PortalDashboardScreenState();
}

class _PortalDashboardScreenState extends State<PortalDashboardScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<PortalAuthService>(context);
    final user = authService.currentPortalUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isAdmin = user.role == 'admin' || user.role == 'president' || user.role == 'staff';

    final List<Widget> tabs = [
      PortalHomeTab(onNavigate: (index) => setState(() => _currentIndex = index)),
      const PortalProfileTab(),
      const PortalAgendaTab(),
      const PortalFinancialTab(),
      if (isAdmin) const PortalAdminTab(),
    ];

    final List<BottomNavigationBarItem> navItems = [
      const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Início'),
      const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
      const BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Agenda'),
      const BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Financeiro'),
      if (isAdmin) const BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings), label: 'Admin'),
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
          if (isAdmin)
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
      body: tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: navItems,
      ),
    );
  }
}
