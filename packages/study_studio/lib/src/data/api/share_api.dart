import '../../domain/entities/studio.dart';
import 'dto_mappers.dart';
import 'sse_client.dart';

/// A studio's share link (null [code] when sharing is off).
class StudioShare {
  const StudioShare({this.code, this.url, this.copies = 0});

  factory StudioShare.fromJson(Map<String, dynamic> j) => StudioShare(
    code: j['code'] as String?,
    url: j['url'] as String?,
    copies: (j['copies'] as num?)?.toInt() ?? 0,
  );

  final String? code;
  final String? url;

  /// How many people added a copy through it.
  final int copies;

  bool get on => code != null;
}

/// What a share link holds, before adding it.
class SharePreview {
  const SharePreview({
    required this.code,
    required this.title,
    this.subject = '',
    this.lessons = 0,
    this.cards = 0,
    this.scenarios = 0,
    this.sharedBy,
    this.sharedByPhoto,
  });

  factory SharePreview.fromJson(Map<String, dynamic> j) => SharePreview(
    code: j['code'] as String? ?? '',
    title: j['title'] as String? ?? '',
    subject: j['subject'] as String? ?? '',
    lessons: (j['lessons'] as num?)?.toInt() ?? 0,
    cards: (j['cards'] as num?)?.toInt() ?? 0,
    scenarios: (j['scenarios'] as num?)?.toInt() ?? 0,
    sharedBy: j['sharedBy'] as String?,
    sharedByPhoto: j['sharedByPhoto'] as String?,
  );

  final String code;
  final String title;
  final String subject;
  final int lessons;
  final int cards;
  final int scenarios;
  final String? sharedBy;
  final String? sharedByPhoto;
}

/// Share links: turn on/off for a studio, preview one, add a copy.
class ShareApi {
  // ignore: prefer_initializing_formals — public name differs from field
  ShareApi({required SseClient sse}) : _sse = sse;

  final SseClient _sse;

  Map<String, dynamic>? _data(List<SseEvent> events) =>
      events.where((e) => e.event == 'data').firstOrNull?.data;

  Future<StudioShare> current(String studioId) async => StudioShare.fromJson(
    _data(await _sse.get('/studios/$studioId/share')) ?? const {},
  );

  /// Turns the link on (the same link if it already is).
  Future<StudioShare> turnOn(String studioId) async => StudioShare.fromJson(
    _data(await _sse.post('/studios/$studioId/share')) ?? const {},
  );

  Future<void> turnOff(String studioId) =>
      _sse.delete('/studios/$studioId/share');

  Future<SharePreview> preview(String code) async {
    final data = _data(await _sse.get('/shares/${Uri.encodeComponent(code)}'));
    if (data == null) throw SseException('This link doesn’t exist.');
    return SharePreview.fromJson(data);
  }

  /// Adds a copy to the signed-in user's studios; one per [requestId].
  Future<Studio> copy(String code, {required String requestId}) async {
    final data = _data(
      await _sse.post(
        '/shares/${Uri.encodeComponent(code)}/copy',
        extraHeaders: {'Idempotency-Key': requestId},
        retry: true,
      ),
    );
    if (data == null) throw SseException('Couldn’t add the studio.');
    return studioFromJson(data);
  }
}
