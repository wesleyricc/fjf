import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/photo_product_model.dart';
import '../services/analytics_service.dart';
import '../services/firestore_cache_service.dart';

enum CheckoutStep { form, loading, pix, success }

class PhotoSalesViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- ESTADO GERAL ---
  bool _isOffline = false;
  String? _errorMessage;

  // --- ESTADO DOS ÁLBUNS (Leve e Barato) ---
  List<Map<String, dynamic>> _albums = [];
  bool _isLoadingAlbums = true;

  // --- ESTADO DAS FOTOS PAGINADAS (Econômico) ---
  List<PhotoProduct> _folderPhotos = [];
  bool _isLoadingPhotos = false;
  bool _isLoadingMore = false;
  bool _hasMorePhotos = true;
  DocumentSnapshot? _lastVisibleDocument;

  // --- CARRINHO E CHECKOUT ---
  final Set<PhotoProduct> _cart = {};
  CheckoutStep _checkoutStep = CheckoutStep.form;
  String _pixCode = "";
  String _paymentId = "";
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _paymentSub;
  String _customerEmail = "";
  List<PhotoProduct> _purchasedItems = []; 

  // --- GETTERS ---
  bool get isOffline => _isOffline;
  String? get errorMessage => _errorMessage;
  
  List<Map<String, dynamic>> get albums => _albums;
  bool get isLoadingAlbums => _isLoadingAlbums;
  
  List<PhotoProduct> get folderPhotos => _folderPhotos;
  bool get isLoadingPhotos => _isLoadingPhotos;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMorePhotos => _hasMorePhotos;
  
  List<PhotoProduct> get cartItems => _cart.toList();
  int get cartCount => _cart.length;
  double get totalPrice => _cart.fold(0.0, (sum, item) => sum + item.price);
  
  CheckoutStep get checkoutStep => _checkoutStep;
  String get pixCode => _pixCode;
  String get customerEmail => _customerEmail;
  List<PhotoProduct> get purchasedItems => _purchasedItems;

  // --- HELPERS ---
  Future<bool> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _isOffline = result == ConnectivityResult.none;
    notifyListeners();
    return !_isOffline;
  }

  // ==============================================================
  // 1. CARREGAR APENAS AS PASTAS (Custo Mínimo de Leitura + Cache PWA)
  // ==============================================================
  Future<void> loadAlbums({bool isRefresh = false}) async {
    if (!await _checkConnectivity()) {
      _isLoadingAlbums = false;
      notifyListeners();
      return;
    }

    _isLoadingAlbums = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final query = _firestore
          .collection('photo_albums')
          .orderBy('year', descending: true)
          .orderBy('name');

      _albums = await FirestoreCacheService.getDocsDataWithCache(
        query: query,
        cacheKey: 'photo_albums_list',
        ttl: const Duration(minutes: 15),
        forceRefresh: isRefresh,
      );
    } catch (e) {
      debugPrint("Erro ao carregar álbuns: $e");
      _errorMessage = "Não foi possível carregar as galerias.";
    } finally {
      _isLoadingAlbums = false;
      notifyListeners();
    }
  }

  // ==============================================================
  // 2. CARREGAR FOTOS DA PASTA COM PAGINAÇÃO (Economia Máxima)
  // ==============================================================
  Future<void> loadPhotosByFolder(String eventName, {bool isRefresh = false}) async {
    if (!await _checkConnectivity()) return;

    if (isRefresh) {
      _isLoadingPhotos = true;
      _folderPhotos.clear();
      _lastVisibleDocument = null;
      _hasMorePhotos = true;
      notifyListeners();
    } else {
      if (_isLoadingMore || !_hasMorePhotos) return;
      _isLoadingMore = true;
      notifyListeners();
    }

    try {
      Query query = _firestore.collection('photo_sales')
          .where('event_name', isEqualTo: eventName)
          .orderBy('taken_at', descending: true)
          .limit(30);

      if (_lastVisibleDocument != null) {
        query = query.startAfterDocument(_lastVisibleDocument!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        _lastVisibleDocument = snapshot.docs.last;
        final newPhotos = snapshot.docs.map((d) => PhotoProduct.fromFirestore(d)).toList();
        _folderPhotos.addAll(newPhotos);
        
        if (snapshot.docs.length < 30) {
          _hasMorePhotos = false;
        }
      } else {
        _hasMorePhotos = false;
      }
      _errorMessage = null;
    } catch (e) {
      debugPrint("Erro ao paginar fotos: $e");
      if (isRefresh) _errorMessage = "Erro ao carregar fotos desta pasta.";
    } finally {
      _isLoadingPhotos = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // ==============================================================
  // CARRINHO E CHECKOUT
  // ==============================================================
  void toggleCartItem(PhotoProduct photo) {
    if (_cart.contains(photo)) {
      _cart.remove(photo);
    } else {
      _cart.add(photo);
    }
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  Future<void> initCheckout() async {
    _checkoutStep = CheckoutStep.form;
    _errorMessage = null;
    
    final prefs = await SharedPreferences.getInstance();
    _customerEmail = prefs.getString('user_email_delivery') ?? "";
    notifyListeners();
  }

  void setEmail(String email) {
    _customerEmail = email;
    notifyListeners(); 
  }

  Future<void> generatePix() async {
    if (_customerEmail.isEmpty || !_customerEmail.contains('@')) {
      _errorMessage = "Por favor, informe um e-mail válido para entrega.";
      notifyListeners();
      return;
    }

    _checkoutStep = CheckoutStep.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email_delivery', _customerEmail);

      final photoIds = _cart.map((e) => e.id).toList();

      final result = await FirebaseFunctions.instance
          .httpsCallable('createPixPayment')
          .call({
            'photoIds': photoIds,
            'customerContact': _customerEmail,
          });

      if (result.data == null || result.data is! Map) {
        throw "O servidor retornou um formato de dados inválido.";
      }

      final data = Map<String, dynamic>.from(result.data as Map);
      _pixCode = data['pix_code']?.toString() ?? '';
      _paymentId = data['payment_id']?.toString() ?? '';

      if (_pixCode.isEmpty || _paymentId.isEmpty) {
        throw "Dados do PIX incompletos recebidos do servidor.";
      }

      // 🚨 RASTREAMENTO DE INTENÇÃO DE COMPRA (PIX GERADO)
      AnalyticsService.logBeginCheckout(
        type: 'photo_pack',
        totalValue: totalPrice,
        itemCount: _cart.length,
      );

      _checkoutStep = CheckoutStep.pix;
      _listenToPaymentStatus();
      
    } on FirebaseFunctionsException catch (e) {
      debugPrint("Erro na Cloud Function: ${e.code} - ${e.message}");
      _errorMessage = "Erro no servidor (${e.code}): ${e.message}";
      _checkoutStep = CheckoutStep.form;
    } catch (e) {
      _errorMessage = "Ocorreu um erro inesperado: $e";
      _checkoutStep = CheckoutStep.form;
    }
    notifyListeners();
  }

  void _listenToPaymentStatus() {
    _paymentSub?.cancel();
    _paymentSub = FirebaseFirestore.instance
        .collection('orders')
        .doc(_paymentId)
        .snapshots()
        .listen((snapshot) {
      
      if (!snapshot.exists) return;
      
      final data = snapshot.data()!;
      final status = data['status'] ?? 'pending';

      if ((status == 'approved' || status == 'paid') && _checkoutStep == CheckoutStep.pix) {
        _finalizeSuccess();
      }
    }, onError: (err) {
      debugPrint("Erro ao monitorar pagamento: $err");
    });
  }

  Future<void> _finalizeSuccess() async {
    _paymentSub?.cancel();
    _paymentSub = null;
    _purchasedItems = List.from(_cart);
    _cart.clear(); 
    _checkoutStep = CheckoutStep.success;
    notifyListeners();
  }

  void resetCheckout() {
    _paymentSub?.cancel();
    _paymentSub = null;
    _checkoutStep = CheckoutStep.form;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _paymentSub?.cancel();
    super.dispose();
  }
}
