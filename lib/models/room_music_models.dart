/// Models for the in-room music player.
///
/// Ports the native `AudioDetails` model from SAFU LivePro and adds the fields
/// needed by the unified [RoomMusicController] / [RoomMusicBar].
library room_music_models;

import 'package:on_audio_query/on_audio_query.dart';

import 'json_annotation_helper.dart';

/// A single track in the room music queue.
///
/// `source` is either a device-local file path or a remote URL. The controller
/// feeds it straight to Agora `startAudioMixing` (host) which accepts both.
class RoomMusicTrack {
  RoomMusicTrack({
    required this.id,
    required this.title,
    this.artist,
    required this.source,
    this.artUri,
    this.durationMs,
    this.isLocal = true,
  });

  /// Build from a scanned device song ([SongModel] from on_audio_query).
  /// Album art is loaded lazily via [QueryArtworkWidget] in the picker; the
  /// bar falls back to a music icon when [artUri] is null.
  factory RoomMusicTrack.fromDeviceSong(SongModel song) {
    final data = song.data; // absolute file path
    return RoomMusicTrack(
      id: 'dev_${song.id}',
      title: song.title.isNotEmpty ? song.title : _fileName(data),
      artist: song.artist,
      source: data,
      artUri: null,
      durationMs: song.duration,
      isLocal: true,
    );
  }

  /// Build from a server song (AddMusicScreen / ApiService.getSongs).
  factory RoomMusicTrack.fromServerSong({
    required String id,
    required String title,
    String? artist,
    required String url,
    String? image,
    int? durationMs,
  }) {
    return RoomMusicTrack(
      id: 'srv_$id',
      title: title,
      artist: artist,
      source: url,
      artUri: image,
      durationMs: durationMs,
      isLocal: false,
    );
  }

  final String id;
  final String title;
  final String? artist;
  final String source;
  final String? artUri;
  final int? durationMs;
  final bool isLocal;

  bool get isRemote => !isLocal;

  Map<String, dynamic> toSocketJson() => {
        'id': id,
        'title': title,
        'artist': artist ?? '',
        'source': source,
        'artUri': artUri ?? '',
        'durationMs': durationMs ?? 0,
        'isLocal': isLocal,
      };

  factory RoomMusicTrack.fromSocketJson(Map<String, dynamic> json) {
    return RoomMusicTrack(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      artist: json['artist']?.toString(),
      source: json['source']?.toString() ?? '',
      artUri: json['artUri']?.toString(),
      durationMs: parseInt(json['durationMs']),
      isLocal: parseBool(json['isLocal']),
    );
  }

  static String _fileName(String path) {
    final idx = path.lastIndexOf('/');
    final jdx = path.lastIndexOf('\\');
    final i = idx > jdx ? idx : jdx;
    return i >= 0 ? path.substring(i + 1) : path;
  }

  @override
  bool operator ==(Object other) => other is RoomMusicTrack && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
