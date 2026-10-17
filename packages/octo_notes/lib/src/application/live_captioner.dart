import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// One caption from the phone's own speech model: partial while the speaker
/// talks, [isFinal] at the end of a sentence (a pause).
class Caption {
  const Caption({required this.segId, required this.text, required this.isFinal, required this.startMs, required this.endMs});
  final String segId;
  final String text;
  final bool isFinal;
  final int startMs;
  final int endMs;

  Map<String, dynamic> toJson() => {'segId': segId, 'text': text, 'final': isFinal, 'startMs': startMs, 'endMs': endMs};
}

/// Live English captions on the phone, from the audio the recorder already
/// captures (no second use of the mic): a small streaming model
/// (sherpa-onnx zipformer) in a background isolate, about a second behind
/// the speaker. The server's transcript stays the record; these are only
/// for reading along.
///
/// The model ships as app assets (`tools/asr/fetch_asr_model.py`); without
/// them [start] returns false and the session falls back to the server's
/// live transcript.
class LiveCaptioner {
  LiveCaptioner({required this.onCaption});

  final ValueChanged<Caption> onCaption;

  static const assetDir = 'assets/asr';
  static const files = ['encoder.int8.onnx', 'decoder.onnx', 'joiner.int8.onnx', 'tokens.txt'];

  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  bool get running => _toWorker != null;

  /// Copies the model out of the assets (once) and starts the worker.
  Future<bool> start() async {
    if (kIsWeb || running) return running;
    final dir = await _modelDir();
    if (dir == null) return false;
    final ready = Completer<SendPort?>();
    final port = ReceivePort();
    _fromWorker = port;
    port.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m is Map) {
        onCaption(Caption(
          segId: m['segId'] as String,
          text: m['text'] as String,
          isFinal: m['final'] as bool,
          startMs: m['startMs'] as int,
          endMs: m['endMs'] as int,
        ));
      } else if (m == null && !ready.isCompleted) {
        ready.complete(null); // the model didn't load
      }
    });
    _isolate = await Isolate.spawn(_worker, (port.sendPort, dir), errorsAreFatal: false);
    _toWorker = await ready.future.timeout(const Duration(seconds: 20), onTimeout: () => null);
    if (_toWorker == null) await stop();
    return running;
  }

  /// 16-bit mono PCM at 16 kHz, as the recorder gets it (times count from
  /// the first audio fed, like the recording's).
  void accept(Uint8List pcm) => _toWorker?.send(TransferableTypedData.fromList([pcm]));

  Future<void> stop() async {
    _toWorker?.send('stop');
    _toWorker = null;
    _fromWorker?.close();
    _fromWorker = null;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
  }

  static Future<String?> _modelDir() async {
    try {
      final root = await getApplicationSupportDirectory();
      final dir = Directory('${root.path}/asr-en-20m');
      for (final f in files) {
        final out = File('${dir.path}/$f');
        if (out.existsSync()) continue;
        final data = await rootBundle.load('$assetDir/$f');
        await dir.create(recursive: true);
        await out.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      }
      return dir.path;
    } on Object {
      return null; // not bundled in this build
    }
  }
}

/// The worker: PCM in, captions out.
Future<void> _worker((SendPort, String) args) async {
  final (out, dir) = args;
  sherpa.OnlineRecognizer? recognizer;
  sherpa.OnlineStream? stream;
  try {
    sherpa.initBindings();
    recognizer = sherpa.OnlineRecognizer(sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: '$dir/encoder.int8.onnx',
          decoder: '$dir/decoder.onnx',
          joiner: '$dir/joiner.int8.onnx',
        ),
        tokens: '$dir/tokens.txt',
        numThreads: 2,
        modelType: 'zipformer',
        debug: false,
      ),
      // A sentence ends after ~0.8 s of quiet, or at 20 s.
      rule2MinTrailingSilence: 0.8,
    ));
    stream = recognizer.createStream();
  } on Object {
    out.send(null);
    return;
  }
  final inbox = ReceivePort();
  out.send(inbox.sendPort);

  final engine = _Engine(recognizer, stream, out);
  await for (final m in inbox) {
    if (m == 'stop') break;
    if (m is TransferableTypedData) engine.feed(m.materialize().asUint8List());
  }
  engine.close();
  inbox.close();
}

class _Engine {
  _Engine(this.recognizer, this.stream, this.out);
  final sherpa.OnlineRecognizer recognizer;
  sherpa.OnlineStream stream;
  final SendPort out;

  int _heardMs = 0; // audio fed so far
  int _segStartMs = 0;
  int _seg = 0;
  String _last = '';

  void feed(Uint8List pcm) {
    stream.acceptWaveform(samples: pcm16ToFloat(pcm), sampleRate: 16000);
    _heardMs += pcm.length ~/ 32;
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
    final text = recognizer.getResult(stream).text.trim();
    final end = recognizer.isEndpoint(stream);
    if (text.isNotEmpty && (text != _last || end)) {
      out.send({'segId': 'd$_seg', 'text': _sentence(text), 'final': end, 'startMs': _segStartMs, 'endMs': _heardMs});
    }
    _last = text;
    if (end) {
      recognizer.reset(stream);
      if (text.isNotEmpty) _seg++;
      _segStartMs = _heardMs;
      _last = '';
    }
  }

  /// The model writes upper case without punctuation.
  static String _sentence(String t) {
    final lower = t.toLowerCase();
    return lower.isEmpty ? lower : lower[0].toUpperCase() + lower.substring(1);
  }

  void close() {
    stream.free();
    recognizer.free();
  }
}

/// 16-bit little-endian PCM to floats in [-1, 1).
Float32List pcm16ToFloat(Uint8List pcm) {
  final n = pcm.lengthInBytes ~/ 2;
  final bytes = ByteData.sublistView(pcm);
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = bytes.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}
