import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fantasy_league_model.dart';
import '../models/fantasy_models.dart';

class FantasyLeagueService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🚨 OTIMIZAÇÃO FINOPS: Cache de Rankings de Ligas Privadas
  final Map<String, List<Map<String, dynamic>>> _rankingCache = {};
  final Map<String, DateTime> _lastRankingFetch = {};

  // Gerador de código estilo "X7B9K2"
  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  // 1. Criar Liga
  Future<String> createLeague(String name, String userId, {String type = 'classic', int? maxTeams, String? imageUrl}) async {
    final String inviteCode = _generateInviteCode();
    
    final newLeague = FantasyLeague(
      id: '', 
      name: name.trim(),
      inviteCode: inviteCode,
      ownerId: userId,
      members: [userId], 
      type: type,
      maxTeams: maxTeams,
      status: type == 'knockout' ? 'waiting' : 'active',
      imageUrl: imageUrl,
    );

    await _firestore.collection('fantasy_leagues').add(newLeague.toMap());
    return inviteCode;
  }

  // 2. Entrar na Liga com Código
  Future<String?> joinLeague(String inviteCode, String userId) async {
    String cleanCode = inviteCode.trim().toUpperCase();
    if (cleanCode.startsWith('FJF-')) {
      cleanCode = cleanCode.substring(4).trim();
    }

    final query = await _firestore
        .collection('fantasy_leagues')
        .where('invite_code', isEqualTo: cleanCode)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return "Código inválido. Nenhuma liga encontrada.";
    }

    final doc = query.docs.first;
    final data = doc.data();
    final List<dynamic> currentMembers = data['members'] ?? [];

    if (currentMembers.contains(userId)) {
      return "Você já participa desta liga!";
    }

    final int? maxTeams = data['max_teams'];
    if (maxTeams != null && currentMembers.length >= maxTeams) {
      return "A liga já atingiu o limite máximo de times ($maxTeams).";
    }

    await doc.reference.update({
      'members': FieldValue.arrayUnion([userId])
    });

    return null; 
  }

  // 2.1. Entrar em Liga Patrocinada (Sem Código)
  Future<String?> joinSponsoredLeague(String leagueId, String userId) async {
    final doc = await _firestore.collection('fantasy_leagues').doc(leagueId).get();

    if (!doc.exists) {
      return "Liga não encontrada.";
    }

    final data = doc.data()!;
    final bool isSponsored = data['is_sponsored'] ?? false;
    
    if (!isSponsored) {
      return "Esta não é uma liga patrocinada aberta.";
    }

    final List<dynamic> currentMembers = data['members'] ?? [];

    if (currentMembers.contains(userId)) {
      return "Você já participa desta liga!";
    }

    await doc.reference.update({
      'members': FieldValue.arrayUnion([userId])
    });

    return null; 
  }

  // 2.2 Sair de uma Liga
  Future<String?> leaveLeague(String leagueId, String userId) async {
    final doc = await _firestore.collection('fantasy_leagues').doc(leagueId).get();

    if (!doc.exists) {
      return "Liga não encontrada.";
    }

    final data = doc.data()!;
    final String ownerId = data['owner_id'] ?? '';

    if (ownerId == userId) {
      return "O dono da liga não pode sair. Exclua a liga se desejar encerrá-la.";
    }

    await doc.reference.update({
      'members': FieldValue.arrayRemove([userId])
    });

    return null;
  }

  // 3. Escutar as Ligas do Usuário
  Stream<List<FantasyLeague>> streamMyLeagues(String userId) {
    return _firestore
        .collection('fantasy_leagues')
        .where('members', arrayContains: userId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => FantasyLeague.fromFirestore(doc)).toList());
  }

  // 3.1. Escutar Ligas Patrocinadas
  Stream<List<FantasyLeague>> streamSponsoredLeagues() {
    return _firestore
        .collection('fantasy_leagues')
        .where('is_sponsored', isEqualTo: true)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => FantasyLeague.fromFirestore(doc)).toList());
  }

  // =================================================================
  // 🚨 4. BUSCAR RANKING DA LIGA (COM CACHE E BATCHING)
  // =================================================================
  Future<List<Map<String, dynamic>>> getLeagueRanking(FantasyLeague league, {bool forceRefresh = false}) async {
    final now = DateTime.now();
    final lastFetch = _lastRankingFetch[league.id];

    // Verifica se temos os dados em cache e se têm menos de 15 minutos
    if (!forceRefresh && _rankingCache.containsKey(league.id) && lastFetch != null) {
      if (now.difference(lastFetch).inMinutes < 15) {
        return _rankingCache[league.id]!;
      }
    }

    final List<Map<String, dynamic>> teamsData = [];
    final members = league.members;
    
    // ⚡ OTIMIZAÇÃO DE VELOCIDADE & LATÊNCIA:
    // O Firestore aceita até 30 itens no operador 'whereIn'. 
    // Fatiamos em blocos de até 30 e executamos as buscas em PARALELO via Future.wait.
    final List<List<dynamic>> chunks = [];
    for (var i = 0; i < members.length; i += 30) {
      chunks.add(members.sublist(i, i + 30 > members.length ? members.length : i + 30));
    }

    final queryFutures = chunks.map((chunk) => _firestore
        .collection('fantasy_teams')
        .where(FieldPath.documentId, whereIn: chunk)
        .get());

    final snapshots = await Future.wait(queryFutures);

    for (var snap in snapshots) {
      for (var doc in snap.docs) {
        final data = doc.data();
        data['uid'] = doc.id;
        teamsData.add(data);
      }
    }

    // 🚨 ORDENAÇÃO LOCAL
    teamsData.sort((a, b) {
      final double pointsA = (a['total_points'] ?? 0.0).toDouble();
      final double pointsB = (b['total_points'] ?? 0.0).toDouble();
      return pointsB.compareTo(pointsA); 
    });

    // Guardar no Cache Local
    _rankingCache[league.id] = teamsData;
    _lastRankingFetch[league.id] = now;

    return teamsData;
  }

  // =================================================================
  // 5. LIGAS MATA-MATA (GERAR CHAVES)
  // =================================================================
  Future<String> generateBracket(FantasyLeague league) async {
    if (league.type != 'knockout') return "Esta liga não é mata-mata.";
    if (league.members.length != league.maxTeams) return "A liga não atingiu a lotação máxima para sortear.";

    try {
      final statusDoc = await _firestore.collection('fantasy_config').doc('status').get();
      int currentRound = 1;
      if (statusDoc.exists) {
        currentRound = statusDoc.data()?['current_round'] ?? 1;
      }
      final int startRound = currentRound + 1;
      
      // Validação de Rodadas Restantes
      const int TOTAL_FANTASY_ROUNDS = 10; // 7 Fase de Grupos + 3 Mata-Mata
      final int roundsNeeded = (log(league.members.length) / ln2).toInt();
      final int roundsAvailable = TOTAL_FANTASY_ROUNDS - startRound + 1;
      
      if (roundsAvailable < roundsNeeded) {
        return "Não há rodadas suficientes restantes no campeonato para finalizar esta liga. Crie uma liga menor.";
      }

      final batch = _firestore.batch();
      final members = List<String>.from(league.members)..shuffle(); 
      
      final int count = members.length;
      final int matchesCount = count ~/ 2; 
      
      String phase;
      if (count == 4) phase = 'Semi';
      else if (count == 8) phase = 'Quartas';
      else if (count == 16) phase = 'Oitavas';
      else phase = 'Dezesseis-Avos';

      for (int i = 0; i < matchesCount; i++) {
        final matchDoc = _firestore.collection('fantasy_leagues').doc(league.id).collection('matches').doc();
        final teamA = members[i * 2];
        final teamB = members[i * 2 + 1];

        final matchData = KnockoutMatch(
          id: matchDoc.id,
          phase: phase,
          round: startRound,
          teamAId: teamA,
          teamBId: teamB,
          matchIndex: i,
        );
        batch.set(matchDoc, matchData.toMap());
      }

      final leagueRef = _firestore.collection('fantasy_leagues').doc(league.id);
      batch.update(leagueRef, {
        'status': 'active',
        'start_round': startRound,
      });

      await batch.commit();
      return "Sucesso";
    } catch (e) {
      return "Erro ao gerar chaveamento: $e";
    }
  }

  Stream<List<KnockoutMatch>> streamKnockoutMatches(String leagueId) {
    return _firestore
        .collection('fantasy_leagues')
        .doc(leagueId)
        .collection('matches')
        .orderBy('round')
        .orderBy('match_index')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => KnockoutMatch.fromFirestore(doc)).toList());
  }

  // =================================================================
  // 6. GERENCIAMENTO DE LIGAS (DONO DA LIGA)
  // =================================================================

  // Escutar uma liga específica em tempo real
  Stream<FantasyLeague> streamLeague(String leagueId) {
    return _firestore
        .collection('fantasy_leagues')
        .doc(leagueId)
        .snapshots()
        .map((snap) => FantasyLeague.fromFirestore(snap));
  }

  // Upload da imagem/escudo da liga para o Firebase Storage
  Future<String?> uploadLeagueImage(String leagueId, XFile imageFile) async {
    try {
      final fileName = 'league_${leagueId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance
          .ref()
          .child('fantasy_leagues_images')
          .child(fileName);

      if (kIsWeb) {
        final bytes = await imageFile.readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg', cacheControl: 'public, max-age=31536000'));
      } else {
        await ref.putFile(File(imageFile.path), SettableMetadata(contentType: 'image/jpeg'));
      }

      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint("Erro ao fazer upload da imagem da liga: $e");
      return null;
    }
  }

  // Atualizar dados cadastrais da liga (Nome e Imagem)
  Future<String?> updateLeagueInfo(
    String leagueId,
    String ownerId, {
    required String newName,
    String? newImageUrl,
    bool removeImage = false,
  }) async {
    try {
      final doc = await _firestore.collection('fantasy_leagues').doc(leagueId).get();
      if (!doc.exists) return "Liga não encontrada.";

      final data = doc.data()!;
      if (data['owner_id'] != ownerId) {
        return "Apenas o dono pode alterar as informações desta liga.";
      }

      final Map<String, dynamic> updates = {
        'name': newName.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (removeImage) {
        updates['image_url'] = FieldValue.delete();
        updates['logo_url'] = FieldValue.delete();
      } else if (newImageUrl != null && newImageUrl.isNotEmpty) {
        updates['image_url'] = newImageUrl;
        updates['logo_url'] = newImageUrl;
      }

      await doc.reference.update(updates);
      _rankingCache.remove(leagueId);
      return null;
    } catch (e) {
      return "Erro ao atualizar informações da liga: $e";
    }
  }

  // Buscar detalhes dos times dos participantes da liga
  Future<List<FantasyTeam>> getLeagueMembersTeams(List<String> memberIds) async {
    if (memberIds.isEmpty) return [];

    final List<FantasyTeam> teams = [];
    final List<List<String>> chunks = [];
    for (var i = 0; i < memberIds.length; i += 30) {
      chunks.add(memberIds.sublist(
          i, i + 30 > memberIds.length ? memberIds.length : i + 30));
    }

    final queryFutures = chunks.map((chunk) => _firestore
        .collection('fantasy_teams')
        .where(FieldPath.documentId, whereIn: chunk)
        .get());

    final snapshots = await Future.wait(queryFutures);
    final Set<String> foundIds = {};

    for (var snap in snapshots) {
      for (var doc in snap.docs) {
        teams.add(FantasyTeam.fromFirestore(doc));
        foundIds.add(doc.id);
      }
    }

    // Fallback para participantes que ainda não definiram nome do time
    for (var id in memberIds) {
      if (!foundIds.contains(id)) {
        teams.add(FantasyTeam(
          id: id,
          userId: id,
          ownerId: id,
          ownerName: 'Participante',
          teamName: 'Time Pendente',
          totalPoints: 0.0,
          lastScore: 0.0,
          teamValue: 50.0,
          currentBalance: 50.0,
          lineupPlayerIds: const [],
          shieldType: '1',
        ));
      }
    }

    return teams;
  }

  // Remover participante da liga (ação de moderação do dono)
  Future<String?> removeMemberFromLeague(String leagueId, String memberId) async {
    try {
      final doc = await _firestore.collection('fantasy_leagues').doc(leagueId).get();
      if (!doc.exists) return "Liga não encontrada.";

      final data = doc.data()!;
      final String ownerId = data['owner_id'] ?? '';
      if (memberId == ownerId) {
        return "Não é possível remover o próprio dono da liga.";
      }

      final String type = data['type'] ?? 'classic';
      final String status = data['status'] ?? 'active';
      if (type == 'knockout' && status == 'active') {
        return "Não é possível remover participantes de um mata-mata já iniciado.";
      }

      await doc.reference.update({
        'members': FieldValue.arrayRemove([memberId]),
      });

      _rankingCache.remove(leagueId);
      return null;
    } catch (e) {
      return "Erro ao remover participante: $e";
    }
  }

  // Transferir administração/liderança da liga para outro participante
  Future<String?> transferLeagueOwnership(
      String leagueId, String currentOwnerId, String newOwnerId) async {
    try {
      final doc = await _firestore.collection('fantasy_leagues').doc(leagueId).get();
      if (!doc.exists) return "Liga não encontrada.";

      final data = doc.data()!;
      if (data['owner_id'] != currentOwnerId) {
        return "Apenas o dono atual pode transferir a administração.";
      }

      final List<dynamic> members = data['members'] ?? [];
      if (!members.contains(newOwnerId)) {
        return "O novo dono precisa ser participante da liga.";
      }

      await doc.reference.update({
        'owner_id': newOwnerId,
        'updated_at': FieldValue.serverTimestamp(),
      });

      _rankingCache.remove(leagueId);
      return null;
    } catch (e) {
      return "Erro ao transferir posse da liga: $e";
    }
  }

  // Excluir permanentemente a liga
  Future<String?> deleteLeague(String leagueId, String ownerId) async {
    try {
      final doc = await _firestore.collection('fantasy_leagues').doc(leagueId).get();
      if (!doc.exists) return "Liga não encontrada.";

      final data = doc.data()!;
      if (data['owner_id'] != ownerId) {
        return "Apenas o dono pode excluir esta liga.";
      }

      // Exclui confrontos vinculados se for mata-mata
      final matchesSnap = await doc.reference.collection('matches').get();
      final batch = _firestore.batch();
      for (var mDoc in matchesSnap.docs) {
        batch.delete(mDoc.reference);
      }
      batch.delete(doc.reference);
      await batch.commit();

      _rankingCache.remove(leagueId);
      return null;
    } catch (e) {
      return "Erro ao excluir a liga: $e";
    }
  }
}