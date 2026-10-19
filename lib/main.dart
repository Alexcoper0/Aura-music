import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const AuraApp());
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

  List<Video> _searchResults = [];
  bool _isLoading = false;
  String _currentTitle = "Golden Hour";
  String _currentArtist = "JVKE";
  String _currentThumb = "https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=300";
  bool _isPlaying = false;

  // Función que busca en YouTube sin anuncios
  Future<void> _searchMusic(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final results = await _yt.search.search("$query official audio");
      setState(() {
        _searchResults = results.toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // Función que extrae SOLO el flujo de audio limpio y lo reproduce
  Future<void> _playTrack(Video video) async {
    setState(() {
      _currentTitle = video.title;
      _currentArtist = video.author;
      _currentThumb = video.thumbnails.highResUrl;
      _isPlaying = true;
    });

    try {
      final manifest = await _yt.videos.streamsClient.getManifest(video.id);
      final audioStream = manifest.audioOnly.withHighestBitrate();
      await _player.setUrl(audioStream.url.toString());
      _player.play();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Reintentando conexión de audio...")),
      );
    }
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
            // Contenido Principal
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
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
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
                  const SizedBox(height: 20),

                  // Barra de Búsqueda
                  TextField(
                    controller: _searchController,
                    onSubmitted: _searchMusic,
                    decoration: InputDecoration(
                      hintText: "¿Qué quieres escuchar hoy?",
                      hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF)),
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

                  // Si hay búsqueda, mostramos resultados; si no, la pantalla de inicio
                  if (_isLoading)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(40.0),
                      child: CircularProgressIndicator(),
                    ))
                  else if (_searchResults.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Resultados directos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () => setState(() => _searchResults.clear()),
                          child: const Text("Volver al inicio"),
                        )
                      ],
                    ),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final video = _searchResults[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 6),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(video.thumbnails.mediumResUrl, width: 55, height: 55, fit: BoxFit.cover),
                          ),
                          title: Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(video.author, style: const TextStyle(color: Color(0xFF9CA3AF))),
                          trailing: const Icon(Icons.play_circle_fill, color: Color(0xFFA855F7), size: 32),
                          onTap: () => _playTrack(video),
                        );
                      },
                    ),
                  ] else ...[
                    // Tarjeta Principal: Importar música sin contraseñas
                    Container(
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
                                    "Pega un enlace de Spotify o YouTube aquí",
                                    style: TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Sección: Tus Playlists
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Tus Playlists", style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Color(0xFF1A1825), shape: BoxShape.circle),
                          child: const Icon(Icons.add, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 150,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _playlistCard("Favoritos", Icons.favorite, const Color(0xFF9333EA)),
                          _playlistCard("Para Concentrarse", Icons.self_improvement, const Color(0xFF0D9488)),
                          _playlistCard("Viaje Nocturno", Icons.nightlight_round, const Color(0xFF3B82F6)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Mini-Reproductor Flotante con Efecto Cristal (Glassmorphism)
            Align(
              alignment: Alignment.bottomCenter,
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
                        color: const Color(0xFF1A1825).withOpacity(0.82),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.55), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(_currentThumb, width: 46, height: 46, fit: BoxFit.cover),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Sonando ahora:",
                                  style: TextStyle(fontSize: 11, color: Colors.purpleAccent.shade100),
                                ),
                                Text(
                                  _currentTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
                            onPressed: () {
                              setState(() {
                                if (_player.playing) {
                                  _player.pause();
                                  _isPlaying = false;
                                } else {
                                  _player.play();
                                  _isPlaying = true;
                                }
                              });
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, size: 28),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      // Barra de Navegación Inferior
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0B0A10),
        selectedItemColor: Colors.white,
        unselectedItemColor: const Color(0xFF9CA3AF),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Inicio"),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: "Buscar"),
          BottomNavigationBarItem(icon: Icon(Icons.library_music_outlined), label: "Mi Biblioteca"),
        ],
      ),
    );
  }

  Widget _playlistCard(String title, IconData icon, Color color) {
    return Container(
      width: 115,
      margin: const EdgeInsets.only(right: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 105,
            width: 115,
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
