import 'package:flutter/material.dart';

import 'data/gw_api.dart';
import 'gw_auth.dart';
import 'mobile/mobile_ai_settings.dart';

/// What the host app borrows from GhostWriter until the shell has its own
/// API: the account behind the sign-in, and the AI settings sheet.
abstract final class GhostWriterHost {
  /// `{ id, name, email, photoUrl, plan, octoCredits }` from `/v1/me`.
  static Future<Map<String, dynamic>> me({GwAuth? auth}) =>
      GwApi(idToken: auth?.idToken).me();

  /// The main chat's answer to [question], given the turns before it
  /// (`{role: user|assistant, text}`, oldest first).
  static Future<String> askApp(
    String question, {
    required List<Map<String, String>> history,
    GwAuth? auth,
  }) => GwApi(
    idToken: auth?.idToken,
  ).askOcto(question, scope: 'app', history: history);

  /// The model and personality sheet (every app, or GhostWriter only).
  static Future<void> showAiSettings(BuildContext context, {GwAuth? auth}) =>
      showGwAiSettings(context, api: GwApi(idToken: auth?.idToken));
}
