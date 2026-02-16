import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class MediaService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(bucket: "fjfapp.firebasestorage.app");

  CollectionReference _getMediaRef(String seasonId) {
    return _firestore.collection('championships').doc(seasonId).collection('news');
  }

  Future<int> getNextMediaOrder(String seasonId) async {
    try {
      final snapshot = await _getMediaRef(seasonId).orderBy('order', descending: true).limit(1).get();
      if (snapshot.docs.isEmpty) return 1;
      final lastOrder = (snapshot.docs.first.data() as Map<String, dynamic>)['order'] as num? ?? 0;
      return lastOrder.toInt() + 1;
    } catch (e) {
      return 1;
    }
  }

  Future<String> createMediaItem({
    required String seasonId,
    required String title,
    required String targetUrl,
    required String imageUrl,
    required int order,
    required String author,
  }) async {
    try {
      await _getMediaRef(seasonId).add({
        'title': title,
        'targetUrl': targetUrl,
        'imageUrl': imageUrl,
        'order': order,
        'author': author,
        'isActive': true
      });
      return "Sucesso: Mídia criada.";
    } catch (e) {
      return "Erro: $e";
    }
  }

  Future<String> updateMediaItem({
    required String seasonId,
    required String docId,
    required String title,
    required String targetUrl,
    required String imageUrl,
    required int order,
    required String author,
  }) async {
    try {
      await _getMediaRef(seasonId).doc(docId).update({
        'title': title,
        'targetUrl': targetUrl,
        'imageUrl': imageUrl,
        'order': order,
        'author': author
      });
      return "Sucesso: Mídia atualizada.";
    } catch (e) {
      return "Erro: $e";
    }
  }

  Future<String> deleteMediaItem(DocumentSnapshot doc, String seasonId) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      if (data['imageUrl'] != null && data['imageUrl'].toString().isNotEmpty) {
        try {
          await _storage.refFromURL(data['imageUrl']).delete();
        } catch (_) {}
      }
      await doc.reference.delete();
      return "Sucesso: Mídia deletada.";
    } catch (e) {
      return "Erro: $e";
    }
  }
}