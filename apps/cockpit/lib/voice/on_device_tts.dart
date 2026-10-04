/// Text-to-speech on the device itself, where it can run (not on the web).
library;

export 'on_device_tts_stub.dart' if (dart.library.ffi) 'on_device_tts_io.dart';
