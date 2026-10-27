part of 'live_session_hub_page.dart';

// ===========================================================================
// Phone, solo or receiver: the lecture as it happens. A dark room: the clock,
// the sound, the transcript like a teleprompter, and a dock of tools with the
// record button in the middle.
// ===========================================================================

/// The room's colours, light or dark as the app is set.
class _RoomPalette {
  const _RoomPalette({
    required this.bg,
    required this.ink,
    required this.muted,
    required this.soft,
    required this.line,
    required this.time,
    required this.dockTop,
    required this.dockBottom,
    required this.tool,
    required this.toolLabel,
    required this.shadow,
  });
  final Color bg, ink, muted, soft, line, time, dockTop, dockBottom, tool, toolLabel, shadow;

  static const dark = _RoomPalette(
    bg: Color(0xFF0F0F11),
    ink: Color(0xFFF3EFE7),
    muted: Color(0xFF8D877C),
    soft: Color(0xFFC9C3B8),
    line: Color(0xFF3A3A3D),
    time: Color(0xFF6B665E),
    dockTop: Color(0xFF1F2023),
    dockBottom: Color(0xFF17181A),
    tool: Color(0xFF26272B),
    toolLabel: Color(0xFFA8A39A),
    shadow: Color(0x99000000),
  );

  static const light = _RoomPalette(
    bg: Color(0xFFF7F3EC),
    ink: Color(0xFF1F1B16),
    muted: Color(0xFF8A8174),
    soft: Color(0xFF5E564B),
    line: Color(0xFFDCD3C4),
    time: Color(0xFFA79E90),
    dockTop: Color(0xFFFFFFFF),
    dockBottom: Color(0xFFF6F1E8),
    tool: Color(0xFFF0E9DD),
    toolLabel: Color(0xFF6F675B),
    shadow: Color(0x2E3C280A),
  );
}

/// Set as the room is built (only one room is open at a time).
var _room = _RoomPalette.dark;

const _roomRed = Color(0xFFE11D2E);
const _roomGold = Color(0xFFE8B84B);
const _display = 'packages/cockpit_ui/Poppins';
const _sans = 'packages/cockpit_ui/PlusJakartaSans';

class _LiveRoom extends StatelessWidget {
  const _LiveRoom({required this.state});
  final _LiveSessionHubPageState state;

  /// What the recording is doing, in words, and whether it's going.
  (String, bool, bool) get _status {
    final r = state._recorder;
    final live = state._live;
    if (r != null) {
      final text = switch (r.status) {
        RecorderStatus.paused => 'Paused',
        RecorderStatus.stopping => 'Saving the recording…',
        RecorderStatus.stopped => 'Recording saved',
        RecorderStatus.idle || RecorderStatus.starting => 'Starting the microphone…',
        _ => 'Recording on this phone',
      };
      return (text, r.isRecording || live.isDemo, r.isPaused);
    }
    if (state.widget.role == SessionRole.solo) {
      // Solo records here; before the mic is up (or in the demo) it says so.
      return state.widget.record ? ('Recording on this phone', live.isDemo, false) : ('Not recording this session', false, false);
    }
    final who = live.recorderName ?? 'Your phone';
    if (live.isRecording) return ('$who is recording', true, false);
    if (live.recordingState == 'paused') return ('Recording paused on $who', false, true);
    if (live.recordingState == 'stopped' || live.recordingState == 'assembled') return ('Recording finished', false, false);
    return ('Waiting for $who to start recording', false, false);
  }

  @override
  Widget build(BuildContext context) {
    final live = state._live;
    final r = state._recorder;
    final (status, recording, paused) = _status;
    final failed = r != null && r.status == RecorderStatus.failed;
    _room = Theme.of(context).brightness == Brightness.dark ? _RoomPalette.dark : _RoomPalette.light;
    return AnimatedTheme(
      data: Theme.of(context),
      child: Scaffold(
        backgroundColor: _room.bg,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 14, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          color: _room.ink,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
                          onPressed: state._leave,
                        ),
                        Expanded(
                          child: Text(
                            live.title ?? (live.isDemo ? 'Biology 101 · Cellular respiration' : 'Live session'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: _display, fontSize: 13.5, fontWeight: FontWeight.w500, color: _room.ink),
                          ),
                        ),
                        _Pressable(
                          onTap: state._finish,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: _room.line)),
                            child: Text('Finish', style: TextStyle(fontFamily: _sans, fontSize: 12.5, fontWeight: FontWeight.w600, color: _room.ink)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (failed)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _RecorderProblem(message: r.error ?? 'Recording stopped.', onRetry: r.start),
                    )
                  else ...[
                    Center(
                      child: Text(
                        _clock(state._elapsedMs),
                        style: TextStyle(
                          fontFamily: _display,
                          fontSize: 46,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -1,
                          color: _room.ink,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Breath(on: recording),
                        const SizedBox(width: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(status, key: ValueKey(status), style: TextStyle(fontFamily: _sans, fontSize: 12, color: _room.soft)),
                        ),
                      ],
                    ),
                    if (r != null && r.behindSeconds > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Uploading · ${r.behindSeconds}s behind',
                            textAlign: TextAlign.center, style: TextStyle(fontFamily: _sans, fontSize: 11, color: _room.muted)),
                      ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                    child: SizedBox(height: 46, child: _RoomWave(level: () => r?.level, active: recording, paused: paused)),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(22, 6, 22, 0),
                    child: Text('Live transcript', style: TextStyle(fontFamily: _sans, fontSize: 11, letterSpacing: .4, color: _room.muted)),
                  ),
                  Expanded(child: _Teleprompter(lines: live.lines)),
                  const SizedBox(height: 104),
                ],
              ),
              Positioned(left: 14, right: 14, bottom: 14, child: _Dock(state: state, recording: recording, paused: paused)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scales down a touch while pressed.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(scale: _down ? .9 : 1, duration: const Duration(milliseconds: 160), curve: Curves.easeOutCubic, child: widget.child),
      );
}

