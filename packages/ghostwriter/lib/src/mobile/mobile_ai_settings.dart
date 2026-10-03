import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../data/gw_api.dart';
import 'mobile_motion.dart';
import 'mobile_theme.dart';

/// AI settings: which model and personality the user runs with, for every
/// app or for GhostWriter only. Saved as soon as something is tapped.
Future<void> showGwAiSettings(BuildContext context, {required GwApi api}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (context, scroll) => _AiSettings(api: api, scroll: scroll),
    ),
  );
}

class _AiModel {
  _AiModel(Map<String, dynamic> j)
    : id = j['id'].toString(),
      name = j['name']?.toString() ?? '',
      tagline = j['tagline']?.toString() ?? '',
      pro = j['pro'] == true,
      locked = j['locked'] == true;

  final String id;
  final String name;
  final String tagline;
  final bool pro;
  final bool locked;
}

class _AiVoice {
  _AiVoice(Map<String, dynamic> j)
    : id = j['id'].toString(),
      name = j['name']?.toString() ?? '',
      description = j['description']?.toString() ?? '';

  final String id;
  final String name;
  final String description;
}

class _AiSettings extends StatefulWidget {
  const _AiSettings({required this.api, required this.scroll});

  final GwApi api;
  final ScrollController scroll;

  @override
  State<_AiSettings> createState() => _AiSettingsState();
}

class _AiSettingsState extends State<_AiSettings> {
  static const _app = 'ghostwriter';

  List<_AiModel> _models = const [];
  List<_AiVoice> _voices = const [];
  Map<String, dynamic> _prefs = const {};
  bool _loading = true;
  String? _error;
  String? _notice;

