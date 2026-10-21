import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../viewmodels/sponsor_viewmodel.dart';
import '../../theme/app_theme.dart';
import '../../services/fantasy_preload_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  Timer? _bannerTimer;
  Timer? _navigationTimer;
  int _currentBannerIndex = 0;

  @override
  void initState() {
    super.initState();

    // Configuração das animações da Logo
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _animationController.forward();

    // Configura o timer para trocar os banners a cada 3 segundos
    _bannerTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      final allSponsors = context.read<SponsorViewModel>().sponsors;
      final sponsors = allSponsors.where((s) {
        final locs = s['locations'] as List<dynamic>? ?? [];
        return locs.contains('splash_loading') || s['location'] == 'splash_loading';
      }).toList();
      if (sponsors.isNotEmpty) {
        final int totalChunks = (sponsors.length / 6).ceil();
        setState(() {
          _currentBannerIndex = (_currentBannerIndex + 1) % totalChunks;
        });
      }
    });

    // Configura a navegação para a home após 5 segundos
    _navigationTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SponsorViewModel>().precachePriorityBanners(context);
        FantasyPreloadService().warmUp(context);
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _bannerTimer?.cancel();
    _navigationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allSponsors = context.watch<SponsorViewModel>().sponsors;
    final sponsors = allSponsors.where((s) {
      final locs = s['locations'] as List<dynamic>? ?? [];
      return locs.contains('splash_loading') || s['location'] == 'splash_loading';
    }).toList();

    return Scaffold(
      body: Stack(
        children: [
          // Background usando o gradiente do tema
          Container(
            decoration: const BoxDecoration(
              image: AppTheme.headerImage,
            ),
          ),

          // Animação da Logo e Barra de Carregamento
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                  children: [
                    Hero(
                      tag: 'app_logo',
                      child: Image.asset(
                        'assets/logo3_fjf.png',
                        width: 220,
                        height: 220,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Barra de Carregamento Animada 0 a 100%
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      duration: const Duration(seconds: 5),
                      builder: (context, value, child) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 150,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: LinearProgressIndicator(
                                  value: value,
                                  color: AppTheme.yellowColor,
                                  backgroundColor: Colors.black26,
                                  minHeight: 6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "Carregando dados... ${(value * 100).toInt()}%",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                shadows: [
                                  Shadow(
                                      color: Colors.black45,
                                      blurRadius: 2,
                                      offset: Offset(1, 1))
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Banner Rotativo de Parceiros na parte inferior
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sponsors.isNotEmpty)
                  const Text(
                    "Nossos Parceiros",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                            color: Colors.black45,
                            blurRadius: 4,
                            offset: Offset(1, 1))
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 230,
                  child: sponsors.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 800),
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                            return FadeTransition(
                                opacity: animation, child: child);
                          },
                          child: _buildSponsorGrid(
                            sponsors,
                            _currentBannerIndex,
                            ValueKey<int>(_currentBannerIndex),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSponsorGrid(
      List<Map<String, dynamic>> sponsors, int chunkIndex, Key key) {
    // Calculando a parte do array que corresponde a esse chunk (exibe até 6 por vez)
    final int startIndex = chunkIndex * 6;
    final int endIndex =
        (startIndex + 6 > sponsors.length) ? sponsors.length : startIndex + 6;

    // Se o startIndex for maior que o tamanho, provavelmente houve uma mudança nos dados. Redefine pra zero.
    if (startIndex >= sponsors.length) {
      return Container(key: key);
    }

    final chunkSponsors = sponsors.sublist(startIndex, endIndex);

    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children:
            chunkSponsors.map((sponsor) => _buildSponsorItem(sponsor)).toList(),
      ),
    );
  }

  Widget _buildSponsorItem(Map<String, dynamic> sponsor) {
    final String? imageUrl = sponsor['imageUrl'];
    final String name = sponsor['name'] ?? 'Patrocinador';

    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: (imageUrl != null && imageUrl.isNotEmpty)
            ? Padding(
                padding: const EdgeInsets.all(6.0),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  memCacheWidth: 200,
                  placeholder: (context, url) => const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.grey, strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Center(
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            )
          : Center(
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
      ),
    );
  }
}
