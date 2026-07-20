import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../viewmodels/mini_bolao_home_viewmodel.dart';
import '../../widgets/ui/bolao_rules_modal.dart';
import '../../widgets/mini_bolao/mini_bolao_modals.dart';
import '../../widgets/mini_bolao/mini_bolao_card.dart';


class MiniBolaoHomeScreen extends StatefulWidget {
  const MiniBolaoHomeScreen({super.key});

  @override
  State<MiniBolaoHomeScreen> createState() => _MiniBolaoHomeScreenState();
}

class _MiniBolaoHomeScreenState extends State<MiniBolaoHomeScreen> {
  final MiniBolaoHomeViewModel _viewModel = MiniBolaoHomeViewModel();
  String _userId = '';
  Stream<Map<String, dynamic>?>? _userStream;


  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Rastreia acesso ao Hub do Mini Bolão
    AnalyticsService.logCustomScreenView('Mini_Bolao_Home_Screen');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<FantasyAuthService>(context);
    final newUserId = authService.user?.uid ?? '';
    
    if (_userId != newUserId || _userStream == null) {
      _userId = newUserId;
      _userStream = _viewModel.streamUser(_userId);
    }
  }

  bool _isProfileComplete(Map<String, dynamic>? userData) {
    if (userData == null) return false;
    final name = userData['name']?.toString() ?? '';
    final cpf = userData['cpf']?.toString() ?? '';
    final phone = userData['phone']?.toString() ?? '';
    return name.isNotEmpty && cpf.isNotEmpty && phone.isNotEmpty;
  }

  // ==========================================================
  // COMPONENTES DE UI E MODAIS
  // ==========================================================


  Widget _buildLoginScreen() {
    final auth = Provider.of<FantasyAuthService>(context);
    
    return Scaffold(
      backgroundColor: Colors.white, 
      appBar: AppBar(
        title: const Text("Mini Bolão FJF", style: TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.brazilGradient)),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.amber),
            tooltip: "Regras do Mini Bolão",
            onPressed: () => BolaoRulesModal.show(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(FontAwesomeIcons.rocket, size: 80, color: Colors.amber), 
              const SizedBox(height: 24),
              const Text("Identificação Necessária", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text("Para dar os seus palpites e concorrer aos prêmios acumulados em dinheiro, faça login com sua conta do Google.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.4, fontSize: 14)),
              const SizedBox(height: 40),
              auth.isLoading 
                ? const CircularProgressIndicator(color: AppTheme.primaryColor)
                : ElevatedButton.icon(
                    onPressed: () async {
                      final error = await auth.signInWithGoogle();
                      if (error != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                      }
                    },
                    icon: const FaIcon(FontAwesomeIcons.google, color: Colors.white),
                    label: const Text("ENTRAR COM O GOOGLE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], minimumSize: const Size(double.infinity, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserHeader(Map<String, dynamic>? userData) {
    if (userData == null && _userId.isEmpty) return const SizedBox.shrink();

    final bool isProfileIncomplete = !_isProfileComplete(userData);
    final String name = userData?['name'] ?? 'Treinador';
    final String? photoUrl = userData?['photo_url'];

    return GestureDetector(
      onTap: () => MiniBolaoModals.showEditProfileModal(context, userData, _userId, _viewModel),
      child: Container(
        margin: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.amber, width: 2.5)),
              child: CircleAvatar(
                radius: 28, backgroundColor: Colors.white,
                backgroundImage: photoUrl != null && photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl == null || photoUrl.isEmpty ? const Icon(Icons.person, color: Color(0xFF1B5E20), size: 30) : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("TREINADOR FJF", style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text(
                    name.isEmpty ? 'Defina seu Nome' : name,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: isProfileIncomplete ? Colors.orangeAccent.withOpacity(0.2) : Colors.greenAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isProfileIncomplete ? Colors.orangeAccent : Colors.greenAccent)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isProfileIncomplete ? Icons.warning_amber_rounded : Icons.check_circle, size: 12, color: isProfileIncomplete ? Colors.orangeAccent : Colors.greenAccent),
                        const SizedBox(width: 4),
                        Text(isProfileIncomplete ? "Completar Cadastro" : "Cadastro Completo", style: TextStyle(color: isProfileIncomplete ? Colors.orangeAccent : Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white70, size: 22),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  tooltip: "Editar Perfil",
                  onPressed: () => MiniBolaoModals.showEditProfileModal(context, userData, _userId, _viewModel),
                ),
                const SizedBox(height: 12),
                const Icon(Icons.workspace_premium, color: Colors.amber, size: 28),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_userId.isEmpty) {
      return _buildLoginScreen();
    }

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _userStream,
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(appBar: AppBar(backgroundColor: const Color(0xFF1B5E20)), body: const Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20))));
        }
        
        final currentUserData = userSnapshot.data;
        final bool profileComplete = _isProfileComplete(currentUserData);

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text("Mini Bolão FJF", style: TextStyle(fontWeight: FontWeight.bold)),
            flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.brazilGradient)),
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline, color: Colors.amber),
                tooltip: "Regras do Mini Bolão",
                onPressed: () => BolaoRulesModal.show(context),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              _buildUserHeader(currentUserData),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _viewModel.streamMiniLeagues(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20)));
                    
                    final allLeagues = snapshot.data?.docs ?? [];
                    
                    final leagues = allLeagues.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final String status = data['status'] ?? '';
                      final bool isActive = data['is_active'] ?? data['isActive'] ?? true;
                      
                      if (status == 'finished') return true;
                      return isActive == true && status != 'inactive';
                    }).toList();

                    leagues.sort((a, b) {
                      final aStat = (a.data() as Map<String, dynamic>)['status'];
                      final bStat = (b.data() as Map<String, dynamic>)['status'];
                      if (aStat == 'finished' && bStat != 'finished') return 1;
                      if (aStat != 'finished' && bStat == 'finished') return -1;
                      return 0; 
                    });

                    if (leagues.isEmpty) return const Center(child: Text("Nenhuma sala aberta no momento.", style: TextStyle(color: Colors.grey)));

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: leagues.length,
                      itemBuilder: (context, index) {
                        final doc = leagues[index];
                        final data = doc.data() as Map<String, dynamic>;
                        
                        return MiniBolaoCard(
                          userId: _userId,
                          leagueId: doc.id,
                          leagueData: data,
                          currentUserData: currentUserData,
                          profileComplete: profileComplete,
                          onGeneratePix: (id, title, fee, data) => MiniBolaoModals.generatePixForMiniBolao(context, id, title, fee, data, _userId),
                          onProfileRequired: (data) => MiniBolaoModals.showProfileRequiredDialog(context, data, _userId, _viewModel),
                          onPredict: (ctx, id, lData, pData) => MiniBolaoModals.showMiniBolaoPredictionModal(ctx, id, lData, pData),
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
    );
  }
}


