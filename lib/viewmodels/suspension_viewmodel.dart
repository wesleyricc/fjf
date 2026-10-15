import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/player_model.dart';

class SuspensionViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<DocumentSnapshot> _suspensions = [];
  final Map<String, Player> _playersById = {};
  bool _isLoading = false;
  bool _hasLoaded = false;

  List<DocumentSnapshot> get suspensions => _suspensions;
  Map<String, Player> get playersById => _playersById;
  bool get isLoading => _isLoading;

  // 🚨 LAZY LOADING: Poupa centenas de leituras no Splash Screen global
  Future<void> loadSuspensions(String seasonId, {bool force = false}) async {
    if (seasonId.isEmpty) return;
    if (!force && _hasLoaded) return;

    _isLoading = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('disciplinary_log')
          .orderBy('timestamp', descending: true)
          .get();

      _suspensions = snapshot.docs;
      _hasLoaded = true;

      if (force) {
        _playersById.clear();
      }

      // 🚨 FINOPS: Busca apenas os atletas específicos presentes nas suspensões
      final Set<String> playerIds = _suspensions
          .map((d) {
            final data = d.data() as Map<String, dynamic>?;
            return data?['playerId'] as String? ?? '';
          })
          .where((id) => id.isNotEmpty)
          .toSet();

      final List<String> toFetch = playerIds.where((id) => !_playersById.containsKey(id)).toList();

      if (toFetch.isNotEmpty) {
        for (var i = 0; i < toFetch.length; i += 30) {
          final end = (i + 30 < toFetch.length) ? i + 30 : toFetch.length;
          final chunk = toFetch.sublist(i, end);

          try {
            final pSnap = await _firestore
                .collection('championships')
                .doc(seasonId)
                .collection('player_stats')
                .where(FieldPath.documentId, whereIn: chunk)
                .get();

            for (var doc in pSnap.docs) {
              _playersById[doc.id] = Player.fromFirestore(doc);
            }
          } catch (e) {
            debugPrint("Erro ao carregar atletas suspensos: $e");
          }
        }

        // Fallback para atletas que possam estar apenas na coleção global /players
        final missingIds = toFetch.where((id) => !_playersById.containsKey(id)).toList();
        if (missingIds.isNotEmpty) {
          for (var i = 0; i < missingIds.length; i += 30) {
            final end = (i + 30 < missingIds.length) ? i + 30 : missingIds.length;
            final chunk = missingIds.sublist(i, end);

            try {
              final gSnap = await _firestore
                  .collection('players')
                  .where(FieldPath.documentId, whereIn: chunk)
                  .get();

              for (var doc in gSnap.docs) {
                _playersById[doc.id] = Player.fromFirestore(doc);
              }
            } catch (e) {
              debugPrint("Erro ao buscar jogadores globais: $e");
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Erro ao carregar suspensões: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}