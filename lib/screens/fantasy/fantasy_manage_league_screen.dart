import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/fantasy_league_model.dart';
import '../../models/fantasy_models.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/analytics_service.dart';
import '../../utils/app_feedback.dart';
import '../../viewmodels/fantasy_league_viewmodel.dart';
import '../../widgets/team_logo_widget.dart';
import '../../widgets/fantasy/league_invite_modal.dart';

class FantasyManageLeagueScreen extends StatelessWidget {
  final FantasyLeague league;

  const FantasyManageLeagueScreen({super.key, required this.league});

  @override
  Widget build(BuildContext context) {
    bool hasProvider = false;
    try {
      Provider.of<FantasyLeagueViewModel>(context, listen: false);
      hasProvider = true;
    } catch (_) {
      hasProvider = false;
    }

    if (hasProvider) {
      return _FantasyManageLeagueBody(league: league);
    }

    final userId =
        Provider.of<FantasyAuthService>(context, listen: false).user?.uid;

    return ChangeNotifierProvider<FantasyLeagueViewModel>(
      create: (_) {
        final vm = FantasyLeagueViewModel();
        if (userId != null) {
          vm.init(userId);
        }
        return vm;
      },
      child: _FantasyManageLeagueBody(league: league),
    );
  }
}

class _FantasyManageLeagueBody extends StatefulWidget {
  final FantasyLeague league;

  const _FantasyManageLeagueBody({required this.league});

  @override
  State<_FantasyManageLeagueBody> createState() =>
      _FantasyManageLeagueBodyState();
}

