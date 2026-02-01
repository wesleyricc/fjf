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
import '../models/team_model.dart'; 

// Widgets
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/home_live_video_card.dart';
import '../widgets/home_news_feed.dart';
import '../widgets/home_footer.dart';
import '../widgets/photo_store_banner.dart';
import 'team_detail_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  static const routeName = '/splash';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isDrawerOpen = false; 
  html.Event? _installPromptEvent;
  bool _showInstallButton = false;
  bool _hasError = false; 
  String _debugStatus = "Iniciando...";

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      html.window.addEventListener('beforeinstallprompt', (html.Event e) {
        e.preventDefault();
        if (mounted) setState(() { _installPromptEvent = e; _showInstallButton = true; });
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  Future<void> _initializeData() async {
    final service = Provider.of<ChampionshipService>(context, listen: false);
    
    if (service.currentSeasonId.isEmpty) {
      setState(() => _debugStatus = "Buscando temporadas no Firebase...");
      
      try {
        await service.init();
        
        if (mounted) {
          if (service.availableSeasons.isNotEmpty) {
            setState(() => _debugStatus = "Sucesso! ${service.availableSeasons.length} encontradas.");
            // O build vai redesenhar e entrar no app automaticamente
          } else {
            setState(() => _debugStatus = "Conectado, mas NENHUMA temporada encontrada na coleção 'championships'.");
            setState(() => _hasError = true);
          }
        }
      } catch (e) {
        if (mounted) {
           setState(() => _debugStatus = "Erro Crítico: $e");
           setState(() => _hasError = true);
        }
      }
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
    
    final List<Map<String, dynamic>> allSeasons = championshipService.availableSeasons;

    if (allSeasons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma temporada disponível.')));
      return;
    }

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
    final championshipService = Provider.of<ChampionshipService>(context);
    final seasonId = championshipService.currentSeasonId;

    // TELA DE CARREGAMENTO COM DIAGNÓSTICO
    if (seasonId.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white, // Fundo branco para ler bem
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_hasError) 
                  const Icon(Icons.error_outline, size: 60, color: Colors.red)
                else 
                  const CircularProgressIndicator(color: Colors.green),
                
                const SizedBox(height: 20),
                
                // --- AQUI ESTÁ O SEGREDO: MOSTRAR O STATUS NA TELA ---
                Text(
                  _debugStatus,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _hasError ? Colors.red : Colors.grey[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 14
                  ),
                ),
                
                const SizedBox(height: 20),
                
                if (_hasError)
                  ElevatedButton(
                    onPressed: () {
                      setState(() { 
                        _hasError = false; 
                        _debugStatus = "Tentando novamente..."; 
                      });
                      _initializeData();
                    },
                    child: const Text("Tentar Novamente"),
                  )
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        backgroundColor: _isDrawerOpen ? Theme.of(context).primaryColor : Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (seasonId.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Trocar Temporada',
              onPressed: () => _showSeasonSelectionDialog(context),
            ),
        ],
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: (isOpen) => setState(() => _isDrawerOpen = isOpen),
      
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildModernHeader(),
                  
                  // Botão de Instalação PWA
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

                  // --- ÁREA DE CONTEÚDO (PROTEGIDA) ---
                  // Se existir temporada, mostra os widgets de dados.
                  // Se não existir (seasonId vazio), mostra mensagem de boas-vindas.
                  if (seasonId.isNotEmpty) ...[
                    HomeLiveVideoCard(hidePlayer: _isDrawerOpen),
                    const SizedBox(height: 10),
                    const HomeNewsFeed(),
                    
                    const SizedBox(height: 20),
                    _buildSectionTitle(context, "Loja de Fotos"),
                    const PhotoStoreBanner(),
                    const SizedBox(height: 20),
                    
                    _buildSectionTitle(context, "Equipes"),
                    _buildTeamsGrid(),
                  ] else ...[
                    // --- ESTADO VAZIO (BOAS VINDAS) ---
                    Padding(
                      padding: const EdgeInsets.all(30.0),
                      child: Column(
                        children: [
                          const Icon(Icons.sports_soccer, size: 80, color: Colors.grey),
                          const SizedBox(height: 20),
                          const Text(
                            "Bem-vindo ao App FJF!",
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "Nenhuma temporada ativa encontrada.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            "Acesse o Menu Lateral > Admin para criar a primeira temporada.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )
                  ],

                  const SizedBox(height: 40),
                  const HomeFooter(), 
                ],
              ),
            ),
          ),
          
          // Só mostra o banner de patrocinadores se houver temporada
          if (seasonId.isNotEmpty)
            const SponsorBannerRotator(),
        ],
      ),
    );
  }

  Widget _buildModernHeader() {
    final championshipService = Provider.of<ChampionshipService>(context);
    final int year = championshipService.currentSeasonYear;
    final String honoree = championshipService.currentSeasonHonoree;
    
    // Se não tiver temporada, usa valores genéricos
    final displayYear = (year > 0) ? year.toString() : "";
    final displayHonoree = honoree.isNotEmpty ? honoree : 'Bem-vindo';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Theme.of(context).primaryColor, Theme.of(context).primaryColor.withOpacity(0.8), Colors.black87],
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
              // Só mostra o ano se ele existir
              Text('FJF $displayYear', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2.0)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  displayHonoree,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
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
    if (seasonId.isEmpty) return const SizedBox();
    final firestoreService = FirestoreService();

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
            crossAxisCount: 2,
            childAspectRatio: 1.1,
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
                      height: 130, width: 130,
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
                    team.name,
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