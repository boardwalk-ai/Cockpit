import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account/account_repository.dart';
import '../data/api/notes_api_client.dart';
import '../data/api/octo_notes_config.dart';
import '../data/auth/notes_auth.dart';
import '../domain/account.dart';

/// Host-provided auth. The Cockpit shell overrides this with an adapter over
/// the app's Firebase sign-in; the default is always signed out.
final notesAuthProvider = Provider<NotesAuth>((ref) => const SignedOutNotesAuth());

/// Sign-in state; user-scoped providers watch it so they refetch with the new
/// token on sign in/out.
final notesAuthStateProvider = StreamProvider<bool>((ref) {
  return ref.watch(notesAuthProvider).authStateChanges();
});

/// One API client for OctoNotes, or null when no backend is configured.
final notesApiClientProvider = Provider<NotesApiClient?>((ref) {
  if (!OctoNotesConfig.hasApiBackend) return null;
  final auth = ref.watch(notesAuthProvider);
  final client = NotesApiClient(
    baseUrl: OctoNotesConfig.apiBaseUrl,
    tokenProvider: auth.idToken,
  );
  ref.onDispose(client.close);
  return client;
});

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final client = ref.watch(notesApiClientProvider);
  if (client == null) return const InMemoryAccountRepository();
  return ApiAccountRepository(client);
});

/// The signed-in account + central OctoCredits balance (the header pill).
final notesMeProvider = FutureProvider<NotesAccount>((ref) {
  ref.watch(notesAuthStateProvider);
  return ref.watch(accountRepositoryProvider).me();
});
