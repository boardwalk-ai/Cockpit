/// Another phone paired to record a session (`/v1/pairings`).
class Pairing {
  const Pairing({
    required this.id,
    required this.status,
    required this.code,
    this.secret,
    this.receiverName,
    this.recorderName,
    this.recorderPlatform,
    this.sessionId,
    this.expiresAt,
  });

  factory Pairing.fromJson(Map<String, dynamic> j) => Pairing(
    id: j['id'] as String,
    status: j['status'] as String? ?? 'waiting',
    code: j['code'] as String? ?? '',
    secret: j['secret'] as String?,
    receiverName: (j['receiverDevice'] as Map?)?['name'] as String?,
    recorderName: (j['recorderDevice'] as Map?)?['name'] as String?,
    recorderPlatform: (j['recorderDevice'] as Map?)?['platform'] as String?,
    sessionId: j['sessionId'] as String?,
    expiresAt: DateTime.tryParse(j['expiresAt'] as String? ?? ''),
  );

  final String id;

  /// `waiting` | `paired` | `started` | `expired` | `cancelled`
  final String status;

  /// Six digits, shown as "482 913".
  final String code;

  /// Only the receiver gets it; the QR carries `octonotes-pair:<secret>`.
  final String? secret;
  final String? receiverName;
  final String? recorderName;
  final String? recorderPlatform;
  final String? sessionId;
  final DateTime? expiresAt;

  bool get isPaired => status == 'paired';
  bool get isStarted => status == 'started';
  bool get isOver => status == 'expired' || status == 'cancelled';

  String get qrText => 'octonotes-pair:$secret';

  String get prettyCode =>
      code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

  /// Reads a scanned QR: the secret, or null when it isn't one of ours.
  static String? secretFromQr(String raw) {
    final t = raw.trim();
    if (!t.startsWith('octonotes-pair:')) return null;
    final s = t.substring('octonotes-pair:'.length);
    return RegExp(r'^[0-9a-f]{32}$').hasMatch(s) ? s : null;
  }
}
