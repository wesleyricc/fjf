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
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO

// removed app_drawer.dart
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/home_live_video_card.dart';
import '../widgets/home_news_feed.dart';
import '../widgets/home_footer.dart';
import '../widgets/photo_store_banner.dart';
import '../widgets/ui/shimmer_effect.dart';
import '../widgets/ui/custom_empty_state.dart';
import 'mini_bolao_home_screen.dart';
import 'team_detail_screen.dart';
import '../services/fantasy_auth_service.dart';
import '../services/auth_service.dart'; 
import '../viewmodels/sponsor_viewmodel.dart';
import '../widgets/main_bottom_nav_bar.dart';

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
    if (SplashScreen.hasShownOpenAd) return;

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    final service = Provider.of<ChampionshipService>(context, listen: false);
    if (!service.isAppOpenAdEnabled) {
      SplashScreen.hasShownOpenAd = true;
      return;
    }

    SplashScreen.hasShownOpenAd = true;
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



  Widget _buildThemedSectionHeader(
      BuildContext context, String title, IconData icon) {
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
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, -2))
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5)),
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
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: ShimmerEffect.rectangular(height: 100, width: double.infinity),
                            );
                          }
                          return _buildSuperAppGrid(context, service);
                        },
                      ),

                      const SizedBox(height: 16),
                      const HomeNewsFeed(),
                      const SizedBox(height: 10),

                      _buildThemedSectionHeader(
                          context, "Equipes Participantes", Icons.groups),
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
                        _TeamsSliverGrid(isCacheResolved: _isCacheResolved),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40, bottom: 0),
                  child: HomeFooter(appVersion: SplashScreen.appVersion),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuperAppGridItem({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                height: 70,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withOpacity(0.5), width: 1.5),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              if (badgeCount > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badgeCount.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showVotingBottomSheet(BuildContext context, List<Poll> activePolls, String seasonId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                height: 4,
                width: 40,
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text("PREMIAÇÕES ABERTAS", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 16),
            ...activePolls.map((poll) {
              final user = Provider.of<FantasyAuthService>(context, listen: false).user;
              return FutureBuilder<bool>(
                future: user != null ? VotingService().hasUserVoted(seasonId, poll.id, user.uid) : Future.value(false),
                builder: (context, voteSnapshot) {
                  final hasVoted = voteSnapshot.data ?? false;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: hasVoted ? Colors.green.withOpacity(0.1) : const Color(0xFFC5A814).withOpacity(0.2),
                      child: Icon(hasVoted ? Icons.check : Icons.how_to_vote, color: hasVoted ? Colors.green : const Color(0xFFC5A814)),
                    ),
                    title: Text(poll.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: hasVoted ? Colors.grey : Colors.black87)),
                    subtitle: Text(poll.category.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                    trailing: hasVoted ? const Icon(Icons.check_circle, color: Colors.green) : ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC5A814), foregroundColor: Colors.black87, elevation: 0),
                      onPressed: () {
                        AnalyticsService.logCustomScreenView('Home_Click_Voting_Banner', parameters: {'poll_id': poll.id});
                        Navigator.pushNamed(context, '/voting', arguments: poll).then((_) {
                            if (context.mounted) Navigator.pop(ctx);
                        });
                      },
                      child: const Text("VOTAR", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                    ),
                    onTap: () {
                      AnalyticsService.logCustomScreenView('Home_Click_Voting_Banner', parameters: {'poll_id': poll.id});
                      Navigator.pushNamed(context, '/voting', arguments: poll).then((_) {
                          if (context.mounted) Navigator.pop(ctx);
                      });
                    },
                  );
                }
              );
            }).toList(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSuperAppGrid(BuildContext context, ChampionshipService service) {
    return StreamBuilder<List<Poll>>(
      stream: service.currentSeasonId.isNotEmpty 
          ? VotingService().streamActivePolls(service.currentSeasonId)
          : Stream.value([]),
      builder: (context, pollSnapshot) {
        final activePolls = pollSnapshot.data ?? [];
        
        List<Widget> items = [];

        if (service.isFantasyEnabled) {
          items.add(_buildSuperAppGridItem(
            context: context,
            title: "Fantasy",
            icon: Icons.sports_soccer,
            color: const Color(0xFF002776),
            onTap: () {
              AnalyticsService.logCustomScreenView('Home_Click_Fantasy');
              Navigator.pushNamed(context, '/fantasy-home');
            },
          ));
        }

        if (service.isBolaoEnabled) {
          items.add(_buildSuperAppGridItem(
            context: context,
            title: "Bolão FJF - Copa do Mundo 2026",
            icon: FontAwesomeIcons.earthAmericas,
            color: const Color(0xFF009C3B),
            onTap: () {
              AnalyticsService.logCustomScreenView('Home_Click_Bolao_VIP');
              Navigator.pushNamed(context, '/wordcup-pool');
            },
          ));
        }

        if (service.isMiniBolaoEnabled) {
          items.add(_buildSuperAppGridItem(
            context: context,
            title: "Mini Bolão FJF",
            icon: Icons.rocket_launch,
            color: Colors.deepOrange.shade600,
            onTap: () {
              AnalyticsService.logCustomScreenView('Home_Click_Mini_Bolao');
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MiniBolaoHomeScreen()));
            },
          ));
        }

        if (service.isPhotoStoreEnabled) {
          items.add(_buildSuperAppGridItem(
            context: context,
            title: "Fotos",
            icon: Icons.camera_enhance,
            color: const Color(0xFF32BCAD),
            onTap: () {
              AnalyticsService.logCustomScreenView('Home_Click_Photo_Store');
              Navigator.pushNamed(context, '/photo-sales');
            },
          ));
        }

        if (activePolls.isNotEmpty) {
          items.add(_buildSuperAppGridItem(
            context: context,
            title: "Votações",
            icon: Icons.how_to_vote,
            color: const Color(0xFFC5A814),
            badgeCount: activePolls.length,
            onTap: () {
               if (activePolls.length == 1) {
                  Navigator.pushNamed(context, '/voting', arguments: activePolls.first).then((_) => setState(() {}));
               } else {
                  _showVotingBottomSheet(context, activePolls, service.currentSeasonId);
               }
            },
          ));
        }

        if (items.isEmpty) return const SizedBox();

        Widget gridLayout;
        if (items.length <= 4) {
          gridLayout = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items.map((item) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: item,
              ),
            )).toList(),
          );
        } else {
          // Ex: se houver 5 cards, divide 3 em cima e 2 embaixo
          List<Widget> firstRow = items.sublist(0, 3).map((item) => Expanded(
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: item)
          )).toList();
          List<Widget> secondRow = items.sublist(3).map((item) => Expanded(
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: item)
          )).toList();

          gridLayout = Column(
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: firstRow),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: secondRow),
            ],
          );
        }

        return Column(
          children: [
            _buildThemedSectionHeader(context, "Central FJF", Icons.apps),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: gridLayout,
            ),
          ],
        );
      }
    );
  }

  // Métodos de construção movidos para MainBottomNavBar
}

