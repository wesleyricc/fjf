import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  
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
    _initAuthListener();
  }

  // Monitora o estado da autenticação em tempo real
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

  // Valida as permissões nas coleções do Firestore
  Future<void> _validateUserRoles(User user) async {
    try {
      final uid = user.uid;
      final results = await Future.wait([
        _firestore.collection('admin_users').doc(uid).get(),
        _firestore.collection('president_users').doc(uid).get(),
      ]);

      _isAdmin = results[0].exists;
      _isPresident = results[1].exists;

      if (_isAdmin || _isPresident) {
        _isAuthenticated = true;
        _adminEmail = user.email;
      } else {
        _isAuthenticated = false;
      }
    } catch (e) {
      // 🚨 ADICIONE ESTA LINHA PARA O CONSOLE TE CONTAR O MOTIVO DO ERRO
      debugPrint("🔥 ERRO DE PERMISSÃO AO LER CARGOS: $e"); 
      _clearAuthData();
    }
  }

  void _clearAuthData() {
    _isAuthenticated = false;
    _isAdmin = false;
    _isPresident = false;
    _adminEmail = null;
  }

  // --- O NOVO LOGIN COM GMAIL ---
  Future<String?> signInWithGoogle() async {
    try {
      _isLoading = true;
      notifyListeners();

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
    await _googleSignIn.signOut();
    await _auth.signOut();
    _clearAuthData();
    notifyListeners();
  }
}