import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF09080F),
    ),
  );
  runApp(const AuraApp());
}

class LyricLine {
  final Duration time;
  final String text;
  LyricLine({required this.time, required this.text});
}

class TrackItem {
  final String id;
  final String title;
  final String artist;
  final String thumb;

  TrackItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumb,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'thumb': thumb,
      };

  factory TrackItem.fromJson(Map<String, dynamic> json) => TrackItem(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        artist: json['artist'] ?? '',
        thumb: json['thumb'] ?? '',
      );
}

class AuraApp extends StatelessWidget {
  const AuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF09080F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFA855F7),
          secondary: Color(0xFF3B82F6),
        ),
      ),
      home: const AuraMainScreen(),
    );
  }
}

class AuraMainScreen extends StatefulWidget {
  const AuraMainScreen({super.key});

  @override
  State<AuraMainScreen> createState() => _AuraMainScreenState();
}

class _AuraMainScreenState extends State<AuraMainScreen> {
  final AudioPlayer _player = AudioPlayer();
  final YoutubeExplode _yt = YoutubeExplode();
  final TextEditingController _searchController = TextEditingController();

  int _selectedTab = 0;
  List<TrackItem> _searchResults = [];
  List<TrackItem> _favorites = [];
  List<TrackItem> _recentTracks = [];
  bool _isLoading = false;
  bool _isBuffering = false;
  String _statusMessage = "Listo para reproducir";

  TrackItem? _currentTrack;

  List<LyricLine> _syncedLyrics = [];
  String _plainLyrics = "Busca y reproduce cualquier canción para ver su letra.";
  bool _hasSyncedLyrics = false;

  @override
  void initState() {
    super.initState();
    _loadSavedData();

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _playNextTrack();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _player.dispose();
    _yt.close();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final favList = prefs.getStringList('aura_clean_favs') ?? [];
    final recList = prefs.getStringList('aura_clean_recents') ?? [];
    setState(() {
      _favorites = favList.map((e) => TrackItem.fromJson(json.decode(e))).toList();
      _recentTracks = recList.map((e) => TrackItem.fromJson(json.decode(e))).toList();
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'aura_clean_favs', _favorites.map((e) => json.encode(e.toJson())).toList());
    await prefs.setStringList(
        'aura_clean_recents', _recentTracks.map((e) => json.encode(e.toJson())).toList());
  }

  Future<void> _searchMusic(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _selectedTab = 1;
    });

    List<TrackItem> found = [];

    // Buscamos directamente en YouTube para asegurar que cada resultado tenga su Video ID listo para sonar
    try {
      final ytRes = await _yt.search.search("$cleanQuery official audio").timeout(const Duration(seconds: 6));
      for (var v in ytRes) {
        found.add(TrackItem(
          id: v.id.value,
          title: v.title,
          artist: v.author.replaceAll(' - Topic', '').replaceAll('VEVO', ''),
          thumb: v.thumbnails.highResUrl,
        ));
      }
    } catch (_) {}

