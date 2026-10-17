import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/config.dart';
import 'sse_client.dart';

/// One OctoCredits pack, as Octopilot's Stripe catalog sells it.
class CreditPack {
  const CreditPack(this.key, this.credits, this.price);

  /// `addon_key` for the checkout (`topup_300`, …).
  final String key;
  final int credits;
  final String price;
}

/// The packs (octopilot-api `billing_routes.py` catalog). The balance is the
/// one shared `users.octo_credits`, so a pack bought anywhere works here.
const creditPacks = [
  CreditPack('topup_50', 50, r'$0.99'),
  CreditPack('topup_300', 300, r'$4.99'),
  CreditPack('topup_500', 500, r'$7.99'),
  CreditPack('topup_1000', 1000, r'$9.99'),
  CreditPack('topup_2500', 2500, r'$19.99'),
  CreditPack('topup_5000', 5000, r'$39.99'),
];

/// Buying OctoCredits: Octopilot's billing API makes a Stripe Checkout page
/// for the signed-in user; its webhook adds the credits when payment lands.
class BillingApi {
  BillingApi({required SseClient sse, http.Client? client})
    // ignore: prefer_initializing_formals — public name differs from field
    : _sse = sse,
      _client = client ?? http.Client();

  final SseClient _sse;
  final http.Client _client;

  /// The Stripe Checkout page for [pack].
  Future<Uri> checkout(CreditPack pack) async {
    final headers = await _sse.authHeaders()
      ..remove('Accept')
      ..remove('X-User-Id')
      ..['Content-Type'] = 'application/json';
    if (!headers.containsKey('Authorization')) {
      throw SseException('Sign in to buy OctoCredits.');
    }
    final resp = await _client.post(
      Uri.parse('${StudioConfig.billingBaseUrl}/billing/checkout-session'),
      headers: headers,
      body: jsonEncode({'kind': 'addon', 'addon_key': pack.key}),
    );
    if (resp.statusCode >= 400) {
      throw SseException('Checkout failed (HTTP ${resp.statusCode}).');
    }
    final url = (jsonDecode(resp.body) as Map<String, dynamic>)['url'];
    if (url is! String) throw SseException('Checkout failed.');
    return Uri.parse(url);
  }
}
