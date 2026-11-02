/// Device music picker — ports SAFU LivePro's `MusicFolderActivity` +
/// `AudioListActivity`.
///
/// Two screens:
/// * [DeviceMusicFolderScreen] — scans the device library (on_audio_query),
///   groups songs by folder, multi-select per folder, "Confirm Add (N)".
/// * [DeviceMusicSongScreen] — lists songs inside one folder, multi-select
///   with select-all, "Add (N)".
///
/// Both return `List<RoomMusicTrack>` to the caller via `Navigator.pop`.
library device_music_picker;

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../models/room_music_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import 'package:belive/widgets/preloader.dart';

/// Opens the folder picker and returns the selected tracks (or null).
Future<List<RoomMusicTrack>?> showDeviceMusicPicker(BuildContext context) async {
  return Navigator.of(context).push<List<RoomMusicTrack>>(
    MaterialPageRoute(builder: (_) => const DeviceMusicFolderScreen()),
  );
}

class _FolderGroup {
  _FolderGroup(this.folderName, this.path);
  final String folderName;
  final String path;
  final List<SongModel> songs = [];
}

class DeviceMusicFolderScreen extends StatefulWidget {
  const DeviceMusicFolderScreen({super.key});

  @override
  State<DeviceMusicFolderScreen> createState() => _DeviceMusicFolderScreenState();
}

class _DeviceMusicFolderScreenState extends State<DeviceMusicFolderScreen> {
  static const String _tag = 'MusicFolder';
  final OnAudioQuery _audioQuery = OnAudioQuery();

  List<_FolderGroup> _folders = [];
  final Map<String, List<SongModel>> _selectedPerFolder = {};
  bool _loading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final granted = await _audioQuery.checkAndRequest();
      if (!granted) {
        if (mounted) setState(() => _permissionDenied = true);
        return;
      }
      await _loadFolders();
    } catch (e, s) {
      Log.e(_tag, 'init failed', e, s);
      if (mounted) setState(() => _permissionDenied = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFolders() async {
    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
    );
    final map = <String, _FolderGroup>{};
    for (final s in songs) {
      final data = s.data;
      if (data.isEmpty) continue;
      final slash = data.lastIndexOf('/');
      final bslash = data.lastIndexOf('\\');
      final sep = slash >= bslash ? slash : bslash;
      final folderPath = sep >= 0 ? data.substring(0, sep) : '';
      final folderName = sep >= 0
          ? (folderPath.lastIndexOf('/') >= 0
              ? folderPath.substring(folderPath.lastIndexOf('/') + 1)
              : folderPath.isNotEmpty
                  ? folderPath
                  : 'Device')
          : 'Device';
      final key = folderPath.isEmpty ? 'Device' : folderPath;
      map.putIfAbsent(key, () => _FolderGroup(folderName, folderPath)).songs.add(s);
    }
    // Sort folders by name.
    final folders = map.values.toList()
      ..sort((a, b) => a.folderName.toLowerCase().compareTo(b.folderName.toLowerCase()));
    if (mounted) setState(() => _folders = folders);
  }

  int get _totalSelected =>
      _selectedPerFolder.values.fold(0, (sum, l) => sum + l.length);

  Future<void> _openFolder(_FolderGroup folder) async {
    final selected = await Navigator.of(context).push<List<SongModel>>(
      MaterialPageRoute(
        builder: (_) => DeviceMusicSongScreen(
          folderName: folder.folderName,
          songs: folder.songs,
          preselected: _selectedPerFolder[folder.path],
        ),
      ),
    );
    if (selected == null) return;
    if (selected.isEmpty) {
      _selectedPerFolder.remove(folder.path);
    } else {
      _selectedPerFolder[folder.path] = selected;
    }
    if (mounted) setState(() {});
  }

  void _confirmAdd() {
    final tracks = <RoomMusicTrack>[];
    for (final songs in _selectedPerFolder.values) {
      for (final s in songs) {
        tracks.add(RoomMusicTrack.fromDeviceSong(s));
      }
    }
    if (tracks.isEmpty) {
      Fluttertoast.showToast(msg: 'No songs selected');
      return;
    }
    Navigator.of(context).pop(tracks);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Music'),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.purpleGradient)),
      ),
      body: _loading
          ? const Center(child: Preloader())
          : _permissionDenied
              ? _permissionView()
              : _folders.isEmpty
                  ? _emptyView()
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _folders.length,
                      itemBuilder: (_, i) => _folderTile(_folders[i]),
                    ),
      bottomNavigationBar: _loading || _permissionDenied
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _confirmAdd,
                  style: FilledButton.styleFrom(
                    backgroundColor: _totalSelected > 0 ? AppTheme.primary : Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Confirm Add${_totalSelected > 0 ? ' ($_totalSelected)' : ''}'),
                ),
              ),
            ),
    );
  }

  Widget _folderTile(_FolderGroup folder) {
    final selected = _selectedPerFolder[folder.path]?.length ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.folder, color: AppTheme.primary),
        ),
        title: Text(
          folder.folderName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${folder.songs.length} song${folder.songs.length == 1 ? '' : 's'}'),
        trailing: selected > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$selected',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              )
            : const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => _openFolder(folder),
      ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.library_music, size: 72, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No audio files found', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _init, child: const Text('Refresh')),
        ],
      ),
    );
  }

  Widget _permissionView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Audio permission needed to browse your music library.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _init, child: const Text('Grant permission')),
          ],
        ),
      ),
    );
  }
}

