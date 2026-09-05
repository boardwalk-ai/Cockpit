import 'dart:async';

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'outline_models.dart';

enum PageMode { start, loading, outline }

class GuidedOutlinePage extends StatefulWidget {
  const GuidedOutlinePage({super.key});

  @override
  State<GuidedOutlinePage> createState() => _GuidedOutlinePageState();
}

class _GuidedOutlinePageState extends State<GuidedOutlinePage> {
  final prompt = TextEditingController();
  final hiddenOpen = ValueNotifier<bool>(false);

  PageMode mode = PageMode.start;
  OutlineKind? filter;
  String loadText = 'Analyzing your assignment...';
  List<OutlineSection> items = [];

  @override
  void dispose() {
    prompt.dispose();
    hiddenOpen.dispose();
    super.dispose();
  }

  Future<void> analyze() async {
    if (prompt.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add your assignment first.')),
      );
      return;
    }

    setState(() {
      loadText = 'Analyzing your assignment...';
      mode = PageMode.loading;
    });

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    setState(() => mode = PageMode.outline);
  }

  Future<void> autoOutline() async {
    setState(() {
      loadText = 'Lily is generating outlines...';
      mode = PageMode.loading;
    });

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    setState(() {
      items = mockItems();
      filter = null;
      mode = PageMode.outline;
    });
  }

  List<OutlineSection> mockItems() {
    final topic = prompt.text.trim();

    return [
      OutlineSection(
        id: 'intro',
        kind: OutlineKind.introduction,
        title: 'Opening Context and Thesis',
        description:
            'Introduce $topic, establish the central question, and finish with a clear thesis that previews the direction of the essay.',
        selected: true,
        isNew: true,
      ),
      const OutlineSection(
        id: 'body-1',
        kind: OutlineKind.body,
        title: 'The Strongest Supporting Argument',
        description:
            'Develop the first major point with a clear claim, specific reasoning, and evidence that directly supports the thesis.',
        isNew: true,
      ),
      const OutlineSection(
        id: 'body-2',
        kind: OutlineKind.body,
        title: 'Counterargument and Response',
        description:
            'Present a credible opposing view, explain why it matters, and respond to it without weakening the main position.',
        isNew: true,
      ),
      const OutlineSection(
        id: 'body-3',
        kind: OutlineKind.body,
        title: 'Broader Impact and Evidence',
        description:
            'Connect the argument to a wider consequence or real-world effect and use evidence to show why the point matters.',
        isNew: true,
      ),
      const OutlineSection(
        id: 'end',
        kind: OutlineKind.conclusion,
        title: 'Conclusion and Final Position',
        description:
            'Bring the main points together, restate the thesis without repeating it word for word, and end with a focused final thought.',
        isNew: true,
      ),
    ];
  }

  List<OutlineSection> get active =>
      items.where((item) => !item.hidden).toList();

  List<OutlineSection> get hidden =>
      items.where((item) => item.hidden).toList();

  List<OutlineSection> get visible {
    final list = active;
    if (filter == null) return list;
    return list.where((item) => item.kind == filter).toList();
  }

  int count(OutlineKind kind) {
    return active.where((item) => item.kind == kind).length;
  }

  int get selectedCount {
    return active.where((item) => item.selected).length;
  }

  void changeItem(String id, OutlineSection next) {
    setState(() {
      items = [
        for (final item in items)
          if (item.id == id) next else item,
      ];
    });
  }

  void toggleSelect(OutlineSection item) {
    changeItem(item.id, item.copyWith(selected: !item.selected, isNew: false));
  }

  void toggleHide(OutlineSection item) {
    changeItem(
      item.id,
      item.copyWith(hidden: !item.hidden, selected: false, isNew: false),
    );
  }

  void removeItem(String id) {
    setState(() {
      items = items.where((item) => item.id != id).toList();
    });
  }

  void moveItem(OutlineSection item, int step) {
    final old = items.indexWhere((value) => value.id == item.id);
    if (old < 0) return;

    final same = items.where((value) => value.kind == item.kind).toList();
    final pos = same.indexWhere((value) => value.id == item.id);
    final nextPos = pos + step;

    if (nextPos < 0 || nextPos >= same.length) return;

    final target = same[nextPos];
    final next = [...items];
    final targetIndex = next.indexWhere((value) => value.id == target.id);

    next[old] = target;
    next[targetIndex] = item;

    setState(() => items = next);
  }

  Future<void> editItem(OutlineSection item) async {
    final title = TextEditingController(text: item.title);
    final body = TextEditingController(text: item.description);

    final next = await showDialog<OutlineSection>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Outline'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: CockpitSpacing.lg),
                TextField(
                  controller: body,
                  minLines: 4,
                  maxLines: 7,
                  decoration: const InputDecoration(labelText: 'Content'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty || body.text.trim().isEmpty) {
                  return;
                }

                context.pop(
                  item.copyWith(
                    title: title.text.trim(),
                    description: body.text.trim(),
                    isNew: false,
                  ),
                );
              },
              child: const Text('Save Changes'),
            ),
          ],
        );
      },
    );

    title.dispose();
    body.dispose();

    if (next != null && mounted) {
      changeItem(item.id, next);
    }
  }

  Future<void> buildItem() async {
    final title = TextEditingController();
    final body = TextEditingController();
    var kind = OutlineKind.body;

    final next = await showDialog<OutlineSection>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setBox) {
            return AlertDialog(
              title: const Text('Build My Way'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<OutlineKind>(
                      initialValue: kind,
                      decoration: const InputDecoration(labelText: 'Section'),
                      items: [
                        for (final value in OutlineKind.values)
                          DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setBox(() => kind = value);
                        }
                      },
                    ),
                    const SizedBox(height: CockpitSpacing.lg),
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: CockpitSpacing.lg),
                    TextField(
                      controller: body,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(labelText: 'Content'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (title.text.trim().isEmpty || body.text.trim().isEmpty) {
                      return;
                    }

                    context.pop(
                      OutlineSection(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        kind: kind,
                        title: title.text.trim(),
                        description: body.text.trim(),
                        isNew: true,
                      ),
                    );
                  },
                  child: const Text('Add Section'),
                ),
              ],
            );
          },
        );
      },
    );

    title.dispose();
    body.dispose();

    if (next != null && mounted) {
      setState(() => items = [...items, next]);
    }
  }

  Future<void> addOne(OutlineKind kind) async {
    setState(() {
      loadText = 'Lily is generating one paragraph...';
      mode = PageMode.loading;
    });

    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    final id = DateTime.now().microsecondsSinceEpoch.toString();

    final next = switch (kind) {
      OutlineKind.introduction => OutlineSection(
        id: id,
        kind: kind,
        title: 'Alternative Introduction',
        description:
            'Open with a focused hook, introduce ${prompt.text.trim()}, and move directly into the thesis.',
        isNew: true,
      ),
      OutlineKind.body => OutlineSection(
        id: id,
        kind: kind,
        title: 'Additional Supporting Point',
        description:
            'Add one more focused argument with evidence and a clear connection back to the main thesis.',
        isNew: true,
      ),
      OutlineKind.conclusion => OutlineSection(
        id: id,
        kind: kind,
        title: 'Alternative Conclusion',
        description:
            'Close by synthesizing the argument, reinforcing the thesis, and leaving the reader with a concise final implication.',
        isNew: true,
      ),
    };

    setState(() {
      items = [...items, next];
      mode = PageMode.outline;
    });
  }

  Future<void> confirm() async {
    final chosen = active.where((item) => item.selected).toList();
    if (chosen.isEmpty) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Outline'),
          content: SizedBox(
            width: 560,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: chosen.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: CockpitSpacing.md),
                itemBuilder: (context, index) {
                  final item = chosen[index];
                  return _ConfirmCard(item: item);
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => context.pop(true),
              child: const Text('Proceed to Configuration'),
            ),
          ],
        );
      },
    );

    if (go == true && mounted) {
      context.go('/guided-generation/configuration');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      bottomNavigationBar: mode == PageMode.outline
          ? _BottomBar(
              canContinue: selectedCount > 0,
              onBack: () {
                setState(() {
                  mode = PageMode.start;
                  items = [];
                  filter = null;
                });
              },
              onContinue: confirm,
            )
          : null,
      body: Column(
        children: [
          const _TopBar(),
          _Steps(current: mode == PageMode.start ? 0 : 1),
          Expanded(
            child: switch (mode) {
              PageMode.start => _StartPage(prompt: prompt, onSubmit: analyze),
              PageMode.loading => _LoadingPage(text: loadText),
              PageMode.outline => _OutlinePage(
                topic: prompt.text.trim(),
                items: visible,
                allCount: active.length,
                introCount: count(OutlineKind.introduction),
                bodyCount: count(OutlineKind.body),
                endCount: count(OutlineKind.conclusion),
                filter: filter,
                hidden: hidden,
                hiddenOpen: hiddenOpen,
                selectedCount: selectedCount,
                onFilter: (value) => setState(() => filter = value),
                onAuto: autoOutline,
                onBuild: buildItem,
                onOne: addOne,
                onSelect: toggleSelect,
                onEdit: editItem,
                onHide: toggleHide,
                onDelete: removeItem,
                onMove: moveItem,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      color: const Color(0xFF0A0A0A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, box) {
          final desktop = box.maxWidth >= 768;

          return Row(
            children: [
              Image.network(
                'https://raw.githubusercontent.com/boardwalk-ai/OctopilotWeb/main/public/OCTOPILOT.png',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(width: 40),
              ),
              const SizedBox(width: 12),
              Image.network(
                'https://raw.githubusercontent.com/boardwalk-ai/OctopilotWeb/main/public/logoText.png',
                height: 34,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Text(
                  'OctoPilot AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (desktop)
                const _HeaderActions()
              else
                IconButton(
                  onPressed: () {},
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderActions extends StatelessWidget {
  const _HeaderActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: () {},
            icon: Icon(
              Icons.notifications_none_rounded,
              size: 20,
              color: Colors.white.withValues(alpha: 0.48),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const _PlanBadge(),
        const SizedBox(width: 10),
        const _CreditBadge(),
        const SizedBox(width: 12),
        const _HeaderAction(
          text: 'Store',
          icon: Icons.storefront_outlined,
          red: true,
        ),
        const SizedBox(width: 12),
        const _HeaderAction(text: 'Save', icon: Icons.save_outlined),
        const SizedBox(width: 12),
        const _ReportAction(),
        const SizedBox(width: 12),
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFE64A19),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const Text(
            'A',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 10, right: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161719),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF94A6B8),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF94A6B8).withValues(alpha: 0.4),
                  blurRadius: 7,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'GUEST',
            style: TextStyle(
              color: Color(0xFFC2CEDB),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.25,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditBadge extends StatelessWidget {
  const _CreditBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 10, right: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF161719),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 15,
            height: 15,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2410),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFCAA45A), width: 1.5),
            ),
            child: const Icon(
              Icons.star_rounded,
              size: 8,
              color: Color(0xFFD4B15E),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '2,067',
            style: TextStyle(
              color: Color(0xFFF5F5F6),
              fontSize: 14.7,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.15,
              height: 1,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'OCTOCREDITS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.25,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatefulWidget {
  const _HeaderAction({
    required this.text,
    required this.icon,
    this.red = false,
  });

  final String text;
  final IconData icon;
  final bool red;

  @override
  State<_HeaderAction> createState() => _HeaderActionState();
}

class _HeaderActionState extends State<_HeaderAction> {
  bool over = false;

  @override
  Widget build(BuildContext context) {
    final red = widget.red;
    final border = red
        ? const Color(0xFFEF4444).withValues(alpha: over ? 0.4 : 0.25)
        : Colors.white.withValues(alpha: over ? 0.18 : 0.1);
    final bg = red
        ? const Color(0xFFEF4444).withValues(alpha: over ? 0.16 : 0.1)
        : Colors.white.withValues(alpha: over ? 0.08 : 0.05);
    final color = red
        ? Color(over ? 0xFFFECACA : 0xFFFCA5A5)
        : Colors.white.withValues(alpha: over ? 1 : 0.8);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => over = true),
      onExit: (_) => setState(() => over = false),
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                widget.text,
                style: TextStyle(
                  color: color,
                  fontSize: 13.1,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportAction extends StatelessWidget {
  const _ReportAction();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: Colors.white.withValues(alpha: 0.28),
          ),
          const SizedBox(height: 1),
          Text(
            'Report a problem',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.22),
              fontSize: 9,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    const steps = [
      'Instructions',
      'Outlines',
      'Configuration',
      'Format',
      'Generation',
      'Preview',
      'Humanizer',
      'Editor',
      'Export',
    ];

    return Container(
      color: const Color(0xFF0D0D0D),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < steps.length; i++) ...[
                        Transform.scale(
                          scale: i == current ? 1.1 : 1,
                          child: Text(
                            steps[i].toUpperCase(),
                            style: TextStyle(
                              color: i == current
                                  ? const Color(0xFFEF4444)
                                  : i < current
                                  ? const Color(
                                      0xFFEF4444,
                                    ).withValues(alpha: 0.45)
                                  : Colors.white.withValues(alpha: 0.16),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.55,
                              height: 1,
                            ),
                          ),
                        ),
                        if (i != steps.length - 1)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '>>>',
                              style: TextStyle(
                                color: i < current
                                    ? const Color(
                                        0xFFEF4444,
                                      ).withValues(alpha: 0.35)
                                    : Colors.white.withValues(alpha: 0.06),
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'WRITING MODE: GUIDED GENERATION',
                  style: TextStyle(
                    color: Color(0xFFFACC15),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.58,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 3,
            color: Colors.white.withValues(alpha: 0.04),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (current + 1) / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(999),
                    bottomRight: Radius.circular(999),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.8),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartPage extends StatelessWidget {
  const _StartPage({required this.prompt, required this.onSubmit});

  final TextEditingController prompt;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFEF4444);

    return Stack(
      children: [
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 672),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.network(
                    'https://raw.githubusercontent.com/boardwalk-ai/OctopilotWeb/main/public/OCTOPILOT.png',
                    width: 56,
                    height: 56,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.auto_awesome_rounded, size: 42),
                  ),
                  const SizedBox(height: 16),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.7,
                            height: 1.08,
                          ),
                      children: const [
                        TextSpan(text: 'Hey, what are we working on'),
                        TextSpan(
                          text: ', Amirjon',
                          style: TextStyle(color: Color(0xFFF87171)),
                        ),
                        TextSpan(text: '?'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.09),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 40,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Focus(
                          onKeyEvent: (_, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.enter &&
                                !HardwareKeyboard.instance.isShiftPressed) {
                              onSubmit();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                            controller: prompt,
                            minLines: 1,
                            maxLines: 10,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            textAlignVertical: TextAlignVertical.top,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontSize: 15.5,
                                  height: 1.45,
                                ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText:
                                  'Paste your assignment instructions, essay topic, or anything you need help writing…',
                              hintStyle: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    fontSize: 15.5,
                                    height: 1.45,
                                  ),
                              contentPadding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minHeight: 22),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 36,
                          child: Row(
                            children: [
                              _SmallAction(
                                icon: Icons.attach_file_rounded,
                                onTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'File attachment is mocked in this frontend draft.',
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 4),
                              _SmallAction(
                                icon: Icons.upload_file_outlined,
                                label: 'Rubric',
                                onTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Rubric upload is mocked in this frontend draft.',
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              Container(
                                height: 24,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      'Imperfect Mode',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.28,
                                            ),
                                            fontSize: 11,
                                            height: 1,
                                          ),
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      'PRO',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: const Color(
                                              0xFFFACC15,
                                            ).withValues(alpha: 0.72),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                            height: 1,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: prompt,
                                builder: (context, value, _) {
                                  final ready = value.text.trim().isNotEmpty;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: ready
                                          ? red
                                          : Colors.white.withValues(
                                              alpha: 0.06,
                                            ),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: ready
                                          ? [
                                              BoxShadow(
                                                color: red.withValues(
                                                  alpha: 0.3,
                                                ),
                                                blurRadius: 16,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: IconButton(
                                      onPressed: ready ? onSubmit : null,
                                      padding: EdgeInsets.zero,
                                      icon: Icon(
                                        Icons.arrow_upward_rounded,
                                        size: 18,
                                        color: ready
                                            ? Colors.white
                                            : Colors.white.withValues(
                                                alpha: 0.2,
                                              ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Text(
                        'Press',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.18),
                          fontSize: 11,
                        ),
                      ),
                      const _KeyBox(text: 'Enter'),
                      Text(
                        'to analyze ·',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.18),
                          fontSize: 11,
                        ),
                      ),
                      const _KeyBox(text: 'Shift+Enter'),
                      Text(
                        'for new line · Up to 3 files',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.18),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          bottom: 22,
          child: OutlinedButton.icon(
            onPressed: () => context.go('/'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.35),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            icon: Image.network(
              'https://raw.githubusercontent.com/boardwalk-ai/OctopilotWeb/main/public/OCTOPILOT.png',
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.chevron_left_rounded, size: 18),
            ),
            label: const Text('Back'),
          ),
        ),
      ],
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.onTap, this.label});

  final IconData icon;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 32,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: label == null ? 17 : 14,
                color: Colors.white.withValues(alpha: 0.35),
              ),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
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

class _KeyBox extends StatelessWidget {
  const _KeyBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.22),
          fontSize: 10,
        ),
      ),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: CockpitSpacing.lg),
          Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinePage extends StatelessWidget {
  const _OutlinePage({
    required this.topic,
    required this.items,
    required this.allCount,
    required this.introCount,
    required this.bodyCount,
    required this.endCount,
    required this.filter,
    required this.hidden,
    required this.hiddenOpen,
    required this.selectedCount,
    required this.onFilter,
    required this.onAuto,
    required this.onBuild,
    required this.onOne,
    required this.onSelect,
    required this.onEdit,
    required this.onHide,
    required this.onDelete,
    required this.onMove,
  });

  final String topic;
  final List<OutlineSection> items;
  final int allCount;
  final int introCount;
  final int bodyCount;
  final int endCount;
  final OutlineKind? filter;
  final List<OutlineSection> hidden;
  final ValueNotifier<bool> hiddenOpen;
  final int selectedCount;
  final ValueChanged<OutlineKind?> onFilter;
  final VoidCallback onAuto;
  final VoidCallback onBuild;
  final ValueChanged<OutlineKind> onOne;
  final ValueChanged<OutlineSection> onSelect;
  final ValueChanged<OutlineSection> onEdit;
  final ValueChanged<OutlineSection> onHide;
  final ValueChanged<String> onDelete;
  final void Function(OutlineSection, int) onMove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.xxl,
        CockpitSpacing.xl,
        CockpitSpacing.xxl,
        CockpitSpacing.xxxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    Text(
                      'Your Assignment Analysis',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    Text(
                      'We’ve analyzed your instructions and created custom outlines',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CockpitSpacing.xxxl),
              Text(
                'According to your instructions, here’s what we know:',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: CockpitSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(CockpitSpacing.xl),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(CockpitRadii.lg),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Text(
                  'The assignment asks for a focused argumentative essay about $topic. The response should take a clear position, support it with distinct body points, address a reasonable counterargument, and finish with a concise conclusion.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.55,
                  ),
                ),
              ),
              const SizedBox(height: CockpitSpacing.xl),
              _Fact(label: 'Essay Topic:', value: topic),
              const _Fact(label: 'Essay Type:', value: 'Argumentative'),
              const _Fact(
                label: 'Scope:',
                value:
                    'Focus on one clear position, balance the strongest supporting points, and use evidence that directly connects to the thesis.',
              ),
              const _Fact(
                label: 'Structure:',
                value:
                    'Introduction with a thesis, three body paragraphs, and a conclusion that brings the argument together.',
              ),
              const SizedBox(height: CockpitSpacing.xxl),
              Text(
                'Filter by Section',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: CockpitSpacing.md),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Filter(
                      label: 'All ($allCount)',
                      selected: filter == null,
                      onTap: () => onFilter(null),
                    ),
                    _Filter(
                      label: 'Introduction ($introCount)',
                      selected: filter == OutlineKind.introduction,
                      onTap: () => onFilter(OutlineKind.introduction),
                    ),
                    _Filter(
                      label: 'Body Paragraph ($bodyCount)',
                      selected: filter == OutlineKind.body,
                      onTap: () => onFilter(OutlineKind.body),
                    ),
                    _Filter(
                      label: 'Conclusion ($endCount)',
                      selected: filter == OutlineKind.conclusion,
                      onTap: () => onFilter(OutlineKind.conclusion),
                    ),
                  ],
                ),
              ),
              if (hidden.isNotEmpty) ...[
                const SizedBox(height: CockpitSpacing.xl),
                ValueListenableBuilder<bool>(
                  valueListenable: hiddenOpen,
                  builder: (context, open, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextButton.icon(
                          onPressed: () => hiddenOpen.value = !open,
                          icon: Icon(
                            open
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.chevron_right_rounded,
                          ),
                          label: Text('Hidden Outlines (${hidden.length})'),
                        ),
                        if (open)
                          for (final item in hidden) ...[
                            const SizedBox(height: CockpitSpacing.md),
                            _HiddenCard(
                              item: item,
                              onShow: () => onHide(item),
                              onEdit: () => onEdit(item),
                              onDelete: () => onDelete(item.id),
                            ),
                          ],
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: CockpitSpacing.xl),
              LayoutBuilder(
                builder: (context, box) {
                  final wide = box.maxWidth > 940;

                  final title = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'We generated outlines for you',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: CockpitSpacing.xs),
                      Text(
                        'Select and reorder the outlines you want to use:',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );

                  final buttons = Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: wide ? WrapAlignment.end : WrapAlignment.start,
                    children: [
                      _BuildAction(onTap: onBuild),
                      _AutoAction(onTap: onAuto),
                      _OneAction(onSelect: onOne),
                    ],
                  );

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: CockpitSpacing.xl),
                        buttons,
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: CockpitSpacing.lg),
                      buttons,
                    ],
                  );
                },
              ),
              const SizedBox(height: CockpitSpacing.lg),
              if (allCount > 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CockpitSpacing.md,
                      vertical: CockpitSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(CockpitRadii.sm),
                    ),
                    child: Text(
                      '$allCount outlines available',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: CockpitSpacing.md),
              if (allCount == 0)
                _EmptyOutlines(onAuto: onAuto)
              else if (items.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(CockpitSpacing.xxl),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(CockpitRadii.lg),
                  ),
                  child: Text(
                    'No outlines match this filter.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                )
              else
                for (var i = 0; i < items.length; i++) ...[
                  _OutlineCard(
                    item: items[i],
                    order: activeOrder(items[i]),
                    onSelect: () => onSelect(items[i]),
                    onEdit: () => onEdit(items[i]),
                    onHide: () => onHide(items[i]),
                    onDelete: () => onDelete(items[i].id),
                    onUp: () => onMove(items[i], -1),
                    onDown: () => onMove(items[i], 1),
                  ),
                  const SizedBox(height: CockpitSpacing.md),
                ],
              if (selectedCount > 0) ...[
                const SizedBox(height: CockpitSpacing.sm),
                Text(
                  '$selectedCount section${selectedCount == 1 ? '' : 's'} selected',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  int activeOrder(OutlineSection item) {
    final same = items.where((value) => value.kind == item.kind).toList();
    final pos = same.indexWhere((value) => value.id == item.id);
    return pos + 1;
  }
}

class _BuildAction extends StatefulWidget {
  const _BuildAction({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_BuildAction> createState() => _BuildActionState();
}

class _BuildActionState extends State<_BuildAction> {
  bool over = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => over = true),
      onExit: (_) => setState(() => over = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Color(over ? 0xFFF87171 : 0xFFEF4444),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                blurRadius: 20,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.content_cut_rounded, size: 16, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Build My Way',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoAction extends StatefulWidget {
  const _AutoAction({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AutoAction> createState() => _AutoActionState();
}

class _AutoActionState extends State<_AutoAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController spin;
  bool over = false;

  @override
  void initState() {
    super.initState();
    spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => over = true),
      onExit: (_) => setState(() => over = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: spin,
          builder: (context, child) {
            return CustomPaint(
              foregroundPainter: _GoldSnakePainter(t: spin.value, over: over),
              child: child,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFFFACC15,
                  ).withValues(alpha: over ? 0.14 : 0.08),
                  blurRadius: over ? 22 : 14,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: over ? Colors.white : const Color(0xFFF8E7A6),
                ),
                const SizedBox(width: 8),
                Text(
                  'Auto Outline',
                  style: TextStyle(
                    color: over ? Colors.white : const Color(0xFFF8E7A6),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1,
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

class _GoldSnakePainter extends CustomPainter {
  const _GoldSnakePainter({required this.t, required this.over});

  final double t;
  final bool over;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.75),
      Radius.circular(size.height / 2),
    );
    final path = Path()..addRRect(rrect);
    final metric = path.computeMetrics().first;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Color(over ? 0xFF7B6218 : 0xFF3A2D0C);

    canvas.drawRRect(rrect, base);

    final length = metric.length;
    final start = length * t;
    final segment = length * (over ? 0.24 : 0.18);
    final end = start + segment;

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = over ? 3.2 : 2.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFACC15).withValues(alpha: over ? 0.48 : 0.28)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, over ? 5 : 3);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = over ? 1.6 : 1.3
      ..strokeCap = StrokeCap.round
      ..color = Color(over ? 0xFFFFE680 : 0xFFFFDD73);

    void drawPart(double a, double b) {
      final part = metric.extractPath(a, b);
      canvas.drawPath(part, glow);
      canvas.drawPath(part, line);
    }

    if (end <= length) {
      drawPart(start, end);
    } else {
      drawPart(start, length);
      drawPart(0, end - length);
    }
  }

  @override
  bool shouldRepaint(covariant _GoldSnakePainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.over != over;
  }
}

class _OneAction extends StatefulWidget {
  const _OneAction({required this.onSelect});

  final ValueChanged<OutlineKind> onSelect;

  @override
  State<_OneAction> createState() => _OneActionState();
}

class _OneActionState extends State<_OneAction> {
  bool over = false;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final kind in OutlineKind.values)
          MenuItemButton(
            onPressed: () => widget.onSelect(kind),
            child: Text(kind.label),
          ),
      ],
      builder: (context, controller, _) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => over = true),
          onExit: (_) => setState(() => over = false),
          child: GestureDetector(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(
                    0xFFEF4444,
                  ).withValues(alpha: over ? 0.5 : 0.3),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 7, color: Color(0xFFF87171)),
                  SizedBox(width: 8),
                  Text(
                    'One Paragraph Only',
                    style: TextStyle(
                      color: Color(0xFFF87171),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 14,
                    color: Color(0xFFF87171),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: CockpitSpacing.md),
      child: LayoutBuilder(
        builder: (context, box) {
          final small = box.maxWidth < 560;

          final name = Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w800,
            ),
          );

          final text = Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.82),
              height: 1.45,
            ),
          );

          if (small) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                name,
                const SizedBox(height: CockpitSpacing.xs),
                text,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 128, child: name),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: CockpitSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(
            horizontal: CockpitSpacing.lg,
            vertical: CockpitSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(CockpitRadii.pill),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyOutlines extends StatelessWidget {
  const _EmptyOutlines({required this.onAuto});

  final VoidCallback onAuto;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.xl,
        vertical: CockpitSpacing.xxxl,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.description_outlined,
            size: 44,
            color: colors.onSurface.withValues(alpha: 0.16),
          ),
          const SizedBox(height: CockpitSpacing.lg),
          Text(
            'No outlines yet',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Text(
            'Generate a full outline or build the first section yourself.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: CockpitSpacing.lg),
          OutlinedButton.icon(
            onPressed: onAuto,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Auto Outline'),
          ),
        ],
      ),
    );
  }
}

