part of 'octo_notes_home_page.dart';

const _red = Color(0xFFE11D2E);
const _gold = Color(0xFFE8B84B);

/// Courses for the home shelf; empty without a backend.
final _homeBooksProvider = FutureProvider<List<Notebook>>((ref) async {
  ref.watch(notesAuthStateProvider);
  final api = ref.watch(octoNotesApiProvider);
  if (api == null) return const [];
  final c = (await api.courses()).cast<Map<String, dynamic>>();
  return [
    for (var i = 0; i < c.length; i++)
      Notebook(
        id: c[i]['id'] as String,
        name: c[i]['name'] as String? ?? 'Course',
        code: c[i]['code'] as String?,
        color: notebookColor(c[i]['color'] as String?, i),
      ),
  ];
});

String _clock(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// The phone Home: what's recording now, start or join a lecture, what's
/// waiting to be finalized, the notebooks, and the latest final notes. Only
/// real data; without any it says so.
class _PhoneHome extends ConsumerWidget {
  const _PhoneHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeDataProvider).valueOrNull;
    final books = ref.watch(_homeBooksProvider).valueOrNull ?? const <Notebook>[];
    final live = home?.live.firstOrNull;
    final ready = [...?home?.continueSessions.where((s) => s.status == 'ended' || s.status == 'reviewing')];
    final recent = home?.recent ?? const <NotesSession>[];
    final api = ref.read(octoNotesApiProvider);
    void open(NotesSession s) {
      HapticFeedback.selectionClick();
      openSession(context, api, s);
    }

    return RefreshIndicator(
      color: _red,
      onRefresh: () async {
        ref.invalidate(homeDataProvider);
        ref.invalidate(_homeBooksProvider);
        await ref.read(homeDataProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const _PhoneTop(),
          const SizedBox(height: CockpitSpacing.xl),
          if (live != null) ...[
            _LiveCard(session: live, onTap: () => open(live)),
            const SizedBox(height: CockpitSpacing.xl),
          ],
          _RecordHero(onTap: () {
            HapticFeedback.mediumImpact();
            showNewSessionSheet(context);
          }),
          const SizedBox(height: CockpitSpacing.sm),
          _JoinRow(onTap: () {
            HapticFeedback.selectionClick();
            context.go('/notes/join');
          }),
          if (ready.isNotEmpty) ...[
            const SizedBox(height: CockpitSpacing.xxl),
            const Eyebrow('Ready to finalize'),
            const SizedBox(height: CockpitSpacing.sm),
            for (final s in ready) _ReadyRow(session: s, onTap: () => open(s)),
          ],
          const SizedBox(height: CockpitSpacing.xxl),
          Row(
            children: [
              const Expanded(child: Eyebrow('Notebooks')),
              TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  context.go('/notes/notebooks');
                },
                child: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: CockpitSpacing.sm),
          if (books.isEmpty)
            const _Quiet('Your courses show up here as notebooks.')
          else
            SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.md),
                itemCount: books.length,
                separatorBuilder: (_, _) => const SizedBox(width: CockpitSpacing.lg),
                itemBuilder: (_, i) => _TiltNotebook(book: books[i], onTap: () => context.push('/notes/notebook?course=${books[i].id}', extra: books[i])),
              ),
            ),
          const SizedBox(height: CockpitSpacing.xl),
          const Eyebrow('Recent pages'),
          const SizedBox(height: CockpitSpacing.sm),
          if (recent.isEmpty)
            const _Quiet('No final notes yet. Record a lecture and finalize it.')
          else
            for (final s in recent)
              _PageRow(
                session: s,
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.push('/notes/notebook?course=${s.courseId ?? 'loose'}&session=${s.id}');
                },
              ),
        ],
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.md),
        child: Text(text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

/// Wordmark on the left; credits and the profile on the right.
class _PhoneTop extends StatelessWidget {
  const _PhoneTop();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text('OctoNotes',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ),
          const _CreditsPill(),
          const SizedBox(width: CockpitSpacing.md),
          const _AccountPill(showCredits: false, ring: true),
        ],
      );
}

