import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/scheduler.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/championship_service.dart';
import '../../models/team_model.dart';
import '../../models/player_model.dart';
import 'dart:math' as math;
import '../../widgets/football_field_painter.dart';
import '../../widgets/tactical_drawing_painter.dart';
import '../../models/tactic_model.dart';
import '../../services/tactic_service.dart';

enum TacticalMode { move, draw, editShape, trajectory, rotate }

class PortalTacticalTab extends StatefulWidget {
  final String? teamId;
  final bool isPresident;

  const PortalTacticalTab({
    super.key,
    this.teamId,
    this.isPresident = false,
  });

  @override
  State<PortalTacticalTab> createState() => _PortalTacticalTabState();
}

class _FieldPlayer {
  final Player player;
  Offset initialPosition;
  final bool isOpponent;
  int appearAtMoment;
  Map<int, List<Offset>> trajectories;
  double rotation;

  _FieldPlayer({
    required this.player, 
    required this.initialPosition, 
    this.isOpponent = false,
    this.appearAtMoment = 0,
    Map<int, List<Offset>>? trajectories,
    this.rotation = 0.0,
  }) : trajectories = trajectories ?? {};

  _FieldPlayer clone() {
    return _FieldPlayer(
      player: player,
      initialPosition: initialPosition,
      isOpponent: isOpponent,
      appearAtMoment: appearAtMoment,
      trajectories: trajectories.map((k, v) => MapEntry(k, List.from(v))),
      rotation: rotation,
    );
  }

  Offset getPositionAtStartOfMoment(int momentIndex) {
    if (momentIndex < appearAtMoment) return initialPosition;
    Offset pos = initialPosition;
    for (int i = appearAtMoment; i < momentIndex; i++) {
      if (trajectories.containsKey(i) && trajectories[i]!.isNotEmpty) {
        final startCenter = pos + const Offset(18, 18);
        final rawPath = trajectories[i]!;
        final shift = startCenter - rawPath.first;
        final endCenter = rawPath.last + shift;
        pos = endCenter - const Offset(18, 18);
      }
    }
    return pos;
  }
}

class _AlwaysActiveTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

class TacticSnapshot {
  final List<_FieldPlayer> players;
  final List<DrawnLine> lines;
  final int maxMoments;
  TacticSnapshot(this.players, this.lines, this.maxMoments);
}

class _PortalTacticalTabState extends State<PortalTacticalTab> {
  String? _selectedTeamId;
  Future<List<Player>>? _rosterFuture;
  final ScreenshotController _screenshotController = ScreenshotController();
  
  final List<_FieldPlayer> _fieldPlayers = [];
  bool _isCapturing = false;

  // Animação
  final _tickerProvider = _AlwaysActiveTickerProvider();
  late AnimationController _playController;
  bool _isPlaying = false;
  double _playSpeed = 1.0;
  int _currentMomentIndex = 0;
  int _maxMoments = 1;

  // Estados de Desenho
  TacticalMode _currentMode = TacticalMode.move;
  ShapeType _currentShape = ShapeType.freehand;
  
  final List<DrawnLine> _lines = [];
  List<Offset> _currentPoints = [];
  Color _selectedColor = Colors.yellow;
  int? _activeLineIndex;
  int? _activeTrajectoryPlayerIndex;
  int? _activeRotatePlayerIndex;
  double _lastScale = 1.0;

  final List<TacticSnapshot> _historyStack = [];
  bool _isUndoStackMutating = false;

  final List<Color> _availableColors = [
    Colors.yellow,
    Colors.blueAccent,
    Colors.redAccent,
    Colors.white,
    Colors.black,
  ];

  StateSetter? _fullScreenSetState;
  bool _isFullScreenRouteActive = false;
  Size? _lastCanvasSize;
  
  final TacticService _tacticService = TacticService();
  bool _isLoading = false;

  void _rescaleCoordinates(Size oldSize, Size newSize) {
    if (oldSize.width <= 0 || oldSize.height <= 0 || newSize.width <= 0 || newSize.height <= 0) return;
    
    final scaleX = newSize.width / oldSize.width;
    final scaleY = newSize.height / oldSize.height;

    for (var fp in _fieldPlayers) {
      fp.initialPosition = Offset(fp.initialPosition.dx * scaleX, fp.initialPosition.dy * scaleY);
      for (var momentIndex in fp.trajectories.keys) {
        var traj = fp.trajectories[momentIndex]!;
        for (int i = 0; i < traj.length; i++) {
          traj[i] = Offset(traj[i].dx * scaleX, traj[i].dy * scaleY);
        }
      }
    }

    for (var line in _lines) {
      for (int i = 0; i < line.points.length; i++) {
        line.points[i] = Offset(line.points[i].dx * scaleX, line.points[i].dy * scaleY);
      }
    }
  }

  void _pushHistory() {
    if (_isUndoStackMutating) return;
    _historyStack.add(TacticSnapshot(
      _fieldPlayers.map((p) => p.clone()).toList(),
      _lines.map((l) => l.clone()).toList(),
      _maxMoments,
    ));
    if (_historyStack.length > 50) {
      _historyStack.removeAt(0);
    }
  }

