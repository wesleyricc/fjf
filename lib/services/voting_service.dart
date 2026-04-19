import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/poll_model.dart';
import '../models/player_model.dart';

class VotingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<Poll>> streamActivePolls(String seasonId) {
    if (seasonId.isEmpty) return Stream.value([]);
    return _db
        .collection('championships')
        .doc(seasonId)
        .collection('polls')
        .where('is_active', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Poll.fromFirestore(doc)).toList());
  }

  Stream<List<Nominee>> streamNominees(String seasonId, String pollId) {
    return _db
        .collection('championships')
        .doc(seasonId)
        .collection('polls')
        .doc(pollId)
        .collection('nominees')
        .orderBy('vote_count', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Nominee.fromFirestore(doc)).toList());
  }

  Future<bool> hasUserVoted(String seasonId, String pollId, String userId) async {
    final doc = await _db
        .collection('championships')
        .doc(seasonId)
        .collection('polls')
        .doc(pollId)
        .collection('votes')
        .doc(userId)
        .get();
    return doc.exists;
  }

  // --- VOTAÇÃO SIMPLES E LIVRE ---
  Future<String> castVote({
    required String seasonId,
    required String pollId,
    required String userId,
    String? existingNomineeId, 
    Player? freePlayerPick,    
  }) async {
    try {
      final pollRef = _db.collection('championships').doc(seasonId).collection('polls').doc(pollId);
      final voteRef = pollRef.collection('votes').doc(userId);
      
      final nomineeId = existingNomineeId ?? freePlayerPick!.id;
      final nomineeRef = pollRef.collection('nominees').doc(nomineeId);

      return await _db.runTransaction((transaction) async {
        // =======================================================
        // 1. LEITURAS OBRIGATÓRIAS (TODOS OS GETS PRIMEIRO)
        // =======================================================
        final voteSnapshot = await transaction.get(voteRef);
        final nomineeSnapshot = await transaction.get(nomineeRef);

        if (voteSnapshot.exists) {
          return "Você já votou nesta categoria!";
        }

        // =======================================================
        // 2. GRAVAÇÕES E ATUALIZAÇÕES
        // =======================================================
        // Grava o Voto do Usuário
        transaction.set(voteRef, {
          'nominee_id': nomineeId,
          'timestamp': FieldValue.serverTimestamp(),
        });

        // Atualiza ou Cria o Indicado
        if (nomineeSnapshot.exists) {
          transaction.update(nomineeRef, {
            'vote_count': FieldValue.increment(1),
          });
        } else {
          if (freePlayerPick == null) throw Exception("Dados do jogador ausentes.");
          transaction.set(nomineeRef, {
            'player_id': freePlayerPick.id,
            'player_name': freePlayerPick.name,
            'player_photo_url': freePlayerPick.photoUrl,
            'team_name': freePlayerPick.teamName,
            'team_shield_url': freePlayerPick.teamShieldUrl,
            'vote_count': 1,
          });
        }

        return "Sucesso";
      });
    } catch (e) {
      return "Erro ao processar voto: $e";
    }
  }

  // --- VOTAÇÃO DA SELEÇÃO (DRAFT - 11 JOGADORES) ---
  Future<String> castDraftVote({
    required String seasonId,
    required String pollId,
    required String userId,
    required List<Player> selectedPlayers,
  }) async {
    try {
      final pollRef = _db.collection('championships').doc(seasonId).collection('polls').doc(pollId);
      final voteRef = pollRef.collection('votes').doc(userId);

      return await _db.runTransaction((transaction) async {
        // =======================================================
        // 1. LEITURAS OBRIGATÓRIAS (TODOS OS GETS PRIMEIRO)
        // =======================================================
        final voteSnapshot = await transaction.get(voteRef);
        if (voteSnapshot.exists) {
          return "Você já escalou sua Seleção do Campeonato!";
        }

        // Lê o status de todos os 11 jogadores selecionados antes de gravar
        Map<String, DocumentSnapshot> nomineesSnaps = {};
        for (var player in selectedPlayers) {
          final nomineeRef = pollRef.collection('nominees').doc(player.id);
          nomineesSnaps[player.id] = await transaction.get(nomineeRef);
        }

        // =======================================================
        // 2. GRAVAÇÕES E ATUALIZAÇÕES
        // =======================================================
        // Grava o "Recibo" de voto do Usuário
        transaction.set(voteRef, {
          'type': 'draft_selection',
          'timestamp': FieldValue.serverTimestamp(),
        });

        // Loop pelos 11 selecionados para computar +1 voto para cada
        for (var player in selectedPlayers) {
          final nomineeRef = pollRef.collection('nominees').doc(player.id);
          final nomineeSnap = nomineesSnaps[player.id]!;

          if (nomineeSnap.exists) {
            transaction.update(nomineeRef, {
              'vote_count': FieldValue.increment(1),
            });
          } else {
            transaction.set(nomineeRef, {
              'player_id': player.id,
              'player_name': player.name,
              'player_photo_url': player.photoUrl,
              'team_name': player.teamName,
              'team_shield_url': player.teamShieldUrl,
              'vote_count': 1,
            });
          }
        }

        return "Sucesso";
      });
    } catch (e) {
      return "Erro ao salvar seleção: $e";
    }
  }
}