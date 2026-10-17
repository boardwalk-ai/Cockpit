part of 'live_session_hub_page.dart';

// ===========================================================================
// Phone: solo (records + works) and receiver (the other phone records)
// ===========================================================================
class _PhoneSession extends StatelessWidget {
  const _PhoneSession({required this.state});
  final _LiveSessionHubPageState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final live = state._live;
    final solo = state.widget.role == SessionRole.solo;
    switch (state._view) {
      case _HubView.typewriter:
        return _PhoneTypewriter(state: state);
      case _HubView.pencil:
        final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: landscape
              ? PhoneMagicPencil(
                  key: const ValueKey('pencil'),
                  ink: state._ink,
                  notes: state._notes,
                  onClose: () => state._open(_HubView.cards),
                  top: _PencilTop(state: state),
                )
              : _RotatePrompt(key: const ValueKey('turn'), onBack: () => state._open(_HubView.cards)),
        );
      case _HubView.cards:
        break;
    }
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(CockpitSpacing.md, CockpitSpacing.xs, CockpitSpacing.md, CockpitSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: state._leave,
                  ),
                  Expanded(
                    child: Text(
                      live.title ?? (live.isDemo ? 'Biology 101 · Cellular respiration' : 'Live session'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(onPressed: state._finish, child: const Text('Finish')),
                ],
              ),
              ...[
                if (solo)
                  _SoloRecorderPanel(state: state)
                else
                  _MiniRecordingBar(state: state),
                const SizedBox(height: CockpitSpacing.md),
                Padding(
                  padding: const EdgeInsets.only(left: CockpitSpacing.xs, bottom: CockpitSpacing.xs),
                  child: Text('Live transcript',
                      style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ),
                Expanded(child: _TranscriptFeed(lines: live.lines, compact: solo)),
                const SizedBox(height: CockpitSpacing.md),
                _ToolRow(state: state),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Solo: this phone records — status, time, waveform, pause / stop.
class _SoloRecorderPanel extends StatelessWidget {
  const _SoloRecorderPanel({required this.state});
  final _LiveSessionHubPageState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = state._recorder;
    final demo = state._live.isDemo;
    if (!state.widget.record) {
      return _Pill(icon: Icons.mic_off_rounded, text: 'Not recording this session', color: scheme.onSurfaceVariant);
    }
    if (r != null && r.status == RecorderStatus.failed) {
      return _RecorderProblem(message: r.error ?? 'Recording stopped.', onRetry: r.start);
    }
    final recording = demo || (r?.isRecording ?? false);
    final paused = r?.isPaused ?? false;
    final stopped = r?.status == RecorderStatus.stopped;
    final label = switch (r?.status) {
      RecorderStatus.paused => 'Paused',
      RecorderStatus.stopping => 'Saving the recording…',
      RecorderStatus.stopped => 'Recording saved',
      RecorderStatus.idle || RecorderStatus.starting => 'Starting the microphone…',
      _ => 'Recording on this phone',
    };
    return Column(
      children: [
        _Pill(
          icon: Icons.circle,
          text: label,
          color: recording ? scheme.primary : scheme.onSurfaceVariant,
          blink: recording,
        ),
        const SizedBox(height: CockpitSpacing.sm),
        Text(
          _clock(state._elapsedMs),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: CockpitSpacing.xs),
        _Waveform(height: 40, level: () => demo ? null : r?.level, active: recording),
        if (r != null && r.behindSeconds > 0)
          Text('Uploading · ${r.behindSeconds}s behind',
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: CockpitSpacing.sm),
        if (!stopped)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: paused ? 'Resume' : 'Pause',
                onPressed: r == null ? null : (paused ? r.resume : r.pause),
                icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
              ),
              const SizedBox(width: CockpitSpacing.md),
              IconButton.filled(
                tooltip: 'Stop recording',
                style: IconButton.styleFrom(
                  backgroundColor: scheme.primary.withValues(alpha: 0.18),
                  foregroundColor: scheme.primary,
                ),
                onPressed: r == null || !r.isActive ? null : () => state._confirmLeave(),
                icon: const Icon(Icons.stop_rounded),
              ),
            ],
          ),
      ],
    );
  }
}

