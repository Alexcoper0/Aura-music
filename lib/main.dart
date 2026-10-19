import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const AuraApp());
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
}

class AuraApp extends StatelessWidget {
  const AuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura Music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0A10),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C3AED),
          secondary: Color(0xFF3B82F6),
        ),
      ),
      home: const AuraHomeScreen(),
    );
  }
}

class AuraHomeScreen extends StatefulWidget {
  const AuraHomeScreen({super.key});

  @override
  State<AuraHomeScreen> createState() => _AuraHomeScreenState();
}

class _AuraHomeScreenState extends State<AuraHomeScreen> {
  final AudioPlayer _player = AudioPlayer();
  final YoutubeExplode _yt = YoutubeExplode();
  final TextEditingController _searchController = TextEditingController();

  int _selectedTab = 0; // 0: Inicio, 1: Buscar, 2: Mi Biblioteca
  List<TrackItem> _searchResults = [];
  final List<TrackItem> _favorites = [];
  bool _isLoading = false;
  bool _isBuffering = false;

  TrackItem _currentTrack = TrackItem(
    id: '',
    title: "Selecciona una canción",
    artist: "Aura Music",
    thumb: "https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=300",
  );

  String _currentLyrics = "Toca una canción para cargar su letra...";

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (mounted) setState(() {});
    });
  }

  // Buscador de canciones en YouTube
  Future<void> _searchMusic(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _selectedTab = 1; // Nos lleva a la vista de resultados
    });
    try {
      final results = await _yt.search.search("$query official audio");
      setState(() {
        _searchResults = results
            .map((v) => TrackItem(
                  id: v.id.value,
                  title: v.title,
                  artist: v.author,
                  thumb: v.thumbnails.highResUrl,
                ))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // Motor de Audio Desbloqueado (Usa clientes especiales para saltar el bloqueo de YouTube)
  Future<void> _playTrack(TrackItem track) async {
    setState(() {
      _currentTrack = track;
      _isBuffering = true;
      _currentLyrics = "Buscando letra sincronizada...";
    });

    _fetchLyrics(track.title, track.artist);

    try {
      // Intento 1: Cliente Android VR / Safari (Evita el error de conexion de YouTube)
      final manifest = await _yt.videos.streamsClient.getManifest(
        track.id,
        ytClients: [
          YoutubeApiClient.androidVr,
          YoutubeApiClient.safari,
          YoutubeApiClient.ios,
        ],
      );

      final audioStreams = manifest.audioOnly;
      final bestAudio = audioStreams.withHighestBitrate();

      await _player.setUrl(bestAudio.url.toString());
      _player.play();
      setState(() => _isBuffering = false);
    } catch (e) {
      // Intento 2: Respaldo estándar
      try {
        final manifest = await _yt.videos.streamsClient.getManifest(track.id);
        final bestAudio = manifest.audioOnly.first;
        await _player.setUrl(bestAudio.url.toString());
        _player.play();
        setState(() => _isBuffering = false);
      } catch (err) {
        setState(() => _isBuffering = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("No se pudo abrir esta pista, prueba la siguiente (${err.runtimeType})")),
          );
        }
      }
    }
  }

  // Buscador de Letras Gratis en LRCLIB
  Future<void> _fetchLyrics(String title, String artist) async {
    try {
      final cleanTitle = title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]|Official|Audio|Video|Visualizer', caseSensitive: false), '').trim();
      final url = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent("$cleanTitle $artist")}');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isNotEmpty && data[0]['plainLyrics'] != null) {
          setState(() => _currentLyrics = data[0]['plainLyrics']);
          return;
        }
      }
      setState(() => _currentLyrics = "Letra no disponible para esta pista.");
    } catch (_) {
      setState(() => _currentLyrics = "No se pudo cargar la letra.");
    }
  }

  // Guardar o quitar de Favoritos
  void _toggleFavorite(TrackItem track) {
    setState(() {
      final exists = _favorites.any((t) => t.id == track.id);
      if (exists) {
        _favorites.removeWhere((t) => t.id == track.id);
      } else {
        _favorites.add(track);
      }
    });
  }

  bool _isFavorite(TrackItem track) {
    return _favorites.any((t) => t.id == track.id);
  }

  // Cuadro para importar enlace de Spotify o YouTube
  void _showImportDialog() {
    final linkController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1825),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Importar con enlace"),
        content: TextField(
          controller: linkController,
          decoration: const InputDecoration(
            hintText: "Pega link de YouTube o nombre de playlist...",
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
            child: const Text("Importar / Buscar"),
          ),
        ],
      ),
    );
  }

  // Pantalla Completa del Reproductor + Letras
  void _openFullPlayer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0A10),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.9,
              minChildSize: 0.6,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Container(
                        width: 45,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.network(
                          _currentTrack.thumb,
                          height: 260,
                          width: 260,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _currentTrack.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _currentTrack.artist,
                        style: const TextStyle(fontSize: 15, color: Color(0xFF9CA3AF)),
                      ),
                      const SizedBox(height: 20),
                      // Barra de tiempo en vivo
                      StreamBuilder<Duration>(
                        stream: _player.positionStream,
                        builder: (context, snapshot) {
                          final pos = snapshot.data ?? Duration.zero;
                          final total = _player.duration ?? const Duration(minutes: 3);
                          return Column(
                            children: [
                              Slider(
                                activeColor: const Color(0xFFA855F7),
                                value: pos.inSeconds.toDouble().clamp(0, total.inSeconds.toDouble() > 0 ? total.inSeconds.toDouble() : 1),
                                max: total.inSeconds.toDouble() > 0 ? total.inSeconds.toDouble() : 1,
                                onChanged: (val) {
                                  _player.seek(Duration(seconds: val.toInt()));
                                },
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("${pos.inMinutes}:${(pos.inSeconds % 60).toString().padLeft(2, '0')}"),
                                  Text("${total.inMinutes}:${(total.inSeconds % 60).toString().padLeft(2, '0')}"),
                                ],
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
                            icon: Icon(
                              _isFavorite(_currentTrack) ? Icons.favorite : Icons.favorite_border,
                              color: Colors.purpleAccent,
                              size: 30,
                            ),
                            onPressed: () {
                              _toggleFavorite(_currentTrack);
                              setModalState(() {});
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              _player.playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              size: 68,
                              color: const Color(0xFFA855F7),
                            ),
                            onPressed: () {
                              if (_player.playing) {
                                _player.pause();
                              } else {
                                _player.play();
                              }
                              setModalState(() {});
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.replay_10_rounded, size: 30),
                            onPressed: () => _player.seek(Duration.zero),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Tarjeta de Letras (Karaoke)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1825),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.lyrics_outlined, color: Color(0xFFA855F7)),
                                SizedBox(width: 8),
                                Text("Letra de la canción", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _currentLyrics,
                              style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _player.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Encabezado: Logo Aura + Botón Apóyanos
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            "Aura",
                            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.graphic_eq, color: Colors.purpleAccent.shade200, size: 26),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => launchUrl(Uri.parse("https://ko-fi.com")),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1825),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: const Color(0xFFA855F7), width: 1.2),
                          ),
                          child: const Row(
                            children: [
                              Text("☕ ", style: TextStyle(fontSize: 14)),
                              Text("Apóyanos", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Barra de Búsqueda siempre visible
                  TextField(
                    controller: _searchController,
                    onSubmitted: _searchMusic,
                    decoration: InputDecoration(
                      hintText: "¿Qué quieres escuchar hoy?",
                      hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF)),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send_rounded, color: Color(0xFFA855F7)),
                        onPressed: () => _searchMusic(_searchController.text),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1A1825),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(100),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Contenido según la pestaña seleccionada
                  if (_selectedTab == 2) ...[
                    // PESTAÑA 2: MI BIBLIOTECA Y FAVORITOS
                    const Text("Mi Biblioteca (Favoritos ❤️)", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (_favorites.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            "Aún no tienes canciones en Favoritos.\nBusca una canción y dale al corazón ❤️.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF9CA3AF)),
                          ),
                        ),
                      )
                    else
                      _buildTrackList(_favorites),
                  ] else if (_selectedTab == 1) ...[
                    // PESTAÑA 1: BUSCADOR Y RESULTADOS
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Resultados directos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () => setState(() => _selectedTab = 0),
                          child: const Text("Volver al inicio"),
                        )
                      ],
                    ),
                    if (_isLoading)
                      const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
                    else if (_searchResults.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: Text("Escribe el nombre de un artista o canción arriba.")),
                      )
                    else
                      _buildTrackList(_searchResults),
                  ] else ...[
                    // PESTAÑA 0: INICIO
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
                              color: const Color(0xFF7C3AED).withOpacity(0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Importa tu música\nsin contraseñas",
                              style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold, height: 1.2),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.28),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.link, color: Colors.white70),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      "Toca aquí para pegar enlace o buscar lista",
                                      style: TextStyle(color: Colors.white70, fontSize: 13),
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
                        const Text("Tus Playlists", style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                        GestureDetector(
                          onTap: _showImportDialog,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: Color(0xFF1A1825), shape: BoxShape.circle),
                            child: const Icon(Icons.add, size: 20),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 150,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _selectedTab = 2),
                            child: _playlistCard("Favoritos (${_favorites.length})", Icons.favorite, const Color(0xFF9333EA)),
                          ),
                          GestureDetector(
                            onTap: () => _searchMusic("Lofi beats study chill"),
                            child: _playlistCard("Para Concentrarse", Icons.self_improvement, const Color(0xFF0D9488)),
                          ),
                          GestureDetector(
                            onTap: () => _searchMusic("Synthwave night drive mix"),
                            child: _playlistCard("Viaje Nocturno", Icons.nightlight_round, const Color(0xFF3B82F6)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Mini-Reproductor Flotante (Tócalo para abrir pantalla completa con letras)
            Align(
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onTap: _openFullPlayer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        height: 68,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1825).withOpacity(0.85),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.55), width: 1.2),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(_currentTrack.thumb, width: 46, height: 46, fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isBuffering ? "Cargando pista sin anuncios..." : "Toca para ver la letra • Sonando:",
                                    style: TextStyle(fontSize: 11, color: Colors.purpleAccent.shade100),
                                  ),
                                  Text(
                                    _currentTrack.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                            if (_isBuffering)
                              const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                              )
                            else
                              IconButton(
                                icon: Icon(_player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
                                onPressed: () {
                                  if (_player.playing) {
                                    _player.pause();
                                  } else {
                                    _player.play();
                                  }
                                },
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
        backgroundColor: const Color(0xFF0B0A10),
        selectedItemColor: const Color(0xFFA855F7),
        unselectedItemColor: const Color(0xFF9CA3AF),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Inicio"),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: "Buscar"),
          BottomNavigationBarItem(icon: Icon(Icons.library_music_outlined), label: "Mi Biblioteca"),
        ],
      ),
    );
  }

  Widget _buildTrackList(List<TrackItem> tracks) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isFav = _isFavorite(track);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(track.thumb, width: 55, height: 55, fit: BoxFit.cover),
          ),
          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(track.artist, style: const TextStyle(color: Color(0xFF9CA3AF))),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.purpleAccent : Colors.white54),
                onPressed: () => _toggleFavorite(track),
              ),
              const Icon(Icons.play_circle_fill, color: Color(0xFFA855F7), size: 32),
            ],
          ),
          onTap: () => _playTrack(track),
        );
      },
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
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [color, color.withOpacity(0.4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(icon, size: 40, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
