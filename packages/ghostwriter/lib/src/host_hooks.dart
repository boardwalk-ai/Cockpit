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

  /// The model and personality sheet (every app, or GhostWriter only).
  static Future<void> showAiSettings(BuildContext context, {GwAuth? auth}) =>
      showGwAiSettings(context, api: GwApi(idToken: auth?.idToken));
}
