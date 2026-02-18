import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/photo_product_model.dart';

enum CheckoutStep { form, loading, pix, success }

class PhotoSalesViewModel extends ChangeNotifier {
  // --- ESTADO ---
  List<PhotoProduct> _allPhotos = [];
  bool _isLoadingPhotos = true;
  String? _errorMessage;

  // Carrinho
  final Set<PhotoProduct> _cart = {};
  
  // Checkout
  CheckoutStep _checkoutStep = CheckoutStep.form;
  String _pixCode = "";
  String _paymentId = "";
  String _customerEmail = "";
  List<PhotoProduct> _purchasedItems = []; // Itens confirmados

  // --- GETTERS (Para a View consumir) ---
  List<PhotoProduct> get allPhotos => _allPhotos;
  bool get isLoadingPhotos => _isLoadingPhotos;
  String? get errorMessage => _errorMessage;
  
  List<PhotoProduct> get cartItems => _cart.toList();
  int get cartCount => _cart.length;
  double get totalPrice => _cart.fold(0.0, (sum, item) => sum + item.price);
  
  CheckoutStep get checkoutStep => _checkoutStep;
  String get pixCode => _pixCode;
  String get customerEmail => _customerEmail;
  List<PhotoProduct> get purchasedItems => _purchasedItems;

  // --- AÇÕES ---

  // 1. Inicialização
  Future<void> loadPhotos() async {
    _isLoadingPhotos = true;
    _errorMessage = null;
    notifyListeners(); 

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('photo_sales')
          .orderBy('taken_at', descending: true)
          .get();

      _allPhotos = snapshot.docs.map((d) => PhotoProduct.fromFirestore(d)).toList();
    } catch (e) {
      _errorMessage = "Erro ao carregar fotos: $e";
    } finally {
      _isLoadingPhotos = false;
      notifyListeners();
    }
  }

  // 2. Carrinho
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

  // 3. Checkout - Preparação
  Future<void> initCheckout() async {
    _checkoutStep = CheckoutStep.form;
    _errorMessage = null;
    
    // Recupera e-mail salvo
    final prefs = await SharedPreferences.getInstance();
    _customerEmail = prefs.getString('user_email_delivery') ?? "";
    notifyListeners();
  }

  void setEmail(String email) {
    _customerEmail = email;
    notifyListeners(); 
  }

  // 4. Checkout - Gerar Pix (CORRIGIDO)
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
      // Salva preferência local
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email_delivery', _customerEmail);

      final photoIds = _cart.map((e) => e.id).toList();

      // Chamada Segura às Cloud Functions
      final result = await FirebaseFunctions.instance
          .httpsCallable('createPixPayment')
          .call({
            'photoIds': photoIds,
            'customerContact': _customerEmail,
          });

      // Validação de Integridade do Retorno
      if (result.data == null || result.data is! Map) {
        throw "O servidor retornou um formato de dados inválido.";
      }

      final data = Map<String, dynamic>.from(result.data as Map);
      _pixCode = data['pix_code']?.toString() ?? '';
      _paymentId = data['payment_id']?.toString() ?? '';

      if (_paymentId.isNotEmpty && _pixCode.isNotEmpty) {
        _checkoutStep = CheckoutStep.pix;
        _listenToPaymentStatus();
      } else {
        throw "Não foi possível gerar o código Pix. Tente novamente mais tarde.";
      }
    } on FirebaseFunctionsException catch (e) {
      _errorMessage = "Erro no servidor (${e.code}): ${e.message}";
      _checkoutStep = CheckoutStep.form;
    } catch (e) {
      _errorMessage = "Ocorreu um erro inesperado: $e";
      _checkoutStep = CheckoutStep.form;
    }
    notifyListeners();
  }

  // 5. Checkout - Monitorar Pagamento (Lógica Real-time)
  void _listenToPaymentStatus() {
    FirebaseFirestore.instance
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
    try {
      String linksHtml = "";
      for (var photo in _cart) {
         linksHtml += '<li><a href="${photo.highResUrl}">Baixar Foto</a></li>';
      }

      await FirebaseFirestore.instance.collection('mail').add({
        'to': [_customerEmail],
        'message': {
          'subject': 'Sua Foto FJF Chegou! 📸',
          'html': '''
            <div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">
              <h2 style="color: #4CAF50;">Pagamento Confirmado!</h2>
              <p>Aqui estão os links para as suas fotos em alta resolução:</p>
              <ul>$linksHtml</ul>
              <hr><p>Equipe FJF</p>
            </div>
          ''',
        },
      });
    } catch (e) {
      debugPrint("Erro ao registrar disparo de e-mail: $e");
    }

    _purchasedItems = List.from(_cart);
    _cart.clear(); 
    _checkoutStep = CheckoutStep.success;
    notifyListeners();
  }

  void resetCheckout() {
    _checkoutStep = CheckoutStep.form;
    _errorMessage = null;
    notifyListeners();
  }
}