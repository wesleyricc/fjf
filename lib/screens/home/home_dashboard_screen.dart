import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/championship_service.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../services/voting_service.dart';

import '../../models/bolao_models.dart';

import '../../theme/app_theme.dart';
import '../../services/bolao_service.dart';
import '../../models/poll_model.dart';

// removed app_drawer.dart
import '../../widgets/main_bottom_nav_bar.dart';
import '../../widgets/sponsor_banner_rotator.dart';
import '../../widgets/home_live_video_card.dart';
import '../../widgets/ui/shimmer_effect.dart';
import '../../widgets/home_news_feed.dart';
import '../../widgets/home/home_teams_grid.dart';
import '../../widgets/home_footer.dart';
import '../../widgets/home/home_super_app_grid.dart';
import '../../widgets/home/home_section_header.dart';

import '../bolao/mini_bolao_home_screen.dart';
import '../championship/team_detail_screen.dart';
class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});
  static const routeName = '/';
  static const String appVersion = '2.0.0';
  static bool hasShownOpenAd = false;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  bool _isDrawerOpen = false;
  html.Event? _installPromptEvent;
  bool _showInstallButton = false;
  bool _hasError = false;
  String _debugStatus = "Iniciando...";

  bool _isCacheResolved = false;

  @override
  void initState() {
    super.initState();

    // 🚨 Analytics: App Aberto (Sessão Iniciada na Home)
    AnalyticsService.logCustomScreenView('App_Home_Dashboard');

    if (kIsWeb) {
      html.window.addEventListener('beforeinstallprompt', (html.Event e) {
        e.preventDefault();
        if (mounted) {
          setState(() {
            _installPromptEvent = e;
            _showInstallButton = true;
          });
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
      _checkAndShowStartupAds();
    });

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && !_isCacheResolved) {
        setState(() {
          _isCacheResolved = true;
        });
      }
    });
  }

  Future<void> _checkAndShowStartupAds() async {
    if (HomeDashboardScreen.hasShownOpenAd) return;

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    final service = Provider.of<ChampionshipService>(context, listen: false);
    if (!service.isAppOpenAdEnabled) {
      HomeDashboardScreen.hasShownOpenAd = true;
      return;
    }

    HomeDashboardScreen.hasShownOpenAd = true;
    _showAdDialog();
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
                    BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 10))
                  ]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: const SponsorBannerRotator(
                  location: 'app_open',
                  isStatic: false,
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(ctx),
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 4)
                        ]),
                    child: const Icon(Icons.close,
                        size: 24, color: Colors.black87),
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

    if (service.currentSeasonId.isNotEmpty) {
      if (mounted) setState(() => _isCacheResolved = true);
      return;
    }

    setState(() => _debugStatus = "Buscando temporadas...");
    try {
      await service.init();
      if (mounted) {
        if (service.availableSeasons.isNotEmpty) {
          setState(() {
            _debugStatus = "Sucesso!";
            _isCacheResolved = true;
          });
        } else {
          setState(() {
            _debugStatus = "Conectado, mas NENHUMA temporada encontrada.";
            _hasError = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _debugStatus = "Erro Crítico: $e";
          _hasError = true;
        });
      }
    }
  }

  void _triggerInstallPrompt() {
    if (_installPromptEvent == null) return;

    // 🚨 Analytics: Rastreia a intenção de instalação do App (PWA)
    AnalyticsService.logCustomScreenView('Home_PWA_Install_Clicked');

    (_installPromptEvent as dynamic).prompt();
    setState(() {
      _installPromptEvent = null;
      _showInstallButton = false;
    });
  }

  Future<void> _showSeasonSelectionDialog(BuildContext context) async {
    final championshipService =
        Provider.of<ChampionshipService>(context, listen: false);
    final currentId = championshipService.currentSeasonId;
    final List<Map<String, dynamic>> allSeasons =
        championshipService.availableSeasons;

    if (allSeasons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma temporada disponível.')));
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
                leading: Icon(isSelected ? Icons.check_circle : Icons.history,
                    color: isSelected ? Colors.green : Colors.grey),
                title: Text(season['name']),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (!isSelected) {
                    await championshipService.setSeason(season['id']);
                  }
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
                  const SizedBox(
                      height: 50,
                      width: 50,
                      child: CircularProgressIndicator(
                          color: Color(0xFFC25F22), strokeWidth: 3)),
                const SizedBox(height: 24),
                Text(_debugStatus,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _hasError ? Colors.red : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                        fontSize: 15)),
                if (_hasError) ...[
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _debugStatus = "Tentando novamente...";
                      });
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
      bottomNavigationBar: const MainBottomNavBar(currentRoute: '/'),
      body: Stack(
        children: [
          Container(color: const Color(0xFFF0F2F5)),
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 160.0,
                floating: false,
                pinned: true,
                backgroundColor: primaryColor,
                elevation: 0,
                stretch: true,
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(
                        right: 12.0, top: 8.0, bottom: 8.0),
                    child: TextButton.icon(
                      onPressed: () => _showSeasonSelectionDialog(context),
                      icon: const Icon(Icons.calendar_month,
                          size: 16, color: Colors.white),
                      label: Text(
                        "Temporada $displayYear",
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.15),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side:
                              const BorderSide(color: Colors.white30, width: 1),
                        ),
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [
                    StretchMode.zoomBackground,
                    StretchMode.blurBackground
                  ],
                  centerTitle: true,
                  title: LayoutBuilder(
                    builder: (context, constraints) {
                      final isCollapsed =
                          constraints.maxHeight <= kToolbarHeight + 30;
                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: isCollapsed ? 1.0 : 0.0,
                        child: Text("FJF $displayYear",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                          decoration: const BoxDecoration(
                              gradient: AppTheme.brazilGradient)),
                      SafeArea(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Hero(
                              tag: 'app_logo',
                              child: Container(
                                decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black45,
                                          blurRadius: 15,
                                          offset: Offset(0, 5))
                                    ]),
                                child: const CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Colors.white,
                                  backgroundImage:
                                      AssetImage('assets/logo3_fjf.png'),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text("FJF $displayYear",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                    shadows: [
                                      Shadow(
                                          color: Colors.black45,
                                          blurRadius: 4,
                                          offset: Offset(0, 2))
                                    ])),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: const Color(0xFFC5A814),
                                      width: 1.5),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                        offset: Offset(0, 2))
                                  ]),
                              child: Text(
                                  championshipService
                                          .currentSeasonHonoree.isNotEmpty
                                      ? championshipService.currentSeasonHonoree
                                      : "Homenageado $displayYear",
                                  style: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5)),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  colors: [Colors.green.shade50, Colors.white]),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.green.withOpacity(0.3)),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.green.withOpacity(0.05),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2))
                              ]),
                          child: Row(
                            children: [
                              const Icon(Icons.download_rounded,
                                  color: Colors.green),
                              const SizedBox(width: 12),
                              const Expanded(
                                  child: Text(
                                      "Instale o app para melhor experiência.",
                                      style: TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13))),
                              TextButton(
                                  onPressed: _triggerInstallPrompt,
                                  style: TextButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8))),
                                  child: const Text("Instalar")),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                      HomeLiveVideoCard(hidePlayer: false),
                      Consumer<ChampionshipService>(
                        builder: (context, service, child) {
                          if (service.isLoading && !_isCacheResolved) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              child: ShimmerEffect.rectangular(
                                  height: 100, width: double.infinity),
                            );
                          }
                          return HomeSuperAppGrid(service: service);
                        },
                      ),
                      const SizedBox(height: 16),
                      const HomeNewsFeed(),
                      const SizedBox(height: 10),
                      HomeSectionHeader(title: "Equipes Participantes", icon: Icons.groups, color: AppTheme.primaryColor),
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
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12)),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 3))
                        ],
                        border: Border.all(color: Colors.grey.shade200)),
                    padding: const EdgeInsets.all(12),
                    child: CustomScrollView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      slivers: [
                        HomeTeamsGrid(isCacheResolved: _isCacheResolved),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40, bottom: 0),
                  child: HomeFooter(appVersion: HomeDashboardScreen.appVersion),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  

  

  

  // Métodos de construção movidos para MainBottomNavBar
}
