import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// An announcement from the admin app.
@immutable
class Announcement {
  const Announcement({required this.title, required this.body, this.image});
  final String title;
  final String body;
  final String? image;
}

/// The announcements that arrive while the app is open. (Android shows a
/// notification only when the app is in the background; in front, this
/// banner does.)
Stream<Announcement> foregroundAnnouncements() {
  if (kIsWeb || Firebase.apps.isEmpty) return const Stream.empty();
  return FirebaseMessaging.onMessage
      .where((m) => m.data['type'] == 'announcement' && m.notification != null)
      .map(
        (m) => Announcement(
          title: m.notification!.title ?? '',
          body: m.notification!.body ?? '',
          image:
              m.notification!.android?.imageUrl ??
              m.notification!.apple?.imageUrl,
        ),
      );
}

/// Shows [announcements] as a card that drops in at the top of every screen
/// for a few seconds. Tapping it calls [onOpen] (the app opens Home);
/// swiping it up puts it away.
class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({
    super.key,
    required this.announcements,
    required this.onOpen,
    required this.child,
  });

  final Stream<Announcement> announcements;
  final VoidCallback onOpen;
  final Widget child;

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 240),
  );
  StreamSubscription<Announcement>? _sub;
  Announcement? _shown;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _sub = widget.announcements.listen(_show);
  }

  void _show(Announcement a) {
    setState(() => _shown = a);
    _anim.forward(from: 0);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 7), _dismiss);
  }

  void _dismiss() {
    _hide?.cancel();
    if (mounted) _anim.reverse();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hide?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = _shown;
    return Stack(
      children: [
        widget.child,
        if (a != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              child: SlideTransition(
                position: Tween(begin: const Offset(0, -1.4), end: Offset.zero)
                    .animate(
                      CurvedAnimation(
                        parent: _anim,
                        curve: Curves.easeOutBack,
                        reverseCurve: Curves.easeIn,
                      ),
                    ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Dismissible(
                    key: ObjectKey(a),
                    direction: DismissDirection.up,
                    onDismissed: (_) => setState(() => _shown = null),
                    child: _Card(
                      a: a,
                      onTap: () {
                        _dismiss();
                        widget.onOpen();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.a, required this.onTap});
  final Announcement a;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Colors.white : const Color(0xFF151517);
    return Material(
      color: dark ? const Color(0xF21C1C1F) : const Color(0xF7FFFFFF),
      elevation: 12,
      shadowColor: const Color(0x66FF343C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x55FF343C)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF343C), Color(0xFFFF8A5B)],
                  ),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (a.body.isNotEmpty)
                      Text(
                        a.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.7),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                  ],
                ),
              ),
              if (a.image != null) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    a.image!,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
