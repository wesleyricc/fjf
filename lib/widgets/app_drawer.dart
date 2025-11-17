// lib/widgets/app_drawer.dart
import 'package:flutter/material.dart';
// Precisamos importar as telas para onde vamos navegar
import '../screens/splash_screen.dart';
import '../services/admin_service.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final AdminService adminService = AdminService();

    return Drawer(
      // A cor de fundo já é definida pelo tema no main.dart (drawerTheme)
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          // --- HEADER DO DRAWER (Com a Logo e Título) ---
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).primaryColor, // Cor definida no main.dart
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/logo2_fjf.png', // Caminho da sua logo
                  height: 80,
                ),
                const SizedBox(height: 8),
                const Text(
                  'FJF 2025',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Taça Mary Neusa Espíndola Bif',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // --- FIM DO HEADER ---

          // --- ITENS DO MENU (Com a lógica de navegação corrigida) ---
          _buildDrawerItem(
            context,
            Icons.home,
            'Início',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacementNamed('/');
            },
          ),

          const Divider(color: Colors.white24, indent: 16, endIndent: 16),
          _buildDrawerItem(
            context,
            Icons.calendar_today,
            'Tabela de Jogos',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacementNamed('/fixtures');
            },
          ),

          const Divider(color: Colors.white24, indent: 16, endIndent: 16),
          _buildDrawerItem(context, Icons.leaderboard, 'Classificação', () {
            Navigator.of(context).pop();
            Navigator.of(context).pushReplacementNamed('/standings');
          }),

          const Divider(color: Colors.white24, indent: 16, endIndent: 16),
          _buildDrawerItem(
            context,
            Icons.group,
            'Equipes',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacementNamed('/teams');
            },
          ),

          const Divider(color: Colors.white24, indent: 16, endIndent: 16),
          _buildDrawerItem(
            context,
            Icons.query_stats,
            'Estatísticas das Equipes',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacementNamed('/team-stats');
            },
          ),

          const Divider(color: Colors.white24, indent: 16, endIndent: 16),
          _buildDrawerItem(
            context,
            Icons.person_search,
            'Estatísticas dos Jogadores',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacementNamed('/player-stats');
            },
          ),

          const Divider(color: Colors.white24, indent: 16, endIndent: 16),
          _buildDrawerItem(
            context,
            Icons.history_toggle_off,
            'Histórico de Suspensões',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/suspension-history');
            },
          ),

          const Divider(color: Colors.white24, indent: 16, endIndent: 16),
          _buildDrawerItem(
            context,
            Icons.bug_report_outlined,
            'Reportar Erro',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/report-bug');
            },
            denseOverride: true,
            contentPaddingOverride: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          ),

          const Divider(color: Colors.white24, indent: 16, endIndent: 16),

         // --- INÍCIO DA ALTERAÇÃO ---
 _buildDrawerItem(
 context,
 AdminService.isAdmin
 ? Icons.admin_panel_settings
 : Icons.lock_outline,
 AdminService.isAdmin
 ? 'Menu Administrador'
 : 'Modo Administrador',
 // Torna o onTap assíncrono
 () async { 
 if (AdminService.isAdmin) {
 // 1. Se já é admin, apenas navega
Navigator.of(context).pop();
 Navigator.of(context).pushNamed('/admin-menu');
 } else {
 // 2. Se não é admin, chama o login e AGUARDA (await) o resultado
 final bool loginSuccess = await adminService.promptAdminPassword(context);

 // 3. Se o login foi bem-sucedido, navega
if (loginSuccess && (context as Element).mounted) {
 Navigator.of(context).pop(); // Fecha o drawer
 Navigator.of(context).pushNamed('/admin-menu');
 }
 // Se loginSuccess for false (cancelado), não faz nada (o drawer continua aberto)
 }
},
denseOverride: true,
 contentPaddingOverride: const EdgeInsets.symmetric(
 horizontal: 16.0,
 vertical: 4.0,
),
),
          // --- FIM DA ALTERAÇÃO ---

          // --- ITEM DE LOGOUT (SÓ SE LOGADO) ---
          if (AdminService.isAdmin)
            _buildDrawerItem(
              context,
              Icons.logout,
              'Sair do Modo Administrador',
              () {
                AdminService.logoutAdmin();
                Navigator.of(context).pop(); // Fecha o drawer
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Modo Administrador desativado.'),
                  ),
                );
                // Opcional: Navegar para a tela inicial para "resetar" visualmente
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (ctx) => const SplashScreen()),
                  (route) => false, // Remove todas as rotas anteriores
                );
              },
              denseOverride: true,
              contentPaddingOverride: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 4.0,
              ),
            ),

          // --- ADICIONAR TEXTO DE COPYRIGHT AQUI ---
          const SizedBox(height: 30), // Espaço antes do texto
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Desenvolvido por Wesley Ricardo.\nTodos os direitos reservados © FJF 2025.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5), // Cor branca sutil
                fontSize: 11, // Fonte pequena
                height: 1.4, // Espaçamento entre linhas
              ),
            ),
          ),
          const SizedBox(height: 24), // Espaço no final do menu
          // --- FIM DA ADIÇÃO ---
          // --- FIM DO ITEM DE LOGOUT ---
        ],
      ),
    );
  }

  // Função auxiliar para construir os itens do Drawer
  Widget _buildDrawerItem(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool? denseOverride,
    EdgeInsets? contentPaddingOverride,
  }) {
    return ListTile(
      dense: denseOverride ?? true,
      contentPadding:
          contentPaddingOverride ??
          const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 4.0,
          ), // Usa override ou o padrão
      leading: Icon(icon, color: Colors.white70, size: 24),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      onTap: onTap,
    );
  }
}