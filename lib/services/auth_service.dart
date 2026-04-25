import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Estado Local
  bool _isAuthenticated = false;
  String? _adminEmail;
  bool _isLoading = true;

  // Getters para a UI consumir
  bool get isAuthenticated => _isAuthenticated;
  String? get adminUsername => _adminEmail; // Mantido o getter como adminUsername para compatibilidade
  bool get isLoading => _isLoading;

  AuthService() {
    _initAuthListener();
  }

  // --- Listener de Autenticação Oficial do Firebase ---
  void _initAuthListener() {
    _auth.authStateChanges().listen((User? user) async {
      if (user != null) {
        // Verifica se o UID do usuário existe na coleção de administradores
        try {
          final doc = await _firestore.collection('admin_users').doc(user.uid).get();
          if (doc.exists) {
            _isAuthenticated = true;
            _adminEmail = user.email;
          } else {
            // Se não está na coleção de admins, não tem permissão para este painel
            await _auth.signOut();
            _isAuthenticated = false;
            _adminEmail = null;
          }
        } catch (e) {
          _isAuthenticated = false;
          _adminEmail = null;
        }
      } else {
        _isAuthenticated = false;
        _adminEmail = null;
      }
      _isLoading = false;
      notifyListeners();
    });
  }

  // --- Login ---
  Future<String?> login(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Autenticação Segura via Firebase Auth
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Validação de Segurança (Role-Based Access)
      final docSnap = await _firestore.collection('admin_users').doc(userCredential.user!.uid).get();

      if (!docSnap.exists) {
        await _auth.signOut();
        _isLoading = false;
        notifyListeners();
        return 'Acesso negado: Você não tem permissão de administrador.';
      }

      // Sucesso!
      _isAuthenticated = true;
      _adminEmail = email.trim();
      
      _isLoading = false;
      notifyListeners(); 
      return null; // Null significa sucesso (sem erro)
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      notifyListeners();
      if (e.code == 'user-not-found' || e.code == 'invalid-email') {
        return 'Administrador não encontrado ou e-mail inválido.';
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return 'Credenciais inválidas. Verifique e tente novamente.';
      }
      return 'Erro de autenticação: ${e.message}';
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Erro de conexão: $e';
    }
  }

  // --- Logout ---
  Future<void> logout() async {
    await _auth.signOut();
    _isAuthenticated = false;
    _adminEmail = null;
    notifyListeners();
  }
}