  void _undo() {
    if (_historyStack.isEmpty) return;
    _isUndoStackMutating = true;
    _updateState(() {
      final snap = _historyStack.removeLast();
      _fieldPlayers.clear();
      _fieldPlayers.addAll(snap.players.map((p) => p.clone()));
      _lines.clear();
      _lines.addAll(snap.lines.map((l) => l.clone()));
      _maxMoments = snap.maxMoments;
      if (_currentMomentIndex >= _maxMoments) {
        _currentMomentIndex = _maxMoments - 1;
      }
      _activeLineIndex = null;
      _activeTrajectoryPlayerIndex = null;
      _activeRotatePlayerIndex = null;
    });
    _isUndoStackMutating = false;
  }

  void _updateState(VoidCallback fn) {
    fn();
    if (mounted) {
      setState(() {});
    }
    if (_fullScreenSetState != null) {
      _fullScreenSetState!(() {});
    }
  }

  Offset _getAnimatedPosition(_FieldPlayer fp) {
    final startPos = fp.getPositionAtStartOfMoment(_currentMomentIndex);
    if (!_isPlaying || !fp.trajectories.containsKey(_currentMomentIndex) || fp.trajectories[_currentMomentIndex]!.isEmpty) {
      return startPos;
    }
    
    final t = _playController.value;
    if (t == 0.0) return startPos;
    
    final startCenter = startPos + const Offset(18, 18);
    final traj = fp.trajectories[_currentMomentIndex]!;
    final shift = startCenter - traj.first;
    final path = traj.map((p) => p + shift).toList();

    if (path.length == 1) return startPos;

    double totalDist = 0.0;
    final List<double> segmentDists = [];
    for (int i = 0; i < path.length - 1; i++) {
      final dist = (path[i+1] - path[i]).distance;
      segmentDists.add(dist);
      totalDist += dist;
    }
    
    if (totalDist == 0) return startPos;
    
    double targetDist = t * totalDist;
    double currentDist = 0.0;
    
    Offset currentCenter = path.last;
    for (int i = 0; i < path.length - 1; i++) {
      if (currentDist + segmentDists[i] >= targetDist) {
        final segmentT = (targetDist - currentDist) / segmentDists[i];
        currentCenter = Offset.lerp(path[i], path[i+1], segmentT)!;
        break;
      }
      currentDist += segmentDists[i];
    }
    return currentCenter - const Offset(18, 18);
  }

