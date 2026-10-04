import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
// The tensor helpers below need the C API directly: empty tensors and
// zero-filled caches, without copying them through Dart lists.
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;

import 'pocket_tts_specs.dart';
import 'pocket_tts_text.dart';

/// Kyutai Pocket TTS on the phone (the soniqo ONNX bundle), in two halves
/// that run on two isolates side by side, one CPU core each: [PocketTtsLm]
/// turns text and a voice into one latent per 80 ms frame (the LM, then
/// four flow-matching steps) and [PocketTtsDecoder] turns each latent into
/// audio (the Mimi decoder). Each half alone is slower than real time on a
/// mid-range phone, and more threads per session do not help; overlapped,
/// the slower half sets the pace. The same steps as
/// tools/voice/onnx_reference.py.
///
/// Both are heavy: keep them off the UI isolate (see on_device_tts_io.dart).
class PocketTtsLm {
  PocketTtsLm.load(String dir, {int threads = 1}) {
    final options = _options(threads);
    _conditioner = _open(dir, 'text_conditioner.onnx', options);
    _lm = _open(dir, 'lm_main.int8.onnx', options);
    _flow = _open(dir, 'lm_flow.int8.onnx', options);
    _tokenizer = PocketTokenizer.fromJson(
      File('$dir/vocab.json').readAsStringSync(),
      File('$dir/token_scores.json').readAsStringSync(),
    );
  }

  static const _latent = 32;
  static const _width = 1024;

  /// The LM's cache axis in [lmStateSpecs]: the export's fixed size, which
  /// the bundle names instead (see tools/voice/fetch_onnx_bundle.py).
  static const _exportCache = 1000;
  static const flowSteps = 4;
  static const eosThreshold = -4.0;
  static const temperature = 0.7;
  static const maxFrames = 500;

  late final OrtSession _conditioner;
  late final OrtSession _lm;
  late final OrtSession _flow;
  late final PocketTokenizer _tokenizer;
  final _run = OrtRunOptions();

  /// Milliseconds in the LM and the flow steps during the last [latents],
  /// for tuning on a phone.
  String lastTimings = '';

  /// The latents for [text] in [voice] (the voice's conditioning, `[N,
  /// 1024]` floats), each as soon as it is ready. Read it to the end: the
  /// LM's memory is freed when it finishes.
  Iterable<Float32List> latents(
    String text,
    Float32List voice, {
    int? seed,
  }) sync* {
    final (prepared, afterEos) = preparePocketText(text);
    if (prepared.isEmpty) return;
    final ids = _tokenizer.encode(prepared);
    final voiceTokens = voice.length ~/ _width;

    final textEmbedding = _run1(_run, _conditioner, {
      'token_ids': _tensor('i', [1, ids.length], ids),
    });

    // Every LM step copies its whole cache, so size it to this text: the
    // voice, the text and room for its frames (about 3 per token as spoken,
    // so 6 is generous), in steps of 64 to keep the shapes few.
    final room = math.min(maxFrames, ids.length * 6 + 48);
    final cache = math.min(
      _exportCache,
      ((voiceTokens + ids.length + room + 63) ~/ 64) * 64,
    );
    var lmState = _zeros([
      for (final (name, type, shape) in lmStateSpecs)
        (
          name,
          type,
          [
            for (final d in shape)
              shape.length == 5 && d == _exportCache ? cache : d,
          ],
        ),
    ]);
    try {
      // Conditioning: the voice, then the text, into the LM's memory.
      lmState = _stepLm(
        _tensor('f', [1, 0, _latent]),
        _tensor('f', [1, voiceTokens, _width], voice),
        lmState,
      ).$3;
      lmState = _stepLm(
        _tensor('f', [1, 0, _latent]),
        textEmbedding,
        lmState,
      ).$3;

      final random = math.Random(seed);
      final noiseScale = math.sqrt(temperature);
      var current = Float32List(_latent)..fillRange(0, _latent, double.nan);
      var eosAt = -1;
      final limit = math.min(maxFrames, cache - voiceTokens - ids.length);
      final lmWatch = Stopwatch(), flowWatch = Stopwatch();

      for (var frame = 0; frame < limit; frame++) {
        lmWatch.start();
        final (conditioning, eos, nextState) = _stepLm(
          _tensor('f', [1, 1, _latent], current),
          _tensor('f', [1, 0, _width]),
          lmState,
        );
        lmState = nextState;
        lmWatch.stop();
        final eosScore = _floats(eos, 1)[0];
        eos.release();
        if (eosAt < 0 && eosScore > eosThreshold) eosAt = frame;
        if (eosAt >= 0 && frame >= eosAt + afterEos) {
          conditioning.release();
          break;
        }

        // Flow matching: from noise to the next latent in four steps.
        flowWatch.start();
        final latent = Float32List(_latent);
        for (var i = 0; i < _latent; i++) {
          latent[i] = _gaussian(random) * noiseScale;
        }
        for (var step = 0; step < flowSteps; step++) {
          final direction = _run1(
            _run,
            _flow,
            {
              'c': conditioning,
              's': _tensor('f', [
                1,
                1,
              ], Float32List.fromList([step / flowSteps])),
              't': _tensor('f', [
                1,
                1,
              ], Float32List.fromList([(step + 1) / flowSteps])),
              'x': _tensor('f', [1, _latent], latent),
            },
            keep: const {'c'},
          );
          final d = _floats(direction, _latent);
          direction.release();
          for (var i = 0; i < _latent; i++) {
            latent[i] += d[i] / flowSteps;
          }
        }
        conditioning.release();
        flowWatch.stop();
        current = latent;
        lastTimings =
            '${frame + 1} frames: lm ${lmWatch.elapsedMilliseconds} ms, '
            'flow ${flowWatch.elapsedMilliseconds} ms';
        yield latent;
      }
    } finally {
      for (final value in lmState) {
        value.release();
      }
    }
  }

