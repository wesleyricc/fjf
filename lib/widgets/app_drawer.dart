// lib/widgets/app_drawer.dart
import 'package:flutter/material.dart';
// Precisamos importar as telas para onde vamos navegar
import '../screens/fixtures_screen.dart';
import '../screens/standings_screen.dart';
import '../screens/scorers_screen.dart';
import '../screens/assists_screen.dart';
import '../screens/disciplinary_screen.dart';
import '../screens/least_conceded_gk_screen.dart'; // <-- NOVO
import '../screens/man_of_the_match_screen.dart'; // <-- NOVO
import '../screens/splash_screen.dart';
import '../screens/teams_list_screen.dart';
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
              color: Theme.of(context).primaryColor, // Cor definida no main.dart
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
            Icons.home, // Ícone de TV ao vivo
            'Início',
            () {
              Navigator.of(context).pop();
              // Use pushReplacement para não empilhar a tela inicial
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (ctx) => const SplashScreen()),
              );
            },
          ),

          const Divider(color: Colors.white54), // Separador visual
          _buildDrawerItem(
            context,
            Icons.calendar_today,
            'Tabela de Jogos',
            () {
              Navigator.of(context).pop(); // Fecha o drawer
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (ctx) => const FixturesScreen()),
              );
            },
          ),

          const Divider(color: Colors.white54), // Separador visual
          _buildDrawerItem(
            context,
            Icons.leaderboard,
            'Classificação',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                // Removemos o 'const' pois StandingsScreen não é mais const
                MaterialPageRoute(builder: (ctx) => StandingsScreen()), 
              );
            },
          ),

          const Divider(color: Colors.white54), // Separador visual
          _buildDrawerItem(
            context,
            Icons.group, // Ícone de grupo/times
            'Equipes',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (ctx) => const TeamsListScreen()), // <-- Vai para a nova tela
              );
            },
          ),

          const Divider(color: Colors.white54), // Separador visual
          _buildDrawerItem(
            context,
            Icons.sports_soccer,
            'Artilheiros',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (ctx) => const ScorersScreen()),
              );
            },
          ),

          const Divider(color: Colors.white54), // Separador visual
          _buildDrawerItem(
            context,
            Icons.assistant,
            'Assistências',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (ctx) => const AssistsScreen()),
              );
            },
          ),

          const Divider(color: Colors.white54), // Separador visual
          _buildDrawerItem(
            context,
            Icons.warning,
            'Cartões',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                // Removemos o 'const' pois DisciplinaryScreen não é mais const
                MaterialPageRoute(builder: (ctx) => DisciplinaryScreen()),
              );
            },
          ),

          const Divider(color: Colors.white54), // Separador visual
          _buildDrawerItem(
            context,
            Icons.shield, // Ícone de escudo/goleiro
            'Goleiro Menos Vazado',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (ctx) => const LeastConcededGkScreen()),
              );
            },
          ),

          const Divider(color: Colors.white54), // Separador visual
          _buildDrawerItem(
            context,
            Icons.star, // Ícone de estrela
            'Craque do Jogo',
            () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (ctx) => const ManOfTheMatchScreen()),
              );
            },
          ),

          const Divider(color: Colors.white54), // Separador visual
          _buildDrawerItem(
            context,
            AdminService.isAdmin ? Icons.admin_panel_settings : Icons.lock_outline, // Ícone muda se logado
            AdminService.isAdmin ? 'Menu Admin' : 'Acesso Admin', // Texto muda
            () {
              Navigator.of(context).pop(); // Fecha o drawer ANTES de mostrar o diálogo
              adminService.promptAdminPassword(context); // Chama a função do serviço
            },
            denseOverride: true, // Força compacto
            contentPaddingOverride: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0), // Força compacto
          ),

          // --- ITEM DE LOGOUT (SÓ SE LOGADO) ---
          if (AdminService.isAdmin)
             _buildDrawerItem(
               context,
               Icons.logout,
               'Sair do Modo Admin',
               () {
                 AdminService.logoutAdmin();
                 Navigator.of(context).pop(); // Fecha o drawer
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('Modo Admin desativado.')),
                 );
                 // Opcional: Navegar para a tela inicial para "resetar" visualmente
                 // Navigator.of(context).pushReplacement(
                 //    MaterialPageRoute(builder: (ctx) => const SplashScreen()),
                 // );
               },
               denseOverride: true,
               contentPaddingOverride: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
             ),
          // --- FIM DO ITEM DE LOGOUT ---
        ],
      ),
    );
  }

  // Função auxiliar para construir os itens do Drawer
  Widget _buildDrawerItem(
        BuildContext context, IconData icon, String title, VoidCallback onTap,
      {bool? denseOverride, EdgeInsets? contentPaddingOverride}) {
    return ListTile(
      dense: denseOverride ?? true,
      contentPadding: contentPaddingOverride ?? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0), // Usa override ou o padrão
      leading: Icon(icon, color: Colors.white70, size: 24),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
        ),
      ),
      onTap: onTap,
    );
  }
}