/// One line: who records and for how long (receiver, or over the pencil).
class _MiniRecordingBar extends StatelessWidget {
  const _MiniRecordingBar({required this.state});
  final _LiveSessionHubPageState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = state._recorder;
    final live = state._live;
    final mine = r != null;
    final recording = mine ? r.isRecording : live.isRecording;
    final paused = mine ? r.isPaused : live.recordingState == 'paused';
    final who = live.recorderName ?? 'Your phone';
    final String text;
    if (mine) {
      text = paused ? 'Paused' : (recording ? 'Recording on this phone' : 'Not recording');
    } else if (recording) {
      text = '$who is recording';
    } else if (paused) {
      text = 'Recording paused on $who';
    } else if (live.recordingState == 'stopped' || live.recordingState == 'assembled') {
      text = 'Recording finished';
    } else {
      text = 'Waiting for ${live.recorderName ?? 'your phone'} to start recording';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.md, vertical: CockpitSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
      ),
      child: Row(
        children: [
          _BlinkDot(color: recording ? scheme.primary : scheme.onSurfaceVariant, blink: recording),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                if (recording || paused)
                  Text(_clock(state._elapsedMs),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
              ],
            ),
          ),
          SizedBox(
            width: 64,
            child: _Waveform(height: 22, level: () => r?.level, active: recording, bars: 12),
          ),
          if (mine && r.isActive)
            IconButton(
              tooltip: paused ? 'Resume' : 'Pause',
              visualDensity: VisualDensity.compact,
              onPressed: paused ? r.resume : r.pause,
              icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}

/// The transcript as it arrives, newest at the bottom.
class _TranscriptFeed extends StatefulWidget {
  const _TranscriptFeed({required this.lines, this.compact = false});
  final List<TranscriptLine> lines;

  /// Solo: a shorter feed under the recorder.
  final bool compact;

  @override
  State<_TranscriptFeed> createState() => _TranscriptFeedState();
}

class _TranscriptFeedState extends State<_TranscriptFeed> {
  final _scroll = ScrollController();
  int _seen = 0;

