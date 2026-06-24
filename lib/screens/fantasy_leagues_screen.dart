import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../viewmodels/fantasy_league_viewmodel.dart';
import '../services/fantasy_auth_service.dart';
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../models/fantasy_league_model.dart';
import 'fantasy_league_ranking_screen.dart';

class FantasyLeaguesScreen extends StatefulWidget {
  const FantasyLeaguesScreen({super.key});

  @override
  State<FantasyLeaguesScreen> createState() => _FantasyLeaguesScreenState();
}

class _FantasyLeaguesScreenState extends State<FantasyLeaguesScreen> {
  @override
  void initState() {
    super.initState();
    
    // 🚨 Analytics: Acesso à tela de gerenciamento de ligas privadas
    AnalyticsService.logCustomScreenView('Fantasy_Leagues_Screen');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = Provider.of<FantasyAuthService>(context, listen: false).user?.uid;
      if (userId != null) {
        Provider.of<FantasyLeagueViewModel>(context, listen: false).init(userId);
      }
    });
  }

  // --- DIÁLOGO PARA CRIAR LIGA ---
  void _showCreateLeagueDialog(FantasyLeagueViewModel vm) {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Criar Nova Liga"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: "Nome da Liga", hintText: "Ex: Amigos do Futsal"),
          maxLength: 20,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              final success = await vm.createLeague(nameController.text);
              if (mounted && success) {
                Navigator.pop(ctx);
                
                // 🚨 Analytics: Sucesso ao criar liga
                AnalyticsService.logCustomScreenView('Fantasy_League_Created', parameters: {'league_name': nameController.text});
                
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Liga criada com sucesso!")));
              }
            },
            child: const Text("Criar"),
          ),
        ],
      ),
    );
  }

  // --- DIÁLOGO PARA ENTRAR EM LIGA ---
  void _showJoinLeagueDialog(FantasyLeagueViewModel vm) {
    final TextEditingController codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Entrar numa Liga"),
        content: TextField(
          controller: codeController,
          decoration: const InputDecoration(labelText: "Código de Convite", hintText: "Ex: FJF-X7B9"),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              if (codeController.text.trim().isEmpty) return;
              
              FocusManager.instance.primaryFocus?.unfocus();
              
              final success = await vm.joinLeague(codeController.text);
              if (mounted) {
                if (success) {
                  Navigator.pop(ctx);
                  
                  // 🚨 Analytics: Sucesso ao entrar via código
                  AnalyticsService.logCustomScreenView('Fantasy_League_Joined', parameters: {'invite_code': codeController.text});

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Agora fazes parte da liga!"))
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(vm.errorMessage ?? "Erro"), 
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.fixed, 
                    )
                  );
                  vm.clearError();
                }
              }
            },
            child: const Text("Entrar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(title: const Text("Minhas Ligas Privadas")),
      body: Consumer<FantasyLeagueViewModel>(
        builder: (context, vm, child) {
          if (vm.isLoading) return const Center(child: CircularProgressIndicator());

          if (vm.myLeagues.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_add, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text("Ainda não participas em nenhuma liga.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: vm.myLeagues.length,
            itemBuilder: (ctx, i) {
              final league = vm.myLeagues[i];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(backgroundColor: primaryColor, child: const Icon(Icons.emoji_events, color: Colors.white)),
                  title: Text(league.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${league.members.length} participantes"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FantasyLeagueRankingScreen(league: league),
                      ),
                    );
                  },
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: league.inviteCode));
                    
                    // 🚨 Analytics: Rastreia a viralidade (O usuário está convidando amigos para a liga)
                    AnalyticsService.logShare('league_invite_code', league.id);
                    
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Código ${league.inviteCode} copiado!")));
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: Consumer<FantasyLeagueViewModel>(
        builder: (context, vm, child) => Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: "join",
              onPressed: () => _showJoinLeagueDialog(vm),
              label: const Text("Entrar"),
              icon: const Icon(Icons.vpn_key),
              backgroundColor: Colors.orange,
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: "create",
              onPressed: () => _showCreateLeagueDialog(vm),
              label: const Text("Criar Liga"),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}