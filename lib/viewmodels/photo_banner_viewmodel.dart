import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/photo_product_model.dart';

class PhotoBannerViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  PhotoProduct? _latestPhotoProduct;
  bool _isLoading = false;

  PhotoProduct? get latestPhotoProduct => _latestPhotoProduct;
  bool get isLoading => _isLoading;

  Future<void> loadLatestPhoto({bool force = false}) async {
    if (!force && _latestPhotoProduct != null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('photo_sales')
          .orderBy('taken_at', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        _latestPhotoProduct = PhotoProduct.fromFirestore(snapshot.docs.first);
      }
    } catch (e) {
      debugPrint("Erro ao carregar foto do banner: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}