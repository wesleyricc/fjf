import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/championship_service.dart';
import 'admin_login_dialog.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  Future<void> _handleAdminAction(BuildContext context, AuthService authService) async {
    if (authService.isAdmin) {
      Navigator.of(context).pop();
      Navigator.of(context).pushNamed('/admin-menu');
    } else {
      // Dispara o login do Google do AuthService
      final String? error = await authService.signInWithGoogle();
      
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      } else if (authService.isAdmin && context.mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).pushNamed('/admin-menu');
      } else if (authService.isPresident && context.mounted) {
        Navigator.of(context).pop(); // 🚨 CORREÇÃO AQUI
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bem-vindo, Presidente! Acesso ao Mercado liberado.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final championshipService = Provider.of<ChampionshipService>(context);
    final int year = championshipService.currentSeasonYear;
    final String honoree = championshipService.currentSeasonHonoree;

    return Consumer<AuthService>(
      builder: (context, authService, child) {
        return Drawer(
          child: Column(
            children: [
              UserAccountsDrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  image: const DecorationImage(
                    image: AssetImage('assets/logo3_fjf.png'),
                    opacity: 0.1,
                    fit: BoxFit.cover,
                  ),
                ),
                accountName: Text('FJF $year', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                accountEmail: Text(
                  honoree.isNotEmpty ? honoree : 'Campeonato Oficial',
                  style: const TextStyle(color: Colors.white70),
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Image.asset('assets/logo3_fjf.png', errorBuilder: (c, o, s) => const Icon(Icons.sports_soccer, color: Colors.orange)),
                  ),
                ),
              ),

              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    _buildDrawerItem(context, Icons.dashboard, 'Início', '/'),
                    
                    _buildSectionHeader(context, "DESTAQUES"),
                    _buildDrawerItem(context, Icons.emoji_events, 'Resumo da Temporada', '/season-summary', highlight: true), 
                    _buildDrawerItem(context, Icons.sports_soccer, 'Fantasy FJF', '/fantasy-home', highlight: true),
                    _buildDrawerItem(context, Icons.collections, 'Loja de Fotos', '/photo-sales', highlight: true),
                    _buildDrawerItem(context, FontAwesomeIcons.earthAmericas, 'Bolão da Copa 2026', '/wordcup-pool', highlight: true),
                    
                    _buildSectionHeader(context, "COMPETIÇÃO"),
                    _buildDrawerItem(context, Icons.calendar_month, 'Tabela de Jogos', '/fixtures'),
                    _buildDrawerItem(context, Icons.leaderboard, 'Classificação', '/standings'),
                    _buildDrawerItem(context, Icons.shield, 'Equipes', '/teams'),

                    _buildSectionHeader(context, "DADOS & ESTATÍSTICAS"),
                    _buildDrawerItem(context, Icons.query_stats, 'Estatísticas de Equipes', '/team-stats'),
                    _buildDrawerItem(context, Icons.person_search, 'Estatísticas de Atletas', '/player-stats'),
                    _buildDrawerItem(context, Icons.history_toggle_off, 'Suspensões', '/suspension-history'),
                    _buildDrawerItem(context, Icons.compare_arrows, 'Comparador de Atletas', '/player-comparison'),
                    
                    // 🚨 NOVA SEÇÃO: SEJA UM ATLETA FJF 🚨
                    _buildSectionHeader(context, "SEJA UM ATLETA FJF"),
                    _buildDrawerItem(context, Icons.assignment_ind, 'Inscrição no Mercado', '/free-agents-registration', highlight: true),
                    _buildDrawerItem(context, Icons.transfer_within_a_station, 'Mercado de Atletas', '/free-agents-market'),

                    _buildSectionHeader(context, "SOBRE A FJF"),
                    _buildDrawerItem(context, Icons.history_edu, 'Nossa História', '/about-history'),
                    _buildDrawerItem(context, Icons.groups_2, 'Diretoria', '/aboutR-board'),

                    const Divider(height: 30),
                    _buildDrawerItem(context, Icons.bug_report_outlined, 'Reportar Erro', '/report-bug'),
                    
                    ListTile(
                      leading: Icon(
                        authService.isAdmin ? Icons.admin_panel_settings : Icons.settings_outlined,
                        color: authService.isAdmin ? Colors.green : Colors.grey,
                      ),
                      title: Text(
                        authService.isAdmin ? 'Painel Admin' : 'Acesso Restrito',
                        style: TextStyle(
                          color: authService.isAdmin ? Colors.green[700] : Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () => _handleAdminAction(context, authService),
                    ),
                    
                    if (authService.isAuthenticated)
                      ListTile(
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: const Text('Sair', style: TextStyle(color: Colors.red)),
                        onTap: () async {
                          await authService.logout();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ),
              
              Container(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'FJF App v2.0.0',
                  style: TextStyle(color: Colors.grey[400], fontSize: 10),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).primaryColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, String route, {bool highlight = false}) {
    return ListTile(
      dense: true,
      horizontalTitleGap: 8,
      leading: Icon(
        icon, 
        color: highlight ? Colors.blueAccent : Colors.grey[700],
        size: 22,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
          color: highlight ? Colors.blueAccent : Colors.black87,
        ),
      ),
      onTap: () {
        Navigator.of(context).pop();
        if (route == '/') {
           Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        } else {
           Navigator.of(context).pushNamed(route);
        }
      },
    );
  }
}