class _FantasyManageLeagueBodyState extends State<_FantasyManageLeagueBody> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  final TextEditingController _searchController = TextEditingController();

  XFile? _selectedImageFile;
  bool _removeCurrentImage = false;
  bool _isSaving = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.league.name);

    AnalyticsService.logCustomScreenView('Fantasy_Manage_League_Screen',
        parameters: {
          'league_id': widget.league.id,
          'league_name': widget.league.name,
        });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (picked != null) {
        setState(() {
          _selectedImageFile = picked;
          _removeCurrentImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, "Erro ao selecionar imagem: $e");
      }
    }
  }

  void _showImageSourceModal(String? currentImageUrl) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                "Foto da Liga",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blueAccent,
                  child: Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: const Text("Tirar Foto"),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.deepPurpleAccent,
                  child: Icon(Icons.photo_library, color: Colors.white),
                ),
                title: const Text("Escolher da Galeria"),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (_selectedImageFile != null ||
                  (currentImageUrl != null &&
                      currentImageUrl.isNotEmpty &&
                      !_removeCurrentImage))
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.redAccent,
                    child: Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  title: const Text("Remover Foto Atual",
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedImageFile = null;
                      _removeCurrentImage = true;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveLeagueInfo(
      FantasyLeagueViewModel vm, FantasyLeague currentLeague) async {
    if (!_formKey.currentState!.validate()) return;

    final newName = _nameController.text.trim();
    final hasNameChanged = newName != currentLeague.name;
    final hasImageChanged =
        _selectedImageFile != null || _removeCurrentImage;

    if (!hasNameChanged && !hasImageChanged) {
      AppFeedback.showWarning(context, "Nenhuma alteração foi realizada.");
      return;
    }

    setState(() => _isSaving = true);

    final success = await vm.updateLeagueInfo(
      currentLeague.id,
      newName: newName,
      newImageFile: _selectedImageFile,
      removeImage: _removeCurrentImage,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        setState(() {
          _selectedImageFile = null;
          _removeCurrentImage = false;
        });
        AppFeedback.showSuccess(
            context, "Informações da liga atualizadas com sucesso!");
      } else {
        AppFeedback.showError(
            context, vm.errorMessage ?? "Erro ao salvar informações da liga.");
        vm.clearError();
      }
    }
  }

  Future<void> _confirmRemoveMember(
    FantasyLeagueViewModel vm,
    FantasyLeague currentLeague,
    FantasyTeam team,
  ) async {
    final isKnockoutActive =
        currentLeague.type == 'knockout' && currentLeague.status == 'active';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.person_remove_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("Remover Participante"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Tem certeza que deseja remover ${team.teamName} (${team.ownerName}) desta liga?",
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            if (isKnockoutActive)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.amber.shade900),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "Atenção: Esta liga mata-mata já possui partidas ativas.",
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              )
            else
              const Text(
                "O participante perderá o acesso e deixará de figurar no ranking.",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Remover"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await vm.removeMember(currentLeague.id, team.userId);
    if (mounted) {
      if (success) {
        AppFeedback.showSuccess(
            context, "${team.teamName} foi removido da liga.");
      } else {
        AppFeedback.showError(
            context, vm.errorMessage ?? "Erro ao remover participante.");
        vm.clearError();
      }
    }
  }

  Future<void> _confirmTransferOwnership(
    FantasyLeagueViewModel vm,
    FantasyLeague currentLeague,
    FantasyTeam newOwnerTeam,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.military_tech_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Text("Transferir Liderança"),
          ],
        ),
        content: Text(
          "Tem certeza que deseja transferir o comando desta liga para ${newOwnerTeam.teamName} (${newOwnerTeam.ownerName})?\n\nVocê deixará de ser o dono e não poderá mais alterar nome, foto ou gerenciar participantes.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Transferir"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success =
        await vm.transferOwnership(currentLeague.id, newOwnerTeam.userId);
    if (mounted) {
      if (success) {
        AppFeedback.showSuccess(context,
            "Liderança transferida para ${newOwnerTeam.teamName}!");
        Navigator.pop(context);
      } else {
        AppFeedback.showError(
            context, vm.errorMessage ?? "Erro ao transferir liderança.");
        vm.clearError();
      }
    }
  }

  Future<void> _confirmDeleteLeague(
    FantasyLeagueViewModel vm,
    FantasyLeague currentLeague,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text("Excluir Liga"),
          ],
        ),
        content: Text(
          "Tem certeza absoluta que deseja excluir permanentemente a liga '${currentLeague.name}'?\n\nEsta ação é irreversível e todos os participantes perderão o ranking e histórico desta liga.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sim, Excluir Liga"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await vm.deleteLeague(currentLeague.id);
    if (mounted) {
      if (success) {
        AppFeedback.showSuccess(context, "Liga excluída com sucesso.");
        Navigator.of(context).popUntil((route) =>
            route.isFirst || route.settings.name == '/fantasy-leagues');
      } else {
        AppFeedback.showError(
            context, vm.errorMessage ?? "Erro ao excluir liga.");
        vm.clearError();
      }
    }
  }

  Widget _buildImageAvatar(FantasyLeague currentLeague, Color primaryColor) {
    ImageProvider? imageProvider;

    if (_selectedImageFile != null) {
      if (kIsWeb) {
        imageProvider = NetworkImage(_selectedImageFile!.path);
      } else {
        imageProvider = FileImage(File(_selectedImageFile!.path));
      }
    } else if (!_removeCurrentImage &&
        currentLeague.imageUrl != null &&
        currentLeague.imageUrl!.isNotEmpty) {
      imageProvider = NetworkImage(currentLeague.imageUrl!);
    }

    return Center(
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: primaryColor, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: imageProvider != null
                  ? Image(
                      image: imageProvider,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildFallbackAvatar(
                          currentLeague, primaryColor),
                    )
                  : _buildFallbackAvatar(currentLeague, primaryColor),
            ),
          ),
          Material(
            color: primaryColor,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _showImageSourceModal(currentLeague.imageUrl),
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.camera_alt, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackAvatar(
      FantasyLeague currentLeague, Color primaryColor) {
    return Container(
      color: currentLeague.type == 'knockout'
          ? Colors.red.shade100
          : primaryColor.withValues(alpha: 0.12),
      child: Center(
        child: Icon(
          currentLeague.type == 'knockout'
              ? Icons.sports_kabaddi
              : Icons.emoji_events_rounded,
          size: 50,
          color: currentLeague.type == 'knockout'
              ? Colors.red.shade700
              : primaryColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final currentUserId =
        Provider.of<FantasyAuthService>(context, listen: false).user?.uid;
    final vm = Provider.of<FantasyLeagueViewModel>(context, listen: false);

    return StreamBuilder<FantasyLeague>(
      stream: vm.streamLeague(widget.league.id),
      initialData: widget.league,
      builder: (context, snapshot) {
        final currentLeague = snapshot.data ?? widget.league;
        final isOwner = currentUserId != null &&
            currentLeague.ownerId == currentUserId;

        // Se o usuário não for dono (ex: transferiu liderança)
        if (!isOwner) {
          return Scaffold(
            appBar: AppBar(title: const Text("Gerenciar Liga")),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      "Você não tem permissão de administrador nesta liga.",
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Voltar"),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text("Gerenciar Liga"),
            elevation: 1,
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: "Convidar Participantes",
                onPressed: () =>
                    LeagueInviteModal.show(context, currentLeague, isOwner: true),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. FOTO E DADOS BÁSICOS
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildImageAvatar(currentLeague, primaryColor),
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton.icon(
                              onPressed: () => _showImageSourceModal(
                                  currentLeague.imageUrl),
                              icon: const Icon(Icons.image, size: 16),
                              label: Text(
                                _selectedImageFile != null
                                    ? "Alterar foto selecionada"
                                    : (currentLeague.imageUrl != null &&
                                            !_removeCurrentImage)
                                        ? "Alterar foto da liga"
                                        : "Adicionar foto ou escudo",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                          if (_selectedImageFile != null || _removeCurrentImage)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline,
                                      size: 16, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _removeCurrentImage
                                          ? "A foto atual será removida ao salvar."
                                          : "Nova foto pronta para ser enviada.",
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue.shade900),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: "Nome da Liga",
                              hintText: "Ex: Liga dos Amigos",
                              prefixIcon: const Icon(Icons.emoji_events_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            maxLength: 30,
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return "Informe o nome da liga";
                              }
                              if (val.trim().length < 3) {
                                return "O nome deve ter pelo menos 3 caracteres";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          // Badges de Tipo e Código de Convite
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Chip(
                                avatar: Icon(
                                  currentLeague.type == 'knockout'
                                      ? Icons.sports_kabaddi
                                      : Icons.format_list_numbered,
                                  size: 16,
                                  color: currentLeague.type == 'knockout'
                                      ? Colors.red
                                      : primaryColor,
                                ),
                                label: Text(
                                  currentLeague.type == 'knockout'
                                      ? "Mata-Mata (${currentLeague.maxTeams} Times)"
                                      : "Pontos Corridos",
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                              InkWell(
                                onTap: () => LeagueInviteModal.copyCode(
                                    context, currentLeague.inviteCode),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.vpn_key,
                                          size: 14, color: primaryColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        "Código: ${currentLeague.inviteCode}",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.copy,
                                          size: 14, color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _isSaving
                                ? null
                                : () => _saveLeagueInfo(vm, currentLeague),
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.check),
                            label: Text(_isSaving
                                ? "Salvando..."
                                : "Salvar Alterações"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 2. GERENCIAMENTO DE PARTICIPANTES
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Participantes (${currentLeague.members.length}${currentLeague.maxTeams != null ? '/${currentLeague.maxTeams}' : ''})",
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: () => LeagueInviteModal.show(
                          context, currentLeague,
                          isOwner: true),
                      icon: const Icon(Icons.person_add, size: 16),
                      label: const Text("Convidar"),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (currentLeague.members.length > 5) ...[
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Buscar participante...",
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 10),
                ],

                FutureBuilder<List<FantasyTeam>>(
                  future: vm.getMembersTeams(currentLeague.members),
                  builder: (context, teamSnap) {
                    if (teamSnap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final teams = teamSnap.data ?? [];
                    if (teams.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text("Nenhum participante encontrado."),
                        ),
                      );
                    }

                    final filteredTeams = teams.where((t) {
                      if (_searchQuery.isEmpty) return true;
                      return t.teamName.toLowerCase().contains(_searchQuery) ||
                          t.ownerName.toLowerCase().contains(_searchQuery);
                    }).toList();

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredTeams.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final team = filteredTeams[idx];
                        final isThisOwner = team.userId == currentLeague.ownerId;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          leading: TeamLogoWidget(
                            logoUrl: team.customLogoUrl,
                            shieldType: team.shieldType,
                            radius: 20,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  team.teamName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isThisOwner)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: Colors.amber.shade400),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.star_rounded,
                                          size: 12,
                                          color: Colors.amber.shade900),
                                      const SizedBox(width: 2),
                                      Text(
                                        "DONO",
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            "${team.ownerName} • ${team.totalPoints.toStringAsFixed(1)} pts",
                            style: TextStyle(
                                color: Colors.grey.shade700, fontSize: 12),
                          ),
                          trailing: isThisOwner
                              ? null
                              : PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 20),
                                  onSelected: (val) {
                                    if (val == 'remove') {
                                      _confirmRemoveMember(
                                          vm, currentLeague, team);
                                    } else if (val == 'transfer') {
                                      _confirmTransferOwnership(
                                          vm, currentLeague, team);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(
                                      value: 'transfer',
                                      child: Row(
                                        children: [
                                          Icon(Icons.military_tech_outlined,
                                              size: 18, color: Colors.amber),
                                          SizedBox(width: 8),
                                          Text("Tornar Dono da Liga"),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: Row(
                                        children: [
                                          Icon(Icons.person_remove_outlined,
                                              size: 18, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text("Remover da Liga",
                                              style: TextStyle(
                                                  color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 32),

                // 3. ZONA DE PERIGO (EXCLUIR LIGA)
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                  color: Colors.red.shade50.withValues(alpha: 0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Text(
                              "Zona de Perigo",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Ao excluir a liga, todos os participantes perderão o acesso imediatamente e os chaveamentos ou rankings serão cancelados.",
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _confirmDeleteLeague(vm, currentLeague),
                          icon: const Icon(Icons.delete_forever, size: 18),
                          label: const Text("Excluir Liga Permanentemente"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade800,
                            side: BorderSide(color: Colors.red.shade400),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }
}
