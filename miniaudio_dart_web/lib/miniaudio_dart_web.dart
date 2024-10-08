// ignore_for_file: omit_local_variable_types

import "dart:typed_data";
import "package:miniaudio_dart_platform_interface/miniaudio_dart_platform_interface.dart";
import "package:miniaudio_dart_web/bindings/miniaudio_dart.dart" as wasm;
import "package:miniaudio_dart_web/bindings/wasm/wasm.dart";

class MiniaudioDartWeb extends MiniaudioDartPlatform {
  MiniaudioDartWeb._();

  static void registerWith(dynamic _) =>
      MiniaudioDartPlatform.instance = MiniaudioDartWeb._();

  @override
  PlatformEngine createEngine() {
    final self = wasm.engine_alloc();
    if (self == nullptr) throw MiniaudioDartPlatformOutOfMemoryException();
    return WebEngine(self);
  }

  @override
  PlatformRecorder createRecorder() {
    final self = wasm.recorder_create();
    if (self == nullptr) throw MiniaudioDartPlatformOutOfMemoryException();
    return WebRecorder(self);
  }

  @override
  PlatformGenerator createGenerator() {
    final self = wasm.generator_create();
    if (self == nullptr) throw MiniaudioDartPlatformOutOfMemoryException();
    return WebGenerator(self);
  }
}

final class WebEngine implements PlatformEngine {
  WebEngine(this._self);

  final Pointer<wasm.Engine> _self;

  @override
  EngineState state = EngineState.uninit;

  @override
  Future<void> init(int periodMs) async {
    await wasm.engine_init(_self, periodMs);
  }

  @override
  void dispose() {
    wasm.engine_uninit(_self);
    malloc.free(_self);
  }

  @override
  void start() {
    wasm.engine_start(_self);
  }

  @override
  Future<PlatformSound> loadSound(AudioData audioData) async {
    final dataPtr = malloc.allocate(audioData.buffer.lengthInBytes);
    heap.copyAudioData(dataPtr, audioData.buffer, audioData.format);

    final sound = wasm.sound_alloc(audioData.buffer.lengthInBytes);
    if (sound == nullptr) {
      malloc.free(dataPtr);
      throw MiniaudioDartPlatformException("Failed to allocate a sound.");
    }

    final result = wasm.engine_load_sound(
        _self,
        sound,
        dataPtr,
        audioData.buffer.lengthInBytes,
        audioData.format,
        audioData.sampleRate,
        audioData.channels);

    return WebSound._fromPtrs(sound, dataPtr);
  }
}

final class WebSound implements PlatformSound {
  WebSound._fromPtrs(this._self, this._data);

  final Pointer<wasm.Sound> _self;
  final Pointer _data;

  late var _volume = wasm.sound_get_volume(_self);
  @override
  double get volume => _volume;
  @override
  set volume(double value) {
    wasm.sound_set_volume(_self, value);
    _volume = value;
  }

  @override
  late final double duration = wasm.sound_get_duration(_self);

  var _looping = (false, 0);
  @override
  PlatformSoundLooping get looping => _looping;

  @override
  set looping(PlatformSoundLooping value) {
    wasm.sound_set_looped(_self, value.$1, value.$2);
    _looping = value;
  }

  @override
  void unload() {
    wasm.sound_unload(_self);
    malloc.free(_data);
  }

  @override
  void play() {
    wasm.sound_play(_self);
  }

  @override
  void replay() {
    wasm.sound_replay(_self);
  }

  @override
  void pause() => wasm.sound_pause(_self);
  @override
  void stop() => wasm.sound_stop(_self);
}

final class WebRecorder implements PlatformRecorder {
  WebRecorder(this._self);

  final Pointer<wasm.Recorder> _self;

  @override
  Future<void> initFile(String filename,
      {int sampleRate = 44800,
      int channels = 1,
      int format = AudioFormat.float32}) async {
    final result = await wasm.recorder_init_file(_self, filename,
        sampleRate: sampleRate, channels: channels, format: format);
    if (result != RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException(
          "Failed to initialize recorder with file. Error code: $result");
    }
  }

