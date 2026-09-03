import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tactic_model.dart';

class TacticService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveTactic(TacticModel tactic) async {
    try {
      await _firestore.collection('tactics').doc(tactic.id).set(tactic.toJson());
    } catch (e) {
      throw Exception('Erro ao salvar tática: $e');
    }
  }

  Future<List<TacticModel>> getTactics(String teamId) async {
    try {
      final snapshot = await _firestore
          .collection('tactics')
          .where('teamId', isEqualTo: teamId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) => TacticModel.fromJson(doc.data())).toList();
    } catch (e) {
      throw Exception('Erro ao buscar táticas: $e');
    }
  }

  Future<void> deleteTactic(String id) async {
    try {
      await _firestore.collection('tactics').doc(id).delete();
    } catch (e) {
      throw Exception('Erro ao excluir tática: $e');
    }
  }
}
