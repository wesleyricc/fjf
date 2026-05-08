import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fantasy_league_model.dart';

class FantasyLeagueService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Gerador de código estilo "X7B9K2"
  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  // 1. Criar Liga
  Future<String> createLeague(String name, String userId) async {
    final String inviteCode = _generateInviteCode();
    
    final newLeague = FantasyLeague(
      id: '', // O Firestore vai gerar
      name: name.trim(),
      inviteCode: inviteCode,
      ownerId: userId,
      members: [userId], // O criador já entra como primeiro membro
    );

    await _firestore.collection('fantasy_leagues').add(newLeague.toMap());
    return inviteCode;
  }

  // 2. Entrar na Liga com Código
  Future<String?> joinLeague(String inviteCode, String userId) async {
    final String cleanCode = inviteCode.trim().toUpperCase();

    // Busca a liga por código
    final query = await _firestore
        .collection('fantasy_leagues')
        .where('invite_code', isEqualTo: cleanCode)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return "Código inválido. Nenhuma liga encontrada.";
    }

    final doc = query.docs.first;
    final List<dynamic> currentMembers = doc.data()['members'] ?? [];

    if (currentMembers.contains(userId)) {
      return "Você já participa desta liga!";
    }

    // 🚀 Otimização: arrayUnion adiciona sem precisar ler todos os dados antes
    await doc.reference.update({
      'members': FieldValue.arrayUnion([userId])
    });

    return null; // Null significa Sucesso (sem erro)
  }

  // 3. Escutar as Ligas do Usuário (Para listar na tela dele)
  Stream<List<FantasyLeague>> streamMyLeagues(String userId) {
    return _firestore
        .collection('fantasy_leagues')
        .where('members', arrayContains: userId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => FantasyLeague.fromFirestore(doc)).toList());
  }
}