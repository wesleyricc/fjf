import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/auth_service.dart';
import '../../../services/fantasy_auth_service.dart';
import '../../../services/bolao_service.dart';
import '../../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../../models/bolao_models.dart';
import '../../../theme/app_theme.dart';
import '../../models/bolao_models.dart';
import '../../theme/app_theme.dart';
import 'bolao_user_dashboard_screen.dart';
import '../../viewmodels/bolao_predictions_viewmodel.dart';
import '../../widgets/bolao/bolao_bonus_tab.dart';
import '../../widgets/bolao/bolao_ranking_tab.dart';
import '../../utils/bolao_constants.dart';
import '../../widgets/bolao/bolao_prediction_card.dart';


enum SyncStatus { idle, syncing, saved }

class BolaoPredictionsScreen extends StatefulWidget {
  const BolaoPredictionsScreen({super.key});

  @override
  State<BolaoPredictionsScreen> createState() => _BolaoPredictionsScreenState();
}

class _BolaoPredictionsScreenState extends State<BolaoPredictionsScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final BolaoPredictionsViewModel _viewModel = BolaoPredictionsViewModel();
  late TabController _tabController;

  late String _userId;
  late Stream<DocumentSnapshot> _settingsStream;
  late Stream<BolaoUser?> _userStream;
  late Future<List<BolaoMatch>> _matchesFuture;
  late Future<List<BolaoPrediction>> _predictionsFuture;

  String _selectedStatusFilter = "Todos";
  String _selectedPhaseFilter = "Todas as Fases";
  int _matchDisplayLimit = 20;

  SyncStatus _syncStatus = SyncStatus.idle;
  Timer? _syncDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.logCustomScreenView('Bolao_Predictions_Screen_Tab_Palpites');

    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    _userId = authService.user?.uid ?? '';

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final tabs = ['Palpites', 'Bonus', 'Ranking'];
        AnalyticsService.logCustomScreenView('Bolao_Predictions_Screen_Tab_${tabs[_tabController.index]}');
      }
      setState(() {}); 
    });

    _settingsStream = _viewModel.streamSettings();
    _userStream = _viewModel.streamBolaoUser(_userId);
    _matchesFuture = _viewModel.getMatches();
    _predictionsFuture = _viewModel.getMyPredictions(_userId);
  }

  void _triggerSyncBanner() {
    setState(() => _syncStatus = SyncStatus.syncing);
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        setState(() => _syncStatus = SyncStatus.saved);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _syncStatus == SyncStatus.saved) {
            setState(() => _syncStatus = SyncStatus.idle);
          }
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      BolaoService.commitPendingPredictions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BolaoService.commitPendingPredictions(); 
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _contactSupport() async {
    final Uri url = Uri.parse("https://wa.me/5548996381626?text=Ol%C3%A1%2C%20preciso%20de%20suporte%20no%20Bol%C3%A3o%20da%20FJF");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Não foi possível abrir o WhatsApp.");
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.logout, color: Colors.red), SizedBox(width: 8), Text("Sair da Conta")]),
        content: const Text("Tem certeza que deseja desconectar do Bolão?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true), child: const Text("Sair"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (mounted) {
        await Provider.of<FantasyAuthService>(context, listen: false).signOut();
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  }

  void _showRulesModal(BuildContext context) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(children: [Icon(Icons.rule, color: Color(0xFF1B5E20), size: 28), SizedBox(width: 8), Text("Regras do Bolão", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)))]),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("💰 PREMIAÇÃO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
                      const Text("O grande vencedor leva 50% de TODO o valor arrecadado!", style: TextStyle(fontSize: 14)),
                      const Divider(height: 30),
                      const Text("⏳ PRAZOS DE ENCERRAMENTO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
                      const Text("• Palpites das Partidas fecham 30 minutos antes do jogo.\n• Bônus Extras fecham dia 17/06/2026 às 23h59.", style: TextStyle(fontSize: 14, height: 1.5)),
                      const Divider(height: 30),
                      const Text("⚽ PONTUAÇÃO DOS JOGOS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                      const Text("🎯 Na Mosca (+5 Pontos)\n⚖️ Acerto de Vencedor + Saldo (+3 Pontos)\n✔️ Acerto Simples (+2 Pontos)", style: TextStyle(fontSize: 14, height: 1.5)),
                      const Divider(height: 30),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1B5E20),
                          side: const BorderSide(color: Color(0xFF1B5E20), width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                        ),
                        icon: const Icon(Icons.support_agent),
                        label: const Text("SUPORTE", style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(context);
                          _contactSupport();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B5E20), 
                          foregroundColor: Colors.white, 
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text("ENTENDI!", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        );
      }
    );
  }

  void _showProfileRequiredDialog(BolaoUser currentUser) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.orange), SizedBox(width: 8), Text("Cadastro Incompleto")]),
        content: const Text("Complete seu cadastro (Nome, CPF e WhatsApp) para começar a palpitar e concorrer aos prêmios."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Agora não", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _showEditProfileModal(currentUser, currentUser.userId); 
            },
            child: const Text("Completar Cadastro"),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditProfileModal(BolaoUser bUser, String userId) async {
    final nameCtrl = TextEditingController(text: bUser.name == 'Utilizador' ? '' : bUser.name);
    final cpfCtrl = TextEditingController(text: bUser.cpf);
    final phoneCtrl = TextEditingController(text: bUser.phone);
    Uint8List? selectedImageBytes; 
    bool isSaving = false;

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Perfil do Treinador", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                        if (pickedFile != null) {
                          final bytes = await pickedFile.readAsBytes();
                          setModalState(() => selectedImageBytes = bytes);
                        }
                      },
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 50, backgroundColor: Colors.grey.shade200,
                            backgroundImage: selectedImageBytes != null ? MemoryImage(selectedImageBytes!) as ImageProvider : (bUser.photoUrl != null ? NetworkImage(bUser.photoUrl!) : null),
                            child: (selectedImageBytes == null && bUser.photoUrl == null) ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                          ),
                          Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Color(0xFF1B5E20), shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 20))
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nome / Nome do Time", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
                  const SizedBox(height: 16),
                  TextField(controller: cpfCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "CPF (Para recebimento de prêmios)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge))),
                  const SizedBox(height: 16),
                  TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "WhatsApp / Telefone", border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: isSaving ? null : () async {
                        if (nameCtrl.text.isEmpty || cpfCtrl.text.isEmpty || phoneCtrl.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preencha todos os campos!"), backgroundColor: Colors.orange));
                          return;
                        }
                        setModalState(() => isSaving = true);
                        try {
                          String? finalPhotoUrl;
                          if (selectedImageBytes != null) {
                            final ref = FirebaseStorage.instance.ref().child('bolao_avatars').child('$_userId.jpg');
                            await ref.putData(selectedImageBytes!); 
                            finalPhotoUrl = await ref.getDownloadURL();
                          }
                          await _viewModel.saveFullUserProfile(_userId, nameCtrl.text.trim(), cpfCtrl.text.trim(), phoneCtrl.text.trim(), finalPhotoUrl);
                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Perfil atualizado! 🏆"), backgroundColor: Colors.green));
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
                        } finally {
                          setModalState(() => isSaving = false);
                        }
                      },
                      child: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("SALVAR PERFIL COMPLETO", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_userId.isEmpty) return const Scaffold(body: Center(child: Text("Sessão expirada.")));

    return StreamBuilder<DocumentSnapshot>(
      stream: _settingsStream, 
      builder: (context, settingsSnapshot) {
        bool isGlobalLocked = true;
        if (settingsSnapshot.hasData && settingsSnapshot.data!.exists) {
          final settingsData = settingsSnapshot.data!.data() as Map<String, dynamic>?;
          if (settingsData != null && settingsData.containsKey('is_predictions_open')) {
            isGlobalLocked = !(settingsData['is_predictions_open'] as bool);
          }
        }

        return StreamBuilder<BolaoUser?>(
          stream: _userStream, 
          builder: (context, userSnapshot) {
            final currentUser = userSnapshot.data;

            return Scaffold(
              backgroundColor: Colors.grey[100],
              appBar: AppBar(
                title: const Text("Bolão Copa do Mundo", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.brazilGradient)),
                iconTheme: const IconThemeData(color: Colors.white),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.help_outline, color: Colors.amber),
                    tooltip: "Regras e Premiação",
                    onPressed: () => _showRulesModal(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.exit_to_app, color: Colors.white),
                    tooltip: "Sair da Conta",
                    onPressed: () => _confirmLogout(context),
                  ),
                  const SizedBox(width: 4),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.amber,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  isScrollable: true, 
                  tabs: const [
                    Tab(text: "Palpites"),
                    Tab(text: "Bônus Extras"),
                    Tab(text: "Ranking Geral"),
                  ],
                ),
              ),
              body: Stack(
                children: [
                  Column(
                    children: [
                      if (isGlobalLocked && _tabController.index != 2)
                        Container(
                          width: double.infinity, color: Colors.red[800], padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                          child: const Row(children: [Icon(Icons.lock, color: Colors.white, size: 20), SizedBox(width: 12), Expanded(child: Text("MERCADO GERAL FECHADO PELO ADMIN!", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))]),
                        ),
                      
                      if (_tabController.index == 0) 
                        _buildFilterBar(),
                      
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildMatchesTab(_userId, isGlobalLocked, currentUser),
                            BolaoBonusTab(
                              userId: _userId, 
                              currentUser: currentUser,
                              onRequireProfile: () => _showProfileRequiredDialog(currentUser!),
                            ),
                            BolaoRankingTab(
                              currentUserId: _userId, 
                              currentUser: currentUser
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  if (_syncStatus != SyncStatus.idle)
                    Positioned(
                      bottom: 24,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: _syncStatus == SyncStatus.syncing ? Colors.orange.shade700 : Colors.green.shade700,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _syncStatus == SyncStatus.syncing 
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.check_circle, color: Colors.white, size: 18),
                              const SizedBox(width: 10),
                              Text(
                                _syncStatus == SyncStatus.syncing ? "Salvando palpites..." : "Palpites salvos!",
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _buildFilterChip("Todos", _selectedStatusFilter == "Todos", (selected) { if (selected) setState(() { _selectedStatusFilter = "Todos"; _matchDisplayLimit = 20; }); }),
            _buildFilterChip("Em Aberto", _selectedStatusFilter == "Em Aberto", (selected) { if (selected) setState(() { _selectedStatusFilter = "Em Aberto"; _matchDisplayLimit = 20; }); }),
            _buildFilterChip("Em Andamento", _selectedStatusFilter == "Em Andamento", (selected) { if (selected) setState(() { _selectedStatusFilter = "Em Andamento"; _matchDisplayLimit = 20; }); }),
            _buildFilterChip("Encerrados", _selectedStatusFilter == "Encerrados", (selected) { if (selected) setState(() { _selectedStatusFilter = "Encerrados"; _matchDisplayLimit = 20; }); }),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(height: 20, child: VerticalDivider(thickness: 1.5, color: Colors.black12)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: _selectedPhaseFilter != "Todas as Fases" ? const Color(0xFF1B5E20).withOpacity(0.1) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _selectedPhaseFilter != "Todas as Fases" ? const Color(0xFF1B5E20) : Colors.black12)
              ),
              child: DropdownButton<String>(
                value: _selectedPhaseFilter, underline: const SizedBox(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _selectedPhaseFilter != "Todas as Fases" ? const Color(0xFF1B5E20) : Colors.black87),
                icon: Icon(Icons.arrow_drop_down, color: _selectedPhaseFilter != "Todas as Fases" ? const Color(0xFF1B5E20) : Colors.black54),
                items: BolaoConstants.phaseOptions.map((phase) => DropdownMenuItem(value: phase, child: Text(phase))).toList(),
                onChanged: (val) { if (val != null) setState(() { _selectedPhaseFilter = val; _matchDisplayLimit = 20; }); },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, ValueChanged<bool> onSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? Colors.white : Colors.black87)),
        selected: isSelected, selectedColor: const Color(0xFF1B5E20), backgroundColor: Colors.grey[100],
        onSelected: onSelected, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: isSelected ? const Color(0xFF1B5E20) : Colors.black12), showCheckmark: false,
      ),
    );
  }

  Widget _buildMatchesTab(String userId, bool isGlobalLocked, BolaoUser? currentUser) {
    return FutureBuilder<List<BolaoMatch>>(
      future: _matchesFuture, 
      builder: (context, matchSnapshot) {
        if (matchSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!matchSnapshot.hasData || matchSnapshot.data!.isEmpty) return const Center(child: Text("Nenhum jogo cadastrado."));

        final rawMatches = matchSnapshot.data!;

        return FutureBuilder<List<BolaoPrediction>>(
          future: _predictionsFuture, 
          builder: (context, predSnapshot) {
            if (predSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

            final predictions = predSnapshot.data ?? [];
            final Map<String, BolaoPrediction> predMap = { for (var p in predictions) p.matchId: p };

            List<BolaoMatch> filteredMatches = rawMatches.where((match) {
              if (_selectedPhaseFilter != "Todas as Fases" && match.group != _selectedPhaseFilter) return false;

              final bool isFinished = match.status == 'finished';
              final bool isInProgress = match.status == 'in_progress'; 
              final now = DateTime.now();
              final bool isMatchLockedLocally = now.isAfter(match.date.subtract(const Duration(minutes: 30)));
              
              final bool isPredictionsClosed = isGlobalLocked || isMatchLockedLocally || isInProgress || isFinished;

              if (_selectedStatusFilter == "Em Aberto" && isPredictionsClosed) return false;
              if (_selectedStatusFilter == "Em Andamento" && (!isPredictionsClosed || isFinished)) return false;
              if (_selectedStatusFilter == "Encerrados" && !isFinished) return false;
              
              return true;
            }).toList();

            if (_selectedStatusFilter == "Encerrados") {
              filteredMatches.sort((a, b) => b.date.compareTo(a.date));
            } else {
              filteredMatches.sort((a, b) => a.date.compareTo(b.date));
            }

            final Map<String, List<BolaoMatch>> matchesByDate = {};
            for (var match in filteredMatches) {
              final dateKey = "${match.date.day.toString().padLeft(2, '0')}/${match.date.month.toString().padLeft(2, '0')}/${match.date.year}";
              if (!matchesByDate.containsKey(dateKey)) matchesByDate[dateKey] = [];
              matchesByDate[dateKey]!.add(match);
            }

            final List<dynamic> listItems = [];
            final now = DateTime.now();

            for (var dateKey in matchesByDate.keys) {
              final matchesForDay = matchesByDate[dateKey]!;
              listItems.add({'type': 'header', 'title': dateKey});
              
              for (var match in matchesForDay) {
                final bool isMatchLockedLocally = now.isAfter(match.date.subtract(const Duration(minutes: 30)));
                listItems.add({'type': 'match', 'match': match, 'isMatchLocked': isMatchLockedLocally});
              }
            }

            if (listItems.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildUserHeader(currentUser),
                  const SizedBox(height: 40),
                  const Center(child: Text("Nenhum jogo corresponde aos filtros selecionados.", style: TextStyle(color: Colors.grey))),
                ],
              );
            }

            final bool hasMore = listItems.length > _matchDisplayLimit;
            final int displayCount = hasMore ? _matchDisplayLimit : listItems.length;
            final int itemCount = 1 + displayCount + (hasMore ? 1 : 0);

            return RefreshIndicator(
              color: const Color(0xFF1B5E20),
              onRefresh: () async {
                setState(() {
                  _matchDisplayLimit = 20; 
                  _matchesFuture = _viewModel.getMatches(forceRefresh: true);
                  _predictionsFuture = _viewModel.getMyPredictions(userId, forceRefresh: true);
                });
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (index == 0) return _buildUserHeader(currentUser);

                  if (hasMore && index == itemCount - 1) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _matchDisplayLimit += 20),
                        icon: const Icon(Icons.add),
                        label: const Text("CARREGAR MAIS PARTIDAS", style: TextStyle(fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1B5E20),
                          side: const BorderSide(color: Color(0xFF1B5E20)),
                        ),
                      ),
                    );
                  }

                  final item = listItems[index - 1];

                  if (item['type'] == 'header') {
                    if (isGlobalLocked) {
                      return Container(
                        margin: const EdgeInsets.only(top: 20, bottom: 10, left: 4, right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200, width: 1)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Dia ${item['title']} - MERCADO FECHADO", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.red[800])),
                            Icon(Icons.lock, size: 18, color: Colors.red[800])
                          ],
                        ),
                      );
                    } else {
                      return Container(
                        margin: const EdgeInsets.only(top: 20, bottom: 10, left: 4, right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300, width: 1)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Jogos do dia ${item['title']}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black87)),
                            const Icon(Icons.calendar_today, size: 18, color: Colors.black54)
                          ],
                        ),
                      );
                    }
                  }

                  final match = item['match'] as BolaoMatch;
                  final myPred = predMap[match.id];
                  final bool isMatchLocked = isGlobalLocked || item['isMatchLocked'] || match.status != 'pending';
                  
                  return BolaoPredictionCard(
                    match: match,
                    myPred: myPred,
                    currentUser: currentUser,
                    userId: userId,
                    viewModel: _viewModel,
                    isGlobalLocked: isMatchLocked,
                    onRequireProfile: () => _showProfileRequiredDialog(currentUser!),
                    onScoreSaved: _triggerSyncBanner,
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUserHeader(BolaoUser? bUser) {
    if (bUser == null) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));

    final bool isProfileIncomplete = !bUser.isProfileComplete;

    return GestureDetector(
      onTap: () {
        if (isProfileIncomplete) {
          _showEditProfileModal(bUser, bUser.userId);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BolaoUserDashboardScreen(user: bUser)),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, left: 4, right: 4),
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
                backgroundImage: bUser.photoUrl != null && bUser.photoUrl!.isNotEmpty ? NetworkImage(bUser.photoUrl!) : null,
                child: bUser.photoUrl == null || bUser.photoUrl!.isEmpty ? const Icon(Icons.sports_soccer, color: Color(0xFF1B5E20), size: 30) : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("TREINADOR FJF OFICIAL", style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text(
                    bUser.name == 'Utilizador' ? 'Defina seu Nome' : bUser.name,
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
                  onPressed: () => _showEditProfileModal(bUser, bUser.userId),
                ),
                const SizedBox(height: 12),
                const Icon(Icons.analytics, color: Colors.amber, size: 28),
              ],
            ),
          ],
        ),
      ),
    );
  }
}