    // Respaldo con iTunes si YouTube llegara a tardar
    if (found.isEmpty) {
      try {
        final url = Uri.parse(
            'https://itunes.apple.com/search?term=${Uri.encodeComponent(cleanQuery)}&entity=song&limit=20');
        final res = await http.get(url).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final List list = data['results'] ?? [];
          for (var item in list) {
            final String art = (item['artworkUrl100'] as String? ?? '')
                .replaceAll('100x100bb', '600x600bb');
            found.add(TrackItem(
              id: '',
              title: item['trackName'] ?? 'Canción',
              artist: item['artistName'] ?? 'Artista',
              thumb: art.isNotEmpty ? art : 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500',
            ));
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _searchResults = found;
        _isLoading = false;
      });
    }
  }

  // ==========================================================================
  // MOTOR DE AUDIO BLINDADO (Extrae el flujo Muxed y MP4 Directo)
  // ==========================================================================
  Future<void> _playTrack(TrackItem track) async {
    setState(() {
      _currentTrack = track;
      _isBuffering = true;
      _statusMessage = "Conectando stream...";
    });

    _recentTracks.removeWhere((t) => t.title == track.title && t.artist == track.artist);
    _recentTracks.insert(0, track);
    if (_recentTracks.length > 12) _recentTracks.removeLast();
    _saveData();

    _fetchSyncedLyrics(track.title, track.artist);

    try {
      await _player.stop();
    } catch (_) {}

    try {
      String videoId = track.id;
      if (videoId.isEmpty) {
        final searchList = await _yt.search
            .search("${track.title} ${track.artist} audio")
            .timeout(const Duration(seconds: 4));
        if (searchList.isNotEmpty) {
          videoId = searchList.first.id.value;
        }
      }

      if (videoId.isEmpty) throw Exception("Sin ID");

      final manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [
          YoutubeApiClient.androidVr,
          YoutubeApiClient.safari,
          YoutubeApiClient.ios,
        ],
      ).timeout(const Duration(seconds: 5));

      final List<String> candidateUrls = [];

      if (manifest.muxed.isNotEmpty) {
        candidateUrls.add(manifest.muxed.withHighestBitrate().url.toString());
      }

      final mp4Audios = manifest.audioOnly
          .where((s) => s.container.name.toLowerCase() == 'mp4')
          .toList();
      if (mp4Audios.isNotEmpty) {
        mp4Audios.sort((a, b) => b.bitrate.compareTo(a.bitrate));
        candidateUrls.add(mp4Audios.first.url.toString());
      }

      if (manifest.audioOnly.isNotEmpty) {
        candidateUrls.add(manifest.audioOnly.withHighestBitrate().url.toString());
      }

      for (final streamUrl in candidateUrls) {
        try {
          await _player.setUrl(streamUrl).timeout(const Duration(seconds: 5));
          _player.play();
          if (mounted) {
            setState(() {
              _isBuffering = false;
              _statusMessage = "Toca para ver la letra 🎤";
            });
          }
          return;
        } catch (_) {}
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isBuffering = false;
        _statusMessage = "Toca otra versión de la lista";
      });
    }
  }

  Future<void> _fetchSyncedLyrics(String rawTitle, String rawArtist) async {
    setState(() {
      _syncedLyrics = [];
      _hasSyncedLyrics = false;
      _plainLyrics = "Buscando letra sincronizada...";
    });

    final cleanTitle = rawTitle
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'Official|Audio|Video|Visualizer|Lyrics|feat\..*|ft\..*', caseSensitive: false), '')
        .trim();
    final cleanArtist = rawArtist.split(',').first.split('&').first.trim();

    try {
      final url = Uri.parse(
          'https://lrclib.net/api/search?q=${Uri.encodeComponent("$cleanTitle $cleanArtist")}');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final List list = json.decode(utf8.decode(res.bodyBytes));
        if (list.isNotEmpty) {
          final syncedItem = list.firstWhere(
            (item) => item['syncedLyrics'] != null && item['syncedLyrics'].toString().isNotEmpty,
            orElse: () => list.first,
          );

          if (syncedItem['syncedLyrics'] != null &&
              syncedItem['syncedLyrics'].toString().isNotEmpty) {
            final parsed = _parseLrc(syncedItem['syncedLyrics'].toString());
            if (parsed.isNotEmpty) {
              setState(() {
                _syncedLyrics = parsed;
                _hasSyncedLyrics = true;
              });
              return;
            }
          }

          if (syncedItem['plainLyrics'] != null) {
            setState(() {
              _plainLyrics = syncedItem['plainLyrics'].toString();
              _hasSyncedLyrics = false;
            });
            return;
          }
        }
      }
    } catch (_) {}

    setState(() {
      _plainLyrics = "Letra no disponible para '$cleanTitle'.";
      _hasSyncedLyrics = false;
    });
  }

  List<LyricLine> _parseLrc(String lrcText) {
    final List<LyricLine> lines = [];
    final regExp = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
    for (final rawLine in lrcText.split('\n')) {
      final match = regExp.firstMatch(rawLine);
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final ms = int.parse(match.group(3)!.padRight(3, '0'));
        final text = match.group(4)!.trim();
        if (text.isNotEmpty) {
          lines.add(LyricLine(
            time: Duration(minutes: min, seconds: sec, milliseconds: ms),
            text: text,
          ));
        }
      }
    }
    return lines;
  }

  void _playNextTrack() {
    final list = _selectedTab == 2 ? _favorites : _searchResults;
    if (list.isEmpty || _currentTrack == null) return;
    final idx = list.indexWhere((t) => t.title == _currentTrack!.title);
    if (idx != -1 && idx + 1 < list.length) {
      _playTrack(list[idx + 1]);
    }
  }

  void _playPrevTrack() {
    final list = _selectedTab == 2 ? _favorites : _searchResults;
    if (list.isEmpty || _currentTrack == null) return;
    final idx = list.indexWhere((t) => t.title == _currentTrack!.title);
    if (idx > 0) {
      _playTrack(list[idx - 1]);
    } else {
      _player.seek(Duration.zero);
    }
  }

  void _toggleFavorite(TrackItem track) {
    setState(() {
      final exists = _favorites.any((t) => t.title == track.title && t.artist == track.artist);
      if (exists) {
        _favorites.removeWhere((t) => t.title == track.title && t.artist == track.artist);
      } else {
        _favorites.add(track);
      }
    });
    _saveData();
  }

  bool _isFavorite(TrackItem track) {
    return _favorites.any((t) => t.title == track.title && t.artist == track.artist);
  }

  void _showImportDialog() {
    final linkController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161421),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text("Importar o Buscar"),
        content: TextField(
          controller: linkController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Escribe artista o canción...",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () {
              final text = linkController.text.trim();
              Navigator.pop(context);
              if (text.isNotEmpty) {
                _searchController.text = text;
                _searchMusic(text);
              }
            },
            child: const Text("Buscar"),
          ),
        ],
      ),
    );
  }

  void _openFullPlayer() {
    if (_currentTrack == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0B14),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        bool showLyricsView = false;
        final ScrollController lyricsScrollController = ScrollController();
        int lastScrolledIndex = -1;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final track = _currentTrack!;
            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF23153C),
                    Color(0xFF0E0C16),
                    Color(0xFF09080F),
                  ],
                ),
                border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
              ),
              child: StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, stateSnap) {
                  final isPlaying = _player.playing &&
                      stateSnap.data?.processingState != ProcessingState.completed;

                  return Column(
                    children: [
                      Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => setModalState(() => showLyricsView = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                decoration: BoxDecoration(
                                  color: !showLyricsView
                                      ? const Color(0xFF7C3AED)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: const Text(
                                  "Portada",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setModalState(() => showLyricsView = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                decoration: BoxDecoration(
                                  color: showLyricsView
                                      ? const Color(0xFF7C3AED)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.lyrics_rounded, size: 16, color: Colors.white),
                                    SizedBox(width: 6),
                                    Text(
                                      "Letra en Vivo",
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: !showLyricsView
                            ? Center(
                                child: AnimatedScale(
                                  scale: isPlaying ? 1.0 : 0.88,
                                  duration: const Duration(milliseconds: 350),
                                  curve: Curves.easeOutCubic,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(26),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF7C3AED)
                                              .withOpacity(isPlaying ? 0.45 : 0.15),
                                          blurRadius: 36,
                                          offset: const Offset(0, 14),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(26),
                                      child: Image.network(
                                        track.thumb,
                                        width: 280,
                                        height: 280,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : StreamBuilder<Duration>(
                                stream: _player.positionStream,
                                builder: (context, posSnap) {
                                  final currentPos = posSnap.data ?? Duration.zero;

                                  if (!_hasSyncedLyrics) {
                                    return Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: SingleChildScrollView(
                                        child: Text(
                                          _plainLyrics,
                                          style: const TextStyle(
                                            fontSize: 16.5,
                                            height: 1.65,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  int activeIndex = 0;
                                  for (int i = 0; i < _syncedLyrics.length; i++) {
                                    if (currentPos >= _syncedLyrics[i].time) {
                                      activeIndex = i;
                                    } else {
                                      break;
                                    }
                                  }

                                  if (activeIndex != lastScrolledIndex &&
                                      lyricsScrollController.hasClients) {
                                    lastScrolledIndex = activeIndex;
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (lyricsScrollController.hasClients) {
                                        final target = (activeIndex * 62.0) - 100.0;
                                        lyricsScrollController.animateTo(
                                          target.clamp(
                                            0.0,
                                            lyricsScrollController.position.maxScrollExtent,
                                          ),
                                          duration: const Duration(milliseconds: 350),
                                          curve: Curves.easeOutCubic,
                                        );
                                      }
                                    });
                                  }

                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: ListView.builder(
                                      controller: lyricsScrollController,
                                      itemCount: _syncedLyrics.length,
                                      itemBuilder: (context, index) {
                                        final line = _syncedLyrics[index];
                                        final isCurrent = index == activeIndex;
                                        return GestureDetector(
                                          onTap: () => _player.seek(line.time),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            child: Text(
                                              line.text,
                                              style: TextStyle(
                                                fontSize: isCurrent ? 21 : 16,
                                                fontWeight: isCurrent
                                                    ? FontWeight.w800
                                                    : FontWeight.w500,
                                                color: isCurrent
                                                    ? Colors.white
                                                    : Colors.white.withOpacity(0.35),
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 21, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 15, color: Color(0xFF9CA3AF)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isFavorite(track)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: _isFavorite(track)
                                  ? const Color(0xFFA855F7)
                                  : Colors.white70,
                              size: 30,
                            ),
                            onPressed: () {
                              _toggleFavorite(track);
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      StreamBuilder<Duration>(
                        stream: _player.positionStream,
                        builder: (context, snapshot) {
                          final pos = snapshot.data ?? Duration.zero;
                          final total = _player.duration ?? Duration.zero;
                          final maxSec = total.inSeconds.toDouble() > 0
                              ? total.inSeconds.toDouble()
                              : 1.0;
                          return Column(
                            children: [
                              Slider(
                                activeColor: const Color(0xFFA855F7),
                                inactiveColor: Colors.white24,
                                value: pos.inSeconds.toDouble().clamp(0, maxSec),
                                max: maxSec,
                                onChanged: (val) {
                                  _player.seek(Duration(seconds: val.toInt()));
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "${pos.inMinutes}:${(pos.inSeconds % 60).toString().padLeft(2, '0')}",
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white60),
                                    ),
                                    Text(
                                      "${total.inMinutes}:${(total.inSeconds % 60).toString().padLeft(2, '0')}",
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white60),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.lyrics_outlined, size: 26),
                            onPressed: () =>
                                setModalState(() => showLyricsView = !showLyricsView),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded, size: 38),
                            onPressed: () {
                              _playPrevTrack();
                              setModalState(() {});
                            },
                          ),
                          GestureDetector(
                            onTap: () {
                              if (isPlaying) {
                                _player.pause();
                              } else {
                                _player.play();
                              }
                              setModalState(() {});
                            },
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [Color(0xFF7C3AED), Color(0xFF3B82F6)],
                                ),
                              ),
                              child: Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: 38,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, size: 38),
                            onPressed: () {
                              _playNextTrack();
                              setModalState(() {});
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.replay_rounded, size: 26),
                            onPressed: () => _player.seek(Duration.zero),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            "Aura",
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(Icons.graphic_eq_rounded,
                              color: Colors.purpleAccent.shade200, size: 26),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => launchUrl(Uri.parse("https://ko-fi.com")),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF171522),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                                color: const Color(0xFFA855F7).withOpacity(0.8),
                                width: 1.2),
                          ),
                          child: const Row(
                            children: [
                              Text("☕ ", style: TextStyle(fontSize: 14)),
                              Text(
                                "Apóyanos",
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: _searchMusic,
                    decoration: InputDecoration(
                      hintText: "¿Qué quieres escuchar hoy?",
                      hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9CA3AF)),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward_rounded,
                            color: Color(0xFFA855F7)),
                        onPressed: () => _searchMusic(_searchController.text),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF171522),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(100),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(100),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _buildBody(),
                ),
              ],
            ),
            if (_currentTrack != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: GestureDetector(
                    onTap: _openFullPlayer,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          height: 68,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF171522).withOpacity(0.88),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFA855F7).withOpacity(0.55),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  _currentTrack!.thumb,
                                  width: 46,
                                  height: 46,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _statusMessage,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.purpleAccent.shade100),
                                    ),
                                    Text(
                                      _currentTrack!.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                              if (_isBuffering)
                                const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.4),
                                  ),
                                )
                              else
                                IconButton(
                                  icon: Icon(
                                    _player.playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 32,
                                  ),
                                  onPressed: () {
                                    if (_player.playing) {
                                      _player.pause();
                                    } else {
                                      _player.play();
                                    }
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.skip_next_rounded, size: 28),
                                onPressed: _playNextTrack,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        onTap: (index) => setState(() => _selectedTab = index),
        backgroundColor: const Color(0xFF09080F),
        selectedItemColor: const Color(0xFFA855F7),
        unselectedItemColor: const Color(0xFF9CA3AF),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Inicio"),
          BottomNavigationBarItem(icon: Icon(Icons.search_rounded), label: "Buscar"),
          BottomNavigationBarItem(
              icon: Icon(Icons.library_music_rounded), label: "Mi Biblioteca"),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_selectedTab == 2) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
        children: [
          const Text("Tus Favoritos ❤️",
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_favorites.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 50),
              child: Center(
                child: Text(
                  "Tu biblioteca está vacía.\nBusca tus canciones favoritas y toca el corazón ❤️.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9CA3AF), height: 1.5),
                ),
              ),
            )
          else
            ..._favorites.map((t) => _trackTile(t)),
        ],
      );
    }

    if (_selectedTab == 1) {
      if (_isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_searchResults.isEmpty) {
        return const Center(
          child: Text(
            "Escribe el nombre de cualquier canción o artista\nen la barra superior para comenzar.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9CA3AF), height: 1.5),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) => _trackTile(_searchResults[index]),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
      children: [
        GestureDetector(
          onTap: _showImportDialog,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFF4F46E5), Color(0xFF3B82F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withOpacity(0.32),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Importa tu música\nsin contraseñas",
                  style: TextStyle(
                      fontSize: 23, fontWeight: FontWeight.bold, height: 1.2),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.link_rounded, color: Colors.white70),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Pega un enlace de Spotify o YouTube aquí",
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Tus Playlists",
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            GestureDetector(
              onTap: _showImportDialog,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                    color: Color(0xFF171522), shape: BoxShape.circle),
                child: const Icon(Icons.add, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 145,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              GestureDetector(
                onTap: () => setState(() => _selectedTab = 2),
                child: _playlistCard(
                    "Favoritos (${_favorites.length})", Icons.favorite_rounded, const Color(0xFF9333EA)),
              ),
              GestureDetector(
                onTap: () => _searchMusic("Chill Lofi Study Beats"),
                child: _playlistCard(
                    "Para Concentrarse", Icons.self_improvement_rounded, const Color(0xFF0D9488)),
              ),
              GestureDetector(
                onTap: () => _searchMusic("Night Drive Synthwave"),
                child: _playlistCard(
                    "Viaje Nocturno", Icons.nightlight_round, const Color(0xFF3B82F6)),
              ),
            ],
          ),
        ),
        if (_recentTracks.isNotEmpty) ...[
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Escuchado Recientemente",
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () {
                  setState(() => _recentTracks.clear());
                  _saveData();
                },
                child: const Text("Limpiar", style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._recentTracks.map((t) => _trackTile(t)),
        ],
      ],
    );
  }

  Widget _trackTile(TrackItem track) {
    final isFav = _isFavorite(track);
    final isPlayingThis = _currentTrack?.title == track.title &&
        _currentTrack?.artist == track.artist;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF151320),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPlayingThis
              ? const Color(0xFFA855F7)
              : Colors.white.withOpacity(0.07),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(track.thumb, width: 52, height: 52, fit: BoxFit.cover),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isPlayingThis ? const Color(0xFFD8B4FE) : Colors.white,
          ),
        ),
        subtitle: Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? const Color(0xFFA855F7) : Colors.white54,
              ),
              onPressed: () => _toggleFavorite(track),
            ),
            const Icon(Icons.play_circle_fill_rounded,
                color: Color(0xFFA855F7), size: 32),
          ],
        ),
        onTap: () => _playTrack(track),
      ),
    );
  }

  Widget _playlistCard(String title, IconData icon, Color color) {
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 105,
            width: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: [color, color.withOpacity(0.45)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Icon(icon, size: 40, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
