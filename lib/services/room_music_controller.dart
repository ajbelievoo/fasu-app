/// Unified in-room music controller for live & audio rooms.
///
/// Wraps Agora audio mixing (host) so the host's background music is broadcast
/// to every viewer through the Agora stream (`loopback: false`). Viewers do NOT
/// play locally — they hear the mix through the stream and only mirror the
/// playback state for UI (synced via socket events).
///
/// Ports the native `PopupBuilder.playMusicPopup` flow from SAFU LivePro (which
/// was a stub there) into a proper player with: play / pause / resume / stop /
/// seek / volume / next / previous / auto-advance queue / position + duration.
library room_music_controller;

import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';

import '../models/room_music_models.dart';
import '../utils/log.dart';

/// Socket event hooks the host fires so viewers can mirror state.
/// The screen wires these to `SocketService.emit(Const.eventMusic*)`.
class RoomMusicSocketHooks {
  const RoomMusicSocketHooks({
    this.onPlay,
    this.onPause,
    this.onResume,
    this.onStop,
    this.onSeek,
    this.onTrackChanged,
    this.onVolume,
  });

  /// Host started/resumed a track from [positionMs].
  final void Function(RoomMusicTrack track, int positionMs)? onPlay;

  /// Host paused.
  final void Function()? onPause;

  /// Host resumed.
  final void Function()? onResume;

  /// Host stopped / cleared.
  final void Function()? onStop;

  /// Host seeked to [positionMs].
  final void Function(int positionMs)? onSeek;

  /// Host switched track (next/prev/playAt) — viewers should mirror.
  final void Function(RoomMusicTrack track)? onTrackChanged;

  /// Host changed mixing volume (0..100).
  final void Function(int volume0to100)? onVolume;
}

/// A ChangeNotifier-backed music controller shared by live & audio rooms.
class RoomMusicController extends ChangeNotifier {
  RoomMusicController({
    required RtcEngine engine,
    required bool isHost,
    RoomMusicSocketHooks? hooks,
  }) : _engine = engine,
       _canControl = isHost,
       _hooks = hooks ?? const RoomMusicSocketHooks();

  static const String _tag = 'RoomMusic';

  final RtcEngine _engine;
  bool _canControl;
  RoomMusicSocketHooks _hooks;

  void setCanControl(bool value) {
    _canControl = value;
  }

  /// Whether this client is allowed to drive Agora audio mixing (host or
  /// authorized admin). When false, the controller mirrors remote state.
  bool get canControl => _canControl;

  /// Update hooks (e.g. after socket subscriptions are wired).
  set hooks(RoomMusicSocketHooks value) {
    _hooks = value;
  }

  // ---- Queue ----
  final List<RoomMusicTrack> _queue = [];
  List<RoomMusicTrack> get queue => List.unmodifiable(_queue);
  int _currentIndex = -1;
  int get currentIndex => _currentIndex;
  RoomMusicTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

  // ---- Playback state ----
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;
  int _positionMs = 0;
  int get positionMs => _positionMs;
  int _durationMs = 0;
  int get durationMs => _durationMs;
  double _volume = 0.8; // 0..1
  double get volume => _volume;

  Timer? _posTimer;
  bool _advancing = false; // guard against re-entrant auto-advance

  // ---- Queue management ----

  void addTracks(List<RoomMusicTrack> tracks) {
    if (tracks.isEmpty) return;
    _queue.addAll(tracks);
    notifyListeners();
  }

  void replaceQueue(List<RoomMusicTrack> tracks) {
    _queue
      ..clear()
      ..addAll(tracks);
    _currentIndex = -1;
    _isPlaying = false;
    _positionMs = 0;
    _durationMs = 0;
    notifyListeners();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final wasCurrent = index == _currentIndex;
    _queue.removeAt(index);
    if (wasCurrent) {
      await stop(notify: false);
      _currentIndex = -1;
    } else if (_currentIndex > index) {
      _currentIndex--;
    }
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    _isPlaying = false;
    _positionMs = 0;
    _durationMs = 0;
    _posTimer?.cancel();
    notifyListeners();
  }

  // ---- Host: Agora audio mixing ----

