import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth.dart';
import 'backend_config.dart';
import 'essays_service.dart';

/// The app's auth boundary. Reading it also wires the ID token into the HTTP
/// services (so every `/api` call carries `Authorization: Bearer …` once signed
/// in).
final docAuthProvider = Provider<DocAuth>((ref) {
  final auth = createDocAuth();
  setAuthTokenSource(auth.idToken);
  return auth;
});

/// The current signed-in user (or null), refreshed on sign in/out/token change.
final authUserProvider = StreamProvider<DocUser?>((ref) {
  return ref.watch(docAuthProvider).userChanges();
});

/// The signed-in user's account + credits (`/v1/me`). Null when signed out or
/// no backend is configured; refetches whenever auth state changes.
final meProvider = FutureProvider<Me?>((ref) async {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return null;
  final svc = createEssaysService();
  if (svc == null) return null;
  return svc.me();
});
