import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/octo_notes_api.dart';
import '../domain/notes_session.dart';
import 'account_providers.dart';

/// Typed API, or null when OctoNotes runs without a backend (in-memory mode).
final octoNotesApiProvider = Provider<OctoNotesApi?>((ref) {
  final client = ref.watch(notesApiClientProvider);
  return client == null ? null : OctoNotesApi(client);
});

/// Home data from the backend; null in in-memory mode (the screen keeps its
/// sample content). Refetches on sign-in changes.
final homeDataProvider = FutureProvider<HomeData?>((ref) async {
  ref.watch(notesAuthStateProvider);
  final api = ref.watch(octoNotesApiProvider);
  if (api == null) return null;
  return api.home();
});