class DeviceMusicSongScreen extends StatefulWidget {
  const DeviceMusicSongScreen({
    super.key,
    required this.folderName,
    required this.songs,
    this.preselected,
  });

  final String folderName;
  final List<SongModel> songs;
  final List<SongModel>? preselected;

  @override
  State<DeviceMusicSongScreen> createState() => _DeviceMusicSongScreenState();
}

class _DeviceMusicSongScreenState extends State<DeviceMusicSongScreen> {
  final Set<int> _selectedIds = {};
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    if (widget.preselected != null) {
      for (final s in widget.preselected!) {
        _selectedIds.add(s.id);
      }
    }
    _selectAll = _selectedIds.length == widget.songs.length && widget.songs.isNotEmpty;
  }

  void _toggle(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      _selectAll = _selectedIds.length == widget.songs.length;
    });
  }

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      _selectedIds.clear();
      if (_selectAll) {
        for (final s in widget.songs) {
          _selectedIds.add(s.id);
        }
      }
    });
  }

  void _add() {
    final selected = widget.songs.where((s) => _selectedIds.contains(s.id)).toList();
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folderName, maxLines: 1, overflow: TextOverflow.ellipsis),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.purpleGradient)),
      ),
      body: widget.songs.isEmpty
          ? const Center(child: Text('No songs in this folder', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: widget.songs.length,
              itemBuilder: (_, i) => _songTile(widget.songs[i]),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _toggleSelectAll,
                icon: Icon(
                  _selectAll ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: AppTheme.primary,
                ),
                label: Text(_selectAll ? 'Unselect all' : 'Select all'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _add,
                style: FilledButton.styleFrom(
                  backgroundColor: _selectedIds.isNotEmpty ? AppTheme.primary : Colors.grey,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                child: Text(_selectedIds.isNotEmpty ? 'Add (${_selectedIds.length})' : 'Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _songTile(SongModel song) {
    final selected = _selectedIds.contains(song.id);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 46,
          height: 46,
          child: QueryArtworkWidget(
            id: song.id,
            type: ArtworkType.AUDIO,
            format: ArtworkFormat.JPEG,
            size: 92,
            artworkWidth: 46,
            artworkHeight: 46,
            artworkFit: BoxFit.cover,
            artworkBorder: BorderRadius.circular(8),
            nullArtworkWidget: Container(
              color: AppTheme.primary.withValues(alpha: 0.12),
              child: const Icon(Icons.music_note, color: AppTheme.primary, size: 22),
            ),
          ),
        ),
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal),
      ),
      subtitle: Text(
        '${song.artist ?? 'Unknown artist'} • ${_fmtDuration(song.duration)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? AppTheme.primary : Colors.grey,
      ),
      onTap: () => _toggle(song.id),
    );
  }

  String _fmtDuration(int? ms) {
    if (ms == null || ms <= 0) return '0:00';
    final s = (ms / 1000).round();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }
}
