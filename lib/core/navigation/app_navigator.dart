// lib/core/navigation/app_navigator.dart
//
// Clé de navigation globale. Elle permet d'afficher des dialogues (comme la
// popup de notation) depuis n'importe où dans l'app — même depuis un Timer
// ou un service qui n'a pas de BuildContext local — peu importe l'écran sur
// lequel se trouve l'utilisateur.
//
// ── Installation (une seule fois) ───────────────────────────────────────────
// Dans ton MaterialApp (lib/main.dart ou app.dart), ajoute :
//
//   MaterialApp(
//     navigatorKey: appNavigatorKey,
//     builder: (context, child) => ReviewPromptManager(child: child ?? const SizedBox()),
//     ...
//   )
//
import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Renvoie un BuildContext valide utilisable pour afficher un dialogue,
/// peu importe l'écran actif. Peut être `null` juste après le démarrage
/// de l'app si l'arbre n'est pas encore monté.
BuildContext? get appContext =>
    appNavigatorKey.currentState?.overlay?.context ??
    appNavigatorKey.currentContext;