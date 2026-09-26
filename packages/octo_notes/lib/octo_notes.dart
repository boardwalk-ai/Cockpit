/// OctoNotes — the lecture-capture & AI notes module for the Octopilot
/// super-app.
///
/// The shell needs [OctoNotesModule], plus [notesAuthProvider] to hand
/// OctoNotes the app's shared sign-in; everything else is internal.
library;

export 'src/application/account_providers.dart' show notesAuthProvider;
export 'src/data/auth/notes_auth.dart';
export 'src/octo_notes_module.dart';
