import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:http/http.dart' as http;
import 'package:octopilot_shell/octopilot_shell.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Octopilot's voices (`tools/voice/voices.json`), each with its orb colours.
const octopilotVoices = [
  ShellVoice(
    id: 'marc',
    name: 'Marc',
    colors: [Color(0xFFFF343C), Color(0xFFFF8A5B)],
  ),
  ShellVoice(
    id: 'noah',
    name: 'Noah',
    colors: [Color(0xFF3D7BFF), Color(0xFF4FD1FF)],
  ),
  ShellVoice(
    id: 'lucas',
    name: 'Lucas',
    colors: [Color(0xFF13B88A), Color(0xFF8BE38F)],
  ),
  ShellVoice(
    id: 'sarah',
    name: 'Sarah',
    female: true,
    colors: [Color(0xFFFF4F9A), Color(0xFFFFB199)],
  ),
  ShellVoice(
    id: 'lucy',
    name: 'Lucy',
    female: true,
    colors: [Color(0xFF8B5CF6), Color(0xFFD08CFF)],
  ),
  ShellVoice(
    id: 'dasha',
    name: 'Dasha',
    female: true,
    colors: [Color(0xFFFFB020), Color(0xFFFF6B3D)],
  ),
];

/// Hears with the phone's own speech recognition and speaks with Pocket TTS
/// through the voice server (`tools/voice/serve.py`), a whole reply at a
/// time.
class PocketVoiceEngine implements VoiceEngine {
  PocketVoiceEngine({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? defaultBaseUrl,
      _client = client ?? http.Client();

  /// `--dart-define=OCTOPILOT_VOICE_URL=...`; otherwise the local dev server
  /// (10.0.2.2 from the Android emulator).
  static String get defaultBaseUrl {
    const configured = String.fromEnvironment('OCTOPILOT_VOICE_URL');
    if (configured.isNotEmpty) return configured;
    final emulator = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return emulator ? 'http://10.0.2.2:8792' : 'http://127.0.0.1:8792';
  }

  final String baseUrl;
  final http.Client _client;
  final _ears = SpeechToText();
  bool? _earsReady;
  Completer<String?>? _heard;
  var _partial = '';
  final _player = AudioPlayer();
  Completer<void>? _cut;

  /// The loudness envelope is sampled this often.
  static const _frame = Duration(milliseconds: 40);

  @override
  Future<String?> listen({
    required ValueChanged<String> onPartial,
    required ValueChanged<double> onLevel,
  }) async {
    _earsReady ??= await _ears.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') _finishHearing();
      },
      onError: (_) => _finishHearing(),
    );
    if (!_earsReady!) {
      _earsReady = null; // ask again next time (permission may be granted)
      throw const VoiceUnavailable(
        "Octopilot can't use the microphone. Allow it in your phone's settings.",
      );
    }
    _partial = '';
    final heard = _heard = Completer<String?>();
    await _ears.listen(
      onResult: (SpeechRecognitionResult result) {
        _partial = result.recognizedWords;
        onPartial(_partial);
        if (result.finalResult) _finishHearing();
      },
      // Roughly -2 (quiet) to 10 (loud) dB on Android.
      onSoundLevelChange: (db) => onLevel(((db + 2) / 12).clamp(0.0, 1.0)),
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(milliseconds: 2500),
        localeId: 'en_US',
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
    final text = await heard.future;
    onLevel(0);
    return text == null || text.trim().isEmpty ? null : text.trim();
  }

  void _finishHearing() {
    final heard = _heard;
    if (heard != null && !heard.isCompleted) heard.complete(_partial);
  }

  @override
  void finishListening() {
    // What was heard so far becomes final, then the status says done.
    if (_ears.isListening) _ears.stop();
    _finishHearing();
  }

  @override
  Future<Speech> prepare(String text, {required String voice}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/v1/tts'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'text': _speakable(text), 'voice': voice}),
    );
    if (response.statusCode != 200) {
      throw StateError('voice server: ${response.statusCode}');
    }
    final clip = _Clip.fromWav(response.bodyBytes, _frame);
    return Speech(text: text, duration: clip.duration, audio: clip);
  }