  /// Speaks [text] in [voice] on this isolate: the latents, decoded one
  /// after another. For tests and tools; the app overlaps the two halves.
  Float32List synthesize(
    String text,
    Float32List voice,
    PocketTtsDecoder decoder, {
    int? seed,
  }) {
    final frames = [
      for (final latent in latents(text, voice, seed: seed))
        decoder.decode(latent),
    ];
    decoder.reset();
    return joinFrames(frames);
  }

  void release() {
    for (final session in [_conditioner, _lm, _flow]) {
      session.release();
    }
    _run.release();
  }

  /// One LM step: (conditioning, eos logit, the new state). Releases the
  /// inputs and the old state.
  (OrtValue, OrtValue, List<OrtValue>) _stepLm(
    OrtValue sequence,
    OrtValue embedding,
    List<OrtValue> state,
  ) {
    final out = _lm.run(_run, {
      'sequence': sequence,
      'text_embeddings': embedding,
      for (final (i, spec) in lmStateSpecs.indexed) spec.$1: state[i],
    });
    sequence.release();
    embedding.release();
    for (final value in state) {
      value.release();
    }
    return (out[0]!, out[1]!, [for (final v in out.skip(2)) v!]);
  }
}

/// The Mimi decoder half: one 80 ms frame of 24 kHz audio per latent,
/// carrying its state from frame to frame until [reset].
class PocketTtsDecoder {
  PocketTtsDecoder.load(String dir, {int threads = 1}) {
    _decoder = _open(dir, 'decoder.int8.onnx', _options(threads));
  }

  static const sampleRate = 24000;
  static const frameSamples = 1920;

  late final OrtSession _decoder;
  final _run = OrtRunOptions();
  List<OrtValue>? _state;

  /// Decodes one or more latents (32 floats each, end to end): a few at a
  /// time is cheaper per frame than one by one.
  Float32List decode(Float32List latents) {
    final count = latents.length ~/ 32;
    final state = _state ?? _zeros(decoderStateSpecs);
    final decoded = _decoder.run(_run, {
      'latent': _tensor('f', [1, count, 32], latents),
      for (final (i, spec) in decoderStateSpecs.indexed) spec.$1: state[i],
    });
    for (final value in state) {
      value.release();
    }
    final audio = decoded[0]!;
    final samples = _floats(audio, count * frameSamples);
    audio.release();
    _state = [for (final v in decoded.skip(1)) v!];
    return samples;
  }

  /// Ready for the next text.
  void reset() {
    for (final value in _state ?? const <OrtValue>[]) {
      value.release();
    }
    _state = null;
  }

  void release() {
    reset();
    _decoder.release();
    _run.release();
  }
}

