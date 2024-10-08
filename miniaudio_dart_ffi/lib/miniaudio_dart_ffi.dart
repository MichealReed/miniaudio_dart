// ignore_for_file: omit_local_variable_types

import "dart:ffi";
import "dart:io";
import "dart:typed_data";

import "package:ffi/ffi.dart";
import "package:miniaudio_dart_ffi/miniaudio_dart_ffi_bindings.dart" as ffi;
import "package:miniaudio_dart_platform_interface/miniaudio_dart_platform_interface.dart";

// dynamic lib
const String _libName = "miniaudio_dart_ffi";
final _bindings = ffi.MiniaudioDartFfiBindings(() {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open("$_libName.framework/$_libName");
  } else if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open("lib$_libName.so");
  } else if (Platform.isWindows) {
    return DynamicLibrary.open("$_libName.dll");
  }
  throw UnsupportedError("Unsupported platform: ${Platform.operatingSystem}");
}());

// miniaudio_dart ffi
class MiniaudioDartFfi extends MiniaudioDartPlatform {
  MiniaudioDartFfi._();

  static void registerWith() =>
      MiniaudioDartPlatform.instance = MiniaudioDartFfi._();

  @override
  PlatformEngine createEngine() {
    final self = _bindings.engine_alloc();
    if (self == nullptr) throw MiniaudioDartPlatformOutOfMemoryException();
    return FfiEngine(self);
  }

  @override
  PlatformRecorder createRecorder() {
    final self = _bindings.recorder_create();
    if (self == nullptr) throw MiniaudioDartPlatformOutOfMemoryException();
    return FfiRecorder(self);
  }

  @override
  PlatformGenerator createGenerator() {
    final self = _bindings.generator_create();
    if (self == nullptr) throw MiniaudioDartPlatformOutOfMemoryException();
    return FfiGenerator(
      self,
    );
  }
}

// engine ffi
final class FfiEngine implements PlatformEngine {
  FfiEngine(Pointer<ffi.Engine> self) : _self = self;

  final Pointer<ffi.Engine> _self;

  @override
  EngineState state = EngineState.uninit;

  @override
  Future<void> init(int periodMs) async {
    if (_bindings.engine_init(_self, periodMs) != 1) {
      throw MiniaudioDartPlatformException("Failed to init the engine.");
    }
  }

  @override
  void dispose() {
    _bindings.engine_uninit(_self);
    malloc.free(_self);
  }

  @override
  void start() {
    if (_bindings.engine_start(_self) != 1) {
      throw MiniaudioDartPlatformException("Failed to start the engine.");
    }
  }

  @override
  Future<PlatformSound> loadSound(AudioData audioData) async {
    final int dataSize = audioData.buffer.lengthInBytes;
    final Pointer<Float> dataPtr =
        malloc.allocate<Float>(audioData.buffer.length * sizeOf<Float>());

    final Float32List floatList = dataPtr.asTypedList(audioData.buffer.length);
    floatList.setAll(0, audioData.buffer);

    final Pointer<ffi.Sound> sound = _bindings.sound_alloc();
    if (sound == nullptr) {
      throw MiniaudioDartPlatformException("Failed to allocate a sound.");
    }

    final int maFormat = audioData.format;
    final int result = _bindings.engine_load_sound(
      _self,
      sound,
      dataPtr,
      dataSize,
      maFormat,
      audioData.sampleRate,
      audioData.channels,
    );

    if (result != 1) {
      _bindings.sound_unload(sound);
      throw MiniaudioDartPlatformException("Failed to load a sound.");
    }

    return FfiSound._fromPtrs(sound, dataPtr);
  }
}

// sound ffi
final class FfiSound implements PlatformSound {
  FfiSound._fromPtrs(Pointer<ffi.Sound> self, Pointer data)
      : _self = self,
        _data = data,
        _volume = _bindings.sound_get_volume(self),
        _duration = _bindings.sound_get_duration(self);

  final Pointer<ffi.Sound> _self;
  final Pointer _data;

  double _volume;
  @override
  double get volume => _volume;
  @override
  set volume(double value) {
    _bindings.sound_set_volume(_self, value);
    _volume = value;
  }

  final double _duration;
  @override
  double get duration => _duration;

  PlatformSoundLooping _looping = (false, 0);
  @override
  PlatformSoundLooping get looping => _looping;
  @override
  set looping(PlatformSoundLooping value) {
    _bindings.sound_set_looped(_self, value.$1, value.$2);
    _looping = value;
  }

  @override
  void unload() {
    _bindings.sound_unload(_self);
    malloc.free(_data);
  }

  @override
  void play() {
    if (_bindings.sound_play(_self) != 1) {
      throw MiniaudioDartPlatformException("Failed to play the sound.");
    }
  }

  @override
  void replay() {
    _bindings.sound_replay(_self);
  }

  @override
  void pause() => _bindings.sound_pause(_self);
  @override
  void stop() => _bindings.sound_stop(_self);
}

// recorder ffi
class FfiRecorder implements PlatformRecorder {
  FfiRecorder(Pointer<ffi.Recorder> self) : _self = self;

