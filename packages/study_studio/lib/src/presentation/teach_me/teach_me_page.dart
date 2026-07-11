import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/topic.dart';

class _Msg {
  _Msg(this.text, {required this.fromUser});
  final String text;
  final bool fromUser;
}

class TeachMePage extends ConsumerStatefulWidget {
  const TeachMePage({super.key, required this.studioId, required this.topicId});
  final String studioId;
  final String topicId;

  @override
  ConsumerState<TeachMePage> createState() => _TeachMePageState();
}

class _TeachMePageState extends ConsumerState<TeachMePage> {
  final _controller = TextEditingController();
  final _messages = <_Msg>[];
  bool _thinking = false;
  bool _greeted = false;

  static const _quick = [
    'Explain Simply',
    'Give Example',
    'Compare',
    'Explain Step-by-Step',
    'Common Mistakes',
    'Why It Matters',
    'Make Analogy',
  ];

  Future<void> _send(Topic topic, String text) async {
    if (text.trim().isEmpty || _thinking) return;
    setState(() {
      _messages.add(_Msg(text, fromUser: true));
      _thinking = true;
      _controller.clear();
    });
    final reply =
        await ref.read(aiServiceProvider).teach(topic: topic, message: text);
    if (!mounted) return;
    setState(() {
      _messages.add(_Msg(reply, fromUser: false));
      _thinking = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(studioProvider(widget.studioId));
    return async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (studio) {
        final topic = studio.topics.firstWhere((t) => t.id == widget.topicId);
        if (!_greeted) {
          _greeted = true;
          _messages.add(_Msg(
            "Hi! Let's work through ${topic.title}. Ask me anything, or tap a button below. "
            "I'll only use what's in your uploaded material.",
            fromUser: false,
          ));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text('Teach Me · ${topic.title}'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/study/${widget.studioId}/topics/${topic.id}'),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(CockpitSpacing.lg),
                  itemCount: _messages.length + (_thinking ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == _messages.length) {
                      return const _Bubble(text: '…', fromUser: false);
                    }
                    final m = _messages[i];
                    return _Bubble(text: m.text, fromUser: m.fromUser);
                  },
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.lg),
                  itemCount: _quick.length,
                  separatorBuilder: (_, _) => const SizedBox(width: CockpitSpacing.sm),
                  itemBuilder: (_, i) => ActionChip(
                    label: Text(_quick[i]),
                    onPressed: () => _send(topic, _quick[i]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(CockpitSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(hintText: 'Ask anything…'),
                        onSubmitted: (v) => _send(topic, v),
                      ),
                    ),
                    const SizedBox(width: CockpitSpacing.sm),
                    IconButton.filled(
                      onPressed: () => _send(topic, _controller.text),
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.fromUser});
  final String text;
  final bool fromUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: CockpitSpacing.md),
        padding: const EdgeInsets.all(CockpitSpacing.md),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: fromUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(CockpitRadii.lg),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: fromUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
