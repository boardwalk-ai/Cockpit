import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'on_device_tts_stub.dart' as api;
import 'pocket_tts_model.dart';

export 'on_device_tts_stub.dart' show OnDeviceTts;

api.OnDeviceTts? createOnDeviceTts() => _PocketOnDevice();

/// The model's files, bundled under assets/tts/.
const _files = [
  'text_conditioner.onnx',
  'lm_main.int8.onnx',
  'lm_flow.int8.onnx',
  'decoder.int8.onnx',
  'vocab.json',
  'token_scores.json',
];

/// Pocket TTS on a background isolate. The ONNX files are copied out of the
/// app bundle once (ONNX Runtime opens files), then stay on the device.
class _PocketOnDevice implements api.OnDeviceTts {
  Future<bool>? _available;
  Future<SendPort>? _worker;
  final _voices = <String, Float32List>{};
  final _pending = <int, Completer<Float32List>>{};
  var _next = 0;
  final _isolates = <Isolate>[];
  ReceivePort? _replies;

  @override
  Future<bool> get available => _available ??= () async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest.listAssets().contains('assets/tts/lm_main.int8.onnx');
    } on Object {
      return false;
    }
  }();

  @override
  Future<Float32List> speak(String text, String voice) async {
    final worker = await (_worker ??= _start());
    final samples = _voices[voice] ??= await _voice(voice);
    final id = _next++;
    final done = _pending[id] = Completer<Float32List>();
    worker.send((id, text, TransferableTypedData.fromList([samples])));
    return done.future;
  }

  Future<Float32List> _voice(String id) async {
    final data = await rootBundle.load('assets/tts/voices/$id.f32');
    return Float32List.fromList(
      data.buffer.asFloat32List(data.offsetInBytes, data.lengthInBytes ~/ 4),
    );
  }

  Future<SendPort> _start() async {
    final dir = await _unpack();
    final replies = _replies = ReceivePort();
    final ready = Completer<SendPort>();
    final decoder = Completer<SendPort>();
    replies.listen((message) {
      switch (message) {
        case ('decoder', SendPort port):
          decoder.complete(port);
        case SendPort port:
          ready.complete(port);
        case (int id, TransferableTypedData audio):
          _pending.remove(id)?.complete(audio.materialize().asFloat32List());
        case (int id, String error):
          _pending.remove(id)?.completeError(StateError(error));
        case String error when !decoder.isCompleted:
          decoder.completeError(StateError(error));
        case String error when !ready.isCompleted:
          ready.completeError(StateError(error));
      }
    });
    _isolates.add(await Isolate.spawn(_decode, (replies.sendPort, dir)));
    final decoderPort = await decoder.future;
    _isolates.add(
      await Isolate.spawn(_work, (replies.sendPort, decoderPort, dir)),
    );
    return ready.future;
  }

  /// Copies the model out of the bundle once; a marker file says it is whole.
  static Future<String> _unpack() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/pocket-tts-v3');
    final marker = File('${dir.path}/.complete');
    if (await marker.exists()) return dir.path;
    await dir.create(recursive: true);
    for (final name in _files) {
      final data = await rootBundle.load('assets/tts/$name');
      await File('${dir.path}/$name').writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    await marker.writeAsString('1');
    return dir.path;
  }

  @override
  void dispose() {
    for (final isolate in _isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    _replies?.close();
    for (final waiting in _pending.values) {
      waiting.completeError(StateError('stopped'));
    }
    _pending.clear();
  }
}

/// ORT threads per session. One each: the LM and the decoder run side by
/// side on the phone's two big cores, and a second thread per session was
/// no faster on a Dimensity 700.
const _threads = int.fromEnvironment('POCKET_TTS_THREADS', defaultValue: 1);

/// The LM isolate: turns each request into latents, passed to the decoder
/// isolate one frame at a time, then an end marker with the timing.
void _work((SendPort, SendPort, String) args) {
  final (replies, decoder, dir) = args;
  final PocketTtsLm model;
  try {
    final started = Stopwatch()..start();
    model = PocketTtsLm.load(dir, threads: _threads);
    debugPrint('pocket-tts: LM loaded in ${started.elapsedMilliseconds} ms');
  } on Object catch (e) {
    replies.send('$e');
    return;
  }
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((message) {
    final (id, text, voice) = message as (int, String, TransferableTypedData);
    final started = DateTime.now().millisecondsSinceEpoch;
    try {
      for (final latent in model.latents(
        text,
        voice.materialize().asFloat32List(),
      )) {
        decoder.send((id, TransferableTypedData.fromList([latent])));
      }
      decoder.send((id, started, model.lastTimings));
    } on Object catch (e) {
      decoder.send((id, '$e'));
    }
  });
}

/// Latents per decoder call. Two frames at once cost about a quarter less
/// per frame than one; the int8 rounding differs a little (about 25 dB SNR
/// against one at a time, the same as a 0.1% nudge to the latents).
const _batch = int.fromEnvironment('POCKET_TTS_BATCH', defaultValue: 2);

/// The decoder isolate: decodes each request's latents as they come and
/// sends the whole clip back once the LM marks its end.
void _decode((SendPort, String) args) {
  final (replies, dir) = args;
  final PocketTtsDecoder decoder;
  try {
    decoder = PocketTtsDecoder.load(dir, threads: _threads);
  } on Object catch (e) {
    replies.send('$e');
    return;
  }
  final latents = ReceivePort();
  replies.send(('decoder', latents.sendPort));
  final frames = <Float32List>[];
  final waiting = <Float32List>[];
  final watch = Stopwatch();
  void flush() {
    if (waiting.isEmpty) return;
    final batch = Float32List(waiting.length * 32);
    for (final (i, latent) in waiting.indexed) {
      batch.setRange(i * 32, (i + 1) * 32, latent);
    }
    waiting.clear();
    watch.start();
    frames.add(decoder.decode(batch));
    watch.stop();
  }

  latents.listen((message) {
    switch (message) {
      case (int _, TransferableTypedData latent):
        if (frames.isEmpty && waiting.isEmpty) watch.reset();
        waiting.add(latent.materialize().asFloat32List());
        if (waiting.length >= _batch) flush();
      case (int id, int started, String lmTimings):
        flush();
        final audio = joinFrames(frames);
        frames.clear();
        decoder.reset();
        final took = DateTime.now().millisecondsSinceEpoch - started;
        final seconds = audio.length / PocketTtsDecoder.sampleRate;
        debugPrint(
          'pocket-tts: ${seconds.toStringAsFixed(1)} s of speech in $took ms '
          '(${(took / 1000 / (seconds == 0 ? 1 : seconds)).toStringAsFixed(2)} RTF; '
          '$lmTimings, decoder ${watch.elapsedMilliseconds} ms, '
          '$_threads threads, batch $_batch)',
        );
        replies.send((id, TransferableTypedData.fromList([audio])));
      case (int id, String error):
        frames.clear();
        waiting.clear();
        decoder.reset();
        replies.send((id, error));
    }
  });
}