  void _showSaveTacticDialog() {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Salvar Tática'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Nome da Tática', hintText: 'Ex: Escanteio Ofensivo 1'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty) return;
                final name = nameController.text;
                Navigator.pop(context);
                _saveTacticData(name);
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveTacticData(String name) async {
    _updateState(() => _isLoading = true);
    try {
      final tactic = TacticModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        teamId: _selectedTeamId!,
        name: name,
        createdAt: DateTime.now(),
        maxMoments: _maxMoments,
        canvasWidth: _lastCanvasSize?.width ?? 1000.0,
        canvasHeight: _lastCanvasSize?.height ?? 1000.0,
        players: _fieldPlayers.map((fp) => TacticPlayer(
          player: fp.player,
          initialPosition: fp.initialPosition,
          appearAtMoment: fp.appearAtMoment,
          isOpponent: fp.isOpponent,
          rotation: fp.rotation,
          trajectories: fp.trajectories,
        )).toList(),
        lines: _lines.map((l) => TacticLine(
          type: l.type,
          color: l.color,
          strokeWidth: l.strokeWidth,
          points: l.points,
        )).toList(),
      );
      
      await _tacticService.saveTactic(tactic);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tática salva com sucesso!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    } finally {
      if (mounted) {
        _updateState(() => _isLoading = false);
      }
    }
  }

  void _showLoadTacticDialog() async {
    _updateState(() => _isLoading = true);
    try {
      final tactics = await _tacticService.getTactics(_selectedTeamId!);
      if (!mounted) return;
      _updateState(() => _isLoading = false);
      
      showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Carregar Tática'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: tactics.isEmpty 
                ? const Center(child: Text('Nenhuma tática salva.'))
                : ListView.builder(
                    itemCount: tactics.length,
                    itemBuilder: (ctx, index) {
                      final tactic = tactics[index];
                      return ListTile(
                        leading: const Icon(Icons.sports_soccer),
                        title: Text(tactic.name),
                        subtitle: Text('${tactic.createdAt.day}/${tactic.createdAt.month}/${tactic.createdAt.year}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _deleteTacticData(tactic.id);
                          },
                        ),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _loadTacticData(tactic);
                        },
                      );
                    },
                  ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fechar')),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      _updateState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
    }
  }

  Future<void> _deleteTacticData(String id) async {
    _updateState(() => _isLoading = true);
    try {
      await _tacticService.deleteTactic(id);
      if (!mounted) return;
      _updateState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tática excluída com sucesso!')));
      _showLoadTacticDialog();
    } catch (e) {
      if (!mounted) return;
      _updateState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
    }
  }

  void _loadTacticData(TacticModel tactic) {
    _updateState(() {
      _maxMoments = tactic.maxMoments;
      _currentMomentIndex = 0;
      _fieldPlayers.clear();
      _lines.clear();
      _activeLineIndex = null;
      _activeTrajectoryPlayerIndex = null;
      _activeRotatePlayerIndex = null;
      _isPlaying = false;
      _playController.stop();

      // Restaurar jogadores
      for (var tp in tactic.players) {
        final fp = _FieldPlayer(player: tp.player, initialPosition: tp.initialPosition, isOpponent: tp.isOpponent, appearAtMoment: tp.appearAtMoment);
        fp.rotation = tp.rotation;
        fp.trajectories.addAll(tp.trajectories);
        _fieldPlayers.add(fp);
      }

      // Restaurar linhas
      for (var tl in tactic.lines) {
        _lines.add(DrawnLine(points: tl.points, color: tl.color, strokeWidth: tl.strokeWidth, type: tl.type));
      }

      // Se a tela mudou de tamanho entre o salvamento e o carregamento, reescalar!
      if (_lastCanvasSize != null) {
        final savedSize = Size(tactic.canvasWidth, tactic.canvasHeight);
        if (savedSize.width != _lastCanvasSize!.width || savedSize.height != _lastCanvasSize!.height) {
          _rescaleCoordinates(savedSize, _lastCanvasSize!);
        }
      }
      
      _historyStack.clear();
      _pushHistory();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tática "${tactic.name}" carregada!')));
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreenRouteActive = true;
    });
    // Wait for the current widget to unmount from the tree to avoid GlobalKey conflicts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) {
            return Scaffold(
              backgroundColor: Colors.grey.shade100,
              body: SafeArea(
                child: StatefulBuilder(
                  builder: (context, setModalState) {
                    _fullScreenSetState = setModalState;
                    return _buildMainContent(context, isFullScreen: true);
                  },
                ),
              ),
            );
          },
        ),
      ).then((_) {
        _fullScreenSetState = null;
        if (mounted) {
          setState(() {
            _isFullScreenRouteActive = false;
          });
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _playController = AnimationController(
      vsync: _tickerProvider,
      duration: const Duration(seconds: 3),
    )..addListener(() {
        _updateState(() {});
      })
      ..addStatusListener((status) async {
        if (status == AnimationStatus.completed && _isPlaying) {
          if (_currentMomentIndex < _maxMoments - 1) {
            _updateState(() {
              _currentMomentIndex++;
            });
            _playController.forward(from: 0.0);
          } else {
            await Future.delayed(const Duration(seconds: 2));
            if (_isPlaying && mounted) {
              _updateState(() {
                _currentMomentIndex = 0;
              });
              _playController.forward(from: 0.0);
            }
          }
        }
      });

    if (widget.isPresident) {
      _selectedTeamId = widget.teamId;
      // Initialize the future immediately if team is present
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateState(() {
          _rosterFuture = Provider.of<ChampionshipService>(context, listen: false).fetchRoster(widget.teamId!);
        });
      });
    } else {
      _selectedTeamId = 'all'; 
    }
  }

  @override
  void dispose() {
    _playController.dispose();
    super.dispose();
  }

  void _shareScreenshot(ScreenshotController targetController) async {
    _updateState(() {
      _isCapturing = true;
      _currentMode = TacticalMode.move; // Remove o modo desenho para não focar a tela
    });

    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final image = await targetController.capture(
        delay: const Duration(milliseconds: 10),
        pixelRatio: 2.0,
      );

      if (image != null) {
        final directory = await getTemporaryDirectory();
        final imagePath = await File('${directory.path}/escalacao.png').create();
        await imagePath.writeAsBytes(image);

        await Share.shareXFiles(
          [XFile(imagePath.path)], 
          text: 'Confira nossa jogada tática!',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar imagem: $e')),
        );
      }
    } finally {
      if (mounted) {
        _updateState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Widget _buildToolButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required bool isSelected,
  }) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      color: isSelected ? Colors.orange : Colors.grey.shade600,
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreenRouteActive) {
      return const SizedBox.shrink();
    }
    return _buildMainContent(context);
  }

  Widget _buildMainContent(BuildContext context, {bool isFullScreen = false}) {
    final ScreenshotController currentScreenshotController = isFullScreen ? ScreenshotController() : _screenshotController;
    final champService = Provider.of<ChampionshipService>(context, listen: false);
    final List<Team> teams = champService.teams;

    return Column(
      children: [
        // A barra de ferramentas agora é sobreposta ao campo
        if (!widget.isPresident)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Selecione a Equipe',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
              value: _selectedTeamId,
              items: [
                const DropdownMenuItem(value: 'all', child: Text('Selecione...')),
                ...teams.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
              ],
              onChanged: (val) {
                _updateState(() {
                  _selectedTeamId = val;
                  _fieldPlayers.clear(); 
                  _lines.clear();
                  if (val != null && val != 'all') {
                    _rosterFuture = Provider.of<ChampionshipService>(context, listen: false).fetchRoster(val);
                  } else {
                    _rosterFuture = null;
                  }
                });
              },
            ),
          ),
        
        if (_selectedTeamId == 'all')
          const Expanded(
            child: Center(
              child: Text('Selecione uma equipe para montar a escalação', 
                style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
          )
        else
          Expanded(
            child: FutureBuilder<List<Player>>(
              future: _rosterFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Erro: ${snapshot.error}'));
                }

                final athletes = (snapshot.data ?? []).where((p) => !p.isStaff).toList();
                
                final fieldPlayerIds = _fieldPlayers.map((p) => p.player.id).toSet();
                final benchAthletes = athletes.where((p) => !fieldPlayerIds.contains(p.id)).toList();

                benchAthletes.add(Player(
                  id: 'adv_fake',
                  name: 'Adversário',
                  position: 'ADV',
                  photoUrl: '',
                  teamId: 'none',
                  teamName: '',
                  teamShieldUrl: '',
                  isStaff: false,
                  isGoalkeeper: false,
                  isActive: true,
                  isSuspended: false,
                  goals: 0,
                  assists: 0,
                  yellowCards: 0,
                  redCards: 0,
                  totalYellowCards: 0,
                  totalRedCards: 0,
                  goalsConceded: 0,
                  motmAwards: 0,
                  matchesPlayed: 0,
                ));

                benchAthletes.add(Player(
                  id: 'ball_fake',
                  name: 'Bola',
                  position: 'BOLA',
                  photoUrl: '',
                  teamId: 'none',
                  teamName: '',
                  teamShieldUrl: '',
                  isStaff: false,
                  isGoalkeeper: false,
                  isActive: true,
                  isSuspended: false,
                  goals: 0,
                  assists: 0,
                  yellowCards: 0,
                  redCards: 0,
                  totalYellowCards: 0,
                  totalRedCards: 0,
                  goalsConceded: 0,
                  motmAwards: 0,
                  matchesPlayed: 0,
                ));

                return Column(
                  children: [
                    if (_selectedTeamId != 'all')
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0),
                        child: _buildToolbar(currentScreenshotController, isFullScreen),
                      ),
                    // Área do campo
                    Expanded(
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Center(
                              child: LayoutBuilder(
                            builder: (context, constraints) {
                              final currentSize = Size(constraints.maxWidth, constraints.maxHeight);
                              
                              if (_lastCanvasSize != null && _lastCanvasSize != currentSize) {
                                final oldSize = _lastCanvasSize!;
                                _lastCanvasSize = currentSize;
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    _updateState(() {
                                      _rescaleCoordinates(oldSize, currentSize);
                                    });
                                  }
                                });
                              } else if (_lastCanvasSize == null) {
                                _lastCanvasSize = currentSize;
                              }

                              return Screenshot(
                                controller: currentScreenshotController,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                              onScaleStart: (details) {
                                if (_currentMode == TacticalMode.draw) {
                                  _updateState(() {
                                    _currentPoints = [details.localFocalPoint];
                                    _activeLineIndex = null;
                                  });
                                } else if (_currentMode == TacticalMode.trajectory) {
                                  int? foundPlayerIndex;
                                  double minDistance = 40.0;
                                  for (int i = 0; i < _fieldPlayers.length; i++) {
                                    final playerCenter = _fieldPlayers[i].getPositionAtStartOfMoment(_currentMomentIndex) + const Offset(18, 18);
                                    final dist = (details.localFocalPoint - playerCenter).distance;
                                    if (dist < minDistance) {
                                      minDistance = dist;
                                      foundPlayerIndex = i;
                                    }
                                  }
                                  _updateState(() {
                                    _activeTrajectoryPlayerIndex = foundPlayerIndex;
                                    if (foundPlayerIndex != null) {
                                      _fieldPlayers[foundPlayerIndex].trajectories[_currentMomentIndex] = [details.localFocalPoint];
                                    }
                                  });
                                } else if (_currentMode == TacticalMode.editShape) {
                                  int? foundIndex;
                                  for (int i = _lines.length - 1; i >= 0; i--) {
                                    if (_lines[i].hitTest(details.localFocalPoint)) {
                                      foundIndex = i;
                                      break;
                                    }
                                  }
                                  _updateState(() {
                                    _activeLineIndex = foundIndex;
                                    _lastScale = 1.0;
                                  });
                                } else if (_currentMode == TacticalMode.rotate) {
                                  int? foundPlayerIndex;
                                  double minDistance = 40.0;
                                  for (int i = 0; i < _fieldPlayers.length; i++) {
                                    final playerCenter = _fieldPlayers[i].getPositionAtStartOfMoment(_currentMomentIndex) + const Offset(18, 18);
                                    final dist = (details.localFocalPoint - playerCenter).distance;
                                    if (dist < minDistance) {
                                      minDistance = dist;
                                      foundPlayerIndex = i;
                                    }
                                  }
                                  _updateState(() {
                                    _activeRotatePlayerIndex = foundPlayerIndex;
                                  });
                                }
                              },
                              onScaleUpdate: (details) {
                                if (_currentMode == TacticalMode.draw) {
                                  _updateState(() {
                                    _currentPoints.add(details.localFocalPoint);
                                  });
                                } else if (_currentMode == TacticalMode.trajectory && _activeTrajectoryPlayerIndex != null) {
                                  _updateState(() {
                                    final player = _fieldPlayers[_activeTrajectoryPlayerIndex!];
                                    if (!player.trajectories.containsKey(_currentMomentIndex)) {
                                      player.trajectories[_currentMomentIndex] = [];
                                    }
                                    final traj = player.trajectories[_currentMomentIndex]!;
                                    if (traj.isNotEmpty) {
                                      if (traj.length == 1) {
                                        traj.add(details.localFocalPoint);
                                      } else {
                                        traj[1] = details.localFocalPoint;
                                      }
                                    }
                                  });
                                } else if (_currentMode == TacticalMode.editShape && _activeLineIndex != null) {
                                  _updateState(() {
                                    final line = _lines[_activeLineIndex!];
                                    if (details.focalPointDelta != Offset.zero) {
                                      line.translate(details.focalPointDelta);
                                    }
                                    if (details.scale != 1.0 && details.scale != _lastScale) {
                                      final scaleDelta = details.scale / _lastScale;
                                      line.scale(scaleDelta, details.localFocalPoint);
                                      _lastScale = details.scale;
                                    }
                                  });
                                } else if (_currentMode == TacticalMode.rotate && _activeRotatePlayerIndex != null) {
                                  _updateState(() {
                                    final player = _fieldPlayers[_activeRotatePlayerIndex!];
                                    final playerCenter = player.getPositionAtStartOfMoment(_currentMomentIndex) + const Offset(18, 18);
                                    final dx = details.localFocalPoint.dx - playerCenter.dx;
                                    final dy = details.localFocalPoint.dy - playerCenter.dy;
                                    player.rotation = math.atan2(dy, dx);
                                  });
                                }
                              },
                              onScaleEnd: (details) {
                                if (_currentMode == TacticalMode.draw && _currentPoints.isNotEmpty) {
                                  _updateState(() {
                                    _lines.add(DrawnLine(
                                      points: List.from(_currentPoints), 
                                      color: _selectedColor,
                                      type: _currentShape,
                                    ));
                                    _currentPoints.clear();
                                  });
                                  _pushHistory();
                                } else if (_currentMode == TacticalMode.trajectory && _activeTrajectoryPlayerIndex != null) {
                                  _updateState(() {
                                    _activeTrajectoryPlayerIndex = null;
                                  });
                                  _pushHistory();
                                } else if (_currentMode == TacticalMode.editShape && _activeLineIndex != null) {
                                  _pushHistory();
                                } else if (_currentMode == TacticalMode.rotate && _activeRotatePlayerIndex != null) {
                                  _updateState(() {
                                    _activeRotatePlayerIndex = null;
                                  });
                                  _pushHistory();
                                }
                              },
                              child: Builder(
                                builder: (dragContext) {
                                  return DragTarget<Player>(
                                    onWillAcceptWithDetails: (_) => _currentMode == TacticalMode.move,
                                    onAcceptWithDetails: (details) {
                                      if (_currentMode != TacticalMode.move) return;
                                      final RenderBox box = dragContext.findRenderObject() as RenderBox;
                                      final Offset localOffset = box.globalToLocal(details.offset);
                                      
                                      _updateState(() {
                                        if (details.data.id == 'adv_fake') {
                                          final newOpponent = Player(
                                            id: 'adv_${DateTime.now().millisecondsSinceEpoch}',
                                            name: 'Adversário',
                                            position: 'ADV',
                                            photoUrl: '',
                                            teamId: 'none',
                                            teamName: '',
                                            teamShieldUrl: '',
                                            isStaff: false,
                                            isGoalkeeper: false,
                                            isActive: true,
                                            isSuspended: false,
                                            goals: 0,
                                            assists: 0,
                                            yellowCards: 0,
                                            redCards: 0,
                                            totalYellowCards: 0,
                                            totalRedCards: 0,
                                            goalsConceded: 0,
                                            motmAwards: 0,
                                            matchesPlayed: 0,
                                          );
                                          _fieldPlayers.add(_FieldPlayer(
                                            player: newOpponent, 
                                            initialPosition: localOffset, 
                                            isOpponent: true,
                                            appearAtMoment: _currentMomentIndex,
                                          ));
                                        } else if (details.data.id == 'ball_fake') {
                                          final newBall = Player(
                                            id: 'ball_${DateTime.now().millisecondsSinceEpoch}',
                                            name: 'Bola',
                                            position: 'BOLA',
                                            photoUrl: '',
                                            teamId: 'none',
                                            teamName: '',
                                            teamShieldUrl: '',
                                            isStaff: false,
                                            isGoalkeeper: false,
                                            isActive: true,
                                            isSuspended: false,
                                            goals: 0,
                                            assists: 0,
                                            yellowCards: 0,
                                            redCards: 0,
                                            totalYellowCards: 0,
                                            totalRedCards: 0,
                                            goalsConceded: 0,
                                            motmAwards: 0,
                                            matchesPlayed: 0,
                                          );
                                          _fieldPlayers.add(_FieldPlayer(
                                            player: newBall, 
                                            initialPosition: localOffset,
                                            appearAtMoment: _currentMomentIndex,
                                          ));
                                        } else {
                                          final existingIndex = _fieldPlayers.indexWhere((p) => p.player.id == details.data.id);
                                          if (existingIndex >= 0) {
                                            _fieldPlayers[existingIndex].initialPosition = localOffset;
                                          } else {
                                            _fieldPlayers.add(_FieldPlayer(
                                              player: details.data, 
                                              initialPosition: localOffset,
                                              appearAtMoment: _currentMomentIndex,
                                            ));
                                          }
                                        }
                                      });
                                    },
                                    builder: (context, candidateData, rejectedData) {
                                      return Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Positioned.fill(
                                            child: Container(color: Colors.transparent),
                                          ),
                                          SizedBox(
                                            width: double.infinity,
                                            height: double.infinity,
                                            child: CustomPaint(
                                              painter: FootballFieldPainter(),
                                            ),
                                          ),
                                          ..._fieldPlayers.map((fp) {
                                            final currentPos = _getAnimatedPosition(fp);
                                            return Positioned(
                                              left: currentPos.dx,
                                              top: currentPos.dy,
                                              child: Draggable<Player>(
                                                maxSimultaneousDrags: _currentMode == TacticalMode.move ? 1 : 0,
                                                data: fp.player,
                                                feedback: _buildPlayerWidget(fp.player, isDragging: true),
                                                childWhenDragging: const SizedBox(width: 50, height: 50),
                                                child: GestureDetector(
                                                  onLongPress: _currentMode == TacticalMode.move ? () {
                                                    _updateState(() {
                                                      _fieldPlayers.remove(fp);
                                                    });
                                                  } : null,
                                                  child: _buildPlayerWidget(fp.player, rotation: fp.rotation),
                                                ),
                                              ),
                                            );
                                          }),
                                          SizedBox(
                                            width: double.infinity,
                                            height: double.infinity,
                                            child: IgnorePointer(
                                              child: CustomPaint(
                                                painter: TacticalDrawingPainter(
                                                  lines: [
                                                    ..._lines,
                                                    ..._fieldPlayers
                                                        .where((p) => p.trajectories.containsKey(_currentMomentIndex) && p.trajectories[_currentMomentIndex]!.isNotEmpty)
                                                        .map((p) {
                                                          final startCenter = p.getPositionAtStartOfMoment(_currentMomentIndex) + const Offset(18, 18);
                                                          final traj = p.trajectories[_currentMomentIndex]!;
                                                          final shift = startCenter - traj.first;
                                                          final shiftedPath = traj.map((pt) => pt + shift).toList();
                                                          return DrawnLine(
                                                              points: shiftedPath,
                                                              color: p.player.id.startsWith('ball_') ? Colors.yellow.shade700 : Colors.grey.withValues(alpha: 0.5),
                                                              type: ShapeType.arrowDashed,
                                                          );
                                                        }),
                                                    if (_currentPoints.isNotEmpty) DrawnLine(
                                                      points: List.from(_currentPoints), 
                                                      color: _selectedColor,
                                                      type: _currentShape,
                                                    )
                                                  ],
                                                  activeLineIndex: _activeLineIndex,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }
                                  );
                                }
                              ),
                            ),
                          );
                        }
                      ),
                    ),
                  ),
                ],
              ),
            ),

                    // Área de Momentos (Linha do Tempo)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Colors.grey.shade200,
                      child: Row(
                        children: [
                          const Text('Momentos:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: List.generate(_maxMoments, (index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: ChoiceChip(
                                      label: Text('Quadro ${index + 1}'),
                                      selected: _currentMomentIndex == index,
                                      onSelected: (selected) {
                                        if (selected) {
                                          _updateState(() {
                                            _currentMomentIndex = index;
                                            _activeTrajectoryPlayerIndex = null;
                                            _activeLineIndex = null;
                                            _isPlaying = false;
                                            _playController.stop();
                                          });
                                        }
                                      },
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle, color: Colors.blue),
                            onPressed: () {
                              _updateState(() {
                                _maxMoments++;
                                _currentMomentIndex = _maxMoments - 1;
                                _isPlaying = false;
                                _playController.stop();
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    // Área do banco de reservas
                    DragTarget<Player>(
                      onAcceptWithDetails: (details) {
                        if (_currentMode == TacticalMode.move) {
                          _updateState(() {
                            _fieldPlayers.removeWhere((p) => p.player.id == details.data.id);
                          });
                        }
                      },
                      builder: (context, candidateData, rejectedData) {
                        return Container(
                          height: 90,
                          decoration: BoxDecoration(
                            color: candidateData.isNotEmpty ? Colors.red.shade50 : Colors.grey.shade100,
                            border: Border(top: BorderSide(color: Colors.grey.shade300)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                color: Colors.grey.shade300,
                                child: const Text(
                                  'Elenco (Arraste para a quadra)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: benchAthletes.length,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  itemBuilder: (context, index) {
                                    final player = benchAthletes[index];
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: Draggable<Player>(
                                        maxSimultaneousDrags: _currentMode == TacticalMode.move ? 1 : 0,
                                        data: player,
                                        feedback: _buildPlayerWidget(player, isDragging: true),
                                        childWhenDragging: Opacity(
                                          opacity: 0.3,
                                          child: _buildPlayerWidget(player),
                                        ),
                                        child: _buildPlayerWidget(player),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  IconData _getIconForShape(ShapeType shape) {
    switch (shape) {
      case ShapeType.freehand: return Icons.edit;
      case ShapeType.arrowSolid: return Icons.arrow_outward;
      case ShapeType.arrowDashed: return Icons.moving;
      case ShapeType.circle: return Icons.radio_button_unchecked;
      case ShapeType.filledCircle: return Icons.lens;
      case ShapeType.square: return Icons.crop_square;
      case ShapeType.filledSquare: return Icons.square;
      case ShapeType.cross: return Icons.close;
      case ShapeType.ball: return Icons.sports_soccer;
      case ShapeType.cone: return Icons.change_history;
    }
  }

  PopupMenuItem<ShapeType> _buildShapeMenuItem(ShapeType type, String label) {
    return PopupMenuItem<ShapeType>(
      value: type,
      child: Row(
        children: [
          Icon(_getIconForShape(type), size: 20, color: Colors.black87),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildToolbar(ScreenshotController currentScreenshotController, bool isFullScreen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12.0,
        runSpacing: 8.0,
        children: [
          // Mover
          ElevatedButton.icon(
            onPressed: () => _updateState(() => _currentMode = TacticalMode.move),
            icon: const Icon(Icons.touch_app, size: 18),
            label: const Text('Mover', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _currentMode == TacticalMode.move ? Colors.teal : Colors.grey.shade400,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          // Ferramentas Agrupadas
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildToolButton(
                  icon: Icons.highlight_alt, 
                  tooltip: 'Selecionar / Editar Desenhos', 
                  isSelected: _currentMode == TacticalMode.editShape,
                  onTap: () => _updateState(() { _currentMode = TacticalMode.editShape; }),
                ),
                PopupMenuButton<ShapeType>(
                  tooltip: 'Formas de Desenho',
                  icon: Icon(
                    _currentMode == TacticalMode.draw ? _getIconForShape(_currentShape) : Icons.edit,
                    color: _currentMode == TacticalMode.draw ? Colors.orange : Colors.grey.shade600,
                  ),
                  onSelected: (ShapeType result) {
                    _updateState(() {
                      _currentMode = TacticalMode.draw;
                      _currentShape = result;
                      _activeLineIndex = null;
                    });
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<ShapeType>>[
                    _buildShapeMenuItem(ShapeType.freehand, 'Livre'),
                    _buildShapeMenuItem(ShapeType.arrowSolid, 'Seta Contínua'),
                    _buildShapeMenuItem(ShapeType.arrowDashed, 'Seta Tracejada'),
                    _buildShapeMenuItem(ShapeType.circle, 'Círculo Borda'),
                    _buildShapeMenuItem(ShapeType.filledCircle, 'Círculo Preenchido'),
                    _buildShapeMenuItem(ShapeType.square, 'Quadrado Borda'),
                    _buildShapeMenuItem(ShapeType.filledSquare, 'Quadrado Preenchido'),
                    _buildShapeMenuItem(ShapeType.cross, 'Marcador X'),
                    const PopupMenuDivider(),
                    _buildShapeMenuItem(ShapeType.ball, 'Bola'),
                    _buildShapeMenuItem(ShapeType.cone, 'Cone'),
                  ],
                ),
                _buildToolButton(
                  icon: Icons.route, 
                  tooltip: 'Trajetória Animada', 
                  isSelected: _currentMode == TacticalMode.trajectory,
                  onTap: () => _updateState(() { _currentMode = TacticalMode.trajectory; _activeLineIndex = null; }),
                ),
                _buildToolButton(
                  icon: Icons.rotate_right,
                  tooltip: 'Rotacionar Jogador',
                  isSelected: _currentMode == TacticalMode.rotate,
                  onTap: () => _updateState(() { _currentMode = TacticalMode.rotate; _activeLineIndex = null; }),
                ),
              ],
            ),
          ),
          // Seletor de Cores
          if (_currentMode != TacticalMode.move) ...[
            if (_currentMode == TacticalMode.draw)
              ..._availableColors.map((color) => GestureDetector(
                onTap: () => _updateState(() => _selectedColor = color),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _selectedColor == color ? Colors.teal : Colors.black26,
                      width: _selectedColor == color ? 3 : 1,
                    ),
                  ),
                ),
              )),
            const SizedBox(width: 8),
            // Apagar Selecionado
            if (_currentMode == TacticalMode.editShape && _activeLineIndex != null)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: 'Apagar Item Selecionado',
                onPressed: () {
                  _updateState(() {
                    _lines.removeAt(_activeLineIndex!);
                    _activeLineIndex = null;
                  });
                  _pushHistory();
                },
              ),
            // Desfazer Universal
            IconButton(
              icon: Icon(Icons.undo, color: _historyStack.isNotEmpty ? Colors.blue : Colors.grey),
              tooltip: 'Desfazer última ação',
              onPressed: _historyStack.isNotEmpty ? _undo : null,
            ),
            // Apagar TUDO
            if (_currentMode == TacticalMode.draw)
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                tooltip: 'Apagar TUDO',
                onPressed: () {
                  _updateState(() {
                    _lines.clear();
                    _activeLineIndex = null;
                  });
                  _pushHistory();
                },
              )
          ],
          // Separator
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            width: 1,
            height: 24,
            color: Colors.grey.shade400,
          ),
          // Play / Pause Animacao
          IconButton(
            icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow, color: _isPlaying ? Colors.red : Colors.green),
            tooltip: _isPlaying ? 'Parar Animação' : 'Rodar Jogada',
            onPressed: () {
              _updateState(() {
                _isPlaying = !_isPlaying;
                if (_isPlaying) {
                  _playController.duration = Duration(milliseconds: (3000 / _playSpeed).round());
                  _playController.forward(from: 0.0);
                } else {
                  _playController.stop();
                }
              });
            },
          ),
          // Velocidade da Animacao
          DropdownButtonHideUnderline(
            child: DropdownButton<double>(
              value: _playSpeed,
              items: const [
                DropdownMenuItem(value: 0.5, child: Text('0.5x', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 1.0, child: Text('1x', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 1.5, child: Text('1.5x', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 2.0, child: Text('2x', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (val) {
                if (val != null) {
                  _updateState(() {
                    _playSpeed = val;
                    if (_isPlaying) {
                      _playController.duration = Duration(milliseconds: (3000 / _playSpeed).round());
                      _playController.forward(from: _playController.value);
                    }
                  });
                }
              },
            ),
          ),
          // Compartilhar
          IconButton(
            icon: _isCapturing 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.share, color: Colors.teal),
            tooltip: 'Compartilhar Tática',
            onPressed: _isCapturing ? null : () => _shareScreenshot(currentScreenshotController),
          ),
          // Maximizar
          IconButton(
            icon: Icon(isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.teal),
            tooltip: isFullScreen ? 'Minimizar' : 'Tela Cheia',
            onPressed: () {
              if (isFullScreen) {
                Navigator.of(context).pop();
              } else {
                _toggleFullScreen();
              }
            },
          ),
          // Separator
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            width: 1,
            height: 24,
            color: Colors.grey.shade400,
          ),
          // Salvar
          IconButton(
            icon: const Icon(Icons.save, color: Colors.indigo),
            tooltip: 'Salvar Tática no Firebase',
            onPressed: _isLoading ? null : _showSaveTacticDialog,
          ),
          // Carregar
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.indigo),
            tooltip: 'Carregar Tática do Firebase',
            onPressed: _isLoading ? null : _showLoadTacticDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerWidget(Player player, {bool isDragging = false, double rotation = 0.0}) {
    final isAdv = player.id.startsWith('adv_');
    final isBall = player.id.startsWith('ball_');
    final names = player.name.split(' ');
    final displayName = isAdv ? 'ADV' : isBall ? 'Bola' : (names.length > 1 ? '${names[0]} ${names.last.substring(0, 1)}.' : names[0]);
    final bgColor = isAdv ? Colors.red.shade600 : isBall ? Colors.white : Colors.orange.shade600;
    final dragColor = isAdv ? Colors.redAccent.withValues(alpha: 0.8) : isBall ? Colors.white.withValues(alpha: 0.8) : Colors.deepOrange.withValues(alpha: 0.8);
    final borderColor = isAdv ? Colors.red.shade900 : isBall ? Colors.black : Colors.orange.shade900;

    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(
            angle: rotation,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDragging ? dragColor : bgColor,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 2),
                boxShadow: [
                  if (!isDragging) const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (!isBall)
                    Positioned(
                      right: -2,
                      child: Icon(Icons.arrow_right, size: 20, color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  Center(
                    child: isBall 
                      ? const Icon(Icons.sports_soccer, color: Colors.black87, size: 24)
                      : Text(
                          isAdv ? 'A' : player.name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              displayName,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