  @override
  void didUpdateWidget(covariant _TranscriptFeed old) {
    super.didUpdateWidget(old);
    if (widget.lines.length != _seen) {
      // Follow the newest line unless the reader scrolled up.
      final atEnd = !_scroll.hasClients || _scroll.position.extentAfter < 80;
      _seen = widget.lines.length;
      if (atEnd) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(_scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = widget.lines;
    if (lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(CockpitSpacing.lg),
          child: Text(
            'The transcript appears here a few seconds after the lecture starts.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: EdgeInsets.zero,
      itemCount: lines.length,
      separatorBuilder: (_, _) => const SizedBox(height: CockpitSpacing.sm),
      itemBuilder: (context, i) {
        final l = lines[i];
        final newest = i == lines.length - 1;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.md, vertical: CockpitSpacing.sm),
          decoration: BoxDecoration(
            color: newest ? scheme.surfaceContainerHigh : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(CockpitRadii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_clock(l.startMs),
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(l.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: newest ? scheme.onSurface : scheme.onSurfaceVariant,
                    height: 1.4,
                  )),
            ],
          ),
        );
      },
    );
  }
}

/// Mark · Pencil · Board · Note.
class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.state});
  final _LiveSessionHubPageState state;

  @override
  Widget build(BuildContext context) {
    final gold = CockpitColors.brand.tertiary;
    return Row(
      children: [
        _Tool(
          icon: Icons.star_rounded,
          label: 'Mark',
          background: gold,
          foreground: const Color(0xFF3A2A05),
          onTap: state._mark,
        ),
        const SizedBox(width: CockpitSpacing.sm),
        _Tool(icon: Icons.gesture_rounded, label: 'Pencil', onTap: () => state._open(_HubView.pencil)),
        const SizedBox(width: CockpitSpacing.sm),
        _Tool(icon: Icons.photo_camera_outlined, label: 'Board', onTap: state._board),
        const SizedBox(width: CockpitSpacing.sm),
        _Tool(icon: Icons.keyboard_rounded, label: 'Type', onTap: () => state._open(_HubView.typewriter)),
      ],
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap, this.background, this.foreground});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = foreground ?? scheme.onSurface;
    return Expanded(
      child: Material(
        color: background ?? scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(CockpitRadii.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(height: 2),
                Text(label, style: theme.textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Recorder: this phone only records, for the receiver
// ===========================================================================
class _RecorderScreen extends StatelessWidget {
  const _RecorderScreen({required this.state});
  final _LiveSessionHubPageState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = state._recorder;
    final live = state._live;
    final to = live.otherDeviceName ?? 'your other device';
    final status = r?.status ?? (live.isDemo ? RecorderStatus.recording : RecorderStatus.starting);
    final recording = status == RecorderStatus.recording;
    final paused = status == RecorderStatus.paused;

    final Widget body;
    if (status == RecorderStatus.failed) {
      body = _RecorderProblem(message: r?.error ?? 'Recording stopped.', onRetry: r?.start);
    } else if (status == RecorderStatus.stopped || status == RecorderStatus.stopping) {
      final done = status == RecorderStatus.stopped;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          done
              ? Icon(Icons.check_circle_rounded, size: 64, color: CockpitColors.brand.success)
              : const CircularProgressIndicator(),
          const SizedBox(height: CockpitSpacing.lg),
          Text(done ? 'Recording saved' : 'Sending the last part…', style: theme.textTheme.headlineSmall),
          const SizedBox(height: CockpitSpacing.sm),
          Text(_clock(state._elapsedMs), style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
          if (done) ...[
            const SizedBox(height: CockpitSpacing.xl),
            FilledButton(onPressed: () => context.go('/notes'), child: const Text('Done')),
          ],
        ],
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MicPulse(level: () => r?.level ?? (live.isDemo ? null : 0), active: recording),
          const SizedBox(height: CockpitSpacing.xl),
          Text(
            status == RecorderStatus.starting || status == RecorderStatus.idle
                ? 'Starting the microphone…'
                : _clock(state._elapsedMs),
            style: (status == RecorderStatus.recording || paused
                    ? theme.textTheme.displayMedium
                    : theme.textTheme.titleLarge)
                ?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: CockpitSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.xl),
            child: Text(
              paused
                  ? 'Paused. Resume when the lecture continues.'
                  : 'Sending to $to. Keep this phone near the speaker. You can lock the screen.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: CockpitSpacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                (r?.behindSeconds ?? 0) > 0 ? Icons.cloud_sync_outlined : Icons.cloud_done_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: CockpitSpacing.xs),
              Text(
                (r?.behindSeconds ?? 0) > 0 ? 'Uploading · ${r!.behindSeconds}s behind' : 'Uploaded · up to date',
                style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      );
    }

    final active = recording || paused;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CockpitSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(width: CockpitSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recording', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          'for ${live.title ?? 'your session'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: active ? 'Stop recording' : 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: state._leave,
                  ),
                ],
              ),
              Expanded(child: Center(child: body)),
              if (active)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: paused ? r?.resume : r?.pause,
                        icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                        label: Text(paused ? 'Resume' : 'Pause'),
                      ),
                    ),
                    const SizedBox(width: CockpitSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: CockpitColors.brand.tertiary,
                          foregroundColor: const Color(0xFF3A2A05),
                        ),
                        onPressed: state._mark,
                        icon: const Icon(Icons.star_rounded),
                        label: const Text('Mark'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecorderProblem extends StatelessWidget {
  const _RecorderProblem({required this.message, this.onRetry});
  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.mic_off_rounded, color: scheme.error),
          const SizedBox(width: CockpitSpacing.sm),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

// ===========================================================================
// Desktop top bar: who records
// ===========================================================================
class _RecordingStatus extends StatelessWidget {
  const _RecordingStatus({required this.state});
  final _LiveSessionHubPageState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = state._recorder;
    final live = state._live;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    if (r != null && r.status == RecorderStatus.failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_off_rounded, size: 16, color: scheme.error),
          const SizedBox(width: CockpitSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(r.error ?? 'Recording stopped.', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
          ),
          TextButton(onPressed: r.start, child: const Text('Try again')),
        ],
      );
    }
    final mine = r != null;
    final recording = mine ? r.isRecording : live.isRecording;
    final paused = mine ? r.isPaused : live.recordingState == 'paused';
    final String text;
    if (state.widget.role == SessionRole.solo && !state.widget.record) {
      text = 'Not recording';
    } else if (mine) {
      text = switch (r.status) {
        RecorderStatus.recording => 'Recording on this computer',
        RecorderStatus.paused => 'Recording paused',
        RecorderStatus.stopping => 'Saving the recording…',
        RecorderStatus.stopped => 'Recording saved',
        _ => 'Starting the microphone…',
      };
    } else if (recording) {
      text = '${live.recorderName ?? 'Your phone'} is recording';
    } else if (paused) {
      text = 'Recording paused on ${live.recorderName ?? 'your phone'}';
    } else if (live.recordingState == 'stopped' || live.recordingState == 'assembled') {
      text = 'Recording finished';
    } else {
      text = 'Waiting for ${live.recorderName ?? 'your phone'} to start recording';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BlinkDot(color: recording ? scheme.primary : scheme.onSurfaceVariant, blink: recording),
        const SizedBox(width: CockpitSpacing.sm),
        Text(text, style: muted),
        if (recording || paused) ...[
          const SizedBox(width: CockpitSpacing.sm),
          Text(_clock(state._elapsedMs),
              style: theme.textTheme.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
        if (mine && r.isActive) ...[
          const SizedBox(width: CockpitSpacing.xs),
          IconButton(
            tooltip: paused ? 'Resume' : 'Pause',
            onPressed: paused ? r.resume : r.pause,
            icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'Stop recording',
            onPressed: state._confirmLeave,
            icon: Icon(Icons.stop_rounded, size: 20, color: scheme.primary),
          ),
        ],
        if (recording || paused)
          IconButton(
            tooltip: 'Mark important',
            onPressed: state._mark,
            icon: Icon(Icons.star_rounded, size: 20, color: CockpitColors.brand.tertiary),
          ),
      ],
    );
  }
}

// ===========================================================================
// Small pieces
// ===========================================================================
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color, this.blink = false});
  final IconData icon;
  final String text;
  final Color color;
  final bool blink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == Icons.circle) _BlinkDot(color: color, blink: blink) else Icon(icon, size: 16, color: color),
          const SizedBox(width: CockpitSpacing.xs),
          Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _BlinkDot extends StatefulWidget {
  const _BlinkDot({required this.color, required this.blink});
  final Color color;
  final bool blink;

  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    if (widget.blink) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _BlinkDot old) {
    super.didUpdateWidget(old);
    if (widget.blink && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.blink && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.25).animate(_c),
        child: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      );
}