  @override
  Future<void> play(
    Speech speech, {
    required ValueChanged<double> onLevel,
    required ValueChanged<double> onProgress,
  }) async {
    final clip = speech.audio! as _Clip;
    final cut = _cut = Completer<void>();
    final done = Completer<void>();
    final ended = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    await _player.play(await _source(clip.wav));
    final clock = Stopwatch()..start();
    final ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final at = clock.elapsed;
      onLevel(clip.levelAt(at));
      onProgress(
        (at.inMilliseconds / clip.duration.inMilliseconds).clamp(0.0, 1.0),
      );
      // In case the player never says it finished.
      if (at > clip.duration + const Duration(seconds: 1) &&
          !done.isCompleted) {
        done.complete();
      }
    });
    await Future.any([done.future, cut.future]);
    ticker.cancel();
    await ended.cancel();
    if (cut.isCompleted) await _player.stop();
    onLevel(0);
    onProgress(1);
    _cut = null;
  }

  @override
  void stop() {
    if (_ears.isListening) _ears.cancel();
    final heard = _heard;
    if (heard != null && !heard.isCompleted) heard.complete(null);
    final cut = _cut;
    if (cut != null && !cut.isCompleted) cut.complete();
  }

  Future<Source> _source(Uint8List wav) async {
    if (kIsWeb) return UrlSource('data:audio/wav;base64,${base64Encode(wav)}');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/octopilot-voice.wav');
    await file.writeAsBytes(wav, flush: true);
    return DeviceFileSource(file.path);
  }

  /// Markdown and symbols read badly aloud.
  static String _speakable(String text) => text
      .replaceAll(RegExp(r'[*_`#>]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// A synthesised reply: the WAV, and how loud it is moment to moment.
class _Clip {
  _Clip(this.wav, this.duration, this.levels, this.frame);

  factory _Clip.fromWav(Uint8List wav, Duration frame) {
    final data = ByteData.sublistView(wav);
    var rate = 24000;
    var offset = 12;
    var start = 0, length = 0;
    // Walk the RIFF chunks for the format and the samples.
    while (offset + 8 <= wav.length) {
      final id = String.fromCharCodes(wav.sublist(offset, offset + 4));
      final size = data.getUint32(offset + 4, Endian.little);
      if (id == 'fmt ') rate = data.getUint32(offset + 12, Endian.little);
      if (id == 'data') {
        start = offset + 8;
        length = math.min(size, wav.length - start);
        break;
      }
      offset += 8 + size + (size.isOdd ? 1 : 0);
    }
    final samples = length ~/ 2;
    final perFrame = math.max(1, rate * frame.inMilliseconds ~/ 1000);
    final levels = <double>[];
    for (var f = 0; f * perFrame < samples; f++) {
      var sum = 0.0;
      final end = math.min(samples, (f + 1) * perFrame);
      for (var i = f * perFrame; i < end; i++) {
        final s = data.getInt16(start + i * 2, Endian.little) / 32768;
        sum += s * s;
      }
      levels.add(math.sqrt(sum / (end - f * perFrame)));
    }
    final peak = levels.fold(0.0, math.max);
    final scaled = [
      for (final l in levels)
        peak == 0 ? 0.0 : math.sqrt(l / peak).clamp(0.0, 1.0),
    ];
    return _Clip(
      wav,
      Duration(microseconds: samples * 1000000 ~/ rate),
      scaled,
      frame,
    );
  }

  final Uint8List wav;
  final Duration duration;
  final List<double> levels;
  final Duration frame;

  double levelAt(Duration at) {
    final i = at.inMilliseconds ~/ frame.inMilliseconds;
    return i < 0 || i >= levels.length ? 0 : levels[i];
  }
}
