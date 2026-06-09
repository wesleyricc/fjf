import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:html' as html; 
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; 
import 'package:url_launcher/url_launcher.dart'; 

import '../theme/app_theme.dart';
import '../services/championship_service.dart';
import '../services/fantasy_service.dart'; 
import '../services/voting_service.dart'; 
import '../models/poll_model.dart'; 

import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart'; 
import '../widgets/home_live_video_card.dart';
import '../widgets/home_news_feed.dart';
import '../widgets/home_footer.dart';
import '../widgets/photo_store_banner.dart';
import '../widgets/ui/shimmer_effect.dart';     
import '../widgets/ui/custom_empty_state.dart';  
import 'team_detail_screen.dart';
import '../services/fantasy_auth_service.dart';
import '../viewmodels/sponsor_viewmodel.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  static const routeName = '/splash';
  static const String appVersion = '2.0.0';
  static bool hasShownOpenAd = false;

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
      _checkAndShowStartupAds(); 
    });
  }

  Future<void> _checkAndShowStartupAds() async {
    if (SplashScreen.hasShownOpenAd) return;
    
    SplashScreen.hasShownOpenAd = true;
    
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) _showAdDialog();
  }

  void _showAdDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent, 
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
             Container(
               width: double.maxFinite,
               margin: const EdgeInsets.only(top: 20, right: 10), 
               decoration: BoxDecoration(
                 borderRadius: BorderRadius.circular(16),
                 boxShadow: [
                   BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))
                 ]
               ),
               child: ClipRRect(
                 borderRadius: BorderRadius.circular(16),
                 child: const SponsorBannerRotator(
                   location: 'app_open', 
                   height: 650, 
                   isStatic: false, 
                 ),
               ),
             ),
             Positioned(
               top: 0, right: 0,
               child: Material(
                 color: Colors.transparent,
                 child: InkWell(
                   onTap: () => Navigator.pop(ctx),
                   borderRadius: BorderRadius.circular(30),
                   child: Container(
                     padding: const EdgeInsets.all(8),
                     decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                     child: const Icon(Icons.close, size: 24, color: Colors.black87),
                   ),
                 ),
               ),
             ),
          ],
        ),
      ),
    );
  }

  Future<void> _initializeData() async {
    final service = Provider.of<ChampionshipService>(context, listen: false);
    if (service.currentSeasonId.isNotEmpty) return;

    setState(() => _debugStatus = "Buscando temporadas...");
    try {
      await service.init();
      if (mounted) {
        if (service.availableSeasons.isNotEmpty) {
          setState(() => _debugStatus = "Sucesso!");
        } else {
          setState(() { _debugStatus = "Conectado, mas NENHUMA temporada encontrada."; _hasError = true; });
        }
      }
    } catch (e) {
      if (mounted) setState(() { _debugStatus = "Erro Crítico: $e"; _hasError = true; });
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
            itemBuilder: (context, index) {
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

  Widget _buildVotingBanner(BuildContext context, Poll poll, String seasonId) {
    final user = Provider.of<FantasyAuthService>(context, listen: false).user;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, '/voting', arguments: poll).then((_) => setState(() {})),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade900, Colors.deepPurpleAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFC5A814), width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.purple.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))
              ],
            ),
            child: FutureBuilder<bool>(
              future: user != null ? VotingService().hasUserVoted(seasonId, poll.id, user.uid) : Future.value(false),
              builder: (context, snapshot) {
                final hasVoted = snapshot.data ?? false;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.how_to_vote, color: Colors.amber, size: 28),
                  ),
                  title: const Text(
                    "VOTAÇÃO ABERTA!", 
                    style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)
                  ),
                  subtitle: Text(
                    poll.title, 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  trailing: hasVoted
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.green.shade500, borderRadius: BorderRadius.circular(20)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text("VOTADO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                            ],
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(20)),
                          child: Text("VOTAR", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.purple.shade900)),
                        ),
                );
              }
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemedSectionHeader(BuildContext context, String title, IconData icon) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 16, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFC5A814), Color(0xFF00873E)], 
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final championshipService = Provider.of<ChampionshipService>(context);
    final seasonId = championshipService.currentSeasonId;

    if (seasonId.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_hasError) 
                  const Icon(Icons.error_outline, size: 60, color: Colors.red)
                else 
                  const SizedBox(height: 50, width: 50, child: CircularProgressIndicator(color: Color(0xFFC25F22), strokeWidth: 3)),
                const SizedBox(height: 24),
                Text(_debugStatus, textAlign: TextAlign.center, style: TextStyle(color: _hasError ? Colors.red : Colors.grey[600], fontWeight: FontWeight.w500, fontSize: 15)),
                if (_hasError) ...[
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() { _hasError = false; _debugStatus = "Tentando novamente..."; });
                      _initializeData();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text("Tentar Novamente"),
                  )
                ]
              ],
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    final int displayYear = championshipService.currentSeasonYear;

    return Scaffold(
      drawer: const AppDrawer(),
      onDrawerChanged: (isOpen) => setState(() => _isDrawerOpen = isOpen),
      body: Stack(
        children: [
          // Fundo levemente texturizado global
          Container(color: const Color(0xFFF0F2F5)),
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 280.0, 
                floating: false,
                pinned: true,
                backgroundColor: primaryColor,
                elevation: 0,
                stretch: true,
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12.0, top: 8.0, bottom: 8.0),
                    child: TextButton.icon(
                      onPressed: () => _showSeasonSelectionDialog(context),
                      icon: const Icon(Icons.calendar_month, size: 16, color: Colors.white),
                      label: Text(
                        "Temporada $displayYear",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.15),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: Colors.white30, width: 1), // Corrigido (apesar de já estar certo no original)
                        ),
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground, StretchMode.blurBackground],
                  centerTitle: true,
                  title: LayoutBuilder(
                    builder: (context, constraints) {
                      final isCollapsed = constraints.maxHeight <= kToolbarHeight + 30;
                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: isCollapsed ? 1.0 : 0.0,
                        child: Text("FJF $displayYear", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Fundo Verde e Amarelo
                      Container(decoration: const BoxDecoration(gradient: AppTheme.brazilGradient)),
                      
                      SafeArea(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                             Hero(
                               tag: 'app_logo',
                               child: Container(
                                 decoration: const BoxDecoration(
                                   shape: BoxShape.circle, 
                                   boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 15, offset: Offset(0, 5))]
                                 ),
                                 child: const CircleAvatar(
                                   radius: 45,
                                   backgroundColor: Colors.white,
                                   backgroundImage: AssetImage('assets/logo3_fjf.png'),
                                 ),
                               ),
                             ),
                             const SizedBox(height: 12),
                             Text(
                               "FJF $displayYear", 
                               style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.5, shadows: [Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))])
                             ),
                             const SizedBox(height: 12),
                             
                             // Ribbon "Homenageado"
                             Container(
                               padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
                               decoration: BoxDecoration(
                                 color: Colors.white.withOpacity(0.95),
                                 borderRadius: BorderRadius.circular(4),
                                 border: Border.all(color: const Color(0xFFC5A814), width: 1.5),
                                 boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]
                               ),
                               child: Text(
                                 championshipService.currentSeasonHonoree.isNotEmpty ? championshipService.currentSeasonHonoree : "Homenageado $displayYear", 
                                 style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5)
                               ),
                             ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_showInstallButton)
                        Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.green.shade50, Colors.white]), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withOpacity(0.3)), boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))]),
                          child: Row(
                            children: [
                              const Icon(Icons.download_rounded, color: Colors.green),
                              const SizedBox(width: 12),
                              const Expanded(child: Text("Instale o app para melhor experiência.", style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 13))),
                              TextButton(onPressed: _triggerInstallPrompt, style: TextButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text("Instalar")),
                            ],
                          ),
                        ),

                      const SizedBox(height: 10),
                      
                      if (seasonId.isNotEmpty)
                        StreamBuilder<List<Poll>>(
                          stream: VotingService().streamActivePolls(seasonId),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
                            final activePolls = snapshot.data!;
                            if (activePolls.length == 1) return _buildVotingBanner(context, activePolls.first, seasonId);
                            
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFC5A814), width: 1.5),
                                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, 4))],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(colors: [Color(0xFF002776), Color(0xFF001133)]),
                                      borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.emoji_events, color: Color(0xFFC5A814), size: 24),
                                        const SizedBox(width: 8),
                                        Text(
                                          "PREMIAÇÕES ABERTAS (${activePolls.length})", 
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 13)
                                        ),
                                      ],
                                    ),
                                  ),
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    itemCount: activePolls.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final poll = activePolls[index];
                                      final user = Provider.of<FantasyAuthService>(context, listen: false).user;

                                      return FutureBuilder<bool>(
                                        future: user != null ? VotingService().hasUserVoted(seasonId, poll.id, user.uid) : Future.value(false),
                                        builder: (context, voteSnapshot) {
                                          final hasVoted = voteSnapshot.data ?? false;
                                          return ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                            leading: CircleAvatar(
                                              radius: 18,
                                              backgroundColor: hasVoted ? Colors.green.withOpacity(0.1) : const Color(0xFFC5A814).withOpacity(0.2),
                                              child: Icon(hasVoted ? Icons.check : Icons.how_to_vote, color: hasVoted ? Colors.green : const Color(0xFFC5A814), size: 18),
                                            ),
                                            title: Text(poll.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: hasVoted ? Colors.grey : Colors.black87)),
                                            subtitle: Text(poll.category.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                                            trailing: hasVoted
                                                ? const Icon(Icons.check_circle, color: Colors.green)
                                                : ElevatedButton(
                                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC5A814), foregroundColor: Colors.black87, elevation: 0),
                                                    onPressed: () => Navigator.pushNamed(context, '/voting', arguments: poll).then((_) => setState(() {})),
                                                    child: const Text("VOTAR", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                                                  ),
                                            onTap: () => Navigator.pushNamed(context, '/voting', arguments: poll).then((_) => setState(() {})),
                                          );
                                        }
                                      );
                                    },
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                      // ------------------------------------------------

                      HomeLiveVideoCard(hidePlayer: _isDrawerOpen),
                      const SizedBox(height: 10),      
                      // Fantasy Card
                      if (championshipService.isFantasyEnabled)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: StreamBuilder<Map<String, dynamic>>(
                            stream: FantasyService().streamMarketStatus(),
                            builder: (context, snapshot) {
                              String statusText = "";
                              Color statusColor = Colors.transparent;
                              IconData statusIcon = Icons.hourglass_empty;
                              bool isDataLoaded = false;

                              if (snapshot.hasData) {
                                isDataLoaded = true;
                                final bool isOpen = snapshot.data!['is_open'] ?? true;
                                if (isOpen) {
                                  statusText = "ABERTO"; statusColor = Colors.greenAccent; statusIcon = Icons.check_circle;
                                } else {
                                  statusText = "FECHADO"; statusColor = Colors.redAccent; statusIcon = Icons.lock;
                                }
                              }

                              return Card(
                                elevation: 4,
                                color: const Color(0xFF002776), // Azul Seleção
                                // CORRIGIDO AQUI: side: BorderSide(...)
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12), 
                                  side: const BorderSide(color: Color(0xFFC5A814), width: 1.5)
                                ),
                                child: ListTile(
                                  leading: const Icon(Icons.sports_soccer, color: Colors.white, size: 32),
                                  title: const Text("FANTASY FJF", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                                  subtitle: const Text("Escale seu time agora!", style: TextStyle(color: Colors.white70)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isDataLoaded)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: statusColor.withOpacity(0.5))),
                                          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(statusIcon, color: statusColor, size: 12), const SizedBox(width: 4), Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11))]),
                                        ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward, color: Colors.white),
                                    ],
                                  ),
                                  onTap: () => Navigator.pushNamed(context, '/fantasy-home'),
                                ),
                              );
                            }
                          ),
                        ),

                      if (championshipService.isBolaoEnabled) ...[
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Card(
                            elevation: 4,
                            clipBehavior: Clip.antiAlias, 
                            // CORRIGIDO AQUI: side: BorderSide(...)
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12), 
                              side: const BorderSide(color: Color(0xFFC5A814), width: 1.5)
                            ),
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: AppTheme.brazilGradient,
                              ),
                              child: ListTile(
                                leading: const Icon(FontAwesomeIcons.earthAmericas, color: Colors.white, size: 32),
                                title: const Text(
                                  "BOLÃO DA COPA 2026", 
                                  style: TextStyle(
                                    color: Colors.white, 
                                    fontWeight: FontWeight.w900, 
                                    shadows: [Shadow(color: Colors.black45, blurRadius: 2)]
                                  )
                                ),
                                subtitle: const Text(
                                  "Dê seus palpites e concorra a prêmios!", 
                                  style: TextStyle(
                                    color: Colors.white, 
                                    fontWeight: FontWeight.w600,
                                    shadows: [Shadow(color: Colors.black26, blurRadius: 2)]
                                  )
                                ),
                                trailing: const Icon(Icons.arrow_forward, color: Colors.white),
                                onTap: () => Navigator.pushNamed(context, '/wordcup-pool'),
                              ),
                            ),
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 16),
                      const HomeNewsFeed(), 
                      const SizedBox(height: 10),

                      if (championshipService.isPhotoStoreEnabled) ...[
                        _buildThemedSectionHeader(context, "Loja de Fotos", Icons.camera_enhance),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
                            border: Border.all(color: Colors.grey.shade200)
                          ),
                          child: const PhotoStoreBanner(),
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      _buildThemedSectionHeader(context, "Equipes Participantes", Icons.groups),
                    ],
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
                      border: Border.all(color: Colors.grey.shade200)
                    ),
                    padding: const EdgeInsets.all(12),
                    child: const CustomScrollView(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      slivers: [
                        _TeamsSliverGrid(),
                      ],
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40, bottom: 80),
                  child: HomeFooter(appVersion: SplashScreen.appVersion),
                ),
              ),
            ],
          ),

          if (seasonId.isNotEmpty)
            const Positioned(
              left: 0, right: 0, bottom: 0,
              child: SponsorBannerRotator(location: 'footer_home'),
            ),
        ],
      ),
    );
  }
}

