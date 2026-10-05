import 'dart:async';

import 'package:flutter/material.dart';

import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';
import 'study_build_run.dart';
import 'study_create_mobile.dart';

/// The phone's building page: the overall percentage, what is happening,
/// and each file on its way in. After a few seconds two ways out fade in:
/// into the studio, or back home while it builds.
class StudyBuildingMobile extends StatefulWidget {
  const StudyBuildingMobile({
    super.key,
    required this.run,
    required this.onProceed,
    required this.onBackground,
    this.actionsAfter = const Duration(seconds: 5),
  });

  final StudyBuildRun run;
  final VoidCallback onProceed;
  final VoidCallback onBackground;

  /// When the two buttons show (at once if it is done sooner).
  final Duration actionsAfter;

  @override
  State<StudyBuildingMobile> createState() => _StudyBuildingMobileState();
}

class _StudyBuildingMobileState extends State<StudyBuildingMobile> {
  Timer? _timer;
  var _actions = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.actionsAfter, () {
      if (mounted) setState(() => _actions = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance;
    return Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(title: widget.run.title, onBack: widget.onBackground),
        child: ListenableBuilder(
          listenable: widget.run,
          builder: (context, _) {
            final run = widget.run;
            final shown = _actions || run.isDone || run.isFailed;
            final files = run.files
                .where((f) => f.stage != FileStage.skipped)
                .toList();
            final size = files.fold<int>(0, (sum, f) => sum + f.file.size);
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(24, top + 18, 24, 0),
                  child: SmAppear(index: 0, child: _Progress(run: run)),
                ),
                const SizedBox(height: 26),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SmAppear(
                    index: 1,
                    child: Row(
                      children: [
                        Text(
                          '${files.length} '
                          '${files.length == 1 ? 'file' : 'files'}',
                          style: t.title.copyWith(fontSize: 14),
                        ),
                        const Spacer(),
                        Text(smFormatSize(size), style: t.small),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ShaderMask(
                    // The list fades out above the buttons.
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.88, 1],
                      colors: [Colors.white, Colors.white, Colors.transparent],
                    ).createShader(r),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      itemCount: files.length,
                      itemBuilder: (context, i) => SmAppear(
                        index: 2 + i.clamp(0, 6),
                        child: _FileRow(
                          file: files[i],
                          first: i == 0,
                          onRetry: () => run.retry(files[i]),
                          onSkip: () => run.skip(files[i]),
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: _Actions(
                      shown: shown,
                      run: run,
                      onProceed: widget.onProceed,
                      onBackground: widget.onBackground,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The big percentage, the stage, the bar, the time left.
class _Progress extends StatelessWidget {
  const _Progress({required this.run});

  final StudyBuildRun run;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final reduce = smReduceMotion(context);
    final tint = run.isFailed
        ? c.accent
        : run.isDone
        ? const Color(0xFF30A46C)
        : c.accentSoft;
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: run.progress),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => Column(
            children: [
              Text.rich(
                TextSpan(
                  text: '${(value * 100).floor()}',
                  children: [
                    TextSpan(
                      text: '%',
                      style: TextStyle(fontSize: 26, color: c.muted),
                    ),
                  ],
                ),
                semanticsLabel: '${(run.progress * 100).floor()} percent',
                style: TextStyle(
                  fontFamily: SmFonts.heading,
                  fontSize: 58,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                  color: c.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.4),
                      end: Offset.zero,
                    ).animate(a),
                    child: child,
                  ),
                ),
                child: Text(
                  run.stageText,
                  key: ValueKey(run.stageText),
                  textAlign: TextAlign.center,
                  style: t.body.copyWith(
                    color: tint,
                    fontFamily: SmFonts.heading,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  height: 6,
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: c.line)),
                      FractionallySizedBox(
                        widthFactor: value.clamp(0, 1),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            gradient: LinearGradient(
                              colors: run.isDone
                                  ? const [Color(0xFF30A46C), Color(0xFF46C08A)]
                                  : [c.accent, const Color(0xFFFF7A7F)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(run.eta, style: t.small),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.first,
    required this.onRetry,
    required this.onSkip,
  });

  final BuildFile file;
  final bool first;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final failed = file.stage == FileStage.failed;
    final busy =
        file.stage == FileStage.uploading || file.stage == FileStage.reading;
    final Widget status = switch (file.stage) {
      FileStage.queued => Text(
        'Queued',
        style: t.small.copyWith(color: c.hint),
      ),
      FileStage.uploading => Text(
        'Uploading',
        style: t.small.copyWith(color: c.accentSoft),
      ),
      FileStage.reading => Text(
        'Reading…',
        style: t.small.copyWith(color: c.accentSoft),
      ),
      FileStage.done => const Icon(
        Icons.check_circle_rounded,
        size: 20,
        color: Color(0xFF30A46C),
      ),
      FileStage.failed => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmPressable(
            semanticLabel: 'Retry ${file.file.name}',
            haptic: () {},
            onTap: onRetry,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(
                'Retry',
                style: t.small.copyWith(
                  color: c.accentSoft,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          SmPressable(
            semanticLabel: 'Skip ${file.file.name}',
            haptic: () {},
            scale: 0.85,
            onTap: onSkip,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close_rounded, size: 16, color: c.hint),
            ),
          ),
        ],
      ),
      FileStage.skipped => const SizedBox.shrink(),
    };
    return Container(
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.line)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: failed
                      ? Container(
                          key: const ValueKey('failed'),
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: c.accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            Icons.error_outline_rounded,
                            size: 17,
                            color: c.accentSoft,
                          ),
                        )
                      : SmFileTypeIcon(
                          key: const ValueKey('type'),
                          type: file.file.type,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    file.file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(
                      color: failed ? c.accentSoft : c.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: ScaleTransition(scale: a, child: child),
                  ),
                  child: KeyedSubtree(key: ValueKey(file.stage), child: status),
                ),
              ],
            ),
          ),
          // The file being worked on: a light running under its row.
          if (busy)
            Positioned(
              left: 42,
              right: 0,
              bottom: 0,
              child: _Sweep(color: c.accent),
            ),
        ],
      ),
    );
  }
}