/// A red-gold ring that slowly turns around the avatar.
class _SpinRing extends StatefulWidget {
  const _SpinRing({required this.child});
  final Widget child;

  @override
  State<_SpinRing> createState() => _SpinRingState();
}

class _SpinRingState extends State<_SpinRing> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _RingPainter(_c),
        child: Padding(padding: const EdgeInsets.all(3), child: widget.child),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawOval(
      r.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = SweepGradient(
          colors: const [_red, _gold, Color(0x00E8B84B), _red],
          stops: const [0, 0.35, 0.7, 1],
          transform: GradientRotation(t.value * 2 * math.pi),
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => false;
}

// ---------------------------------------------------------------------------
// Live card
// ---------------------------------------------------------------------------

/// The lecture recording right now: a light that runs round its edge, the
/// clock, and a mirrored waveform that flows in from the right.
class _LiveCard extends ConsumerStatefulWidget {
  const _LiveCard({required this.session, required this.onTap});
  final NotesSession session;
  final VoidCallback onTap;

  @override
  ConsumerState<_LiveCard> createState() => _LiveCardState();
}

class _LiveCardState extends ConsumerState<_LiveCard> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  LiveSocket? _socket;

  // From the recording phone: levels waiting to be drawn (one per 50 ms),
  // the bars drawn so far, its recorded time and the latest caption.
  final _pending = <double>[];
  final _bars = <double>[];
  Duration _lastPop = Duration.zero;
  int? _ms;
  DateTime _msAt = DateTime.now();
  String? _caption;
  String? _status;

  @override
  void initState() {
    super.initState();
    if (ref.read(octoNotesApiProvider) == null) return;
    _socket = LiveSocket(
      baseUrl: OctoNotesConfig.apiBaseUrl,
      sessionId: widget.session.id,
      tokenProvider: ref.read(notesAuthProvider).idToken,
    );
    _socket!.events.listen(_event);
    unawaited(_socket!.connect());
    _c.addListener(_drain);
  }

  void _event(Map<String, dynamic> e) {
    final d = e['data'];
    if (d is! Map<String, dynamic>) return;
    switch (e['type']) {
      case 'audio.level':
        _pending.addAll([for (final v in (d['v'] as List? ?? const [])) (v as num).toDouble()]);
        // Never fall more than a second behind.
        if (_pending.length > 20) _pending.removeRange(0, _pending.length - 20);
        final ms = (d['ms'] as num?)?.toInt();
        if (ms != null) {
          _ms = ms;
          _msAt = DateTime.now();
        }
      case 'transcript.live':
        final t = (d['text'] as String?)?.trim();
        if (t != null && t.isNotEmpty) setState(() => _caption = t);
      case 'recording.state':
        setState(() => _status = d['state'] as String?);
    }
  }

  void _drain() {
    final now = _c.lastElapsedDuration ?? Duration.zero;
    if (_pending.isEmpty || now - _lastPop < const Duration(milliseconds: 50)) return;
    _lastPop = now;
    _bars.add(_pending.removeAt(0));
    if (_bars.length > 120) _bars.removeAt(0);
  }

  @override
  void dispose() {
    _c.dispose();
    unawaited(_socket?.close());
    super.dispose();
  }

  bool get _paused => (_status ?? widget.session.status) == 'paused';

  Duration get _elapsed {
    final s = widget.session;
    // The phone's own count, pauses excluded, ticking on between messages.
    if (_ms != null) return Duration(milliseconds: _ms! + (_paused ? 0 : DateTime.now().difference(_msAt).inMilliseconds.clamp(0, 1500)));
    // shortcut: until the phone reports, wall clock since the start (pauses
    // included); fine for the first fraction of a second.
    if (_paused || s.startedAt == null) return Duration(milliseconds: s.durationMs);
    final d = DateTime.now().difference(s.startedAt!);
    return d.isNegative ? Duration.zero : d;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value * 60; // seconds
          return CustomPaint(
            painter: _EdgeLight(t, scheme.surface),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      LiveDot(label: _paused ? 'PAUSED' : 'LIVE'),
                      const Spacer(),
                      Text(_clock(_elapsed),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                    ],
                  ),
                  const SizedBox(height: CockpitSpacing.md),
                  Text(widget.session.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: CockpitSpacing.lg),
                  SizedBox(
                    height: 56,
                    width: double.infinity,
                    child: CustomPaint(painter: _WavePainter(t, paused: _paused, real: _bars.isEmpty ? null : _bars)),
                  ),
                  const SizedBox(height: CockpitSpacing.md),
                  Row(
                    children: [
                      Icon(Icons.graphic_eq_rounded, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: CockpitSpacing.xs),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 450),
                          layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
                          child: Text(
                              _paused
                                  ? 'Paused · tap to pick it up'
                                  : _caption == null
                                      ? 'Recording · tap to follow the transcript'
                                      : '“$_caption”',
                              key: ValueKey(_paused ? '' : _caption),
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                        ),
                      ),
                      Icon(Icons.arrow_forward_rounded, size: 18, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A faint red wash and a light running round the rounded edge.
class _EdgeLight extends CustomPainter {
  _EdgeLight(this.t, this.surface);
  final double t;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(24));
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_red.withValues(alpha: 0.10), _gold.withValues(alpha: 0.05)],
        ).createShader(rect),
    );
    final sweep = SweepGradient(
      colors: const [Color(0x00E11D2E), _red, _gold, Color(0x00E8B84B), Color(0x00E11D2E)],
      stops: const [0, 0.12, 0.22, 0.34, 1],
      transform: GradientRotation(t * 1.1),
    ).createShader(rect);
    // The glow under the line, then the line.
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
        ..shader = sweep,
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = sweep,
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _red.withValues(alpha: 0.14),
    );
  }

  @override
  bool shouldRepaint(_EdgeLight old) => old.t != t || old.surface != surface;
}