  Future<void> playAt(int index, {int startPosMs = 0}) async {
    if (index < 0 || index >= _queue.length) return;
    if (!_canControl) {
      // Viewer: just mirror state.
      _currentIndex = index;
      _isPlaying = true;
      _positionMs = startPosMs;
      _durationMs = _queue[index].durationMs ?? 0;
      _startViewerClock();
      notifyListeners();
      return;
    }
    final track = _queue[index];
    try {
      await _engine.stopAudioMixing();
      await _engine.startAudioMixing(
        filePath: track.source,
        loopback: false,
        cycle: 1,
        startPos: startPosMs,
      );
      await _engine.adjustAudioMixingVolume((_volume * 100).round());
      _currentIndex = index;
      _isPlaying = true;
      _positionMs = startPosMs;
      // Duration may not be known until playing; fall back to model value.
      _durationMs = track.durationMs ?? 0;
      _startPosPolling();
      _hooks.onPlay?.call(track, startPosMs);
      _hooks.onTrackChanged?.call(track);
      _refreshDuration();
    } catch (e, s) {
      Log.e(_tag, 'playAt failed', e, s);
    }
    notifyListeners();
  }

  Future<void> play() async {
    if (!_canControl) return;
    if (_currentIndex == -1) {
      if (_queue.isNotEmpty) {
        await playAt(0);
      }
      return;
    }
    // Resume.
    try {
      await _engine.resumeAudioMixing();
      _isPlaying = true;
      _startPosPolling();
      _hooks.onResume?.call();
    } catch (e, s) {
      Log.e(_tag, 'resume failed', e, s);
    }
    notifyListeners();
  }