/// A short light running along a hairline, over and over.
class _Sweep extends StatefulWidget {
  const _Sweep({required this.color});

  final Color color;

  @override
  State<_Sweep> createState() => _SweepState();
}

class _SweepState extends State<_Sweep> with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (smReduceMotion(context)) {
      _run.stop();
    } else if (!_run.isAnimating) {
      _run.repeat();
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: AnimatedBuilder(
        animation: _run,
        builder: (context, _) {
          final x = -1.6 + 3.2 * Curves.easeInOut.transform(_run.value);
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(x - 0.5, 0),
                end: Alignment(x + 0.5, 0),
                colors: [
                  widget.color.withValues(alpha: 0),
                  widget.color,
                  widget.color.withValues(alpha: 0),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Into the studio, or home while it builds; on a failed build, Try again.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.shown,
    required this.run,
    required this.onProceed,
    required this.onBackground,
  });

  final bool shown;
  final StudyBuildRun run;
  final VoidCallback onProceed;
  final VoidCallback onBackground;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    Widget button(
      String label,
      IconData icon, {
      required VoidCallback onTap,
      bool filled = false,
      void Function() haptic = SmHaptics.tap,
    }) {
      final color = filled ? Colors.white : c.text;
      return SmPressable(
        semanticLabel: label,
        haptic: haptic,
        onTap: shown ? onTap : null,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: filled ? c.accent : c.raised,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: t.body.copyWith(
                  color: color,
                  fontSize: 14,
                  fontFamily: SmFonts.heading,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final failedBuild = run.isFailed;
    return AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: shown ? Offset.zero : const Offset(0, 0.15),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          ignoring: !shown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (failedBuild)
                button(
                  'Try again',
                  Icons.refresh_rounded,
                  filled: true,
                  onTap: run.retryBuild,
                )
              else
                button(
                  run.isDone ? 'Open studio' : 'Proceed to studio',
                  Icons.arrow_forward_rounded,
                  filled: true,
                  haptic: SmHaptics.thud,
                  onTap: onProceed,
                ),
              const SizedBox(height: 10),
              button(
                run.isDone ? 'Back to home' : 'Continue in background',
                run.isDone ? Icons.home_outlined : Icons.schedule_rounded,
                onTap: onBackground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
