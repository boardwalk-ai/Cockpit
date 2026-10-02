import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../data/gw_api.dart';
import 'mobile_motion.dart';
import 'mobile_theme.dart';

/// Ask Octo: a bottom sheet for one question about using the app and one
/// short answer. It knows the app, not the user's essay.
Future<void> showGwOctoSheet(
  BuildContext context, {
  required Future<String> Function(String question) ask,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => _OctoSheet(ask: ask),
  );
}

class _OctoSheet extends StatefulWidget {
  const _OctoSheet({required this.ask});

  final Future<String> Function(String question) ask;

  @override
  State<_OctoSheet> createState() => _OctoSheetState();
}

class _OctoSheetState extends State<_OctoSheet> {
  static const _limit = 500;
  static const _suggestions = [
    'Where is my essay?',
    'How do I change the essay?',
    'What do OctoCredits pay for?',
  ];

  final _input = TextEditingController();
  String? _question;
  String? _answer;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final question = (text ?? _input.text).trim();
    if (question.isEmpty || _loading) return;
    _input.clear();
    setState(() {
      _question = question;
      _answer = null;
      _error = null;
      _loading = true;
    });
    try {
      final answer = await widget.ask(question);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (answer.trim().isEmpty) {
          _error = 'Octo could not answer right now.';
        } else {
          _answer = answer.trim();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is GwApiException
            ? e.message
            : 'Octo could not answer right now.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.vertical(top: Radius.circular(28));
    final media = MediaQuery.of(context);
    final canSend = _input.text.trim().isNotEmpty && !_loading;

    return Padding(
      // Stay above the keyboard.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.8),
            decoration: const BoxDecoration(
              color: Color(0xF01B1C1C),
              borderRadius: radius,
              border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
            ),
            padding: EdgeInsets.fromLTRB(16, 10, 16, 14 + media.padding.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0x40FFFFFF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Image.asset(GwAssets.octo, width: 38, height: 38),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ask Octo',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'Help with using the app',
                            style: TextStyle(
                              color: GwColors.muted,
                              fontFamily: GwFonts.secondary,
                              fontFamilyFallback: GwFonts.secondaryFallback,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      child: _question == null
                          ? _Suggestions(
                              key: const ValueKey('suggestions'),
                              items: _suggestions,
                              onPick: _send,
                            )
                          : _Exchange(
                              key: ValueKey(_question),
                              question: _question!,
                              answer: _answer,
                              error: _error,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.only(left: 16, right: 5),
                  decoration: BoxDecoration(
                    color: const Color(0x0FFFFFFF),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: const Color(0x1AFFFFFF)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          maxLength: _limit,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          cursorColor: GwColors.accentSoft,
                          style: kGwBody,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            counterText: '',
                            hintText: 'Ask about the app...',
                            hintStyle: TextStyle(
                              color: GwColors.hint,
                              fontFamily: GwFonts.secondary,
                              fontFamilyFallback: GwFonts.secondaryFallback,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      GwPressable(
                        tooltip: 'Ask',
                        haptic: GwHaptic.medium,
                        onTap: canSend ? _send : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: canSend
                                ? GwColors.accent
                                : const Color(0x14FFFFFF),
                          ),
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            size: 20,
                            color: canSend ? Colors.white : GwColors.hint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({super.key, required this.items, required this.onPick});

  final List<String> items;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    // Full width, so the switcher does not centre it.
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TRY ASKING', style: kGwLabel),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                GwPressable(
                  haptic: GwHaptic.selection,
                  pressedScale: 0.96,
                  onTap: () => onPick(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: GwColors.chip,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: GwColors.border),
                    ),
                    child: Text(
                      item,
                      style: kGwBody.copyWith(fontSize: 13.5, height: 1.2),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The question, and under it the answer, the wait, or what went wrong.
class _Exchange extends StatelessWidget {
  const _Exchange({
    super.key,
    required this.question,
    required this.answer,
    required this.error,
  });

  final String question;
  final String? answer;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    final answer = this.answer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(left: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(question, style: kGwBody.copyWith(fontSize: 14.5)),
          ),
        ),
        const SizedBox(height: 12),
        if (error != null)
          Text(
            error,
            style: kGwBody.copyWith(color: GwColors.accentSoft, fontSize: 14),
          )
        else if (answer != null)
          SelectableText(answer, style: kGwBody)
        else
          Semantics(
            label: 'Octo is thinking',
            child: const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: GwColors.accentSoft,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