  Future<void> pause() async {
    if (!_canControl) {
      _isPlaying = false;
      _posTimer?.cancel();
      notifyListeners();
      return;
    }
    try {
      await _engine.pauseAudioMixing();
      _isPlaying = false;
      _posTimer?.cancel();
      _hooks.onPause?.call();
    } catch (e, s) {
      Log.e(_tag, 'pause failed', e, s);
    }
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> stop({bool notify = true}) async {
    if (_canControl) {
      try {
        await _engine.stopAudioMixing();
      } catch (e, s) {
        Log.e(_tag, 'stop failed', e, s);
      }
      _hooks.onStop?.call();
    }
    _isPlaying = false;
    _positionMs = 0;
    _posTimer?.cancel();
    if (notify) notifyListeners();
  }

  /// Stop only the local Agora audio mixing without invoking the [onStop]
  /// hook. Used when another host/admin has taken over music playback so this
  /// client stops its own output without emitting a competing stop event.
  Future<void> stopLocalMixing() async {
    if (_canControl) {
      try {
        await _engine.stopAudioMixing();
      } catch (e, s) {
        Log.e(_tag, 'stopLocalMixing failed', e, s);
      }
    }
    _isPlaying = false;
    _posTimer?.cancel();
    notifyListeners();
  }

  Future<void> close() async {
    await stop(notify: false);
    _queue.clear();
    _currentIndex = -1;
    _durationMs = 0;
    notifyListeners();
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    final n = (_currentIndex + 1) % _queue.length;
    await playAt(n);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    final p = _currentIndex <= 0 ? _queue.length - 1 : _currentIndex - 1;
    await playAt(p);
  }

  /// Seek to [positionMs]. Agora's `seekAudioMixing` is not exposed in this
  /// SDK build, so for the host we restart the track at the new position.
  Future<void> seekTo(int positionMs) async {
    if (_currentIndex < 0) return;
    if (!_canControl) {
      _positionMs = positionMs;
      notifyListeners();
      return;
    }
    final idx = _currentIndex;
    try {
      await _engine.stopAudioMixing();
      await _engine.startAudioMixing(
        filePath: _queue[idx].source,
        loopback: false,
        cycle: 1,
        startPos: positionMs,
      );
      await _engine.adjustAudioMixingVolume((_volume * 100).round());
      _positionMs = positionMs;
      _isPlaying = true;
      _startPosPolling();
      _hooks.onSeek?.call(positionMs);
    } catch (e, s) {
      Log.e(_tag, 'seek failed', e, s);
    }
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    if (_canControl) {
      try {
        await _engine.adjustAudioMixingVolume((_volume * 100).round());
        _hooks.onVolume?.call((_volume * 100).round());
      } catch (e, s) {
        Log.e(_tag, 'setVolume failed', e, s);
      }
    }
    notifyListeners();
  }

  // ---- Agora completion callback (wired by the screen) ----

  /// Called from `onAudioMixingStateChanged`. Handles auto-advance.
  void onAudioMixingStateChanged(
    AudioMixingStateType state,
    AudioMixingReasonType reason,
  ) {
    if (!_canControl) return;
    if (state == AudioMixingStateType.audioMixingStateStopped &&
        reason == AudioMixingReasonType.audioMixingReasonAllLoopsCompleted) {
      _autoAdvance();
    } else if (state == AudioMixingStateType.audioMixingStateFailed) {
      Log.e(_tag, 'audioMixing failed: $reason', null);
    }
  }

  Future<void> _autoAdvance() async {
    if (_advancing) return;
    _advancing = true;
    try {
      _posTimer?.cancel();
      if (_queue.length > 1) {
        await next();
      } else {
        _isPlaying = false;
        _positionMs = 0;
        _currentIndex = -1;
        _hooks.onStop?.call();
        notifyListeners();
      }
    } finally {
      _advancing = false;
    }
  }

  // ---- Position polling (host) ----

  void _startPosPolling() {
    _posTimer?.cancel();
    // Agora docs: interval between getAudioMixingCurrentPosition calls must be
    // greater than 500 ms.
    _posTimer = Timer.periodic(const Duration(milliseconds: 600), (_) async {
      if (!_canControl || !_isPlaying) return;
      try {
        final pos = await _engine.getAudioMixingCurrentPosition();
        if (pos >= 0 && _isPlaying) {
          _positionMs = pos;
          notifyListeners();
        }
      } catch (e, s) {
        Log.e(_tag, 'pos poll failed', e, s);
      }
    });
  }

  Future<void> _refreshDuration() async {
    if (!_canControl) return;
    try {
      final d = await _engine.getAudioMixingDuration();
      if (d > 0) {
        _durationMs = d;
        notifyListeners();
      }
    } catch (e, s) {
      Log.e(_tag, 'duration fetch failed', e, s);
    }
  }

  // ---- Viewer clock (estimate position from wall clock) ----

  void _startViewerClock() {
    _posTimer?.cancel();
    final dur = _durationMs;
    if (dur <= 0) return;
    _posTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPlaying) return;
      _positionMs = (_positionMs + 1000).clamp(0, dur);
      if (_positionMs >= dur) {
        _posTimer?.cancel();
        _isPlaying = false;
      }
      notifyListeners();
    });
  }

  // ---- Viewer: mirror state from host (via socket) ----

  void mirrorPlay(RoomMusicTrack track, int positionMs) {
    if (_canControl) return;
    // Ensure track is in queue (single-track mirror if queue empty).
    final existing = _queue.indexWhere((t) => t.id == track.id);
    if (existing >= 0) {
      _currentIndex = existing;
    } else {
      _queue.add(track);
      _currentIndex = _queue.length - 1;
    }
    _isPlaying = true;
    _positionMs = positionMs;
    _durationMs = track.durationMs ?? 0;
    _startViewerClock();
    notifyListeners();
  }

  void mirrorPause() {
    if (_canControl) return;
    _isPlaying = false;
    _posTimer?.cancel();
    notifyListeners();
  }

  void mirrorResume() {
    if (_canControl) return;
    if (_currentIndex < 0) return;
    _isPlaying = true;
    _startViewerClock();
    notifyListeners();
  }

  void mirrorStop() {
    if (_canControl) return;
    _isPlaying = false;
    _positionMs = 0;
    _durationMs = 0;
    _currentIndex = -1;
    _queue.clear();
    _posTimer?.cancel();
    notifyListeners();
  }

  void mirrorSeek(int positionMs) {
    if (_canControl) return;
    _positionMs = positionMs;
    notifyListeners();
  }

  void mirrorVolume(int volume0to100) {
    if (_canControl) return;
    _volume = (volume0to100 / 100).clamp(0.0, 1.0);
    notifyListeners();
  }

  @override
  void dispose() {
    _posTimer?.cancel();
    super.dispose();
  }
}
