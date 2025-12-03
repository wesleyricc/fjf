import 'package:flutter/material.dart';
import 'dart:html' as html; // Para PWA
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart'; 

// Services & Models
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../models/team_model.dart'; // <-- Importante: Model Team

// Widgets
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/home_live_video_card.dart';
import '../widgets/home_news_feed.dart';
import '../widgets/home_footer.dart';
import 'team_detail_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  static const routeName = '/splash';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Estado para controlar a visibilidade do player
  bool _isDrawerOpen = false; 
  
  // PWA
  html.Event? _installPromptEvent;
  bool _showInstallButton = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      html.window.addEventListener('beforeinstallprompt', (html.Event e) {
        e.preventDefault();
        if (mounted) setState(() { _installPromptEvent = e; _showInstallButton = true; });
      });
    }
  }

  void _triggerInstallPrompt() {
    if (_installPromptEvent == null) return;
    (_installPromptEvent as dynamic).prompt();
    setState(() { _installPromptEvent = null; _showInstallButton = false; });
  }

  Future<void> _showSeasonSelectionDialog(BuildContext context) async {
    final championshipService = Provider.of<ChampionshipService>(context, listen: false);
    final currentId = championshipService.currentSeasonId;
    
    final List<Map<String, dynamic>> allSeasons = [
      {'id': FirestoreService.LEGACY_ID, 'name': 'FJF 2025 (Original)', 'isActive': false},
      ...championshipService.availableSeasons
    ];

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Histórico de Temporadas'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: allSeasons.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, index) {
              final season = allSeasons[index];
              final bool isSelected = season['id'] == currentId;
              return ListTile(
                selected: isSelected,
                leading: Icon(isSelected ? Icons.check_circle : Icons.history, color: isSelected ? Colors.green : Colors.grey),
                title: Text(season['name']),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (!isSelected) await championshipService.setSeason(season['id']);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        backgroundColor: _isDrawerOpen ? Theme.of(context).primaryColor : Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Trocar Temporada',
            onPressed: () => _showSeasonSelectionDialog(context),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: (isOpen) {
        setState(() {
          _isDrawerOpen = isOpen;
        });
      },
      
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildModernHeader(),
                  
                  // Botão de Instalação (PWA)
                  if (_showInstallButton)
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade200)),
                      child: Row(
                        children: [
                          const Icon(Icons.download_for_offline, color: Colors.green, size: 30),
                          const SizedBox(width: 12),
                          const Expanded(child: Text("Instale o app para uma melhor experiência.", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                          ElevatedButton(onPressed: _triggerInstallPrompt, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), child: const Text("Instalar")),
                        ],
                      ),
                    ),

                  // Passamos o estado do Drawer para o Player
                  HomeLiveVideoCard(hidePlayer: _isDrawerOpen),
                  
                  const SizedBox(height: 10),
                  const HomeNewsFeed(),
                  
                  const SizedBox(height: 20),
                  _buildSectionTitle(context, "Equipes Participantes"),
                  _buildTeamsGrid(),
                  
                  const SizedBox(height: 40),
                  const HomeFooter(), 
                ],
              ),
            ),
          ),
          const SponsorBannerRotator(),
        ],
      ),
    );
  }

  Widget _buildModernHeader() {
    final championshipService = Provider.of<ChampionshipService>(context);
    final int year = championshipService.currentSeasonYear;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withOpacity(0.8),
            Colors.black87,
          ],
        ),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Image.asset('assets/logo3_fjf.png', height: 110, errorBuilder: (_,__,___) => const Icon(Icons.sports_soccer, size: 100, color: Colors.white)),
              const SizedBox(height: 16),
              Text(
                'FJF $year',
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2.0),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                child: const Text('O Maior Campeonato da Região', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Container(width: 4, height: 24, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTeamsGrid() {
    final seasonId = Provider.of<ChampionshipService>(context).currentSeasonId;
    final firestoreService = FirestoreService();

    // Consome o Stream de List<Team>
    return StreamBuilder<List<Team>>(
      stream: firestoreService.streamTeams(seasonId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
        
        final teams = snapshot.data ?? [];
        if (teams.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("Nenhuma equipe cadastrada.")));

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, // 2 Colunas para 8 times (4 linhas)
            childAspectRatio: 1.3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: teams.length,
          itemBuilder: (context, index) {
            final team = teams[index];
            
            return InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team))),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 5, spreadRadius: 1)],
                    ),
                    child: SizedBox(
                      height: 60, width: 60,
                      child: CachedNetworkImage(
                        imageUrl: team.shieldUrl,
                        fit: BoxFit.contain,
                        placeholder: (_,__) => const Icon(Icons.shield, color: Colors.grey),
                        errorWidget: (_,__,___) => const Icon(Icons.shield, color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    team.name, // Nome completo
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}