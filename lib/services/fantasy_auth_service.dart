import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'fantasy_service.dart';

class FantasyAuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // ---> COLE O SEU WEB CLIENT ID AQUI <---
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? '893803829585-jp8uuugt42m2qknabm4lene03mimllai.apps.googleusercontent.com' : null,
  );

  final FantasyService _fantasyService; 

  User? _user;
  bool _isLoading = false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;

  FantasyAuthService(this._fantasyService) {
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  Future<String?> signInWithGoogle() async {
    try {
      _setLoading(true);

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _setLoading(false);
        return "Login cancelado pelo usuário."; 
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 1. Faz o login no Firebase
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        // 🚨 TRUQUE SÊNIOR V2: RETRY LOOP PARA LATÊNCIA DE REDE 🚨
        // Força a renovação e propagação do Token de Acesso
        await user.getIdToken(true);
        
        bool isTokenPropagated = false;
        int attempts = 0;
        
        while (!isTokenPropagated && attempts < 5) {
          attempts++;
          try {
            // Tempo progressivo: 600ms, 1200ms, 1800ms... 
            // Dá o tempo exato que a rede do usuário precisar!
            await Future.delayed(Duration(milliseconds: 600 * attempts));
            
            // 2. Garante que o time existe no banco
            final docSnap = await FirebaseFirestore.instance
                .collection('fantasy_teams')
                .doc(user.uid)
                .get(const GetOptions(source: Source.server)); // 🚨 FORÇA BUSCAR NO SERVIDOR E IGNORAR CACHE CORROMPIDO DA WEB

            // Se chegou aqui, a permissão foi concedida pelo Firestore!
            if (!docSnap.exists) {
              await _fantasyService.createUserTeam(
                userId: user.uid,
                userName: user.displayName ?? 'Treinador',
                teamName: 'Time de ${user.displayName?.split(' ').first ?? 'Treinador'}',
              );
            }
            
            isTokenPropagated = true; // Sucesso! Sai do loop.
          } catch (e) {
            final errorStr = e.toString().toLowerCase();
            // Se for erro de permissão e ainda tiver tentativas, tenta de novo
            if (errorStr.contains('permission') || errorStr.contains('insufficient')) {
              debugPrint('Aguardando token propagar no Firestore... (Tentativa $attempts)');
              if (attempts == 5) rethrow; // Falhou definitivamente
            } else {
              rethrow; // Erro de conexão / offline, devolve pra tela
            }
          }
        }
      }

      _setLoading(false);
      return null; // Retorna nulo indicando Sucesso Absoluto
      
    } on FirebaseAuthException catch (e) {
      _setLoading(false);
      return "Erro no Firebase: ${e.message}";
    } catch (e) {
      _setLoading(false);
      return "Falha de comunicação: $e";
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}