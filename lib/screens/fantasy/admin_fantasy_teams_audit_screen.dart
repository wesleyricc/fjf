import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/fantasy_models.dart';
import '../../services/fantasy_service.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_cache_service.dart';
import '../../widgets/team_logo_widget.dart';

class FantasyTeamAuditData {
  final FantasyTeam team;
  final int targetRound;
  final double currentPatrimony;
  final double previousPatrimony;
  final double roundScore;
  final double totalScore;
  final double currentBalance;
  final List<String> originalStarters;
  final List<String> scoringStarters;
  final List<String> bench;
  final String? captainId;
  final List<dynamic> substitutions;
  final bool hasHistory;
  final List<String> financialWarnings;
  final List<String> generalWarnings;
  final double startersValue;
  final bool isPastConcludedRound;

  FantasyTeamAuditData({
    required this.team,
    required this.targetRound,
    required this.currentPatrimony,
    required this.previousPatrimony,
    required this.roundScore,
    required this.totalScore,
    required this.currentBalance,
    required this.originalStarters,
    required this.scoringStarters,
    required this.bench,
    required this.captainId,
    required this.substitutions,
    required this.hasHistory,
    required this.financialWarnings,
    required this.generalWarnings,
    required this.startersValue,
    this.isPastConcludedRound = false,
  });

  List<String> get starters => originalStarters;
  List<String> get allWarnings => [...financialWarnings, ...generalWarnings];
  List<String> get warnings => allWarnings;
  bool get hasFinancialWarnings => financialWarnings.isNotEmpty;
  bool get hasGeneralWarnings => generalWarnings.isNotEmpty;
  bool get hasWarnings => hasFinancialWarnings || hasGeneralWarnings;
  double get priceVariation => currentPatrimony - previousPatrimony;
}

enum AuditFilterOption {
  all,
  onlyFinancialAlerts,
  onlyGeneralAlerts,
  highestScore,
  lowestScore,
  highestAppreciation,
  lowestAppreciation,
  highestPatrimony,
}

class AdminFantasyTeamsAuditScreen extends StatefulWidget {
  final int initialRound;

  const AdminFantasyTeamsAuditScreen({
    super.key,
    required this.initialRound,
  });

  @override
  State<AdminFantasyTeamsAuditScreen> createState() =>
      _AdminFantasyTeamsAuditScreenState();
}

