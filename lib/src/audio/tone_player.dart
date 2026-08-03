import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

enum Tone { success, duplicate, error }

/// Generates the three feedback tones as WAV files at startup and plays them.
///
/// At an unattended station sound is the primary channel, not the secondary
/// one: a runner scans and is already moving before the screen finishes
/// changing. The three tones are deliberately far apart in pitch and length so
/// they are distinguishable while out of breath and not looking.
class TonePlayer {
  TonePlayer._(this._files, this._players);

  final Map<Tone, File> _files;
  final Map<Tone, AudioPlayer> _players;

  static const int _sampleRate = 44100;

  static Future<TonePlayer> create() async {
    // The sandbox container's Caches directory does not necessarily exist yet
    // on a first run, so it has to be created rather than assumed.
    final dir = Directory('${(await getTemporaryDirectory()).path}/tones');
    try {
      await dir.create(recursive: true);
    } catch (_) {
      // Handled per-tone below; the station still has to start.
    }
    final files = <Tone, File>{};
    final players = <Tone, AudioPlayer>{};

    final specs = <Tone, List<_ToneSegment>>{
      // Two rising notes: unmistakably "done, go".
      Tone.success: [
        const _ToneSegment(1180, 90),
        const _ToneSegment(1760, 150),
      ],
      // A single flat mid note: noticed, but not a new record.
      Tone.duplicate: [const _ToneSegment(880, 240)],
      // Low and long: something is wrong, stay put.
      Tone.error: [
        const _ToneSegment(330, 240),
        const _ToneSegment(0, 60),
        const _ToneSegment(330, 320),
      ],
    };

    for (final entry in specs.entries) {
      // Losing the beeps is bad; refusing to start the station because of it
      // would be far worse. Every tone is best-effort and independent.
      try {
        final file = File('${dir.path}/tone_${entry.key.name}.wav');
        await file.writeAsBytes(_buildWav(entry.value), flush: true);
        files[entry.key] = file;

        final player = AudioPlayer()
          ..setReleaseMode(ReleaseMode.stop)
          ..setPlayerMode(PlayerMode.lowLatency);
        await player.setVolume(1);
        players[entry.key] = player;
      } catch (e) {
        unavailableReason ??= '音效無法初始化:$e';
      }
    }

    return TonePlayer._(files, players);
  }

  /// Non-null when at least one tone could not be prepared, surfaced in the
  /// admin panel so a silent station is noticed before the event rather than
  /// after it.
  static String? unavailableReason;

  Future<void> play(Tone tone) async {
    final file = _files[tone];
    final player = _players[tone];
    if (file == null || player == null) return;
    try {
      await player.stop();
      await player.play(DeviceFileSource(file.path));
    } catch (_) {
      // A station with no audio device must still record scans.
    }
  }

  Future<void> dispose() async {
    for (final p in _players.values) {
      await p.dispose();
    }
  }

  static Uint8List _buildWav(List<_ToneSegment> segments) {
    final samples = <int>[];
    for (final segment in segments) {
      final count = (_sampleRate * segment.millis / 1000).round();
      for (var i = 0; i < count; i++) {
        if (segment.hz == 0) {
          samples.add(0);
          continue;
        }
        // Short linear fades stop the click that a hard square edge makes.
        const fade = 240;
        var gain = 1.0;
        if (i < fade) gain = i / fade;
        if (count - i < fade) gain = math.min(gain, (count - i) / fade);
        final value =
            math.sin(2 * math.pi * segment.hz * i / _sampleRate) * gain * 0.62;
        samples.add((value * 32767).round());
      }
    }

    final dataBytes = samples.length * 2;
    final bytes = BytesBuilder();
    void ascii(String s) => bytes.add(s.codeUnits);
    void u32(int v) => bytes.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little),
    );
    void u16(int v) => bytes.add(
      Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little),
    );

    ascii('RIFF');
    u32(36 + dataBytes);
    ascii('WAVE');
    ascii('fmt ');
    u32(16);
    u16(1); // PCM
    u16(1); // mono
    u32(_sampleRate);
    u32(_sampleRate * 2); // byte rate
    u16(2); // block align
    u16(16); // bits per sample
    ascii('data');
    u32(dataBytes);

    final pcm = Uint8List(dataBytes);
    final view = pcm.buffer.asByteData();
    for (var i = 0; i < samples.length; i++) {
      view.setInt16(i * 2, samples[i], Endian.little);
    }
    bytes.add(pcm);
    return bytes.toBytes();
  }
}

class _ToneSegment {
  const _ToneSegment(this.hz, this.millis);
  final double hz;
  final int millis;
}
