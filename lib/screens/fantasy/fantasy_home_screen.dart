import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/fantasy_auth_service.dart';
import '../../services/championship_service.dart';
import '../../services/fantasy_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../models/fantasy_models.dart';
import '../../viewmodels/fantasy_home_viewmodel.dart';
import '../../widgets/team_logo_widget.dart';
import '../../widgets/ui/shimmer_effect.dart';
import '../../widgets/ui/custom_empty_state.dart';
import '../../widgets/fantasy/fantasy_landing_page.dart';
import '../../widgets/fantasy/fantasy_dashboard.dart';
import '../../widgets/skeleton_loader.dart';


class FantasyHomeScreen extends StatefulWidget {
  const FantasyHomeScreen({super.key});

  @override
  State<FantasyHomeScreen> createState() => _FantasyHomeScreenState();
}

class _FantasyHomeScreenState extends State<FantasyHomeScreen> {
  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Acesso ao Dashboard do Fantasy
    AnalyticsService.logCustomScreenView('Fantasy_Home_Screen');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FantasyAuthService>(
      builder: (context, authService, _) {
        if (!authService.isGoogleAuthenticated) {
          return FantasyLandingPage(authService: authService);
        }

        if (authService.isLoading) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final champService =
              Provider.of<ChampionshipService>(context, listen: false);
          Provider.of<FantasyHomeViewModel>(context, listen: false)
              .init(authService.user!.uid, champService.currentSeasonId);
        });

        return Consumer<FantasyHomeViewModel>(
          builder: (context, vm, child) {
            if (vm.isOffline && vm.team == null) {
              return Scaffold(
                appBar: AppBar(title: const Text("Fantasy FJF"), elevation: 0),
                body: CustomEmptyState.offline(
                    onRetry: () => vm.init(
                        authService.user!.uid,
                        Provider.of<ChampionshipService>(context, listen: false)
                            .currentSeasonId,
                        force: true)),
              );
            }

            if (vm.errorMessage != null && vm.team == null) {
              return Scaffold(
                appBar: AppBar(title: const Text("Fantasy FJF"), elevation: 0),
                body: CustomEmptyState(
                    icon: Icons.error_outline,
                    title: "Erro ao carregar",
                    message: vm.errorMessage!,
                    buttonText: "Tentar Novamente",
                    onButtonPressed: () => vm.init(
                        authService.user!.uid,
                        Provider.of<ChampionshipService>(context, listen: false)
                            .currentSeasonId,
                        force: true)),
              );
            }

            if (vm.isLoading) return _buildLoadingSkeleton(context);

            if (vm.team == null) {
              return Scaffold(
                appBar: AppBar(title: const Text("Fantasy FJF"), elevation: 0),
                body: CustomEmptyState(
                  icon: Icons.sync_problem,
                  title: "Sincronizando...",
                  message:
                      "Seu esquadrão está sendo preparado no servidor.\nClique abaixo para atualizar.",
                  buttonText: "Atualizar Agora",
                  onButtonPressed: () => vm.init(
                      authService.user!.uid,
                      Provider.of<ChampionshipService>(context, listen: false)
                          .currentSeasonId,
                      force: true),
                  secondaryButtonText: "Fazer Login com Google",
                  onSecondaryButtonPressed: () async {
                    final error = await authService.signInWithGoogle();
                    if (error != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                    } else if (context.mounted) {
                      vm.init(
                          authService.user!.uid,
                          Provider.of<ChampionshipService>(context, listen: false).currentSeasonId,
                          force: true);
                    }
                  },
                ),
              );
            }

            return FantasyDashboard(authService: authService, vm: vm);
          },
        );
      },
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Meu Time"), elevation: 0),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SkeletonLoader(height: 120, borderRadius: 0),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: const [
                      Expanded(child: SkeletonLoader(height: 100)),
                      SizedBox(width: 12),
                      Expanded(child: SkeletonLoader(height: 100)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const SkeletonLoader(height: 200),
                  const SizedBox(height: 24),
                  const SkeletonLoader(height: 150),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