/// Bars mirrored about the middle, red to gold, flowing left; the newest
/// bar on the right carries a glowing head.
/// [real] holds the recording phone's levels (newest last); until any arrive
/// the bars move on their own.
class _WavePainter extends CustomPainter {
  _WavePainter(this.t, {required this.paused, this.real});
  final double t;
  final bool paused;
  final List<double>? real;

  static double _hash(int n) {
    final v = math.sin(n * 12.9898) * 43758.5453;
    return v - v.floorToDouble();
  }

  static double _sample(double x) {
    final i = x.floor();
    final f = x - i;
    final a = _hash(i), b = _hash(i + 1);
    final s = a + (b - a) * (f * f * (3 - 2 * f));
    // Speech comes in phrases: a slow envelope over the jitter.
    final phrase = 0.55 + 0.45 * math.sin(x * 0.21);
    return (0.18 + 0.82 * s) * phrase;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const step = 5.0, bar = 3.0;
    final n = (size.width / step).floor();
    final mid = size.height / 2;
    final flow = paused ? 0.0 : t * 9;
    final shader = const LinearGradient(colors: [_red, _gold]).createShader(Offset.zero & size);
    final p = Paint()..shader = shader;
    var headH = 0.0;
    for (var i = 0; i < n; i++) {
      final r = real;
      var a = r == null ? _sample(i + flow) : (r.length - n + i >= 0 ? math.sqrt(r[r.length - n + i]) : 0.0);
      if (paused && r == null) a *= 0.12;
      // Older bars fade toward the left edge.
      final fade = (i / n).clamp(0.0, 1.0);
      final h = math.max(2.0, a * (size.height - 6));
      final x = i * step;
      // The paint's alpha scales the gradient.
      p.color = Colors.black.withValues(alpha: 0.25 + 0.75 * fade);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x + bar / 2, mid), width: bar, height: h), const Radius.circular(2)),
        p,
      );
      if (i == n - 1) headH = h;
    }
    if (paused) return;
    final head = Offset((n - 1) * step + bar / 2, mid - headH / 2);
    canvas.drawCircle(head, 7, Paint()..color = _gold.withValues(alpha: 0.55)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(head, 2.6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

// ---------------------------------------------------------------------------
// Start / join
// ---------------------------------------------------------------------------

/// A glossy record button breathing three rings, with a shine across the title.
class _RecordHero extends StatefulWidget {
  const _RecordHero({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_RecordHero> createState() => _RecordHeroState();
}

class _RecordHeroState extends State<_RecordHero> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();
  bool _down = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Row(
          children: [
            SizedBox(
              width: 104,
              height: 104,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) => CustomPaint(
                  painter: _Breath(_c.value, grow: _down ? 1.12 : 1),
                  child: Center(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          center: Alignment(-0.4, -0.5),
                          radius: 1.1,
                          colors: [Color(0xFFFF6B5E), _red, Color(0xFF8E0C18)],
                          stops: [0, 0.5, 1],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _red.withValues(alpha: 0.45 + 0.15 * math.sin(_c.value * 2 * math.pi)),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: CockpitSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedBuilder(
                    animation: _c,
                    builder: (_, child) => ShaderMask(
                      blendMode: BlendMode.srcATop,
                      shaderCallback: (r) {
                        final x = -1.5 + 4 * _c.value;
                        return LinearGradient(
                          begin: Alignment(x - 0.6, 0),
                          end: Alignment(x + 0.6, 0),
                          colors: [Colors.transparent, _gold.withValues(alpha: 0.9), Colors.transparent],
                        ).createShader(r);
                      },
                      child: child,
                    ),
                    child: Text('New Session', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: CockpitSpacing.xxs),
                  Text('Record a lecture with this phone',
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _Breath extends CustomPainter {
  _Breath(this.t, {required this.grow});
  final double t;
  final double grow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var k = 0; k < 3; k++) {
      final p = (t + k / 3) % 1;
      final r = (30 + p * 22) * grow;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _red.withValues(alpha: (1 - p) * 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(_Breath old) => old.t != t || old.grow != grow;
}

/// A slim row: a QR with a gold line scanning over it.
class _JoinRow extends StatefulWidget {
  const _JoinRow({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_JoinRow> createState() => _JoinRowState();
}

class _JoinRowState extends State<_JoinRow> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Center(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    children: [
                      Icon(Icons.qr_code_2_rounded, size: 40, color: scheme.onSurface.withValues(alpha: 0.75)),
                      AnimatedBuilder(
                        animation: _c,
                        builder: (_, _) => Positioned(
                          left: 0,
                          right: 0,
                          top: 3 + 32 * Curves.easeInOut.transform(_c.value),
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: _gold,
                              boxShadow: [BoxShadow(color: _gold.withValues(alpha: 0.8), blurRadius: 8)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: CockpitSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Join as recorder', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text("Record for your other device's session",
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

String _minutes(int ms) => ms <= 0 ? '' : ' · ${(ms / 60000).round()} min';

class _ReadyRow extends StatelessWidget {
  const _ReadyRow({required this.session, required this.onTap});
  final NotesSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: _gold, size: 22),
            const SizedBox(width: CockpitSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  Text('Ready to finalize${_minutes(session.durationMs)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: _gold, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _PageRow extends StatelessWidget {
  const _PageRow({required this.session, required this.onTap});
  final NotesSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  const SizedBox(height: CockpitSpacing.xxs),
                  Text('${_RecentNotesSection._date(session.updatedAt)}${_minutes(session.durationMs)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notebook with a smooth 3D tilt
// ---------------------------------------------------------------------------

/// A notebook that leans toward the finger (or pointer) and lifts off its
/// shadow. Every frame eases toward the target, so leaning in and settling
/// back move at the same unhurried pace.
class _TiltNotebook extends StatefulWidget {
  const _TiltNotebook({required this.book, required this.onTap});
  final Notebook book;
  final VoidCallback onTap;

  @override
  State<_TiltNotebook> createState() => _TiltNotebookState();
}

class _TiltNotebookState extends State<_TiltNotebook> with SingleTickerProviderStateMixin {
  static const _w = 124.0, _h = 164.0;
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  // x, y in -1..1 (where the finger is), z = lift 0..1.
  double _tx = 0, _ty = 0, _tz = 0, _x = 0, _y = 0, _z = 0;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _aim(Offset? local) {
    if (local == null) {
      _tx = _ty = _tz = 0;
    } else {
      _tx = (local.dx / _w * 2 - 1).clamp(-1.0, 1.0);
      _ty = (local.dy / _h * 2 - 1).clamp(-1.0, 1.0);
      _tz = 1;
    }
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 1 / 60 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    // ~0.1 of the way per 60 Hz frame, independent of the refresh rate.
    final k = 1 - math.pow(0.9, dt * 60).toDouble();
    setState(() {
      _x += (_tx - _x) * k;
      _y += (_ty - _y) * k;
      _z += (_tz - _z) * k;
    });
    if ((_tx - _x).abs() + (_ty - _y).abs() + (_tz - _z).abs() < 0.002) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.book;
    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0016)
      ..translateByDouble(0, -12 * _z, 0, 1)
      ..rotateX(_y * 0.32 * _z)
      ..rotateY(-_x * 0.42 * _z)
      ..scaleByDouble(1 + 0.05 * _z, 1 + 0.05 * _z, 1, 1);
    return MouseRegion(
      onHover: (e) => _aim(e.localPosition),
      onExit: (_) => _aim(null),
      child: Listener(
        onPointerDown: (e) {
          HapticFeedback.lightImpact();
          _aim(e.localPosition);
        },
        onPointerMove: (e) => _aim(e.localPosition),
        onPointerUp: (_) => _aim(null),
        onPointerCancel: (_) => _aim(null),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          child: SizedBox(
            width: _w,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Ground shadow: shrinks and fades as the notebook lifts.
                Positioned(
                  left: 14 + 10 * _z,
                  right: 14 + 10 * _z,
                  top: _h - 6,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.32 - 0.16 * _z), blurRadius: 14 + 10 * _z, spreadRadius: 1),
                      ],
                    ),
                  ),
                ),
                Transform(
                  alignment: Alignment.center,
                  transform: m,
                  child: SizedBox(width: _w, height: _h, child: _miniCover(b)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniCover(Notebook b) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        // Page edges peeking out on the right.
        Positioned(
          top: 5,
          bottom: 5,
          right: 0,
          width: 20,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF4EFE6),
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
              border: Border(right: BorderSide(color: Colors.black.withValues(alpha: 0.12))),
            ),
          ),
        ),
        Positioned.fill(
          right: 4,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(4), right: Radius.circular(12)),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [b.color, b.deep]),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Spine.
                Positioned(left: 0, top: 0, bottom: 0, width: 10, child: ColoredBox(color: Colors.black.withValues(alpha: 0.22))),
                // The sheen follows the finger.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(_x, _y),
                        radius: 0.9,
                        colors: [Colors.white.withValues(alpha: 0.32 * _z), Colors.white.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
                // The label floats a little above the cover.
                Positioned(
                  left: 18 + _x * 4 * _z,
                  right: 8 - _x * 4 * _z,
                  bottom: 14 + _y * 4 * _z,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (b.code != null)
                        Text(b.code!,
                            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.8), letterSpacing: 1, fontWeight: FontWeight.w700)),
                      Text(b.name,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            shadows: [Shadow(color: Colors.black.withValues(alpha: 0.35 * _z), blurRadius: 6, offset: Offset(_x * -3 * _z, 3 * _z))],
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