  final Pointer<ffi.Recorder> _self;

  @override
  Future<void> initFile(String filename,
      {int sampleRate = 44800, int channels = 1, int format = 4}) async {
    final filenamePtr = filename.toNativeUtf8();
    try {
      if (_bindings.recorder_init_file(
              _self, filenamePtr.cast(), sampleRate, channels, format) !=
          ffi.RecorderResult.RECORDER_OK) {
        throw MiniaudioDartPlatformException(
            "Failed to initialize recorder with file.");
      }
    } finally {
      malloc.free(filenamePtr);
    }
  }

  @override
  Future<void> initStream(
      {int sampleRate = 44800,
      int channels = 1,
      int format = 4, // float32
      int bufferDurationSeconds = 5}) async {
    if (_bindings.recorder_init_stream(
            _self, sampleRate, channels, format, bufferDurationSeconds) !=
        ffi.RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException(
          "Failed to initialize recorder stream.");
    }
  }

  @override
  void start() {
    if (_bindings.recorder_start(_self) != ffi.RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException("Failed to start recording.");
    }
  }

  @override
  void stop() {
    if (_bindings.recorder_stop(_self) != ffi.RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException("Failed to stop recording.");
    }
  }

  @override
  bool get isRecording => _bindings.recorder_is_recording(_self);

  Pointer<Float> bufferPtr = malloc.allocate<Float>(0);

  @override
  Float32List getBuffer(int framesToRead) {
    try {
      final floatsToRead = framesToRead *
          sizeOf<Float>(); // Calculate the actual number of floats to read

      bufferPtr = malloc.allocate<Float>(
          floatsToRead); // Allocate memory for the float buffer
      final floatsRead =
          _bindings.recorder_get_buffer(_self, bufferPtr, floatsToRead);

      // Error handling for negative return values
      if (floatsRead < 0) {
        throw MiniaudioDartPlatformException(
            "Failed to get recorder buffer. Error code: $floatsRead");
      }

      // Convert the data in the allocated memory to a Dart Float32List
      return Float32List.fromList(bufferPtr.asTypedList(floatsRead));
    } finally {}
  }

  @override
  int getAvailableFrames() => _bindings.recorder_get_available_frames(_self);

  @override
  void dispose() {
    _bindings.recorder_destroy(_self);
  }
}

// generator ffi
class FfiGenerator implements PlatformGenerator {
  FfiGenerator(Pointer<ffi.Generator> self)
      : _self = self,
        _volume = _bindings.generator_get_volume(self);

  final Pointer<ffi.Generator> _self;

  double _volume;
  @override
  double get volume => _volume;
  @override
  set volume(double value) {
    _bindings.generator_set_volume(_self, value);
    _volume = value;
  }

  @override
  Future<int> init(int format, int channels, int sampleRate,
      int bufferDurationSeconds) async {
    final result = _bindings.generator_init(
        _self, format, channels, sampleRate, bufferDurationSeconds);
    if (result != ffi.GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException(
          "Failed to initialize generator. Error code: $result");
    }
    return result;
  }

  @override
  void setWaveform(WaveformType type, double frequency, double amplitude) {
    final result = _bindings.generator_set_waveform(
        _self, type.index, frequency, amplitude);
    if (result != ffi.GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to set waveform.");
    }
  }

  @override
  void setPulsewave(double frequency, double amplitude, double dutyCycle) {
    final result = _bindings.generator_set_pulsewave(
        _self, frequency, amplitude, dutyCycle);
    if (result != ffi.GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to set pulse wave.");
    }
  }

  @override
  void setNoise(NoiseType type, int seed, double amplitude) {
    final result =
        _bindings.generator_set_noise(_self, type.index, seed, amplitude);
    if (result != ffi.GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to set noise.");
    }
  }

  @override
  void start() {
    final result = _bindings.generator_start(_self);
    if (result != ffi.GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to start generator.");
    }
  }

  @override
  void stop() {
    final result = _bindings.generator_stop(_self);
    if (result != ffi.GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to stop generator.");
    }
  }

  Pointer<Float> bufferPtr = malloc.allocate<Float>(0);

  @override
  Float32List getBuffer(int framesToRead) {
    try {
      final floatsToRead =
          framesToRead * 8; // Calculate the actual number of floats to read

      bufferPtr = malloc.allocate<Float>(
          floatsToRead); // Allocate memory for the float buffer
      final floatsRead =
          _bindings.generator_get_buffer(_self, bufferPtr, floatsToRead);

      // Error handling for negative return values
      if (floatsRead < 0) {
        throw MiniaudioDartPlatformException(
            "Failed to get recorder buffer. Error code: $floatsRead");
      }

      // Convert the data in the allocated memory to a Dart Float32List
      return Float32List.fromList(bufferPtr.asTypedList(floatsRead));
    } finally {}
  }

  @override
  int getAvailableFrames() => _bindings.generator_get_available_frames(_self);

  @override
  void dispose() {
    _bindings.generator_destroy(_self);
  }
}