class _AdminFantasyTeamsAuditScreenState
    extends State<AdminFantasyTeamsAuditScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  late int _selectedRound;
  bool _isLoading = true;
  String? _errorMessage;

  bool _isMarketOpen = false;
  int _dbRound = 1;

  List<FantasyTeamAuditData> _allTeamsAudit = [];
  Map<String, FantasyPlayer> _playersMap = {};

  AuditFilterOption _currentFilter = AuditFilterOption.all;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedRound = widget.initialRound > 0 ? widget.initialRound : 1;
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _loadAuditData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAuditData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Carrega status do mercado
      final statusDoc =
          await _firestore.collection('fantasy_config').doc('status').get();
      if (statusDoc.exists) {
        final data = statusDoc.data()!;
        _isMarketOpen = data['is_open'] ?? false;
        _dbRound = data['current_round'] ?? 1;
      }

      // 2. Carrega todos os jogadores do mercado para lookup de nome, preço e notas
      final playersSnap =
          await _firestore.collection('fantasy_market_players').get();
      _playersMap = {
        for (var doc in playersSnap.docs)
          doc.id: FantasyPlayer.fromFirestore(doc)
      };

      // 3. Carrega todas as equipes do fantasy
      final teamsSnap = await _firestore.collection('fantasy_teams').get();

      // 4. Carrega histórico de cada time para a rodada atual e anterior em paralelo
      final Map<String, DocumentSnapshot> historyCurrentMap = {};
      final Map<String, DocumentSnapshot> historyPrevMap = {};

      final List<Future<void>> historyTasks = [];
      for (var doc in teamsSnap.docs) {
        historyTasks.add(() async {
          try {
            final curDoc = await doc.reference
                .collection('history')
                .doc(_selectedRound.toString())
                .get();
            if (curDoc.exists) {
              historyCurrentMap[doc.id] = curDoc;
            }
          } catch (e) {
            debugPrint(
                "Erro ao buscar histórico rodada $_selectedRound do time ${doc.id}: $e");
          }

          if (_selectedRound > 1) {
            try {
              final prevDoc = await doc.reference
                  .collection('history')
                  .doc((_selectedRound - 1).toString())
                  .get();
              if (prevDoc.exists) {
                historyPrevMap[doc.id] = prevDoc;
              }
            } catch (e) {
              debugPrint(
                  "Erro ao buscar histórico anterior do time ${doc.id}: $e");
            }
          }
        }());
      }

      await Future.wait(historyTasks);

      // 5. Monta o modelo de auditoria de cada equipe
      final List<FantasyTeamAuditData> list = [];

      for (var doc in teamsSnap.docs) {
        final team = FantasyTeam.fromFirestore(doc);
        final currentHistDoc = historyCurrentMap[doc.id];
        final prevHistDoc = historyPrevMap[doc.id];

        final hasHistory = currentHistDoc != null && currentHistDoc.exists;
        final currentHistData =
            hasHistory ? (currentHistDoc.data() as Map<String, dynamic>) : null;

        final hasPrevHistory = prevHistDoc != null && prevHistDoc.exists;
        final prevHistData = hasPrevHistory
            ? (prevHistDoc.data() as Map<String, dynamic>)
            : null;

        final bool isPastConcludedRound = _selectedRound < _dbRound ||
            (hasHistory && _selectedRound != _dbRound);

        // Patrimônio atual pós-rodada
        final double currentPatrimony = currentHistData != null && currentHistData['patrimony'] != null
            ? (currentHistData['patrimony'] as num).toDouble()
            : (isPastConcludedRound ? 50.00 : team.teamValue);

        // Patrimônio anterior pré-rodada
        final double previousPatrimony = _selectedRound == 1
            ? 50.00
            : (prevHistData != null && prevHistData['patrimony'] != null
                ? (prevHistData['patrimony'] as num).toDouble()
                : 50.00);

        // Pontuação da rodada
        final double roundScore = currentHistData != null && currentHistData['points'] != null
            ? (currentHistData['points'] as num).toDouble()
            : (isPastConcludedRound ? 0.0 : team.lastScore);

        // Titulares originais da escalação (base contábil do patrimônio)
        final List<String> originalStarters;
        final List<String> scoringStarters;

        if (isPastConcludedRound) {
          // Em rodadas passadas já concluídas, a escalação DEVE vir do histórico daquela rodada.
          // Se o histórico não possui snapshot de escalação (a equipe não escalou ou se cadastrou após a rodada),
          // a lista de titulares daquela rodada é vazia ([]).
          // NUNCA utilizar team.lineupPlayerIds aqui, pois ela pertence à rodada seguinte/aberta!
          if (currentHistData != null && currentHistData['lineup_snapshot'] != null) {
            originalStarters = List<String>.from(currentHistData['lineup_snapshot']);
          } else if (currentHistData != null && currentHistData['final_lineup'] != null) {
            originalStarters = List<String>.from(currentHistData['final_lineup']);
          } else {
            originalStarters = const [];
          }

          if (currentHistData != null && currentHistData['final_lineup'] != null) {
            scoringStarters = List<String>.from(currentHistData['final_lineup']);
          } else {
            scoringStarters = originalStarters;
          }
        } else {
          // Rodada atual em andamento / mercado aberto
          originalStarters = currentHistData != null && currentHistData['lineup_snapshot'] != null
              ? List<String>.from(currentHistData['lineup_snapshot'])
              : team.lineupPlayerIds;
          scoringStarters = currentHistData != null && currentHistData['final_lineup'] != null
              ? List<String>.from(currentHistData['final_lineup'])
              : team.lineupPlayerIds;
        }

        final List<String> bench = isPastConcludedRound && (currentHistData == null || currentHistData['lineup_snapshot'] == null)
            ? const []
            : team.benchPlayerIds;

        final String? captainId = currentHistData != null
            ? currentHistData['captain_id'] as String? ?? (isPastConcludedRound ? null : team.captainId)
            : (isPastConcludedRound ? null : team.captainId);

        final List<dynamic> substitutions =
            currentHistData?['substitutions'] as List<dynamic>? ?? [];

        // Valor de mercado dos titulares escalados (base contábil do patrimônio)
        double startersValue = 0.0;
        for (var pid in originalStarters) {
          final p = _playersMap[pid];
          if (p != null) {
            startersValue += p.currentPrice;
          }
        }

        // 1. Determina o saldo em caixa aplicável à rodada auditada
        final double roundBalance;
        if (isPastConcludedRound) {
          if (currentHistData != null && currentHistData['balance'] != null) {
            roundBalance = (currentHistData['balance'] as num).toDouble();
          } else {
            // Em rodadas anteriores já concluídas sem campo 'balance' salvo no snapshot,
            // o saldo histórico em caixa no fechamento foi (patrimônio fechado - valor dos titulares escalados).
            // NUNCA usar team.currentBalance aqui pois ele já foi alterado pelo mercado das rodadas seguintes!
            roundBalance = double.parse(
                (currentPatrimony - startersValue).clamp(0.0, currentPatrimony).toStringAsFixed(2));
          }
        } else {
          // Rodada atual em andamento / mercado aberto
          roundBalance = team.currentBalance;
        }

        // Validações e Alertas de Auditoria
        final List<String> financialWarnings = [];
        final List<String> generalWarnings = [];

        // 1. DIVERGÊNCIAS FINANCEIRAS
        if (roundBalance < -0.01) {
          financialWarnings.add(
              "Saldo em caixa negativo: C\$ ${roundBalance.toStringAsFixed(2)}");
        }

        if (currentPatrimony <= 0) {
          financialWarnings.add("Patrimônio total zerado ou inconsistente");
        }

        if (roundBalance > currentPatrimony + 0.01) {
          financialWarnings.add(
              "Saldo em caixa (C\$ ${roundBalance.toStringAsFixed(2)}) maior que patrimônio (C\$ ${currentPatrimony.toStringAsFixed(2)})");
        }

        // Conferência Caixa + Atletas Escalados vs Patrimônio
        final double sumCheck = roundBalance + startersValue;
        if ((sumCheck - currentPatrimony).abs() > 0.15 && originalStarters.length == 6) {
          financialWarnings.add(
              "Divergência matemática: Caixa (C\$ ${roundBalance.toStringAsFixed(2)}) + Atletas Escalados (C\$ ${startersValue.toStringAsFixed(2)}) = C\$ ${sumCheck.toStringAsFixed(2)} ≠ Patrimônio (C\$ ${currentPatrimony.toStringAsFixed(2)})");
        }

        // 2. ALERTAS GERAIS DE ESCALAÇÃO / REGRAS
        if (originalStarters.isEmpty) {
          generalWarnings.add("Equipe não escalou nenhum titular na rodada");
        } else if (originalStarters.length < 6) {
          generalWarnings.add("Escalação incompleta (${originalStarters.length}/6 titulares)");
        }

        if (originalStarters.isNotEmpty && captainId == null) {
          generalWarnings.add("Sem capitão definido na rodada");
        }

        list.add(FantasyTeamAuditData(
          team: team,
          targetRound: _selectedRound,
          currentPatrimony: currentPatrimony,
          previousPatrimony: previousPatrimony,
          roundScore: roundScore,
          totalScore: team.totalPoints,
          currentBalance: roundBalance,
          originalStarters: originalStarters,
          scoringStarters: scoringStarters,
          bench: bench,
          captainId: captainId,
          substitutions: substitutions,
          hasHistory: hasHistory,
          financialWarnings: financialWarnings,
          generalWarnings: generalWarnings,
          startersValue: startersValue,
          isPastConcludedRound: isPastConcludedRound,
        ));
      }

      setState(() {
        _allTeamsAudit = list;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Erro ao carregar auditoria das equipes: $e";
        _isLoading = false;
      });
    }
  }

  List<FantasyTeamAuditData> get _filteredAndSortedTeams {
    var list = _allTeamsAudit.where((item) {
      if (_searchQuery.isNotEmpty) {
        final name = item.team.teamName.toLowerCase();
        final owner = item.team.ownerName.toLowerCase();
        if (!name.contains(_searchQuery) && !owner.contains(_searchQuery)) {
          return false;
        }
      }
      if (_currentFilter == AuditFilterOption.onlyFinancialAlerts) {
        return item.hasFinancialWarnings;
      }
      if (_currentFilter == AuditFilterOption.onlyGeneralAlerts) {
        return item.hasGeneralWarnings;
      }
      return true;
    }).toList();

    switch (_currentFilter) {
      case AuditFilterOption.onlyFinancialAlerts:
        list.sort((a, b) => b.roundScore.compareTo(a.roundScore));
        break;
      case AuditFilterOption.onlyGeneralAlerts:
        list.sort((a, b) => b.roundScore.compareTo(a.roundScore));
        break;
      case AuditFilterOption.highestScore:
        list.sort((a, b) => b.roundScore.compareTo(a.roundScore));
        break;
      case AuditFilterOption.lowestScore:
        list.sort((a, b) => a.roundScore.compareTo(b.roundScore));
        break;
      case AuditFilterOption.highestAppreciation:
        list.sort((a, b) => b.priceVariation.compareTo(a.priceVariation));
        break;
      case AuditFilterOption.lowestAppreciation:
        list.sort((a, b) => a.priceVariation.compareTo(b.priceVariation));
        break;
      case AuditFilterOption.highestPatrimony:
        list.sort((a, b) => b.currentPatrimony.compareTo(a.currentPatrimony));
        break;
      case AuditFilterOption.all:
        list.sort((a, b) {
          if (a.hasFinancialWarnings && !b.hasFinancialWarnings) return -1;
          if (!a.hasFinancialWarnings && b.hasFinancialWarnings) return 1;
          if (a.hasGeneralWarnings && !b.hasGeneralWarnings) return -1;
          if (!a.hasGeneralWarnings && b.hasGeneralWarnings) return 1;
          return b.roundScore.compareTo(a.roundScore);
        });
        break;
    }

    return list;
  }

  Future<void> _quickReopenMarket() async {
    final fantasyService = Provider.of<FantasyService>(context, listen: false);
    final nextRound = _selectedRound + 1;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_open, color: Colors.green),
            SizedBox(width: 8),
            Text("Reabrir Mercado"),
          ],
        ),
        content: Text(
          "Você confirmou a auditoria de todas as equipes da Rodada $_selectedRound?\n\n"
          "O mercado será ABERTO para a Rodada $nextRound e os usuários poderão voltar a escalar seus times.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Confirmar & Reabrir"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // 🏆 FinOps: Publica o resumo consolidado auditado da rodada e sincroniza variações
      await _publishRoundSummary(showConfirm: false);

      await fantasyService.setMarketStatus(true, nextRound);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                "Mercado REABERTO com sucesso para a Rodada $nextRound!"),
            backgroundColor: Colors.green,
          ),
        );
        _loadAuditData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao reabrir mercado: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 🏆 FinOps & Retroativo: Publica o resumo consolidado auditado da rodada
  /// e sincroniza last_variation nas equipes do banco para alimentar tela inicial e rankings
  Future<void> _publishRoundSummary({bool showConfirm = true}) async {
    final fantasyService = Provider.of<FantasyService>(context, listen: false);
    if (_allTeamsAudit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Aguarde o carregamento da auditoria para publicar."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (showConfirm) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.cloud_upload_outlined, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Text("Publicar Resumo da Rodada $_selectedRound"),
            ],
          ),
          content: Text(
            "Esta ação irá:\n\n"
            "1. Calcular e salvar o Resumo Oficial da Rodada $_selectedRound (Mito, Maior Valorização, Menor Pontuação e Maior Desvalorização de times escalados);\n"
            "2. Atualizar o documento consolidado da tela inicial (last_round_summary);\n"
            "3. Sincronizar a variação de patrimônio (last_variation) de todas as equipes no banco de dados para alimentar o Ranking de Cartoletas da rodada;\n"
            "4. Renovar os caches locais para exibição instantânea.\n\n"
            "Deseja confirmar a publicação?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Confirmar & Publicar"),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    setState(() => _isLoading = true);

    try {
      final activeAudit =
          _allTeamsAudit.where((t) => t.originalStarters.isNotEmpty).toList();
      final int totalCount = _allTeamsAudit.length;
      final int activeCount = activeAudit.length;
      final double avg = activeCount > 0
          ? activeAudit.fold<double>(0.0, (acc, t) => acc + t.roundScore) /
              activeCount
          : 0.0;

      FantasyTeamAuditData? mito;
      FantasyTeamAuditData? lanterna;
      FantasyTeamAuditData? maiorVal;
      FantasyTeamAuditData? maiorDesv;

      for (var t in _allTeamsAudit) {
        if (mito == null || t.roundScore > mito.roundScore) mito = t;
        if (maiorVal == null || t.priceVariation > maiorVal.priceVariation) {
          maiorVal = t;
        }
      }

      for (var t in activeAudit) {
        if (lanterna == null || t.roundScore < lanterna.roundScore) lanterna = t;
        if (maiorDesv == null ||
            t.priceVariation < maiorDesv.priceVariation) {
          maiorDesv = t;
        }
      }

      final summary = FantasyRoundSummary(
        round: _selectedRound,
        totalTeams: totalCount,
        activeTeams: activeCount,
        averageScore: double.parse(avg.toStringAsFixed(2)),
        highestScoreTeam: mito != null
            ? FantasyRoundHighlightTeam(
                teamId: mito.team.id,
                userId: mito.team.userId,
                teamName: mito.team.teamName,
                ownerName: mito.team.ownerName,
                customLogoUrl: mito.team.customLogoUrl,
                shieldType: mito.team.shieldType,
                score: mito.roundScore,
                variation: mito.priceVariation,
                patrimony: mito.currentPatrimony,
              )
            : null,
        lowestScoreTeam: lanterna != null
            ? FantasyRoundHighlightTeam(
                teamId: lanterna.team.id,
                userId: lanterna.team.userId,
                teamName: lanterna.team.teamName,
                ownerName: lanterna.team.ownerName,
                customLogoUrl: lanterna.team.customLogoUrl,
                shieldType: lanterna.team.shieldType,
                score: lanterna.roundScore,
                variation: lanterna.priceVariation,
                patrimony: lanterna.currentPatrimony,
              )
            : null,
        highestAppreciationTeam: maiorVal != null
            ? FantasyRoundHighlightTeam(
                teamId: maiorVal.team.id,
                userId: maiorVal.team.userId,
                teamName: maiorVal.team.teamName,
                ownerName: maiorVal.team.ownerName,
                customLogoUrl: maiorVal.team.customLogoUrl,
                shieldType: maiorVal.team.shieldType,
                score: maiorVal.roundScore,
                variation: maiorVal.priceVariation,
                patrimony: maiorVal.currentPatrimony,
              )
            : null,
        lowestAppreciationTeam: maiorDesv != null
            ? FantasyRoundHighlightTeam(
                teamId: maiorDesv.team.id,
                userId: maiorDesv.team.userId,
                teamName: maiorDesv.team.teamName,
                ownerName: maiorDesv.team.ownerName,
                customLogoUrl: maiorDesv.team.customLogoUrl,
                shieldType: maiorDesv.team.shieldType,
                score: maiorDesv.roundScore,
                variation: maiorDesv.priceVariation,
                patrimony: maiorDesv.currentPatrimony,
              )
            : null,
        updatedAt: DateTime.now(),
      );

      await fantasyService.saveRoundSummary(summary);

      // Sincroniza em batches no Firestore o last_variation e last_score de cada equipe
      final firestore = FirebaseFirestore.instance;
      final chunks = <List<FantasyTeamAuditData>>[];
      for (var i = 0; i < _allTeamsAudit.length; i += 200) {
        chunks.add(_allTeamsAudit.sublist(
            i,
            i + 200 > _allTeamsAudit.length
                ? _allTeamsAudit.length
                : i + 200));
      }

      for (var chunk in chunks) {
        final batch = firestore.batch();
        for (var item in chunk) {
          final teamRef =
              firestore.collection('fantasy_teams').doc(item.team.id);
          batch.update(teamRef, {
            'last_variation':
                double.parse(item.priceVariation.toStringAsFixed(2)),
            'last_score': double.parse(item.roundScore.toStringAsFixed(2)),
          });
          final histRef =
              teamRef.collection('history').doc(_selectedRound.toString());
          batch.set(histRef, {
            'variation': double.parse(item.priceVariation.toStringAsFixed(2)),
          }, SetOptions(merge: true));
        }
        await batch.commit();
      }

      // Invalida caches para os usuários e o admin verem na hora
      await FirestoreCacheService.invalidateCache(
          'fantasy_round_summary_$_selectedRound');
      await FirestoreCacheService.invalidateCache(
          'fantasy_round_summary_last');
      await FirestoreCacheService.invalidateCache(
          'fantasy_ranking_patrimony_false_20');
      await FirestoreCacheService.invalidateCache(
          'fantasy_ranking_patrimony_true_20');
      await FirestoreCacheService.invalidateCache(
          'fantasy_ranking_points_false_20');
      await FirestoreCacheService.invalidateCache(
          'fantasy_ranking_points_true_20');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                "Resumo da Rodada $_selectedRound e variações de patrimônio sincronizados com sucesso!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao publicar resumo da rodada: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showTeamDetailsModal(FantasyTeamAuditData item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, scrollController) {
            return _buildTeamDetailsSheet(item, scrollController);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final isAdmin = authService.isAdmin;

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Acesso Restrito"),
          backgroundColor: Colors.red.shade900,
        ),
        body: const Center(
          child: Text("Acesso restrito exclusivamente aos administradores."),
        ),
      );
    }

    final filtered = _filteredAndSortedTeams;

    // Métricas para os KPIs
    final int totalTeams = _allTeamsAudit.length;
    final int activeTeams =
        _allTeamsAudit.where((t) => t.starters.isNotEmpty).length;
    final double avgScore = totalTeams > 0
        ? _allTeamsAudit.fold<double>(0.0, (acc, t) => acc + t.roundScore) /
            totalTeams
        : 0.0;

    FantasyTeamAuditData? highestScoreTeam;
    FantasyTeamAuditData? highestAppreciationTeam;
    int financialWarningCount = 0;
    int generalWarningCount = 0;

    for (var t in _allTeamsAudit) {
      if (t.hasFinancialWarnings) financialWarningCount++;
      if (t.hasGeneralWarnings) generalWarningCount++;
      if (highestScoreTeam == null || t.roundScore > highestScoreTeam.roundScore) {
        highestScoreTeam = t;
      }
      if (highestAppreciationTeam == null ||
          t.priceVariation > highestAppreciationTeam.priceVariation) {
        highestAppreciationTeam = t;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          "Auditoria de Equipes",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: "Atualizar dados",
            icon: const Icon(Icons.refresh),
            onPressed: _loadAuditData,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text("Publicar Resumo R$_selectedRound"),
              onPressed: _isLoading
                  ? null
                  : () => _publishRoundSummary(showConfirm: true),
            ),
          ),
          if (!_isMarketOpen)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text("Reabrir Mercado"),
                onPressed: _quickReopenMarket,
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    "Carregando e auditando dados de todas as equipes...",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 60, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadAuditData,
                          icon: const Icon(Icons.refresh),
                          label: const Text("Tentar Novamente"),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAuditData,
                  child: CustomScrollView(
                    slivers: [
                      // 1. Banner de Status do Mercado
                      SliverToBoxAdapter(
                        child: _buildMarketStatusBanner(),
                      ),

                      // 2. Seletor de Rodada
                      SliverToBoxAdapter(
                        child: _buildRoundSelector(),
                      ),

                      // 3. Grid de KPIs
                      SliverToBoxAdapter(
                        child: _buildKpiGrid(
                          totalTeams: totalTeams,
                          activeTeams: activeTeams,
                          avgScore: avgScore,
                          highestScoreTeam: highestScoreTeam,
                          highestAppreciationTeam: highestAppreciationTeam,
                          financialWarningCount: financialWarningCount,
                          generalWarningCount: generalWarningCount,
                        ),
                      ),

                      // 4. Barra de Pesquisa e Filtros
                      SliverToBoxAdapter(
                        child: _buildSearchAndFilters(
                          financialWarningCount: financialWarningCount,
                          generalWarningCount: generalWarningCount,
                          totalTeams: totalTeams,
                        ),
                      ),

                      // 5. Lista de Equipes Auditadas
                      if (filtered.isEmpty)
                        SliverToBoxAdapter(
                          child: Container(
                            margin: const EdgeInsets.all(32),
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  _currentFilter == AuditFilterOption.onlyFinancialAlerts
                                      ? Icons.verified
                                      : (_currentFilter == AuditFilterOption.onlyGeneralAlerts
                                          ? Icons.check_circle_outline
                                          : Icons.search_off),
                                  size: 48,
                                  color: (_currentFilter == AuditFilterOption.onlyFinancialAlerts ||
                                          _currentFilter == AuditFilterOption.onlyGeneralAlerts)
                                      ? const Color(0xFF10B981)
                                      : Colors.grey,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _currentFilter == AuditFilterOption.onlyFinancialAlerts
                                      ? "Nenhuma divergência financeira encontrada! Todas as contas e patrimônios estão 100% íntegros."
                                      : (_currentFilter == AuditFilterOption.onlyGeneralAlerts
                                          ? "Nenhum alerta geral de escalação encontrado! Todas as equipes escalaram os 6 titulares e capitão."
                                          : "Nenhuma equipe encontrada para os filtros selecionados."),
                                  style: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final item = filtered[index];
                                return _buildTeamCard(item);
                              },
                              childCount: filtered.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  // --- WIDGETS DE CABEÇALHO E FILTRO ---

  Widget _buildMarketStatusBanner() {
    final isClosed = !_isMarketOpen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isClosed ? const Color(0xFFFEF3C7) : const Color(0xFFD1FAE5),
        border: Border(
          bottom: BorderSide(
            color: isClosed
                ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                : const Color(0xFF10B981).withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isClosed ? Icons.lock : Icons.lock_open,
            color: isClosed ? const Color(0xFFD97706) : const Color(0xFF059669),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isClosed
                  ? "MERCADO FECHADO: Momento ideal para validar pontuações e patrimônios das equipes antes da reabertura."
                  : "MERCADO ABERTO para a Rodada $_dbRound.",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isClosed
                    ? const Color(0xFF92400E)
                    : const Color(0xFF065F46),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _selectedRound > 1
                    ? () {
                        setState(() => _selectedRound--);
                        _loadAuditData();
                      }
                    : null,
              ),
              Row(
                children: [
                  const Icon(Icons.sports_soccer, color: Color(0xFF0F172A), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "Rodada $_selectedRound",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (_selectedRound == _dbRound)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        "Atual",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() => _selectedRound++);
                  _loadAuditData();
                },
              ),
            ],
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.cloud_upload_outlined, size: 16),
            label: Text("Publicar Resumo R$_selectedRound"),
            onPressed: _isLoading
                ? null
                : () => _publishRoundSummary(showConfirm: true),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid({
    required int totalTeams,
    required int activeTeams,
    required double avgScore,
    required FantasyTeamAuditData? highestScoreTeam,
    required FantasyTeamAuditData? highestAppreciationTeam,
    required int financialWarningCount,
    required int generalWarningCount,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildKpiCard(
              title: "Equipes",
              value: "$totalTeams",
              subtitle: "$activeTeams escalaram",
              icon: Icons.groups_outlined,
              iconColor: const Color(0xFF3B82F6),
              width: isNarrow ? (constraints.maxWidth - 12) / 2 : 180,
              onTap: () => setState(() => _currentFilter = AuditFilterOption.all),
            ),
            _buildKpiCard(
              title: "Média Rodada",
              value: "${avgScore.toStringAsFixed(1)} pts",
              subtitle: "Desempenho geral",
              icon: Icons.analytics_outlined,
              iconColor: const Color(0xFF8B5CF6),
              width: isNarrow ? (constraints.maxWidth - 12) / 2 : 180,
            ),
            _buildKpiCard(
              title: "Mito da Rodada",
              value: highestScoreTeam != null
                  ? "${highestScoreTeam.roundScore.toStringAsFixed(2)} pts"
                  : "--",
              subtitle: highestScoreTeam?.team.teamName ?? "Nenhum",
              icon: Icons.emoji_events_outlined,
              iconColor: const Color(0xFFF59E0B),
              width: isNarrow ? (constraints.maxWidth - 12) / 2 : 210,
              onTap: () => setState(() => _currentFilter = AuditFilterOption.highestScore),
            ),
            _buildKpiCard(
              title: "Maior Valorização",
              value: highestAppreciationTeam != null
                  ? "+C\$ ${highestAppreciationTeam.priceVariation.toStringAsFixed(2)}"
                  : "--",
              subtitle: highestAppreciationTeam?.team.teamName ?? "Nenhum",
              icon: Icons.trending_up,
              iconColor: const Color(0xFF10B981),
              width: isNarrow ? (constraints.maxWidth - 12) / 2 : 210,
              onTap: () => setState(() => _currentFilter = AuditFilterOption.highestAppreciation),
            ),
            _buildKpiCard(
              title: "Finanças & Caixa",
              value: financialWarningCount == 0
                  ? "100% OK"
                  : "$financialWarningCount Divergência${financialWarningCount > 1 ? 's' : ''}",
              subtitle: financialWarningCount == 0
                  ? "Saldos e Atletas batidos"
                  : "Toque para filtrar",
              icon: financialWarningCount == 0
                  ? Icons.verified
                  : Icons.account_balance_wallet,
              iconColor: financialWarningCount == 0
                  ? const Color(0xFF10B981)
                  : const Color(0xFFDC2626),
              width: isNarrow ? (constraints.maxWidth - 12) / 2 : 210,
              highlight: financialWarningCount > 0,
              highlightBgColor: const Color(0xFFFEF2F2),
              highlightBorderColor: const Color(0xFFEF4444),
              onTap: () => setState(() => _currentFilter = AuditFilterOption.onlyFinancialAlerts),
            ),
            _buildKpiCard(
              title: "Alertas Gerais",
              value: generalWarningCount == 0
                  ? "100% OK"
                  : "$generalWarningCount Alerta${generalWarningCount > 1 ? 's' : ''}",
              subtitle: generalWarningCount == 0
                  ? "Capitães e times completos"
                  : "Toque para filtrar",
              icon: generalWarningCount == 0
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_rounded,
              iconColor: generalWarningCount == 0
                  ? const Color(0xFF10B981)
                  : const Color(0xFFD97706),
              width: isNarrow ? (constraints.maxWidth - 12) / 2 : 210,
              highlight: generalWarningCount > 0,
              highlightBgColor: const Color(0xFFFFFBEB),
              highlightBorderColor: const Color(0xFFFCD34D),
              onTap: () => setState(() => _currentFilter = AuditFilterOption.onlyGeneralAlerts),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required double width,
    bool highlight = false,
    Color? highlightBgColor,
    Color? highlightBorderColor,
    VoidCallback? onTap,
  }) {
    final bg = highlight ? (highlightBgColor ?? const Color(0xFFFEF2F2)) : Colors.white;
    final border = highlight
        ? Border.all(
            color: (highlightBorderColor ?? const Color(0xFFEF4444))
                .withValues(alpha: 0.5))
        : null;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: border,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: highlight
                          ? (highlightBorderColor ?? const Color(0xFF991B1B))
                          : Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: highlight
                    ? (highlightBorderColor ?? const Color(0xFFDC2626))
                    : const Color(0xFF0F172A),
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: highlight
                    ? (highlightBorderColor ?? const Color(0xFFB91C1C))
                    : Colors.grey.shade500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters({
    required int financialWarningCount,
    required int generalWarningCount,
    required int totalTeams,
  }) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Campo de busca
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "Buscar por time ou cartoleiro...",
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 12),

          // Chips de ordenação e filtro
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSortChip(
                  label: "Todos ($totalTeams)",
                  option: AuditFilterOption.all,
                ),
                _buildSortChip(
                  label: "💰 Divergências Financeiras ($financialWarningCount)",
                  option: AuditFilterOption.onlyFinancialAlerts,
                  isAlert: financialWarningCount > 0,
                  alertColor: const Color(0xFFDC2626),
                ),
                _buildSortChip(
                  label: "⚠️ Alertas Gerais ($generalWarningCount)",
                  option: AuditFilterOption.onlyGeneralAlerts,
                  isAlert: generalWarningCount > 0,
                  alertColor: const Color(0xFFD97706),
                ),
                _buildSortChip(
                  label: "🏆 Mais Pontos",
                  option: AuditFilterOption.highestScore,
                ),
                _buildSortChip(
                  label: "📉 Menos Pontos",
                  option: AuditFilterOption.lowestScore,
                ),
                _buildSortChip(
                  label: "📈 Maior Valorização",
                  option: AuditFilterOption.highestAppreciation,
                ),
                _buildSortChip(
                  label: "📉 Maior Desvalorização",
                  option: AuditFilterOption.lowestAppreciation,
                ),
                _buildSortChip(
                  label: "💵 Maior Patrimônio",
                  option: AuditFilterOption.highestPatrimony,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip({
    required String label,
    required AuditFilterOption option,
    bool isAlert = false,
    Color? alertColor,
  }) {
    final isSelected = _currentFilter == option;
    final themeColor = alertColor ?? const Color(0xFFDC2626);
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        backgroundColor: Colors.white,
        selectedColor: isAlert ? themeColor.withValues(alpha: 0.15) : const Color(0xFF0F172A),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected
              ? (isAlert ? themeColor : Colors.white)
              : (isAlert ? themeColor : Colors.black87),
        ),
        checkmarkColor: isAlert ? themeColor : Colors.white,
        side: BorderSide(
          color: isAlert
              ? themeColor.withValues(alpha: 0.5)
              : (isSelected ? Colors.transparent : Colors.grey.shade300),
        ),
        onSelected: (val) {
          setState(() {
            _currentFilter = option;
          });
        },
      ),
    );
  }

  // --- CARD DE EQUIPE ---

  Widget _buildTeamCard(FantasyTeamAuditData item) {
    final variation = item.priceVariation;
    final isPositive = variation > 0;
    final isNeutral = variation.abs() < 0.001;

    final borderColor = item.hasFinancialWarnings
        ? const Color(0xFFEF4444)
        : (item.hasGeneralWarnings
            ? const Color(0xFFF59E0B)
            : Colors.black.withValues(alpha: 0.05));
    final borderWidth = (item.hasFinancialWarnings || item.hasGeneralWarnings) ? 1.5 : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showTeamDetailsModal(item),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho da Equipe
              Row(
                children: [
                  TeamLogoWidget(
                    logoUrl: item.team.customLogoUrl,
                    shieldType: item.team.shieldType,
                    radius: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.team.teamName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          item.team.ownerName,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Pontuação em Destaque
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "${item.roundScore.toStringAsFixed(2)} pts",
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // Métricas Financeiras
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildFinancialColumn(
                    label: "Patr. Anterior",
                    value: "C\$ ${item.previousPatrimony.toStringAsFixed(2)}",
                  ),
                  _buildFinancialColumn(
                    label: "Novo Patrimônio",
                    value: "C\$ ${item.currentPatrimony.toStringAsFixed(2)}",
                    isBold: true,
                  ),
                  _buildFinancialColumn(
                    label: "Valorização",
                    value: isNeutral
                        ? "C\$ 0.00"
                        : "${isPositive ? '+' : ''}C\$ ${variation.toStringAsFixed(2)}",
                    color: isNeutral
                        ? Colors.grey.shade600
                        : (isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                    isBold: true,
                  ),
                  _buildFinancialColumn(
                    label: "Saldo Caixa",
                    value: "C\$ ${item.currentBalance.toStringAsFixed(2)}",
                    color: item.currentBalance < 0
                        ? Colors.red
                        : Colors.grey.shade800,
                  ),
                ],
              ),

              // 1. DIVERGÊNCIAS FINANCEIRAS
              if (item.hasFinancialWarnings) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.account_balance_wallet,
                              color: Color(0xFFDC2626), size: 16),
                          SizedBox(width: 6),
                          Text(
                            "Divergência Financeira",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF991B1B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...item.financialWarnings.map((w) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            "• $w",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFB91C1C),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],

              // 2. ALERTAS GERAIS DE ESCALAÇÃO
              if (item.hasGeneralWarnings) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFD97706), size: 16),
                          SizedBox(width: 6),
                          Text(
                            "Alerta de Escalação / Regras",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...item.generalWarnings.map((w) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            "• $w",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],

              if (!item.hasWarnings) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 14, color: Color(0xFF10B981)),
                    const SizedBox(width: 4),
                    Text(
                      "Integridade OK • ${item.originalStarters.length} titulares • Capitão definido",
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF059669),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "Toque para ver detalhes",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 14, color: Colors.blue.shade700),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinancialColumn({
    required String label,
    required String value,
    Color? color,
    bool isBold = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color ?? const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  // --- MODAL DE DETALHES COMPLETOS DA EQUIPE ---

  Widget _buildTeamDetailsSheet(
      FantasyTeamAuditData item, ScrollController scrollController) {
    final variation = item.priceVariation;
    final isPositive = variation > 0;
    final isNeutral = variation.abs() < 0.001;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          // Puxador do Modal
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Cabeçalho da Equipe
          Row(
            children: [
              TeamLogoWidget(
                logoUrl: item.team.customLogoUrl,
                shieldType: item.team.shieldType,
                radius: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.team.teamName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      "Cartoleiro: ${item.team.ownerName}",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text(
                      "RODADA",
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    Text(
                      "${item.roundScore.toStringAsFixed(2)} pts",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(),

          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                // 1. Extrato Financeiro & Matemático
                const Text(
                  "EXTRATO DE PATRIMÔNIO & CAIXA",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      _buildReceiptRow(
                        "Patrimônio Anterior",
                        "C\$ ${item.previousPatrimony.toStringAsFixed(2)}",
                      ),
                      const SizedBox(height: 6),
                      _buildReceiptRow(
                        "Variação na Rodada",
                        isNeutral
                            ? "C\$ 0.00"
                            : "${isPositive ? '+' : ''}C\$ ${variation.toStringAsFixed(2)}",
                        valueColor: isNeutral
                            ? Colors.grey.shade600
                            : (isPositive
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444)),
                        isBold: true,
                      ),
                      const Divider(height: 16),
                      _buildReceiptRow(
                        "Novo Patrimônio Fechado",
                        "C\$ ${item.currentPatrimony.toStringAsFixed(2)}",
                        isBold: true,
                      ),
                      const SizedBox(height: 6),
                      _buildReceiptRow(
                        item.isPastConcludedRound
                            ? "Saldo Livre em Caixa (na Rodada ${item.targetRound})"
                            : "Saldo Livre em Caixa",
                        "C\$ ${item.currentBalance.toStringAsFixed(2)}",
                      ),
                      if (item.isPastConcludedRound) ...[
                        const SizedBox(height: 4),
                        _buildReceiptRow(
                          "Saldo Atual (Mercado Aberto R$_dbRound)",
                          "C\$ ${item.team.currentBalance.toStringAsFixed(2)}",
                          valueColor: Colors.blueGrey.shade700,
                        ),
                      ],
                      const SizedBox(height: 6),
                      _buildReceiptRow(
                        "Valor dos 6 Atletas Escalados (Titulares)",
                        "C\$ ${item.startersValue.toStringAsFixed(2)}",
                      ),
                      const Divider(height: 16),
                      // Conferência
                      _buildReceiptRow(
                        "Conferência Matemática (Caixa + Atletas)",
                        "C\$ ${(item.currentBalance + item.startersValue).toStringAsFixed(2)}",
                        isBold: true,
                        valueColor: ((item.currentBalance + item.startersValue) -
                                        item.currentPatrimony)
                                    .abs() <=
                                0.15
                            ? const Color(0xFF059669)
                            : const Color(0xFFDC2626),
                      ),
                      if (item.isPastConcludedRound) ...[
                        const SizedBox(height: 8),
                        Text(
                          "ℹ️ Esta rodada já foi concluída. Os valores contábeis de patrimônio e titulares acima refletem o fechamento oficial da Rodada ${item.targetRound}. O saldo atual após as transferências do mercado aberto é C\$ ${item.team.currentBalance.toStringAsFixed(2)}.",
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                      ],
                      if (item.substitutions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          "ℹ️ Esta equipe teve ${item.substitutions.length} substituição(ões) na pontuação em campo (ex: Reserva de Luxo). O patrimônio permanece atrelado aos 6 atletas titulares originais escalados.",
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 2. Avisos de Inconsistência Separados
                if (item.hasFinancialWarnings) ...[
                  const Text(
                    "DIVERGÊNCIAS FINANCEIRAS",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: item.financialWarnings
                          .map((w) => Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.account_balance_wallet,
                                        color: Color(0xFFDC2626), size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(w,
                                          style: const TextStyle(
                                              color: Color(0xFF991B1B),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (item.hasGeneralWarnings) ...[
                  const Text(
                    "ALERTAS GERAIS DE ESCALAÇÃO / REGRAS",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Color(0xFFD97706),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: item.generalWarnings
                          .map((w) => Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.warning_amber_rounded,
                                        color: Color(0xFFD97706), size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(w,
                                          style: const TextStyle(
                                              color: Color(0xFF92400E),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 3. Substituições Ocorridas
                if (item.substitutions.isNotEmpty) ...[
                  const Text(
                    "SUBSTITUIÇÕES DA RODADA",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: item.substitutions.map((sub) {
                        final outId = sub['out']?.toString();
                        final inId = sub['in']?.toString();
                        final type = sub['type']?.toString();
                        final pos = sub['slot_position']?.toString() ?? '';

                        final outP = _playersMap[outId];
                        final inP = _playersMap[inId];

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Icon(
                                type == 'luxury'
                                    ? Icons.hotel_class
                                    : Icons.swap_horiz,
                                color: type == 'luxury'
                                    ? Colors.amber.shade700
                                    : Colors.blue.shade700,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  type == 'luxury'
                                      ? "Reserva de Luxo ($pos): Entrou ${inP?.name ?? inId} no lugar de ${outP?.name ?? outId}"
                                      : "Titular Ausente ($pos): Entrou ${inP?.name ?? inId} no lugar de ${outP?.name ?? outId}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // 4. Titulares Escalados
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "TITULARES ESCALADOS (BASE DO PATRIMÔNIO)",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      "${item.originalStarters.length}/6 escalados",
                      style: TextStyle(
                        fontSize: 12,
                        color: item.originalStarters.length == 6
                            ? Colors.green
                            : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (item.originalStarters.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        "Nenhum atleta titular escalado.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ...item.originalStarters.map((pid) {
                    final p = _playersMap[pid];
                    final isCaptain = item.captainId == pid;
                    
                    // Verifica se o titular foi substituído na pontuação
                    String? statusNote;
                    for (var sub in item.substitutions) {
                      if (sub['out']?.toString() == pid) {
                        final inP = _playersMap[sub['in']?.toString()];
                        statusNote = sub['type'] == 'luxury'
                            ? "Substituído na pontuação por ${inP?.name ?? 'Reserva'} (Reserva de Luxo)"
                            : "Substituído na pontuação por ${inP?.name ?? 'Reserva'} (Não jogou)";
                        break;
                      }
                    }

                    return _buildPlayerRow(
                      player: p,
                      fallbackId: pid,
                      isCaptain: isCaptain,
                      round: item.targetRound,
                      statusNote: statusNote,
                    );
                  }),

                const SizedBox(height: 20),

                // 5. Reservas
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "BANCO DE RESERVAS",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      "${item.bench.length}/5 no banco",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (item.bench.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        "Nenhum atleta no banco de reservas.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ...item.bench.map((pid) {
                    final p = _playersMap[pid];
                    return _buildPlayerRow(
                      player: p,
                      fallbackId: pid,
                      isBench: true,
                      round: item.targetRound,
                    );
                  }),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: valueColor ?? const Color(0xFF0F172A),
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerRow({
    required FantasyPlayer? player,
    required String fallbackId,
    bool isCaptain = false,
    bool isBench = false,
    required int round,
    String? statusNote,
  }) {
    if (player == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text("Atleta ID $fallbackId não encontrado no mercado"),
      );
    }

    // Busca dados no histórico do atleta para esta rodada
    Map<String, dynamic>? roundHistory;
    if (player.history.isNotEmpty) {
      try {
        final matches = player.history.where((h) => h['round'] == round);
        if (matches.isNotEmpty) {
          roundHistory = Map<String, dynamic>.from(matches.first as Map);
        }
      } catch (_) {}
    }

    final double score = (roundHistory?['score'] as num?)?.toDouble() ??
        player.lastScore;
    final double variation =
        (roundHistory?['variation'] as num?)?.toDouble() ??
            player.lastPriceChange;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isCaptain ? const Color(0xFFFEF3C7) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCaptain ? const Color(0xFFF59E0B) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          // Foto ou Posição
          ClipOval(
            child: Container(
              width: 36,
              height: 36,
              color: const Color(0xFF0F172A),
              child: player.photoUrl.trim().isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: player.photoUrl.trim(),
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Center(
                        child: Text(
                          player.position.isNotEmpty
                              ? player.position.substring(0, 1).toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        player.position.isNotEmpty
                            ? player.position.substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),

          // Nome e Clube
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        player.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCaptain) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "CAP (2x)",
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  "${player.position} • C\$ ${player.currentPrice.toStringAsFixed(2)}",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (statusNote != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    statusNote,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Variação e Pontos
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${score.toStringAsFixed(1)} pts",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isCaptain
                      ? Colors.amber.shade900
                      : const Color(0xFF0F172A),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    variation >= 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    size: 14,
                    color: variation >= 0 ? Colors.green : Colors.red,
                  ),
                  Text(
                    "${variation >= 0 ? '+' : ''}${variation.toStringAsFixed(2)}",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: variation >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