/// A red dot that breathes a ring while recording.
class _Breath extends StatefulWidget {
  const _Breath({required this.on});
  final bool on;

  @override
  State<_Breath> createState() => _BreathState();
}

class _BreathState extends State<_Breath> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 20,
        height: 20,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(painter: _BreathPainter(widget.on ? _c.value : 0, widget.on)),
        ),
      );
}

class _BreathPainter extends CustomPainter {
  _BreathPainter(this.t, this.on);
  final double t;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (on) canvas.drawCircle(c, 4 + 6 * t, Paint()..color = _roomRed.withValues(alpha: .5 * (1 - t)));
    canvas.drawCircle(c, 4, Paint()..color = on ? _roomRed : _room.muted);
  }

  @override
  bool shouldRepaint(_BreathPainter old) => old.t != t || old.on != on;
}

/// The sound: bars from red to gold, following the mic (or moving on their
/// own for the other phone's recording).
class _RoomWave extends StatefulWidget {
  const _RoomWave({required this.level, required this.active, required this.paused});
  final double? Function() level;
  final bool active, paused;

  @override
  State<_RoomWave> createState() => _RoomWaveState();
}

class _RoomWaveState extends State<_RoomWave> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => setState(() => _t = e.inMilliseconds / 1000))..start();
  }
  final List<double> _levels = [];
  double _last = 0;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A real level every 60 ms, eased so the bars glide.
    if (_t - _last > .06) {
      _last = _t;
      final l = widget.level();
      _levels.add(!widget.active ? 0.04 : (l ?? (.2 + .6 * (math.sin(_t * 5.3) * math.sin(_t * 1.7)).abs())));
      if (_levels.length > 90) _levels.removeAt(0);
    }
    return CustomPaint(painter: _RoomWavePainter(List.of(_levels), widget.active), size: Size.infinite);
  }
}

class _RoomWavePainter extends CustomPainter {
  _RoomWavePainter(this.levels, this.active);
  final List<double> levels;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 5.0;
    final n = (size.width / step).floor();
    final paint = Paint()
      ..shader = const LinearGradient(colors: [Color(0x33E11D2E), _roomRed, _roomGold], stops: [0, .55, 1]).createShader(Offset.zero & size);
    for (var i = 0; i < n; i++) {
      final k = levels.length - n + i;
      final l = k >= 0 ? levels[k] : 0.04;
      final h = math.max(2.5, math.sqrt(l.clamp(0, 1)) * size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(i * step + 1.5, size.height / 2), width: 3, height: h), const Radius.circular(1.5)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RoomWavePainter old) => true;
}

/// The transcript as a teleprompter: the newest line large and bright,
/// older ones smaller and fading up.
class _Teleprompter extends StatefulWidget {
  const _Teleprompter({required this.lines});
  final List<TranscriptLine> lines;

  @override
  State<_Teleprompter> createState() => _TeleprompterState();
}

class _TeleprompterState extends State<_Teleprompter> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_Teleprompter old) {
    super.didUpdateWidget(old);
    // Follow the newest line unless the reader scrolled back.
    if (_scroll.hasClients && _scroll.offset < 60) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    if (lines.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text('The transcript appears here a few seconds after the lecture starts.',
              textAlign: TextAlign.center, style: TextStyle(fontFamily: _sans, fontSize: 14, color: _room.muted, height: 1.5)),
        ),
      );
    }
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
        stops: [0, .3, .9, 1],
      ).createShader(r),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(22, 40, 22, 12),
        itemCount: lines.length,
        itemBuilder: (context, k) {
          final i = lines.length - 1 - k;
          final l = lines[i];
          final newest = k == 0;
          return TweenAnimationBuilder<double>(
            key: ValueKey('${l.startMs}:${l.text.hashCode}'),
            tween: Tween(begin: newest ? 0 : 1, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child)),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontFamily: _sans,
                  fontSize: newest ? 18 : 14.5,
                  height: 1.45,
                  fontWeight: newest ? FontWeight.w500 : FontWeight.w400,
                  color: newest ? _room.ink : _room.muted.withValues(alpha: (1 - k * .08).clamp(.45, 1)),
                ),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${_clock(l.startMs)}  ', style: TextStyle(fontSize: 10.5, color: _room.time)),
                  TextSpan(text: l.text),
                ])),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The tools, floating: Mark · Type · record · Pencil · Board.
