/// Gift sound effect service.
///
/// Provides two sound layers for gifts (matching native SAFU LivePro behaviour):
///
/// 1. **Default gift sound** — a short coin/chime (`assets/sounds/gift.wav`)
///    played on every gift send & receive. Native SVGA gifts carry their own
///    embedded audio; for non-SVGA gifts and as a reliable baseline we play
///    this default chime.
/// 2. **SVGA embedded audio** — SVGA files can contain audio tracks (stored in
///    `MovieEntity.audios` → `images[audioKey]`). The `svgaplayer_flutter`
///    package parses but never plays them. `playSvgaAudio()` plays those bytes
///    via `just_audio`, mirroring the native `SVGAImageView` which plays
///    embedded audio automatically.
///
/// Throttling: the default sound is rate-limited (default 220ms) so rapid
/// gift streaks / combos don't machine-gun the audio.
library gift_sound_service;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/log.dart';

class GiftSoundService {
  GiftSoundService._();
  static final GiftSoundService instance = GiftSoundService._();

  static const String _tag = 'GiftSoundService';
  static const String _defaultAsset = 'assets/sounds/gift.wav';

  // Default sound player (reused for low latency).
  AudioPlayer? _defaultPlayer;
  bool _defaultReady = false;

  // Dedicated player for SVGA embedded audio (separate so the default chime
  // can overlap / not be cut off by longer SVGA audio).
  AudioPlayer? _svgaPlayer;

  // Throttle state for the default sound.
  DateTime? _lastDefaultPlay;
  Duration _minInterval = const Duration(milliseconds: 220);

  /// Initialise & preload the default gift sound. Safe to call multiple times.
  Future<void> init() async {
    if (_defaultPlayer != null && _defaultReady) return;
    try {
      final p = AudioPlayer();
      await p.setAsset(_defaultAsset);
      await p.setVolume(1.0);
      _defaultPlayer = p;
      _defaultReady = true;
      Log.d(_tag, 'default gift sound preloaded');
    } catch (e) {
      Log.e(_tag, 'preload default gift sound failed', e);
      // Mark not ready so playDefault falls back to a fresh attempt.
      _defaultReady = false;
    }
  }

  /// Play the default gift chime. [send] true for sender, false for receiver.
  Future<void> playDefault({bool send = false}) async {
    final now = DateTime.now();
    final last = _lastDefaultPlay;
    if (last != null && now.difference(last) < _minInterval) return;
    _lastDefaultPlay = now;

    try {
      var player = _defaultPlayer;
      if (player == null || !_defaultReady) {
        await init();
        player = _defaultPlayer;
      }
      if (player != null) {
        await player.setVolume(1.0);
        await player.seek(Duration.zero);
        await player.play();
        return;
      }
    } catch (e) {
      Log.e(_tag, 'playDefault failed, trying fresh player', e);
    }

    // Fallback: create a fresh player if the preloaded player had an issue.
    // Store it as _defaultPlayer so it's reused and disposed — a bare local
    // AudioPlayer leaks native resources on every fallback play.
    try {
      await _defaultPlayer?.dispose();
      final p = AudioPlayer();
      _defaultPlayer = p;
      await p.setAsset(_defaultAsset);
      _defaultReady = true;
      await p.setVolume(1.0);
      await p.play();
    } catch (e) {
      Log.e(_tag, 'fallback playDefault failed', e);
    }
  }

  /// Convenience wrappers.
  Future<void> playSendSound() => playDefault(send: true);
  Future<void> playReceiveSound() => playDefault(send: false);

  /// Play embedded audio bytes extracted from an SVGA file.
  ///
  /// [bytes] is the raw audio payload (typically mp3/aac) stored under
  /// `MovieEntity.images[audioKey]`. We persist it to a temp file and play via
  /// `just_audio` (which can't play from an in-memory byte buffer directly).
  Future<void> playSvgaAudio(Uint8List bytes) async {
    if (bytes.isEmpty) return;
    try {
      final dir = await getTemporaryDirectory();
      // Reuse ONE temp file — previously every SVGA gift wrote a new file
      // (svga_audio_0/1/2...) that was never deleted, growing cache forever.
      final file = File('${dir.path}/svga_audio.mp3');
      await file.writeAsBytes(bytes, flush: true);

      // Reuse a single SVGA player; stop any in-flight audio first.
      _svgaPlayer ??= AudioPlayer();
      final p = _svgaPlayer!;
      await p.stop();
      await p.setVolume(1.0);
      // Explicitly disable looping — SVGA gift audio should play ONCE, not
      // repeat endlessly after the animation finishes.
      await p.setLoopMode(LoopMode.off);
      await p.setFilePath(file.path);
      await p.play();
      Log.d(_tag, 'SVGA embedded audio playing (${bytes.length} bytes)');
    } catch (e) {
      Log.e(_tag, 'playSvgaAudio failed', e);
    }
  }

  /// Stop any currently playing SVGA audio (called when a gift overlay hides).
  Future<void> stopSvgaAudio() async {
    try {
      await _svgaPlayer?.stop();
    } catch (_) {}
  }

  /// Set the minimum interval between default chime plays (for streaks).
  void setThrottleInterval(Duration d) => _minInterval = d;

  Future<void> dispose() async {
    try {
      await _defaultPlayer?.dispose();
      await _svgaPlayer?.dispose();
    } catch (_) {}
    _defaultPlayer = null;
    _svgaPlayer = null;
    _defaultReady = false;
  }
}