/// Bars that follow the mic level; [level] null (another device's mic, or
/// the demo) draws a lively stand-in while [active].
class _Waveform extends StatefulWidget {
  const _Waveform({required this.height, required this.level, required this.active, this.bars = 28});
  final double height;
  final double? Function() level;
  final bool active;
  final int bars;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform> {
  late List<double> _v = List.filled(widget.bars, 0.08);
  Timer? _t;
  final _rand = math.Random();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      final l = widget.active ? (widget.level() ?? (0.15 + _rand.nextDouble() * 0.6)) : 0.0;
      setState(() => _v = [..._v.skip(1), math.max(0.08, l)]);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: widget.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final v in _v)
            Flexible(
              child: Container(
                width: 3,
                height: widget.height * v,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: widget.active ? color : color.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The recorder's big mic, breathing with the level.
class _MicPulse extends StatefulWidget {
  const _MicPulse({required this.level, required this.active});
  final double? Function() level;
  final bool active;

  @override
  State<_MicPulse> createState() => _MicPulseState();
}

class _MicPulseState extends State<_MicPulse> {
  double _scale = 1;
  Timer? _t;
  final _rand = math.Random();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!mounted) return;
      final l = widget.active ? (widget.level() ?? _rand.nextDouble() * 0.6) : 0.0;
      setState(() => _scale = 1 + l * 0.35);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final red = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedScale(
            scale: _scale,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(color: red.withValues(alpha: 0.16), shape: BoxShape.circle),
            ),
          ),
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: widget.active ? red : red.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_rounded, color: Colors.white, size: 40),
          ),
        ],
      ),
    );
  }
}

/// Over the landscape page: who records, the newest transcript line.
class _PencilTop extends StatelessWidget {
  const _PencilTop({required this.state});
  final _LiveSessionHubPageState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final line = state._live.lines.lastOrNull;
    return Row(
      children: [
        _RecordingPill(state: state),
        const SizedBox(width: CockpitSpacing.sm),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              children: [
                Icon(Icons.format_quote_rounded, size: 16, color: CockpitColors.brand.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      line?.text ?? 'Live transcript',
                      key: ValueKey(line?.id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
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
