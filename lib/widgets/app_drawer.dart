import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/championship_service.dart';
import 'admin_login_dialog.dart'; // <-- Importa o novo widget

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  Future<void> _handleAdminAction(BuildContext context, AuthService authService) async {
    // Fecha o Drawer primeiro para evitar sobreposição visual
    Navigator.of(context).pop();

    if (authService.isAuthenticated) {
      // Se já está logado, vai pro menu
      Navigator.of(context).pushNamed('/admin-menu');
    } else {
      // Se não, abre o diálogo de login
      final bool? success = await showDialog<bool>(
        context: context,
        builder: (ctx) => const AdminLoginDialog(),
      );

      // Se logou com sucesso, navega para o menu
      if (success == true && context.mounted) {
        Navigator.of(context).pushNamed('/admin-menu');
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
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              // --- HEADER ---
              DrawerHeader(
                decoration: BoxDecoration(color: Theme.of(context).primaryColor),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/logo2_fjf.png', height: 80, errorBuilder: (c, o, s) => const Icon(Icons.sports_soccer, size: 80, color: Colors.white)),
                    const SizedBox(height: 8),
                    Text('FJF $year', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        honoree.isNotEmpty ? honoree : 'Campeonato Oficial',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // --- ITENS DE NAVEGAÇÃO ---
              _buildDrawerItem(context, Icons.home, 'Início', '/'),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.calendar_today, 'Tabela de Jogos', '/fixtures'),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.leaderboard, 'Classificação', '/standings'),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.group, 'Equipes', '/teams'),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.query_stats, 'Estatísticas das Equipes', '/team-stats'),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.person_search, 'Estatísticas dos Jogadores', '/player-stats'),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.history_toggle_off, 'Histórico de Suspensões', '/suspension-history'),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.compare_arrows, 'Comparador de Jogadores', '/player-comparison'),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.bug_report_outlined, 'Reportar Erro', '/report-bug'),
              const Divider(height: 1, indent: 16, endIndent: 16),

              // --- ÁREA ADMIN ---
              ListTile(
                leading: Icon(
                  authService.isAuthenticated ? Icons.admin_panel_settings : Icons.lock_outline,
                  color: authService.isAuthenticated ? Colors.green : Colors.grey,
                ),
                title: Text(
                  authService.isAuthenticated ? 'Menu Administrador' : 'Acesso Admin',
                  style: TextStyle(
                    color: authService.isAuthenticated ? Colors.green[700] : Colors.grey[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: authService.isAuthenticated ? Text('Logado como: ${authService.adminUsername}') : null,
                onTap: () => _handleAdminAction(context, authService),
              ),

              if (authService.isAuthenticated)
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Sair', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    await authService.logout();
                    if (context.mounted) {
                      Navigator.of(context).pop(); // Fecha Drawer
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sessão encerrada.')));
                    }
                  },
                ),

              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Versão 2.0.0\n© FJF 2026',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400], fontSize: 10),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, String route) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[700]),
      title: Text(title),
      dense: true,
      onTap: () {
        Navigator.of(context).pop(); // Fecha o Drawer
        // Usa pushReplacement para não empilhar telas infinitamente
        // Exceto se for a Home (/) que geralmente é a base
        if (route == '/') {
           Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        } else {
           Navigator.of(context).pushNamed(route);
        }
      },
    );
  }
}