class _SponsorGridCard extends StatelessWidget {
  const _SponsorGridCard();
  static const String _partnerContactUrl = "https://wa.me/5548996381626?text=Quero%20anunciar%20no%20Grid";

  @override
  Widget build(BuildContext context) {
    final champService = Provider.of<ChampionshipService>(context);

    return Consumer<SponsorViewModel>(
      builder: (context, sponsorVm, _) {

        if (champService.isOffline && champService.currentSeasonId.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('FJF')),
            body: CustomEmptyState.offline(
              onRetry: () => champService.init(), 
            ),
          );
        }

        if (champService.isLoading && champService.currentSeasonId.isEmpty) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final sponsors = sponsorVm.sponsors.where((s) {
           return s['location'] == 'grid_teams' && s['isActive'] == true;
        }).toList();

        if (sponsors.isNotEmpty) {
          final data = sponsors.first;
          
          return InkWell(
            onTap: () async {
              final url = data['targetUrl'];
              if (url != null && url.isNotEmpty) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFC5A814), width: 1.5)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: data['imageUrl'] ?? '',
                  fit: BoxFit.contain,
                  errorWidget: (_,__,___) => _buildDefaultCard(),
                ),
              ),
            ),
          );
        }
        return _buildDefaultCard();
      }
    );
  }

  Widget _buildDefaultCard() {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(_partnerContactUrl), mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF002776), Color(0xFF001133)], 
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12), 
          border: Border.all(color: const Color(0xFFC5A814), width: 1.5) 
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20, bottom: -20,
              child: Icon(Icons.all_inclusive, size: 100, color: Colors.white.withOpacity(0.05)),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFC5A814).withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(FontAwesomeIcons.handshake, color: Color(0xFFC5A814), size: 24),
                  ),
                  const SizedBox(height: 8),
                  const Text("SEJA PARCEIRO", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Color(0xFFC5A814), letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  const Text("Anuncie aqui", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamsSliverGrid extends StatelessWidget {
  const _TeamsSliverGrid();

  @override
  Widget build(BuildContext context) {
    return Consumer<ChampionshipService>(
      builder: (context, service, _) {
        
        if (service.isLoading && service.teams.isEmpty) {
          return SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, 
              childAspectRatio: 0.85,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildSkeletonItem(),
              childCount: 6, 
            ),
          );
        }
        
        final teams = service.teams;

        if (teams.isEmpty) {
          return SliverToBoxAdapter(
            child: CustomEmptyState(
              icon: Icons.groups_outlined,
              title: "Sem Equipes",
              message: "As equipes desta temporada ainda estão sendo cadastradas.",
              buttonText: "Atualizar",
              onButtonPressed: () => service.fetchStaticData(forceRefresh: true),
            )
          );
        }

        final bool insertSponsor = (teams.length == 8);
        final int itemCount = insertSponsor ? 9 : teams.length;

        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, 
            childAspectRatio: 0.85,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (insertSponsor && index == 4) {
                return const _SponsorGridCard();
              }

              final int teamIndex = (insertSponsor && index > 4) ? index - 1 : index;
              final team = teams[teamIndex];
              
              return InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team))),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFC5A814), width: 1.5), 
                      boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: CachedNetworkImage(
                              imageUrl: team.shieldUrl,
                              fit: BoxFit.contain,
                              placeholder: (_,__) => Container(color: Colors.grey.shade50),
                              errorWidget: (_,__,___) => const Icon(Icons.shield_outlined, color: Colors.grey),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                          child: Text(
                            team.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
            },
            childCount: itemCount,
          ),
        );
      },
    );
  }

  Widget _buildSkeletonItem() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC5A814), width: 1.5),
      ),
      padding: const EdgeInsets.all(12),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(child: ShimmerEffect.circular(size: 60)),
          SizedBox(height: 10),
          ShimmerEffect.rectangular(height: 10, width: 60),
        ],
      ),
    );
  }
}