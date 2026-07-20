import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../viewmodels/fantasy_league_viewmodel.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../models/fantasy_league_model.dart';
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
    String selectedType = 'classic';
    int maxTeams = 8;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Criar Nova Liga"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: "Nome da Liga", hintText: "Ex: Amigos do Futsal"),
                  maxLength: 20,
                ),
                const SizedBox(height: 16),
                const Text("Tipo de Liga:", style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  isExpanded: true,
                  value: selectedType,
                  items: const [
                    DropdownMenuItem(value: 'classic', child: Text("Clássica (Pontos Corridos)")),
                    DropdownMenuItem(value: 'knockout', child: Text("Mata-Mata (Eliminatória)")),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => selectedType = val);
                  },
                ),
                if (selectedType == 'knockout') ...[
                  const SizedBox(height: 16),
                  const Text("Tamanho do Mata-Mata:", style: TextStyle(fontWeight: FontWeight.bold)),
                  DropdownButton<int>(
                    isExpanded: true,
                    value: maxTeams,
                    items: const [
                      DropdownMenuItem(value: 4, child: Text("4 Times (Semifinal)")),
                      DropdownMenuItem(value: 8, child: Text("8 Times (Quartas)")),
                      DropdownMenuItem(value: 16, child: Text("16 Times (Oitavas)")),
                      DropdownMenuItem(value: 32, child: Text("32 Times")),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => maxTeams = val);
                    },
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) return;
                  final success = await vm.createLeague(
                    nameController.text, 
                    type: selectedType, 
                    maxTeams: selectedType == 'knockout' ? maxTeams : null
                  );
                  if (mounted && success) {
                    Navigator.pop(ctx);
                    
                    AnalyticsService.logCustomScreenView('Fantasy_League_Created', parameters: {'league_name': nameController.text, 'type': selectedType});
                    
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Liga criada com sucesso!")));
                  }
                },
                child: const Text("Criar"),
              ),
            ],
          );
        }
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
    return Scaffold(
      appBar: AppBar(title: const Text("Ligas do Fantasy")),
      body: Consumer<FantasyLeagueViewModel>(
        builder: (context, vm, child) {
          if (vm.isLoading) return const Center(child: CircularProgressIndicator());

          final currentUserId = Provider.of<FantasyAuthService>(context, listen: false).user?.uid;

          return CustomScrollView(
            slivers: [
              if (vm.sponsoredLeagues.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text("Ligas Patrocinadas (Oficiais)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _buildSponsoredLeagueCard(context, vm, vm.sponsoredLeagues[i], currentUserId),
                      childCount: vm.sponsoredLeagues.length,
                    ),
                  ),
                ),
              ],

              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text("Minhas Ligas Privadas", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),

              if (vm.myLeagues.isEmpty)
                SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.group_add, size: 80, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          const Text("Ainda não participas em nenhuma liga privada.", style: TextStyle(color: Colors.grey, fontSize: 16), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _buildPrivateLeagueCard(context, vm.myLeagues[i]),
                      childCount: vm.myLeagues.length,
                    ),
                  ),
                ),
                
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
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

  Widget _buildSponsoredLeagueCard(BuildContext context, FantasyLeagueViewModel vm, FantasyLeague league, String? currentUserId) {
    final isMember = currentUserId != null && league.members.contains(currentUserId);
    
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.amber, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          if (isMember) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => FantasyLeagueRankingScreen(league: league)));
          } else {
            // Confirmar entrada na liga patrocinada
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(league.name),
                content: const Text("Deseja participar desta liga patrocinada gratuitamente e concorrer aos prêmios?"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                    onPressed: () => Navigator.pop(ctx, true), 
                    child: const Text("Participar")
                  ),
                ],
              )
            );
            
            if (confirm == true) {
              final success = await vm.joinSponsoredLeague(league.id);
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bem-vindo à liga patrocinada!")));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.errorMessage ?? "Erro"), backgroundColor: Colors.red));
                  vm.clearError();
                }
              }
            }
          }
        },
        child: Column(
          children: [
            if (league.sponsorImageUrl != null && league.sponsorImageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                child: Image.network(
                  league.sponsorImageUrl!,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => Container(
                    height: 120, color: Colors.grey[300], 
                    child: const Icon(Icons.broken_image, size: 50, color: Colors.grey)
                  ),
                ),
              ),
            ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Row(
                children: [
                  Expanded(child: Text(league.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                  if (isMember)
                    const Icon(Icons.check_circle, color: Colors.green)
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  if (league.prizeDescription != null && league.prizeDescription!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.amber[100], borderRadius: BorderRadius.circular(4)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.redeem, size: 14, color: Colors.amber),
                          const SizedBox(width: 4),
                          Flexible(child: Text(league.prizeDescription!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text("${league.members.length} participantes", style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              trailing: isMember 
                ? const Icon(Icons.arrow_forward_ios)
                : const ElevatedButton(onPressed: null, child: Text("Entrar")),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivateLeagueCard(BuildContext context, FantasyLeague league) {
    final primaryColor = Theme.of(context).primaryColor;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: league.type == 'knockout' ? Colors.red : primaryColor, 
          child: Icon(league.type == 'knockout' ? Icons.sports_kabaddi : Icons.emoji_events, color: Colors.white)
        ),
        title: Row(
          children: [
            Expanded(child: Text(league.name, style: const TextStyle(fontWeight: FontWeight.bold))),
            if (league.type == 'knockout')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(4)),
                child: const Text("MATA-MATA", style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold)),
              )
          ],
        ),
        subtitle: Text(league.type == 'knockout' 
          ? "${league.members.length}/${league.maxTeams} participantes - ${league.status == 'waiting' ? 'Aguardando' : 'Em Andamento'}"
          : "${league.members.length} participantes"),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          if (league.type == 'knockout') {
            Navigator.pushNamed(context, '/fantasy-knockout', arguments: league);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FantasyLeagueRankingScreen(league: league),
              ),
            );
          }
        },
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: league.inviteCode));
          
          // 🚨 Analytics: Rastreia a viralidade (O usuário está convidando amigos para a liga)
          AnalyticsService.logShare('league_invite_code', league.id);
          
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Código ${league.inviteCode} copiado!")));
        },
      ),
    );
  }
}