class _SponsorGridCard extends StatelessWidget {
  const _SponsorGridCard();
  static const String _partnerContactUrl =
      "https://wa.me/5548996381626?text=Quero%20anunciar%20no%20Grid";

  @override
  Widget build(BuildContext context) {
    final champService = Provider.of<ChampionshipService>(context);

    return Consumer<SponsorViewModel>(builder: (context, sponsorVm, _) {
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
            if (url != null && url.isNotEmpty) {
              await launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC5A814), width: 1.5)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: data['imageUrl'] ?? '',
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => _buildDefaultCard(),
              ),
            ),
          ),
        );
      }
      return _buildDefaultCard();
    });
  }

  Widget _buildDefaultCard() {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(_partnerContactUrl),
          mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF002776), Color(0xFF001133)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC5A814), width: 1.5)),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(Icons.all_inclusive,
                  size: 100, color: Colors.white.withOpacity(0.05)),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFC5A814).withOpacity(0.2),
                        shape: BoxShape.circle),
                    child: const Icon(FontAwesomeIcons.handshake,
                        color: Color(0xFFC5A814), size: 24),
                  ),
                  const SizedBox(height: 8),
                  const Text("SEJA PARCEIRO",
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          color: Color(0xFFC5A814),
                          letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  const Text("Anuncie aqui",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.white70)),
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
  final bool isCacheResolved; 
  const _TeamsSliverGrid({required this.isCacheResolved});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChampionshipService>(
      builder: (context, service, _) {
        if (service.isLoading && service.teams.isEmpty && !isCacheResolved) {
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
            message:
                "As equipes desta temporada ainda estão sendo cadastradas.",
            buttonText: "Atualizar",
            onButtonPressed: () => service.fetchStaticData(forceRefresh: true),
          ));
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

              final int teamIndex =
                  (insertSponsor && index > 4) ? index - 1 : index;
              final team = teams[teamIndex];

              return InkWell(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TeamDetailScreen(team: team))),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: const Color(0xFFC5A814), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 3))
                    ],
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
                            placeholder: (_, __) =>
                                Container(color: Colors.grey.shade50),
                            errorWidget: (_, __, ___) => const Icon(
                                Icons.shield_outlined,
                                color: Colors.grey),
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
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                              color: Colors.black87),
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