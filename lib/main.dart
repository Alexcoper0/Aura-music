import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF07060B),
    ),
  );
  runApp(const AuraLiquidApp());
}

// ============================================================================
// MODELOS DE DATOS Y LETRAS SINCRONIZADAS (KARAOKE LRC)
// ============================================================================
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
  final String? directUrl;

  TrackItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumb,
    this.directUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'thumb': thumb,
        'directUrl': directUrl,
      };

  factory TrackItem.fromJson(Map<String, dynamic> json) => TrackItem(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        artist: json['artist'] ?? '',
        thumb: json['thumb'] ?? '',
        directUrl: json['directUrl'],
      );
}

// ============================================================================
// COMPONENTE VISUAL: LIQUID GLASS (CRISTAL LÍQUIDO ESTILO iOS)
// ============================================================================
class LiquidGlassBox extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final Color tint;
  final bool highlightBorder;

  const LiquidGlassBox({
    super.key,
    required this.child,
    this.borderRadius = 26,
    this.padding,
    this.blur = 28,
    this.tint = const Color(0xFF1A162B),
    this.highlightBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.16),
                tint.withOpacity(0.52),
                Colors.black.withOpacity(0.45),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
            border: Border.all(
              color: highlightBorder
                  ? Colors.white.withOpacity(0.24)
                  : Colors.white.withOpacity(0.10),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ============================================================================
// APLICACIÓN PRINCIPAL AURA
// ============================================================================
class AuraLiquidApp extends StatelessWidget {
  const AuraLiquidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF07060B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFA855F7),
          secondary: Color(0xFF38BDF8),
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

class _AuraMainScreenState extends State<AuraMainScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  final YoutubeExplode _yt = YoutubeExplode();
  final TextEditingController _searchController = TextEditingController();

  late AnimationController _ambientController;

  int _selectedTab = 0; // 0: Inicio, 1: Explorar, 2: Biblioteca
  List<TrackItem> _searchResults = [];
  List<TrackItem> _favorites = [];
  List<TrackItem> _recentTracks = [];
  bool _isLoading = false;
  bool _isBuffering = false;
  String _statusMessage = "Audio HD • Sin anuncios";

  TrackItem _currentTrack = TrackItem(
    id: 'init',
    title: "Aura Liquid Glass",
    artist: "Busca una canción para comenzar",
    thumb: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=600",
  );

  List<LyricLine> _syncedLyrics = [];
  String _plainLyrics = "Reproduce una pista para sincronizar la letra en vivo.";
  bool _hasSyncedLyrics = false;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    _loadSavedData();
    _loadInitialTrending();

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _playNextTrack();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _player.dispose();
    _yt.close();
    _searchController.dispose();
    super.dispose();
  }

  // Persistencia local de Favoritos e Historial
  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final favList = prefs.getStringList('aura_favs_v2') ?? [];
    final recList = prefs.getStringList('aura_recents_v2') ?? [];
    setState(() {
      _favorites = favList.map((e) => TrackItem.fromJson(json.decode(e))).toList();
      _recentTracks = recList.map((e) => TrackItem.fromJson(json.decode(e))).toList();
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'aura_favs_v2', _favorites.map((e) => json.encode(e.toJson())).toList());
    await prefs.setStringList(
        'aura_recents_v2', _recentTracks.map((e) => json.encode(e.toJson())).toList());
  }

  Future<void> _loadInitialTrending() async {
    await _searchMusic("Feid Ferxxo", switchTab: false);
  }

  // ==========================================================================
  // BUSCADOR MULTICAPA (Combina Catálogo HD + YouTube IDs)
  // ==========================================================================
  Future<void> _searchMusic(String query, {bool switchTab = true}) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      if (switchTab) _selectedTab = 1;
    });

    List<TrackItem> results = [];

    // 1. Intentamos catálogo directo con URL de 320kbps pre-cargada (Saavn API)
    try {
      final saavnUrl = Uri.parse(
          "https://saavn.sumit.co/api/search/songs?query=${Uri.encodeComponent(query)}&limit=15");
      final res = await http.get(saavnUrl).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List items = data['data']?['results'] ?? [];
        for (var item in items) {
          final List imgs = item['image'] ?? [];
          final List dls = item['downloadUrl'] ?? [];
          final String thumbUrl = imgs.isNotEmpty
              ? (imgs.last['url'] ?? imgs.last['link'] ?? '')
              : '';
          final String audioUrl = dls.isNotEmpty
              ? (dls.last['url'] ?? dls.last['link'] ?? '')
              : '';
          final String artistName = (item['artists']?['primary'] as List?)
                  ?.map((a) => a['name'])
                  .join(', ') ??
              item['primaryArtists'] ??
              'Artista';

          if (audioUrl.isNotEmpty) {
            results.add(TrackItem(
              id: item['id']?.toString() ?? '',
              title: _cleanHtml(item['name'] ?? 'Canción'),
              artist: _cleanHtml(artistName),
              thumb: thumbUrl.isNotEmpty
                  ? thumbUrl
                  : 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=500',
              directUrl: audioUrl,
            ));
          }
        }
      }
    } catch (_) {}

    // 2. Complementamos con búsqueda directa de YouTube para que jamás falte ninguna canción
    try {
      final ytList = await _yt.search
          .search("$query official audio")
          .timeout(const Duration(seconds: 5));
      for (var v in ytList) {
        results.add(TrackItem(
          id: v.id.value,
          title: v.title,
          artist: v.author.replaceAll(' - Topic', '').replaceAll('VEVO', ''),
          thumb: v.thumbnails.highResUrl,
        ));
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  String _cleanHtml(String input) {
    return input
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'");
  }

  // ==========================================================================
  // MOTOR DE AUDIO INFALIBLE (Archivo Local Temporal + 320kbps Directo)
  // ==========================================================================
  Future<void> _playTrack(TrackItem track) async {
    setState(() {
      _currentTrack = track;
      _isBuffering = true;
      _statusMessage = "Sincronizando audio HD...";
    });

    // Guardar en historial reciente
    _recentTracks.removeWhere((t) => t.title == track.title);
    _recentTracks.insert(0, track);
    if (_recentTracks.length > 15) _recentTracks.removeLast();
    _saveData();

    // Disparar búsqueda de letras sincronizadas tipo Apple Music en paralelo
    _fetchSyncedLyrics(track.title, track.artist);

    try {
      await _player.stop();
    } catch (_) {}

    final cleanTitle = track.title
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]|Official|Audio|Video|Lyrics|Visualizer', caseSensitive: false), '')
        .trim();
    final cleanArtist = track.artist.split(',').first.split('&').first.trim();

    // ------------------------------------------------------------------------
    // NIVEL 1: Si la canción ya trae enlace directo M4A/320kbps, suena en 0.5s
    // ------------------------------------------------------------------------
    if (track.directUrl != null && track.directUrl!.isNotEmpty) {
      try {
        await _player.setUrl(track.directUrl!).timeout(const Duration(seconds: 5));
        _player.play();
        setState(() {
          _isBuffering = false;
          _statusMessage = "320kbps Liquid Audio • En vivo";
        });
        return;
      } catch (_) {}
    }

    // ------------------------------------------------------------------------
    // NIVEL 2: Buscar versión 320kbps en servidores espejo de música
    // ------------------------------------------------------------------------
    final mirrorEndpoints = [
      "https://saavn.sumit.co/api/search/songs?query=${Uri.encodeComponent("$cleanTitle $cleanArtist")}",
      "https://jiosaavn-api-privatecvc2.vercel.app/search/songs?query=${Uri.encodeComponent("$cleanTitle $cleanArtist")}",
    ];

    for (final url in mirrorEndpoints) {
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
        if (r.statusCode == 200) {
          final d = json.decode(r.body);
          final List resList = d['data']?['results'] ?? [];
          if (resList.isNotEmpty) {
            final List dls = resList[0]['downloadUrl'] ?? [];
            if (dls.isNotEmpty) {
              final String bestLink = dls.last['url'] ?? dls.last['link'] ?? '';
              if (bestLink.isNotEmpty) {
                await _player.setUrl(bestLink).timeout(const Duration(seconds: 5));
                _player.play();
                setState(() {
                  _isBuffering = false;
                  _statusMessage = "320kbps Liquid Audio • En vivo";
                });
                return;
              }
            }
          }
        }
      } catch (_) {}
    }

    // ------------------------------------------------------------------------
    // NIVEL 3: DESCARGA A ARCHIVO FÍSICO TEMPORAL EN EL TELÉFONO
    // Esto elimina al 100% el error 403 de ExoPlayer en Android porque
    // reproduce el archivo desde la memoria interna del celular.
    // ------------------------------------------------------------------------
    setState(() => _statusMessage = "Desbloqueando pista desde la nube...");

    String videoId = track.id;
    if (videoId.isEmpty || videoId.length < 8) {
      try {
        final s = await _yt.search
            .search("$cleanTitle $cleanArtist audio")
            .timeout(const Duration(seconds: 4));
        if (s.isNotEmpty) videoId = s.first.id.value;
      } catch (_) {}
    }

    if (videoId.isNotEmpty) {
      final clientCombinations = [
        [YoutubeApiClient.ios],
        [YoutubeApiClient.androidVr],
        [YoutubeApiClient.safari],
        [YoutubeApiClient.tv],
      ];

      for (final clients in clientCombinations) {
        try {
          final manifest = await _yt.videos.streamsClient
              .getManifest(videoId, ytClients: clients)
              .timeout(const Duration(seconds: 5));

          StreamInfo? chosenStream;
          final mp4Audio = manifest.audioOnly
              .where((s) => s.container.name.toLowerCase() == 'mp4')
              .toList();
          if (mp4Audio.isNotEmpty) {
            mp4Audio.sort((a, b) => b.bitrate.compareTo(a.bitrate));
            chosenStream = mp4Audio.first;
          } else if (manifest.muxed.isNotEmpty) {
            chosenStream = manifest.muxed.withHighestBitrate();
          } else if (manifest.audioOnly.isNotEmpty) {
            chosenStream = manifest.audioOnly.withHighestBitrate();
          }

          if (chosenStream != null) {
            // Primero intentamos descarga rápida a caché físico del teléfono
            try {
              final tempDir = Directory.systemTemp;
              final tempFile = File('${tempDir.path}/aura_track_$videoId.mp4');

              if (!await tempFile.exists() || await tempFile.length() < 50000) {
                final byteStream = _yt.videos.streamsClient.get(chosenStream);
                final sink = tempFile.openWrite();
                await byteStream.pipe(sink).timeout(const Duration(seconds: 12));
                await sink.flush();
                await sink.close();
              }

              if (await tempFile.exists() && await tempFile.length() > 20000) {
                await _player.setFilePath(tempFile.path);
                _player.play();
                setState(() {
                  _isBuffering = false;
                  _statusMessage = "Audio Caché HD • Sin anuncios";
                });
                return;
              }
            } catch (_) {
              // Si la descarga por pipe tarda, intentamos URL directa con User-Agent nativo
              await _player.setAudioSource(
                AudioSource.uri(
                  chosenStream.url,
                  headers: const {'User-Agent': 'com.google.android.youtube/19.09.37 (Linux; U; Android 13)'},
                ),
              ).timeout(const Duration(seconds: 5));
              _player.play();
              setState(() {
                _isBuffering = false;
                _statusMessage = "Streaming Directo • En vivo";
              });
              return;
            }
          }
        } catch (_) {}
      }
    }

    setState(() {
      _isBuffering = false;
      _statusMessage = "Toca otra versión de la lista";
    });
  }

  // ==========================================================================
  // MOTOR DE LETRAS SINCRONIZADAS EN TIEMPO REAL (PARSEADOR LRC)
  // ==========================================================================
  Future<void> _fetchSyncedLyrics(String rawTitle, String rawArtist) async {
    setState(() {
      _syncedLyrics = [];
      _hasSyncedLyrics = false;
      _plainLyrics = "Sincronizando letra con la voz del artista...";
    });

    final cleanTitle = rawTitle
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'Official|Audio|Video|Visualizer|Lyrics|feat\..*|ft\..*', caseSensitive: false), '')
        .split('-')
        .last
        .trim();

    final cleanArtist = rawArtist
        .replaceAll(' - Topic', '')
        .replaceAll('VEVO', '')
        .split('&')
        .first
        .split(',')
        .first
        .trim();

    try {
      final url = Uri.parse(
          'https://lrclib.net/api/search?q=${Uri.encodeComponent("$cleanTitle $cleanArtist")}');
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final List list = json.decode(utf8.decode(res.bodyBytes));
        if (list.isNotEmpty) {
          // Buscamos primero alguna que tenga syncedLyrics (con tiempos exactos)
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
      _plainLyrics = "Letra sincronizada no disponible para '$cleanTitle'.";
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
        final msStr = match.group(3)!;
        final ms = int.parse(msStr.padRight(3, '0'));
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
    if (list.isEmpty) return;
    final idx = list.indexWhere((t) => t.title == _currentTrack.title);
    if (idx != -1 && idx + 1 < list.length) {
      _playTrack(list[idx + 1]);
    }
  }

  void _playPrevTrack() {
    final list = _selectedTab == 2 ? _favorites : _searchResults;
    if (list.isEmpty) return;
    final idx = list.indexWhere((t) => t.title == _currentTrack.title);
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

  // ==========================================================================
  // REPRODUCTOR APPLE MUSIC + LIQUID GLASS A PANTALLA COMPLETA
  // ==========================================================================
  void _openLiquidPlayer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        bool showLyricsView = false;
        final ScrollController lyricsScrollController = ScrollController();
        int lastScrolledIndex = -1;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.94,
              decoration: const BoxDecoration(
                color: Color(0xFF07060B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(38)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(38)),
                child: Stack(
                  children: [
                    // 1. FONDO DINÁMICO ANIMADO CON LA PORTADA DEL ÁLBUM (Apple Music Blur)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _ambientController,
                        builder: (context, _) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Transform.scale(
                                scale: 1.45,
                                child: Transform.rotate(
                                  angle: _ambientController.value * 2 * math.pi * 0.15,
                                  child: Image.network(
                                    _currentTrack.thumb,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E1035)),
                                  ),
                                ),
                              ),
                              BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 65, sigmaY: 65),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withOpacity(0.35),
                                        const Color(0xFF07060B).withOpacity(0.78),
                                        const Color(0xFF07060B).withOpacity(0.95),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    // 2. CONTENIDO DEL REPRODUCTOR LIQUID GLASS
                    StreamBuilder<PlayerState>(
                      stream: _player.playerStateStream,
                      builder: (context, stateSnap) {
                        final isPlaying = _player.playing &&
                            stateSnap.data?.processingState != ProcessingState.completed;

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                          child: Column(
                            children: [
                              // Píldora superior de arrastre
                              Container(
                                width: 46,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Selector Superior: Portada Viva vs Karaoke Sincronizado
                              LiquidGlassBox(
                                borderRadius: 100,
                                padding: const EdgeInsets.all(5),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () => setModalState(() => showLyricsView = false),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 250),
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: !showLyricsView
                                              ? Colors.white.withOpacity(0.22)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(100),
                                        ),
                                        child: const Text(
                                          "Portada Viva",
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => setModalState(() => showLyricsView = true),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 250),
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: showLyricsView
                                              ? Colors.white.withOpacity(0.22)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(100),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(Icons.lyrics_rounded, size: 16, color: Color(0xFFD8B4FE)),
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
                              const SizedBox(height: 22),

                              // ÁREA CENTRAL: PORTADA ANIMADA APPLE MUSIC O KARAOKE EN TIEMPO REAL
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 400),
                                  child: !showLyricsView
                                      ? Center(
                                          key: const ValueKey("artwork_view"),
                                          child: AnimatedScale(
                                            scale: isPlaying ? 1.02 : 0.86,
                                            duration: const Duration(milliseconds: 550),
                                            curve: Curves.easeOutBack,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(30),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(0xFFA855F7)
                                                        .withOpacity(isPlaying ? 0.50 : 0.15),
                                                    blurRadius: isPlaying ? 50 : 20,
                                                    spreadRadius: isPlaying ? 6 : 0,
                                                    offset: const Offset(0, 18),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(30),
                                                child: Image.network(
                                                  _currentTrack.thumb,
                                                  width: 300,
                                                  height: 300,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                      : StreamBuilder<Duration>(
                                          key: const ValueKey("lyrics_view"),
                                          stream: _player.positionStream,
                                          builder: (context, posSnap) {
                                            final currentPos = posSnap.data ?? Duration.zero;

                                            if (!_hasSyncedLyrics) {
                                              return LiquidGlassBox(
                                                padding: const EdgeInsets.all(22),
                                                child: SingleChildScrollView(
                                                  child: Text(
                                                    _plainLyrics,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      height: 1.7,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }

                                            // Calcular qué línea está cantando el artista en este milisegundo
                                            int activeIndex = 0;
                                            for (int i = 0; i < _syncedLyrics.length; i++) {
                                              if (currentPos >= _syncedLyrics[i].time) {
                                                activeIndex = i;
                                              } else {
                                                break;
                                              }
                                            }

                                            // Auto-scroll suave tipo Apple Music
                                            if (activeIndex != lastScrolledIndex &&
                                                lyricsScrollController.hasClients) {
                                              lastScrolledIndex = activeIndex;
                                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                                if (lyricsScrollController.hasClients) {
                                                  final targetOffset = (activeIndex * 66.0) - 110.0;
                                                  lyricsScrollController.animateTo(
                                                    targetOffset.clamp(
                                                      0.0,
                                                      lyricsScrollController.position.maxScrollExtent,
                                                    ),
                                                    duration: const Duration(milliseconds: 450),
                                                    curve: Curves.easeOutCubic,
                                                  );
                                                }
                                              });
                                            }

                                            return LiquidGlassBox(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 18, vertical: 14),
                                              child: ListView.builder(
                                                controller: lyricsScrollController,
                                                itemCount: _syncedLyrics.length,
                                                itemBuilder: (context, index) {
                                                  final line = _syncedLyrics[index];
                                                  final isCurrent = index == activeIndex;
                                                  return GestureDetector(
                                                    onTap: () => _player.seek(line.time),
                                                    child: AnimatedContainer(
                                                      duration: const Duration(milliseconds: 300),
                                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                                      child: AnimatedDefaultTextStyle(
                                                        duration: const Duration(milliseconds: 300),
                                                        style: TextStyle(
                                                          fontSize: isCurrent ? 23 : 16.5,
                                                          fontWeight: isCurrent
                                                              ? FontWeight.w900
                                                              : FontWeight.w500,
                                                          color: isCurrent
                                                              ? Colors.white
                                                              : Colors.white.withOpacity(0.32),
                                                          height: 1.35,
                                                          shadows: isCurrent
                                                              ? [
                                                                  const Shadow(
                                                                    color: Color(0xFFA855F7),
                                                                    blurRadius: 18,
                                                                  )
                                                                ]
                                                              : [],
                                                        ),
                                                        child: Text(line.text),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ),
                              const SizedBox(height: 20),

                              // TÍTULO, ARTISTA Y FAVORITO
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _currentTrack.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.4,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _currentTrack.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15.5,
                                            color: Colors.white.withOpacity(0.68),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _isFavorite(_currentTrack)
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color: _isFavorite(_currentTrack)
                                          ? const Color(0xFFD8B4FE)
                                          : Colors.white70,
                                      size: 30,
                                    ),
                                    onPressed: () {
                                      _toggleFavorite(_currentTrack);
                                      setModalState(() {});
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // BARRA DE PROGRESO CRISTAL
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
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 5,
                                          thumbShape: const RoundSliderThumbShape(
                                              enabledThumbRadius: 7),
                                          activeTrackColor: Colors.white,
                                          inactiveTrackColor: Colors.white24,
                                          thumbColor: Colors.white,
                                        ),
                                        child: Slider(
                                          value: pos.inSeconds.toDouble().clamp(0, maxSec),
                                          max: maxSec,
                                          onChanged: (val) {
                                            _player.seek(Duration(seconds: val.toInt()));
                                          },
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              "${pos.inMinutes}:${(pos.inSeconds % 60).toString().padLeft(2, '0')}",
                                              style: const TextStyle(
                                                  fontSize: 12, color: Colors.white60),
                                            ),
                                            Text(
                                              _statusMessage,
                                              style: const TextStyle(
                                                  fontSize: 11, color: Color(0xFFD8B4FE)),
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
                              const SizedBox(height: 16),

                              // CONTROLES EN CÁPSULA LIQUID GLASS
                              LiquidGlassBox(
                                borderRadius: 34,
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.Lyrics_outlined, size: 26),
                                      onPressed: () =>
                                          setModalState(() => showLyricsView = !showLyricsView),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.skip_previous_rounded, size: 40),
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
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFFA855F7), Color(0xFF3B82F6)],
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFA855F7).withOpacity(0.5),
                                              blurRadius: 20,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          size: 40,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.skip_next_rounded, size: 40),
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
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================================
  // PANTALLA PRINCIPAL CON FONDO DE CRISTAL LÍQUIDO VIVO
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. FONDO AMBIENTAL DINÁMICO QUE CAMBIA CON LA CANCIÓN ACTUAL
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ambientController,
              builder: (context, _) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: 0.42,
                      child: Transform.scale(
                        scale: 1.3,
                        child: Image.network(
                          _currentTrack.thumb,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: const Color(0xFF07060B)),
                        ),
                      ),
                    ),
                    BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                      child: Container(
                        color: const Color(0xFF07060B).withOpacity(0.76),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // 2. CONTENIDO PRINCIPAL CON TRANSICIONES SUAVES
          SafeArea(
            child: Column(
              children: [
                // HEADER LIQUID GLASS
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            "Aura",
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.blur_on_rounded,
                              color: Colors.purpleAccent.shade100, size: 28),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => launchUrl(Uri.parse("https://ko-fi.com")),
                        child: const LiquidGlassBox(
                          borderRadius: 100,
                          padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                          child: Row(
                            children: [
                              Text("☕ ", style: TextStyle(fontSize: 14)),
                              Text(
                                "Apóyanos",
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // BARRA DE BÚSQUEDA DE CRISTAL LÍQUIDO
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: LiquidGlassBox(
                    borderRadius: 100,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: TextField(
                      controller: _searchController,
                      onSubmitted: (v) => _searchMusic(v),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Artistas, canciones o pega un link...",
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded, color: Color(0xFFD8B4FE)),
                          onPressed: () => _searchMusic(_searchController.text),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),

                // CUERPO CAMBIANTE CON ANIMACIÓN FLUIDA ENTRE PESTAÑAS
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: _buildCurrentTabContent(),
                  ),
                ),
              ],
            ),
          ),

          // 3. MINI-REPRODUCTOR FLOTANTE LIQUID GLASS + BARRA DE NAVEGACIÓN DE CRISTAL
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mini-Reproductor
                  GestureDetector(
                    onTap: _openLiquidPlayer,
                    child: LiquidGlassBox(
                      borderRadius: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Hero(
                            tag: 'player_thumb',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.network(
                                _currentTrack.thumb,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isBuffering
                                      ? _statusMessage
                                      : "Toca para abrir Liquid Player & Karaoke 🎤",
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFFD8B4FE),
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _currentTrack.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 14.5),
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
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white),
                              ),
                            )
                          else
                            IconButton(
                              icon: Icon(
                                _player.playing
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                size: 38,
                                color: Colors.white,
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
                  const SizedBox(height: 10),

                  // Barra de Navegación Flotante iOS 19 Liquid Glass
                  LiquidGlassBox(
                    borderRadius: 100,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _glassNavItem(0, Icons.home_rounded, "Inicio"),
                        _glassNavItem(1, Icons.Graphic_eq_rounded, "Explorar"),
                        _glassNavItem(2, Icons.favorite_rounded, "Biblioteca"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.55)),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    if (_selectedTab == 2) {
      // PESTAÑA BIBLIOTECA Y FAVORITOS
      return ListView(
        key: const ValueKey("tab_library"),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 175),
        children: [
          const Text("Tus Favoritos ❤️",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (_favorites.isEmpty)
            const LiquidGlassBox(
              padding: EdgeInsets.all(28),
              child: Text(
                "Aún no has guardado canciones.\nToca el corazón ❤️ en cualquier pista para guardarla en tu biblioteca.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
            )
          else
            ..._favorites.map((t) => _glassTrackTile(t)),
        ],
      );
    }

    if (_selectedTab == 1) {
      // PESTAÑA EXPLORAR / RESULTADOS
      return ListView(
        key: const ValueKey("tab_explore"),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 175),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Catálogo en Alta Calidad",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              if (_isLoading)
                const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 12),
          ..._searchResults.map((t) => _glassTrackTile(t)),
        ],
      );
    }

    // PESTAÑA 0: INICIO
    return ListView(
      key: const ValueKey("tab_home"),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 175),
      children: [
        // Tarjeta Principal Liquid Glass
        LiquidGlassBox(
          borderRadius: 28,
          padding: const EdgeInsets.all(22),
          tint: const Color(0xFF5B21B6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Color(0xFFD8B4FE), size: 20),
                  SizedBox(width: 8),
                  Text("AURA LIQUID ENGINE",
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Color(0xFFD8B4FE))),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                "Música sin límites,\nletras vivas y cero anuncios.",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.2),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _moodChip("🔥 Feid / Reggaetón", "Feid Ferxxo"),
                    _moodChip("🌙 Night Drive Synth", "Synthwave chill"),
                    _moodChip("🎧 Lo-Fi Focus", "Lofi beats study"),
                    _moodChip("⚡ Éxitos Globales", "Top hits 2026"),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        if (_recentTracks.isNotEmpty) ...[
          const Text("Escuchado Recientemente",
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SizedBox(
            height: 155,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _recentTracks.length,
              itemBuilder: (context, i) {
                final tr = _recentTracks[i];
                return GestureDetector(
                  onTap: () => _playTrack(tr),
                  child: Container(
                    width: 118,
                    margin: const EdgeInsets.only(right: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.network(tr.thumb,
                              width: 118, height: 110, fit: BoxFit.cover),
                        ),
                        const SizedBox(height: 6),
                        Text(tr.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.5)),
                        Text(tr.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white60, fontSize: 11)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
        ],

        const Text("Recomendado para ti",
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ..._searchResults.take(10).map((t) => _glassTrackTile(t)),
      ],
    );
  }

  Widget _moodChip(String label, String query) {
    return GestureDetector(
      onTap: () => _searchMusic(query),
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _glassTrackTile(TrackItem track) {
    final isFav = _isFavorite(track);
    final isCurrent = _currentTrack.title == track.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _playTrack(track),
        child: LiquidGlassBox(
          borderRadius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          highlightBorder: isCurrent,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.network(track.thumb, width: 54, height: 54, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isCurrent ? const Color(0xFFD8B4FE) : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withOpacity(0.62), fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFav ? const Color(0xFFD8B4FE) : Colors.white60,
                ),
                onPressed: () => _toggleFavorite(track),
              ),
              const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}