  @override
  Future<void> initStream(
      {int sampleRate = 44800,
      int channels = 1,
      int format = AudioFormat.float32,
      int bufferDurationSeconds = 5}) async {
    final result = await wasm.recorder_init_stream(_self,
        sampleRate: sampleRate,
        channels: channels,
        format: format,
        bufferDurationSeconds: bufferDurationSeconds);
    if (result != RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException(
          "Failed to initialize recorder stream. Error code: $result");
    }
  }

  @override
  void start() {
    if (wasm.recorder_start(_self) != RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException("Failed to start recording.");
    }
  }

  @override
  void stop() {
    if (wasm.recorder_stop(_self) != RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException("Failed to stop recording.");
    }
  }

  @override
  int getAvailableFrames() => wasm.recorder_get_available_frames(_self);
  Pointer<Float> bufferPtr = malloc.allocate<Float>(0);

  @override
  Float32List getBuffer(int framesToRead, {int channels = 2}) {
    try {
      final int floatsToRead =
          framesToRead * 8; // Calculate the actual number of floats to read

      bufferPtr = malloc.allocate<Float>(floatsToRead);
      bufferPtr.retain(); // Allocate memory for the float buffer
      final floatsRead =
          wasm.recorder_get_buffer(_self, bufferPtr, floatsToRead);

      // Error handling for negative return values
      if (floatsRead < 0) {
        throw MiniaudioDartPlatformException(
            "Failed to get recorder buffer. Error code: $floatsRead");
      }

      // Convert the data in the allocated memory to a Dart Float32List
      return Float32List.fromList(
          bufferPtr.asTypedList(floatsRead) as List<double>);
    } finally {}
  }

  @override
  bool get isRecording => wasm.recorder_is_recording(_self);

  @override
  void dispose() {
    wasm.recorder_destroy(_self);
    malloc.free(_self);
  }
}

final class WebGenerator implements PlatformGenerator {
  WebGenerator(this._self);
  final Pointer<wasm.Generator> _self;

  late var _volume = wasm.generator_get_volume(_self);
  @override
  double get volume => _volume;
  @override
  set volume(double value) {
    wasm.generator_set_volume(_self, value);
    _volume = value;
  }

  @override
  Future<void> init(int format, int channels, int sampleRate,
      int bufferDurationSeconds) async {
    final result = await wasm.generator_init(
        _self, format, channels, sampleRate, bufferDurationSeconds);
    if (result != GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException(
          "Failed to initialize generator. Error code: $result");
    }
  }

  @override
  void setWaveform(WaveformType type, double frequency, double amplitude) {
    final result =
        wasm.generator_set_waveform(_self, type.index, frequency, amplitude);
    if (result != GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to set waveform.");
    }
  }

  @override
  void setPulsewave(double frequency, double amplitude, double dutyCycle) {
    final result =
        wasm.generator_set_pulsewave(_self, frequency, amplitude, dutyCycle);
    if (result != GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to set pulse wave.");
    }
  }

  @override
  void setNoise(NoiseType type, int seed, double amplitude) {
    final result = wasm.generator_set_noise(_self, type.index, seed, amplitude);
    if (result != GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to set noise.");
    }
  }

  @override
  void start() {
    final result = wasm.generator_start(_self);
    if (result != GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to start generator.");
    }
  }

  @override
  void stop() {
    final result = wasm.generator_stop(_self);
    if (result != GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to stop generator.");
    }
  }

  @override
  Float32List getBuffer(int framesToRead) {
    final bufferPtr = malloc.allocate<Float>(framesToRead * 8);
    try {
      final framesRead =
          wasm.generator_get_buffer(_self, bufferPtr, framesToRead);
      if (framesRead < 0) {
        throw MiniaudioDartPlatformException(
            "Failed to read generator data. Error code: $framesRead");
      }
      return Float32List.fromList(
          bufferPtr.asTypedList(framesRead) as List<double>);
    } finally {}
  }

  @override
  int getAvailableFrames() => wasm.generator_get_available_frames(_self);

  @override
  void dispose() {
    wasm.generator_destroy(_self);
    malloc.free(_self);
  }
}
