import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../mobile/mobile_style.dart';
import '../mobile/studio_ready_mobile.dart';

/// The ready moment for a studio, opened by its link (`/ready`).
class ReadyPhonePage extends ConsumerWidget {
  const ReadyPhonePage({super.key, required this.studioId});

  final String studioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SmColors.of(context);
    final base = '/study/$studioId';
    final studio = ref.watch(studioProvider(studioId)).valueOrNull;
    if (studio == null) {
      return Scaffold(
        backgroundColor: c.background,
        body: Center(
          child: CircularProgressIndicator(color: c.accent, strokeWidth: 2.5),
        ),
      );
    }
    return StudioReadyMobile(
      studio: studio,
      onStart: (t) => context.go('$base/teach/${t.id}'),
      onLook: () => context.go(base),
    );
  }
}