/// Decoded audio end to end.
Float32List joinFrames(List<Float32List> frames) {
  final out = Float32List(frames.fold(0, (n, f) => n + f.length));
  var at = 0;
  for (final frame in frames) {
    out.setRange(at, at += frame.length, frame);
  }
  return out;
}

OrtSessionOptions _options(int threads) {
  OrtEnv.instance.init();
  return OrtSessionOptions()
    ..setIntraOpNumThreads(threads)
    ..setInterOpNumThreads(1)
    ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
}

OrtSession _open(String dir, String name, OrtSessionOptions options) =>
    OrtSession.fromFile(File('$dir/$name'), options);

/// Runs [session] for its first output, releasing the inputs (but not
/// those named in [keep]).
OrtValue _run1(
  OrtRunOptions run,
  OrtSession session,
  Map<String, OrtValue> inputs, {
  Set<String> keep = const {},
}) {
  final out = session.run(run, inputs);
  for (final entry in inputs.entries) {
    if (!keep.contains(entry.key)) entry.value.release();
  }
  for (final extra in out.skip(1)) {
    extra?.release();
  }
  return out[0]!;
}

List<OrtValue> _zeros(List<(String, String, List<int>)> specs) => [
  for (final (_, type, shape) in specs) _tensor(type, shape),
];

/// A tensor over native memory: zeros, or a copy of [data].
OrtValueTensor _tensor(String type, List<int> shape, [TypedData? data]) {
  final count = shape.fold(1, (a, b) => a * b);
  final (element, size) = switch (type) {
    'f' => (ONNXTensorElementDataType.float, 4),
    'i' => (ONNXTensorElementDataType.int64, 8),
    _ => (ONNXTensorElementDataType.bool, 1),
  };
  final bytes = count * size;
  // calloc zeroes; one spare byte so an empty tensor still has a pointer.
  final buffer = calloc<ffi.Uint8>(bytes + 1);
  if (data != null) {
    buffer
        .asTypedList(bytes)
        .setAll(0, data.buffer.asUint8List(data.offsetInBytes, bytes));
  }
  final api = OrtEnv.instance.ortApiPtr.ref;
  final shapePtr = calloc<ffi.Int64>(shape.length);
  shapePtr.asTypedList(shape.length).setAll(0, shape);
  final infoPtr = calloc<ffi.Pointer<bg.OrtMemoryInfo>>();
  final valuePtr = calloc<ffi.Pointer<bg.OrtValue>>();
  try {
    OrtStatus.checkOrtStatus(
      api.AllocatorGetInfo.asFunction<
        bg.OrtStatusPtr Function(
          ffi.Pointer<bg.OrtAllocator>,
          ffi.Pointer<ffi.Pointer<bg.OrtMemoryInfo>>,
        )
      >()(OrtAllocator.instance.ptr, infoPtr),
    );
    OrtStatus.checkOrtStatus(
      api.CreateTensorWithDataAsOrtValue.asFunction<
        bg.OrtStatusPtr Function(
          ffi.Pointer<bg.OrtMemoryInfo>,
          ffi.Pointer<ffi.Void>,
          int,
          ffi.Pointer<ffi.Int64>,
          int,
          int,
          ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
        )
      >()(
        infoPtr.value,
        buffer.cast(),
        bytes,
        shapePtr,
        shape.length,
        element.value,
        valuePtr,
      ),
    );
    return OrtValueTensor(valuePtr.value, buffer.cast());
  } finally {
    calloc
      ..free(shapePtr)
      ..free(infoPtr)
      ..free(valuePtr);
  }
}

/// The first [count] floats of [value], copied out.
Float32List _floats(OrtValue value, int count) {
  final api = OrtEnv.instance.ortApiPtr.ref;
  final dataPtr = calloc<ffi.Pointer<ffi.Void>>();
  try {
    OrtStatus.checkOrtStatus(
      api.GetTensorMutableData.asFunction<
        bg.OrtStatusPtr Function(
          ffi.Pointer<bg.OrtValue>,
          ffi.Pointer<ffi.Pointer<ffi.Void>>,
        )
      >()(value.ptr, dataPtr),
    );
    return Float32List.fromList(
      dataPtr.value.cast<ffi.Float>().asTypedList(count),
    );
  } finally {
    calloc.free(dataPtr);
  }
}

/// A standard normal sample (Box-Muller).
double _gaussian(math.Random random) {
  final u = 1 - random.nextDouble();
  final v = random.nextDouble();
  return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
}
