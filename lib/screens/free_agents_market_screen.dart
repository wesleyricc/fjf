import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/free_agent_model.dart';
import '../widgets/ui/custom_empty_state.dart';
import '../services/auth_service.dart';

class FreeAgentsMarketScreen extends StatefulWidget {
  const FreeAgentsMarketScreen({super.key});

  @override
  State<FreeAgentsMarketScreen> createState() => _FreeAgentsMarketScreenState();
}

class _FreeAgentsMarketScreenState extends State<FreeAgentsMarketScreen> {
  String _selectedPositionFilter = 'Todos';

  Future<void> _openWhatsApp(String phone, String name) async {
    final message = "Olá $name! Vi seu perfil no Mercado de Atletas da FJF e tenho interesse em conversar sobre a nossa equipe.";
    final encodedMessage = Uri.encodeComponent(message);
    final url = Uri.parse('https://wa.me/$phone?text=$encodedMessage');
    
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')));
    }
  }

  void _showPlayerDetails(BuildContext context, FreeAgent agent) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 16),
            
            ListTile(
              leading: CircleAvatar(
                radius: 30,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: agent.photoUrl.isNotEmpty ? CachedNetworkImageProvider(agent.photoUrl) : null,
                child: agent.photoUrl.isEmpty ? const Icon(Icons.person, size: 30, color: Colors.grey) : null,
              ),
              title: Text(agent.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              subtitle: Text("${agent.position} • ${agent.age} anos", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
            ),
            const Divider(),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.withOpacity(0.5))),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Nível do Atleta", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                          Text(agent.selfEvaluation, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatInfo("Altura", "${agent.height.toStringAsFixed(2)}m"),
                  _buildStatInfo("Peso", "${agent.weight.toStringAsFixed(1)}kg"),
                  _buildStatInfo("Pé Preferido", agent.preferredFoot),
                ],
              ),
            ),
            
            const Divider(),

            ListTile(
              leading: const Icon(Icons.gavel, color: Colors.grey),
              title: const Text("Status de Elegibilidade", style: TextStyle(fontSize: 12, color: Colors.grey)),
              subtitle: Text(agent.eligibilityType, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
            ),
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ElevatedButton.icon(
                onPressed: () => _openWhatsApp(agent.phone, agent.name),
                icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white),
                label: const Text("CHAMAR NO WHATSAPP", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600, 
                  minimumSize: const Size(double.infinity, 55), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatInfo(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    if (authService.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!authService.isAuthenticated) {
      return _buildAccessDenied(
        context, 
        "Identificação Necessária", 
        "Para acessar o mercado de atletas, faça login com sua conta do Google.",
        showLoginButton: true
      );
    }

    if (!authService.isPresident && !authService.isAdmin) {
      return _buildAccessDenied(
        context, 
        "Acesso Restrito", 
        "Esta área é exclusiva para Presidentes de Clubes e Diretoria da ACEFJF.",
        showLoginButton: false
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mercado de Atletas"),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (val) => setState(() => _selectedPositionFilter = val),
            itemBuilder: (context) => ['Todos', 'Linha', 'Goleiro', 'Comissão']
                .map((pos) => PopupMenuItem(value: pos, child: Text(pos)))
                .toList(),
          )
        ],
      ),
      body: Column(
        children: [
          if (_selectedPositionFilter != 'Todos')
            Container(
              width: double.infinity,
              color: Colors.blue.shade50,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Filtrando por: $_selectedPositionFilter", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                  InkWell(onTap: () => setState(() => _selectedPositionFilter = 'Todos'), child: const Icon(Icons.close, size: 18, color: Colors.blue)),
                ],
              ),
            ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('free_agents')
                .orderBy('createdAt', descending: true)
                .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const CustomEmptyState(icon: Icons.person_search, title: "Mercado Vazio", message: "Nenhum atleta disponível no momento. Volte mais tarde!");
                }

                final List<FreeAgent> agents = snapshot.data!.docs.map((doc) {
                  return FreeAgent.fromMap(doc.data() as Map<String, dynamic>, doc.id);
                }).where((agent) {
                  if (_selectedPositionFilter == 'Todos') return true;
                  return agent.position == _selectedPositionFilter;
                }).toList();

                if (agents.isEmpty) return const Center(child: Text("Nenhum atleta encontrado para este filtro."));

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: agents.length,
                  itemBuilder: (context, index) {
                    final agent = agents[index];
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Hero(
                          tag: 'avatar_${agent.id}',
                          child: CircleAvatar(
                            radius: 26,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: agent.photoUrl.isNotEmpty ? CachedNetworkImageProvider(agent.photoUrl) : null,
                            child: agent.photoUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
                          ),
                        ),
                        title: Text(agent.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Row(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: agent.isGoalkeeper ? Colors.orange.shade100 : Colors.blue.shade100, borderRadius: BorderRadius.circular(4)),
                              child: Text(agent.position, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: agent.isGoalkeeper ? Colors.orange.shade900 : Colors.blue.shade900)),
                            ),
                            const SizedBox(width: 8),
                            Padding(padding: const EdgeInsets.only(top: 6), child: Text("${agent.age} anos", style: const TextStyle(fontSize: 12, color: Colors.grey))),
                          ],
                        ),
                        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
                        // 🚨 AGORA SIM! O BOTÃO ESTÁ DESCOMENTADO E FUNCIONANDO! 🚨
                        onTap: () => _showPlayerDetails(context, agent), 
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessDenied(BuildContext context, String title, String msg, {bool showLoginButton = false}) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mercado de Atletas")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(showLoginButton ? Icons.lock_person : Icons.gavel, size: 80, color: Colors.orange),
              const SizedBox(height: 24),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              if (showLoginButton) ...[
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  icon: const FaIcon(FontAwesomeIcons.google),
                  label: const Text("ENTRAR COM GMAIL (PRESIDENTE)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50)
                  ),
                  onPressed: () async {
                    final auth = Provider.of<AuthService>(context, listen: false);
                    final String? error = await auth.signInWithGoogle();
                    if (error != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                    }
                  },
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}