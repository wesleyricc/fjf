import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/bolao_models.dart';
import '../../utils/bolao_constants.dart';
import '../../viewmodels/bolao_predictions_viewmodel.dart';
import '../../screens/bolao/bolao_match_chat_screen.dart';

class BolaoPredictionCard extends StatefulWidget {
  final BolaoMatch match;
  final BolaoPrediction? myPred;
  final BolaoUser? currentUser;
  final String userId;
  final BolaoPredictionsViewModel viewModel;
  final bool isGlobalLocked;
  final VoidCallback onRequireProfile;
  final VoidCallback onScoreSaved;

  const BolaoPredictionCard({
    super.key,
    required this.match,
    required this.myPred,
    required this.currentUser,
    required this.userId,
    required this.viewModel,
    required this.isGlobalLocked,
    required this.onRequireProfile,
    required this.onScoreSaved,
  });

  @override
  State<BolaoPredictionCard> createState() => _BolaoPredictionCardState();
}

class _BolaoPredictionCardState extends State<BolaoPredictionCard> {
  late TextEditingController _homeController;
  late TextEditingController _awayController;

  @override
  void initState() {
    super.initState();
    _homeController = TextEditingController(text: widget.myPred?.scoreHome.toString() ?? '');
    _awayController = TextEditingController(text: widget.myPred?.scoreAway.toString() ?? '');
  }

  @override
  void didUpdateWidget(BolaoPredictionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.myPred != oldWidget.myPred) {
      final newHome = widget.myPred?.scoreHome.toString() ?? '';
      final newAway = widget.myPred?.scoreAway.toString() ?? '';
      
      if (_homeController.text != newHome && !FocusScope.of(context).hasFocus) {
        _homeController.text = newHome;
      }
      if (_awayController.text != newAway && !FocusScope.of(context).hasFocus) {
        _awayController.text = newAway;
      }
    }
  }

  @override
  void dispose() {
    _homeController.dispose();
    _awayController.dispose();
    super.dispose();
  }

  void _onScoreChanged() {
    final homeStr = _homeController.text;
    final awayStr = _awayController.text;

    if (homeStr.isNotEmpty && awayStr.isNotEmpty) {
      final newHomeScore = int.parse(homeStr);
      final newAwayScore = int.parse(awayStr);

      if (widget.myPred != null && widget.myPred!.scoreHome == newHomeScore && widget.myPred!.scoreAway == newAwayScore) return; 

      widget.viewModel.savePrediction(widget.userId, widget.match.id, newHomeScore, newAwayScore);
      widget.onScoreSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isFinished = widget.match.status == 'finished';
    final bool isInProgress = widget.match.status == 'in_progress';
    final bool isLocked = widget.isGlobalLocked || widget.match.status != 'pending';

    Color badgeColor = Colors.green.shade600;
    String badgeText = "ABERTO";
    if (isFinished) { badgeColor = Colors.grey.shade700; badgeText = "FINALIZADO"; }
    else if (isInProgress) { badgeColor = Colors.red.shade600; badgeText = "AO VIVO"; }
    else if (isLocked) { badgeColor = Colors.orange.shade700; badgeText = "TRANCADO"; }

    return GestureDetector(
      onTap: () {
        if (isLocked) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => BolaoMatchChatScreen(match: widget.match, currentUser: widget.currentUser!)));
        }
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: isLocked ? 1 : 4,
        shadowColor: isLocked ? Colors.transparent : Colors.green.withOpacity(0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(colors: [Colors.white, Colors.grey.shade50], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(12)), child: Text(badgeText, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                    Text("${widget.match.date.hour.toString().padLeft(2, '0')}:${widget.match.date.minute.toString().padLeft(2, '0')} - ${widget.match.group}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                  ],
                ),
                const SizedBox(height: 16),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(child: Column(children: [Text(BolaoConstants.teamsFlagsMap[widget.match.homeTeam] ?? '❓', style: const TextStyle(fontSize: 40)), const SizedBox(height: 4), Text(widget.match.homeTeam, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))])),
                    
                    if (isFinished) 
                      _buildFinishedResult()
                    else 
                      Row(
                        children: [
                          _buildScoreInput(_homeController, isLocked),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("X", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.grey))),
                          _buildScoreInput(_awayController, isLocked),
                        ],
                      ),
                      
                    Expanded(child: Column(children: [Text(BolaoConstants.teamsFlagsMap[widget.match.awayTeam] ?? '❓', style: const TextStyle(fontSize: 40)), const SizedBox(height: 4), Text(widget.match.awayTeam, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))])),
                  ],
                ),
                
                if (isLocked)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isInProgress ? Colors.green.shade700 : const Color(0xFF1B5E20), 
                      borderRadius: BorderRadius.circular(8)
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isInProgress ? Icons.sensors : Icons.forum, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          isInProgress ? "ACOMPANHAR AO VIVO" : "VER PALPITES E RESENHA", 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)
                        ),
                      ],
                    ),
                  )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinishedResult() {
    final bool hasPredicted = widget.myPred != null;
    final int points = widget.myPred?.pointsEarned ?? 0;

    Color badgeColor = Colors.grey.shade200; Color textColor = Colors.black87;
    if (points == 5) { badgeColor = Colors.green.shade100; textColor = Colors.green.shade900; } 
    else if (points > 0) { badgeColor = Colors.blue.shade50; textColor = Colors.blue.shade900; } 
    else if (hasPredicted) { badgeColor = Colors.red.shade50; textColor = Colors.red.shade900; }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
          child: Text("${widget.match.realScoreHome ?? '-'}  x  ${widget.match.realScoreAway ?? '-'}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: textColor.withOpacity(0.3))),
          child: Column(
            children: [
              Text(hasPredicted ? "Seu Palpite: ${widget.myPred!.scoreHome} x ${widget.myPred!.scoreAway}" : "Você não palpitou", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
              if (hasPredicted) Text(points == 5 ? "Na Mosca! +5 Pts" : (points > 0 ? "Ganhou +$points Pts" : "Não pontuou"), style: TextStyle(fontSize: 10, color: textColor)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildScoreInput(TextEditingController controller, bool isLocked) {
    final bool isProfileIncomplete = widget.currentUser == null || !widget.currentUser!.isProfileComplete;

    return GestureDetector(
      onTap: () {
        if (isProfileIncomplete && !isLocked) {
           widget.onRequireProfile();
        }
      },
      child: AbsorbPointer(
        absorbing: isProfileIncomplete,
        child: SizedBox(
          width: 44, height: 44,
          child: TextField(
            controller: controller,
            enabled: !isLocked,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            maxLength: 2,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
                counterText: "",
                filled: true,
                fillColor: isLocked ? Colors.grey.shade100 : Colors.white,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onChanged: (_) => _onScoreChanged(),
          ),
        ),
      ),
    );
  }
}