  /// Editing `global` (every app) or this app only.
  String _scope = 'global';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.api.aiCatalog(),
        widget.api.aiPreferences(),
      ]);
      if (!mounted) return;
      final catalog = results[0];
      setState(() {
        _models = [
          for (final m in (catalog['models'] as List? ?? const []))
            _AiModel(m as Map<String, dynamic>),
        ];
        _voices = [
          for (final p in (catalog['personalities'] as List? ?? const []))
            _AiVoice(p as Map<String, dynamic>),
        ];
        _prefs = results[1];
        _loading = false;
        // Someone who set GhostWriter on its own starts there.
        if (_saved(_app) != null) _scope = _app;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is GwApiException
            ? e.message
            : 'Could not load the settings.';
      });
    }
  }

  Map<String, dynamic>? _saved(String scope) =>
      (_prefs['scopes'] as Map<String, dynamic>?)?[scope]
          as Map<String, dynamic>?;

  /// What GhostWriter runs with now.
  String? _effective(String field) =>
      ((_prefs['effective'] as Map<String, dynamic>?)?[_app]
              as Map<String, dynamic>?)?[field]
          as String?;

  /// The value shown as chosen for [field] in the scope being edited: the
  /// scope's own choice, else what GhostWriter ends up with.
  String? _chosen(String field) =>
      _saved(_scope)?[field] as String? ?? _effective(field);

  /// In GhostWriter-only mode, nothing of its own: it follows "All apps".
  bool _following(String field) =>
      _scope == _app && _saved(_app)?[field] == null;

  Future<void> _save(Map<String, Object?> change) async {
    setState(() => _notice = null);
    try {
      final prefs = await widget.api.putAiPreference(_scope, change);
      if (mounted) setState(() => _prefs = prefs);
    } on GwApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _notice = e.code == 'pro_required'
            ? 'That model needs a Pro plan.'
            : e.message,
      );
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not save. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.vertical(top: Radius.circular(28));

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xF01B1C1C),
            borderRadius: radius,
            border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
          ),
          child: ListView(
            controller: widget.scroll,
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
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
              const Text(
                'AI settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: GwColors.accentSoft,
                    ),
                  ),
                )
              else if (_error != null)
                Text(
                  _error!,
                  style: kGwBody.copyWith(color: GwColors.accentSoft),
                )
              else ...[
                _ScopeSwitch(
                  scope: _scope,
                  onChanged: (scope) => setState(() {
                    _scope = scope;
                    _notice = null;
                  }),
                ),
                if (_notice != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _notice!,
                    style: kGwBody.copyWith(
                      color: GwColors.accentSoft,
                      fontSize: 13.5,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _Heading(
                  'MODEL',
                  following: _following('model'),
                  onFollow: _scope == _app && !_following('model')
                      ? () => _save({'model': null})
                      : null,
                ),
                if (_models.isEmpty)
                  Text(
                    'No models to choose from yet.',
                    style: kGwBody.copyWith(
                      color: GwColors.muted,
                      fontSize: 14,
                    ),
                  )
                else
                  for (final model in _models)
                    _ModelCard(
                      model: model,
                      selected: _chosen('model') == model.id,
                      onTap: model.locked
                          ? () => setState(
                              () => _notice = 'That model needs a Pro plan.',
                            )
                          : () => _save({'model': model.id}),
                    ),
                const SizedBox(height: 20),
                _Heading(
                  'PERSONALITY',
                  following: _following('personality'),
                  onFollow: _scope == _app && !_following('personality')
                      ? () => _save({'personality': null})
                      : null,
                ),
                Text(
                  'How the AI talks to you in chat. Your essay always stays academic.',
                  style: kGwBody.copyWith(color: GwColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final voice in _voices)
                      _VoiceChip(
                        voice: voice,
                        selected: _chosen('personality') == voice.id,
                        onTap: () => _save({'personality': voice.id}),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScopeSwitch extends StatelessWidget {
  const _ScopeSwitch({required this.scope, required this.onChanged});

  final String scope;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(String value, String label) {
      final on = scope == value;
      return Expanded(
        child: GwPressable(
          haptic: GwHaptic.selection,
          pressedScale: 0.97,
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? const Color(0x24FFFFFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: on ? Colors.white : GwColors.muted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: GwColors.chip,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GwColors.border),
      ),
      child: Row(
        children: [
          option('global', 'All apps'),
          option('ghostwriter', 'GhostWriter only'),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label, {required this.following, this.onFollow});

  final String label;

  /// Follows the All apps choice (GhostWriter-only mode, nothing set).
  final bool following;
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    final onFollow = this.onFollow;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(label, style: kGwLabel),
          const Spacer(),
          if (following)
            Text(
              'Same as all apps',
              style: kGwBody.copyWith(color: GwColors.hint, fontSize: 12),
            )
          else if (onFollow != null)
            GwPressable(
              haptic: GwHaptic.selection,
              onTap: onFollow,
              child: Text(
                'Use all-apps setting',
                style: kGwBody.copyWith(
                  color: GwColors.accentSoft,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final _AiModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GwPressable(
        haptic: GwHaptic.selection,
        pressedScale: 0.98,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0x22FF343C) : GwColors.chip,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? GwColors.accent : GwColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            model.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: model.locked
                                  ? GwColors.muted
                                  : Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (model.pro) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x33FFC53D),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'PRO',
                              style: TextStyle(
                                color: GwColors.gold,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (model.tagline.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        model.tagline,
                        style: kGwBody.copyWith(
                          color: GwColors.muted,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                model.locked
                    ? Icons.lock_outline_rounded
                    : selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 21,
                color: model.locked
                    ? GwColors.hint
                    : selected
                    ? GwColors.accentSoft
                    : GwColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceChip extends StatelessWidget {
  const _VoiceChip({
    required this.voice,
    required this.selected,
    required this.onTap,
  });

  final _AiVoice voice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: voice.description,
      child: GwPressable(
        haptic: GwHaptic.selection,
        pressedScale: 0.96,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? const Color(0x22FF343C) : GwColors.chip,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? GwColors.accent : GwColors.border,
            ),
          ),
          child: Text(
            voice.name,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFFD5D6D8),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
