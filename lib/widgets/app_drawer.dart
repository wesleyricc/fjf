import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/championship_service.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  
  Future<void> _showLoginDialog(BuildContext originalContext) async {
    final authService = Provider.of<AuthService>(originalContext, listen: false);
    final userController = TextEditingController();
    final passController = TextEditingController();
    
    // Não usamos StatefulBuilder aqui para simplificar o contexto, 
    // pois o loading será controlado por um ValueNotifier local ou setState do pai se necessário.
    // Mas para manter o padrão visual, vamos ajustar a lógica de fechamento.
    
    await showDialog(
      context: originalContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool isLocalLoading = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Acesso Administrativo'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: userController,
                    decoration: const InputDecoration(labelText: 'Usuário'),
                    enabled: !isLocalLoading,
                  ),
                  TextField(
                    controller: passController,
                    decoration: const InputDecoration(labelText: 'Senha'),
                    obscureText: true,
                    enabled: !isLocalLoading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLocalLoading ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isLocalLoading
                      ? null
                      : () async {
                          setDialogState(() => isLocalLoading = true);
                          
                          // 1. Tenta Logar
                          final error = await authService.login(
                            userController.text.trim(),
                            passController.text,
                          );

                          setDialogState(() => isLocalLoading = false);

                          if (error == null) {
                            // SUCESSO
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(); // Fecha o Diálogo
                            }
                            
                            // Pequeno delay para garantir que o diálogo fechou visualmente
                            await Future.delayed(const Duration(milliseconds: 200));

                            if (originalContext.mounted) {
                              Navigator.of(originalContext).pop(); // Fecha o Drawer
                              Navigator.of(originalContext).pushNamed('/admin-menu'); // Vai pro Menu
                            }
                          } else {
                            // ERRO
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text(error), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                  child: isLocalLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Entrar'),
                ),
              ],
            );
          },
        );
      },
    );
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
                      child: Text(honoree.isNotEmpty ? honoree : 'Taça 2025', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),

              _buildDrawerItem(context, Icons.home, 'Início', '/'),
              const Divider(color: Colors.black12, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.calendar_today, 'Tabela de Jogos', '/fixtures'),
              const Divider(color: Colors.black12, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.leaderboard, 'Classificação', '/standings'),
              const Divider(color: Colors.black12, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.group, 'Equipes', '/teams'),
              const Divider(color: Colors.black12, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.query_stats, 'Estatísticas das Equipes', '/team-stats'),
              const Divider(color: Colors.black12, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.person_search, 'Estatísticas dos Jogadores', '/player-stats'),
              const Divider(color: Colors.black12, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.history_toggle_off, 'Histórico de Suspensões', '/suspension-history'),
              const Divider(color: Colors.black12, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.compare_arrows, 'Comparador de Jogadores', '/player-comparison'),
              const Divider(color: Colors.black12, indent: 16, endIndent: 16),
              _buildDrawerItem(context, Icons.bug_report_outlined, 'Reportar Erro', '/report-bug'),
              const Divider(color: Colors.black12, indent: 16, endIndent: 16),

              ListTile(
                leading: Icon(authService.isAuthenticated ? Icons.admin_panel_settings : Icons.lock_outline, color: authService.isAuthenticated ? Colors.green : Colors.grey),
                title: Text(authService.isAuthenticated ? 'Menu Administrador' : 'Acesso Admin', style: TextStyle(color: authService.isAuthenticated ? Colors.green[700] : Colors.grey[700], fontWeight: FontWeight.bold)),
                subtitle: authService.isAuthenticated ? Text('Logado como: ${authService.adminUsername}') : null,
                onTap: () {
                  if (authService.isAuthenticated) {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushNamed('/admin-menu');
                  } else {
                    _showLoginDialog(context);
                  }
                },
              ),

              if (authService.isAuthenticated)
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Sair', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    await authService.logout();
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logout realizado com sucesso.')));
                  },
                ),

              const SizedBox(height: 20),
              Center(child: Text('Versão 2.0.1 (PWA)\n© FJF 2025', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[400], fontSize: 10))),
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
        Navigator.of(context).pop();
        Navigator.of(context).pushReplacementNamed(route);
      },
    );
  }
}