import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'analytics_service.dart';

const String environment = String.fromEnvironment('ENV', defaultValue: 'prod');

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Chaves mantidas e seguras
  final String _prodWebClientId = '893803829585-jp8uuugt42m2qknabm4lene03mimllai.apps.googleusercontent.com';
  final String _testWebClientId = '39829597186-27ckegqg46o1e825k19drdsdfdgtu99u.apps.googleusercontent.com';

  late final GoogleSignIn _googleSignIn;
  
  bool _isAuthenticated = false;
  bool _isAdmin = false;
  bool _isPresident = false;
  String? _adminEmail;
  bool _isLoading = true;

  bool get isAuthenticated => _isAuthenticated;
  bool get isAdmin => _isAdmin;
  bool get isPresident => _isPresident;
  String? get adminEmail => _adminEmail; 
  bool get isLoading => _isLoading;

  AuthService() {
    // Inicialização correta com as chaves para Web
    _googleSignIn = GoogleSignIn(
      clientId: kIsWeb 
          ? (environment == 'test' ? _testWebClientId : _prodWebClientId) 
          : null,
    );
    _initAuthListener();
  }

  void _initAuthListener() {
    _auth.authStateChanges().listen((User? user) async {
      if (user != null) {
        await _validateUserRoles(user);
      } else {
        _clearAuthData();
      }
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> _validateUserRoles(User user) async {
    try {
      final uid = user.uid;
      final results = await Future.wait([
        _firestore.collection('admin_users').doc(uid).get(),
        _firestore.collection('president_users').doc(uid).get(),
      ]);

      _isAdmin = results[0].exists;
      _isPresident = results[1].exists;

      String userRole = 'user';

      if (_isAdmin || _isPresident) {
        _isAuthenticated = true;
        _adminEmail = user.email;
        if (_isAdmin) userRole = 'admin';
        else if (_isPresident) userRole = 'president';
      } else {
        _isAuthenticated = false;
      }

      // 🚨 MANDA A TAG PARA O GOOGLE ANALYTICS
      AnalyticsService.setUserProperties(userId: uid, role: userRole);

    } catch (e) {
      debugPrint("⛔ ERRO DE PERMISSÃO AO LER CARGOS: $e");
      _clearAuthData();
    }
  }

  void _clearAuthData() {
    _isAuthenticated = false;
    _isAdmin = false;
    _isPresident = false;
    _adminEmail = null;
  }

  Future<String?> signInWithGoogle() async {
    try {
      _isLoading = true;
      notifyListeners();

      // Fluxo direto e limpo usando o pacote Google Sign In
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        _isLoading = false;
        notifyListeners();
        return "Login cancelado.";
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        await _validateUserRoles(user);
        
        if (!_isAdmin && !_isPresident) {
          _isLoading = false;
          notifyListeners();
          return 'Acesso negado: Seu e-mail não está cadastrado como Administrador ou Presidente.';
        }
      }

      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Erro ao entrar com Google: $e';
    }
  }

  Future<void> logout() async {
    if (!kIsWeb) {
      await _googleSignIn.signOut();
    }
    await _auth.signOut();
    _clearAuthData();
    notifyListeners();
  }
}