class _OutlineCard extends StatelessWidget {
  const _OutlineCard({
    required this.item,
    required this.order,
    required this.onSelect,
    required this.onEdit,
    required this.onHide,
    required this.onDelete,
    required this.onUp,
    required this.onDown,
  });

  final OutlineSection item;
  final int order;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onHide;
  final VoidCallback onDelete;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final small = box.maxWidth < 720;

          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: item.selected,
                onChanged: (_) => onSelect(),
                side: BorderSide(color: colors.outline),
              ),
              const SizedBox(width: CockpitSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: CockpitSpacing.sm,
                      runSpacing: CockpitSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _TypeTag(kind: item.kind),
                        if (item.isNew)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: CockpitSpacing.sm,
                              vertical: CockpitSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: colors.secondary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                CockpitRadii.sm,
                              ),
                              border: Border.all(
                                color: colors.secondary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              'New',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colors.secondary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: CockpitSpacing.md),
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: CockpitSpacing.sm),
                    Text(
                      item.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = Wrap(
            spacing: CockpitSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Move up',
                onPressed: onUp,
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
              ),
              IconButton(
                tooltip: 'Move down',
                onPressed: onDown,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              ),
              IconButton(
                tooltip: 'Edit',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Hide',
                onPressed: onHide,
                icon: const Icon(Icons.visibility_off_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                color: colors.error.withValues(alpha: 0.72),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
              ),
              Padding(
                padding: const EdgeInsets.only(left: CockpitSpacing.xs),
                child: Text(
                  'Order: $order',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.26),
                  ),
                ),
              ),
            ],
          );

          if (small) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: CockpitSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(left: CockpitSpacing.xxxl),
                  child: actions,
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: info),
              const SizedBox(width: CockpitSpacing.md),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _HiddenCard extends StatelessWidget {
  const _HiddenCard({
    required this.item,
    required this.onShow,
    required this.onEdit,
    required this.onDelete,
  });

  final OutlineSection item;
  final VoidCallback onShow;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Opacity(
      opacity: 0.58,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(CockpitSpacing.lg),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(CockpitRadii.lg),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TypeTag(kind: item.kind),
                  const SizedBox(height: CockpitSpacing.sm),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
            IconButton(
              tooltip: 'Show',
              onPressed: onShow,
              icon: const Icon(Icons.visibility_outlined, size: 18),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: onDelete,
              color: colors.error.withValues(alpha: 0.72),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.kind});

  final OutlineKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (kind) {
      OutlineKind.introduction => colors.primary,
      OutlineKind.body => colors.secondary,
      OutlineKind.conclusion => colors.tertiary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.sm,
        vertical: CockpitSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        kind.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.canContinue,
    required this.onBack,
    required this.onContinue,
  });

  final bool canContinue;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.xl,
          vertical: CockpitSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final small = box.maxWidth < 560;

            final back = OutlinedButton.icon(
              onPressed: onBack,
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.xl,
                  vertical: CockpitSpacing.md,
                ),
              ),
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text('Back'),
            );

            final next = FilledButton(
              onPressed: canContinue ? onContinue : null,
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: CockpitSpacing.xl,
                  vertical: CockpitSpacing.md,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Continue'),
                  SizedBox(width: CockpitSpacing.sm),
                  Icon(Icons.chevron_right_rounded),
                ],
              ),
            );

            if (small) {
              return Row(
                children: [
                  back,
                  const SizedBox(width: CockpitSpacing.md),
                  Expanded(child: next),
                ],
              );
            }

            return Row(
              children: [
                back,
                const Spacer(),
                SizedBox(width: 250, child: next),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.item});

  final OutlineSection item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(CockpitSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(CockpitRadii.lg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TypeTag(kind: item.kind),
          const SizedBox(height: CockpitSpacing.sm),
          Text(
            item.title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: CockpitSpacing.xs),
          Text(
            item.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class GuidedNextPage extends StatelessWidget {
  const GuidedNextPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: colors.surfaceContainerLowest,
        leading: IconButton(
          onPressed: () => context.go('/guided-generation'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Guided Generation'),
      ),
      body: Center(
        child: Container(
          width: 520,
          margin: const EdgeInsets.all(CockpitSpacing.xl),
          padding: const EdgeInsets.all(CockpitSpacing.xxl),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(CockpitRadii.xl),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_rounded, size: 42, color: colors.primary),
              const SizedBox(height: CockpitSpacing.lg),
              Text(
                'Configuration comes next',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: CockpitSpacing.sm),
              Text(
                'The Outline Generation frontend ends here. This route is the handoff to the next Guided Generation step.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
