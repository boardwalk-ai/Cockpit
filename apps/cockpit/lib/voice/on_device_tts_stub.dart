import 'dart:typed_data';

/// Speaks on the device. Null where that is not possible (the web).
OnDeviceTts? createOnDeviceTts() => null;

abstract class OnDeviceTts {
  /// Whether the model is in this build.
  Future<bool> get available;

  /// [text] in [voice] as 24 kHz mono samples.
  Future<Float32List> speak(String text, String voice);

  void dispose();
}
