import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/hein_analysis.dart';
import '../domain/outline.dart';

/// Persists the wizard essay topic (and Hein's breakdown) so the editor source
/// panel can reuse it. On web this is `window.localStorage` via shared_preferences.
class WizardSession {
  static const topicKey = 'dococt.essayTopic';
  static const promptKey = 'dococt.essayPrompt';
  static const analysisKey = 'dococt.heinAnalysis';
  static const outlinesKey = 'dococt.outlines';

  static SharedPreferences? _prefs;
  static String _topic = '';
  static String _prompt = '';
  static HeinAnalysis? _analysis;
  static List<OutlineData> _outlines = [];

  static String get topic => _topic;
  static String get prompt => _prompt;
  static HeinAnalysis? get analysis => _analysis;
  static List<OutlineData> get outlines => List.unmodifiable(_outlines);

  /// Topic used for source search: Hein's extracted subject, else the raw prompt.
  static String get searchTopic {
    final fromHein = _analysis?.essayTopic.trim() ?? '';
    if (fromHein.isNotEmpty) return fromHein;
    if (_topic.trim().isNotEmpty) return _topic.trim();
    return _prompt.trim();
  }

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _topic = _prefs?.getString(topicKey) ?? '';
    _prompt = _prefs?.getString(promptKey) ?? '';
    final raw = _prefs?.getString(analysisKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _analysis = HeinAnalysis.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        _analysis = null;
      }
    } else {
      _analysis = null;
    }
    final rawOut = _prefs?.getString(outlinesKey);
    if (rawOut != null && rawOut.isNotEmpty) {
      try {
        _outlines = (jsonDecode(rawOut) as List)
            .map((e) => OutlineData.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _outlines = [];
      }
    } else {
      _outlines = [];
    }
  }

  static Future<void> savePrompt(String value) async {
    _prompt = value.trim();
    _topic = _prompt;
    _analysis = null;
    _outlines = [];
    await _prefs?.setString(promptKey, _prompt);
    if (_topic.isNotEmpty) {
      await _prefs?.setString(topicKey, _topic);
    } else {
      await _prefs?.remove(topicKey);
    }
    await _prefs?.remove(analysisKey);
    await _prefs?.remove(outlinesKey);
  }

  /// Forget the topic, analysis and outlines — a fresh document without a topic
  /// ("Start writing" / a blank format template). In-memory state clears
  /// synchronously, so the next screen already sees an empty session.
  static Future<void> clear() => savePrompt('');

  /// Replace the whole session with a saved document's (opening a doc). Missing
  /// parts clear, so one document's analysis/outlines never leak into another.
  /// In-memory state is set synchronously — panels built next frame see it.
  static Future<void> restore({
    String prompt = '',
    HeinAnalysis? analysis,
    List<OutlineData> outlines = const [],
  }) async {
    _prompt = prompt.trim();
    _analysis = analysis;
    _topic = analysis != null && analysis.essayTopic.trim().isNotEmpty
        ? analysis.essayTopic.trim()
        : _prompt;
    _outlines = List.of(outlines);
    await _setOrRemove(promptKey, _prompt);
    await _setOrRemove(topicKey, _topic);
    await _setOrRemove(
      analysisKey,
      analysis == null ? '' : jsonEncode(analysis.toJson()),
    );
    await _setOrRemove(
      outlinesKey,
      _outlines.isEmpty
          ? ''
          : jsonEncode(_outlines.map((o) => o.toJson()).toList()),
    );
  }

  static Future<void> _setOrRemove(String key, String value) async {
    if (value.isEmpty) {
      await _prefs?.remove(key);
    } else {
      await _prefs?.setString(key, value);
    }
  }

  static Future<void> saveTopic(String value) async {
    _topic = value.trim();
    await _prefs?.setString(topicKey, _topic);
  }

  static Future<void> saveAnalysis(HeinAnalysis value) async {
    _analysis = value;
    if (value.essayTopic.trim().isNotEmpty) {
      _topic = value.essayTopic.trim();
      await _prefs?.setString(topicKey, _topic);
    }
    await _prefs?.setString(analysisKey, jsonEncode(value.toJson()));
  }

  static Future<void> saveOutlines(List<OutlineData> value) async {
    _outlines = List.of(value);
    await _prefs?.setString(
      outlinesKey,
      jsonEncode(value.map((o) => o.toJson()).toList()),
    );
  }
}