class _Dock extends StatelessWidget {
  const _Dock({required this.state, required this.recording, required this.paused});
  final _LiveSessionHubPageState state;
  final bool recording, paused;

  @override
  Widget build(BuildContext context) {
    final r = state._recorder;
    final mine = r != null && r.isActive;
    return Container(
      height: 76,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_room.dockTop, _room.dockBottom]),
        border: Border.all(color: _room.line.withValues(alpha: .7)),
        boxShadow: [BoxShadow(color: _room.shadow, blurRadius: 30, offset: const Offset(0, 14))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MarkTool(onTap: state._mark),
          _DockTool(icon: Icons.keyboard_rounded, label: 'Type', onTap: () => state._open(_HubView.typewriter)),
          _RecordKnob(
            recording: recording,
            paused: paused,
            onTap: mine
                ? () {
                    HapticFeedback.mediumImpact();
                    paused ? r.resume() : r.pause();
                  }
                : null,
          ),
          _DockTool(icon: Icons.gesture_rounded, label: 'Pencil', onTap: () => state._open(_HubView.pencil)),
          _DockTool(icon: Icons.photo_camera_outlined, label: 'Board', onTap: state._board),
        ],
      ),
    );
  }
}

class _DockTool extends StatelessWidget {
  const _DockTool({required this.icon, required this.label, required this.onTap, this.color, this.iconWidget});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: _Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            width: 56,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: _room.tool, borderRadius: BorderRadius.circular(14)),
                  child: iconWidget ?? Icon(icon, size: 21, color: color ?? _room.ink),
                ),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontFamily: _sans, fontSize: 10.5, color: _room.toolLabel)),
              ],
            ),
          ),
        ),
      );
}

/// ★ Mark: the star pops and throws sparks.
class _MarkTool extends StatefulWidget {
  const _MarkTool({required this.onTap});
  final Future<void> Function() onTap;

  @override
  State<_MarkTool> createState() => _MarkToolState();
}

class _MarkToolState extends State<_MarkTool> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          _DockTool(
            icon: Icons.star_rounded,
            label: 'Mark',
            color: _roomGold,
            iconWidget: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Transform.scale(
                scale: 1 + .3 * math.sin(math.pi * _c.value.clamp(0, .5) * 2),
                child: const Icon(Icons.star_rounded, size: 21, color: _roomGold),
              ),
            ),
            onTap: () {
              HapticFeedback.heavyImpact();
              unawaited(_c.forward(from: 0));
              unawaited(widget.onTap());
            },
          ),
          Positioned(
            top: 20,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) => CustomPaint(size: Size.zero, painter: _Sparks(_c.value)),
              ),
            ),
          ),
        ],
      );
}

class _Sparks extends CustomPainter {
  _Sparks(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t == 0 || t == 1) return;
    final e = Curves.easeOutCubic.transform(t);
    for (var k = 0; k < 8; k++) {
      final a = k / 8 * math.pi * 2;
      final o = Offset(math.cos(a), math.sin(a)) * (8 + 34 * e) - Offset(0, 14 * e);
      canvas.drawCircle(o, 2.4 * (1 - t) + .6, Paint()..color = _roomGold.withValues(alpha: 1 - t));
    }
  }

  @override
  bool shouldRepaint(_Sparks old) => old.t != t;
}

/// The record knob: round while recording, a soft square when paused.
class _RecordKnob extends StatelessWidget {
  const _RecordKnob({required this.recording, required this.paused, required this.onTap});
  final bool recording, paused;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: paused ? 'Resume recording' : (recording ? 'Pause recording' : 'Recording'),
        excludeSemantics: true,
        child: Transform.translate(
          offset: const Offset(0, -14),
          child: _Pressable(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(paused ? 18 : 30),
                gradient: RadialGradient(
                  center: const Alignment(-.3, -.4),
                  colors: recording || paused ? const [Color(0xFFFF6B5E), _roomRed, Color(0xFF8E0C18)] : [_room.toolLabel, _room.muted, _room.soft],
                  stops: const [0, .55, 1],
                ),
                boxShadow: [BoxShadow(color: (recording ? _roomRed : Colors.black).withValues(alpha: .45), blurRadius: 22, offset: const Offset(0, 8))],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(
                  paused ? Icons.mic_rounded : (onTap == null ? Icons.graphic_eq_rounded : Icons.pause_rounded),
                  key: ValueKey('$paused${onTap == null}'),
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
        ),
      );
}
