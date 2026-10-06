import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../mobile/mobile_style.dart';
import '../mobile/studio_ready_mobile.dart';
import '../mobile/study_build_run.dart';
import '../mobile/study_building_mobile.dart';

/// A build on the phone: the building page, then — a beat after it
/// finishes — the ready moment, with the first lesson one tap away.
class StudyBuildFlowPhone extends ConsumerStatefulWidget {
  const StudyBuildFlowPhone({super.key, required this.run});

  final StudyBuildRun run;

  @override
  ConsumerState<StudyBuildFlowPhone> createState() =>
      _StudyBuildFlowPhoneState();
}

class _StudyBuildFlowPhoneState extends ConsumerState<StudyBuildFlowPhone> {
  final _started = DateTime.now();
  Duration? _took;
  var _ready = false;
  Timer? _beat;

  @override
  void initState() {
    super.initState();
    widget.run.addListener(_changed);
  }

  @override
  void dispose() {
    widget.run.removeListener(_changed);
    _beat?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!widget.run.isDone || _beat != null || _ready) return;
    _took = DateTime.now().difference(_started);
    final id = widget.run.studioId;
    if (id != null) ref.invalidate(studioProvider(id));
    ref.invalidate(studioListProvider);
    // Let the bar sit at 100% a moment before the page turns.
    _beat = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  void _toStudio() {
    ref.invalidate(studioListProvider);
    final run = widget.run;
    final id = run.studioId;
    final build = run.buildId;
    context.go(
      id == null
          ? '/study'
          : build == null || run.isDone
          ? '/study/$id'
          : '/study/$id?building=$build',
    );
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final id = run.studioId;
    final Widget page;
    if (_ready && id != null) {
      final studio = ref.watch(studioProvider(id)).valueOrNull;
      page = studio == null
          ? Scaffold(
              key: const ValueKey('wait'),
              backgroundColor: SmColors.of(context).background,
              body: Center(
                child: CircularProgressIndicator(
                  color: SmColors.of(context).accent,
                  strokeWidth: 2.5,
                ),
              ),
            )
          : StudioReadyMobile(
              key: const ValueKey('ready'),
              studio: studio,
              builtIn: _took,
              updated: run.updating,
              onStart: (t) => context.go('/study/$id/teach/${t.id}'),
              onLook: () => context.go('/study/$id'),
            );
    } else {
      page = StudyBuildingMobile(
        key: const ValueKey('building'),
        run: run,
        onProceed: _toStudio,
        onBackground: () {
          ref.invalidate(studioListProvider);
          context.go(run.updating && id != null ? '/study/$id' : '/study');
        },
      );
    }
    return AnimatedSwitcher(
      duration: smReduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 520),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(a),
          child: child,
        ),
      ),
      child: page,
    );
  }
}
