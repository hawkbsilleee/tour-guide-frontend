import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'services/preferences_service.dart';

void main() {
  runApp(MyApp());
}

// Anthropic-inspired warm color palette
class AppColors {
  static const primary = Color(0xFFFF6B35);        // Warm coral/orange
  static const primaryDark = Color(0xFFE85D2F);    // Deep coral
  static const accent = Color(0xFFF59E42);         // Warm golden
  static const background = Color(0xFFFFFAF5);     // Warm cream
  static const surface = Color(0xFFFFFFFF);        // Pure white
  static const textPrimary = Color(0xFF2D1B12);    // Warm dark brown
  static const textSecondary = Color(0xFF8B6F5C);  // Warm medium brown
  static const border = Color(0xFFFFE8D6);         // Warm light border
  static const success = Color(0xFF34C759);        // Green
  static const error = Color(0xFFFF3B30);          // Red
  static const mapAccent = Color(0xFF4A90E2);      // Soft blue for contrast
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Atlas',
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.dmSansTextTheme(),
        colorScheme: ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
          error: AppColors.error,
        ),
        scaffoldBackgroundColor: AppColors.background,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.border, width: 1),
          ),
          color: AppColors.surface,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: AppInitializer(),
    );
  }
}

// Initialize app and check onboarding status
class AppInitializer extends StatefulWidget {
  @override
  _AppInitializerState createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isChecking = true;
  bool _hasCompletedOnboarding = false;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    // Clear old data so user always goes through onboarding
    await PreferencesService.clearUserData();

    // Check if user has set preferences
    final hasPreferences = await PreferencesService.hasCompletedOnboarding();

    setState(() {
      _hasCompletedOnboarding = hasPreferences;
      _isChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      // Show loading screen while checking
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
          ),
        ),
      );
    }

    // Navigate to appropriate screen
    if (_hasCompletedOnboarding) {
      return TourGuideScreen();
    } else {
      return OnboardingScreen();
    }
  }
}

class PlaceInfo {
  final String name;
  final double latitude;
  final double longitude;
  final String? relativeDirection;
  final double? distanceMeters;

  PlaceInfo({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.relativeDirection,
    this.distanceMeters,
  });

  factory PlaceInfo.fromJson(Map<String, dynamic> json) {
    return PlaceInfo(
      name: json['name'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      relativeDirection: json['relative_direction'],
      distanceMeters: json['distance_meters']?.toDouble(),
    );
  }
}

class TourSegment {
  final String narrative;
  final List<PlaceInfo> places;
  final String summary;
  final double latitude;
  final double longitude;
  final double heading;
  final DateTime timestamp;

  TourSegment({
    required this.narrative,
    required this.places,
    required this.summary,
    required this.latitude,
    required this.longitude,
    required this.heading,
    required this.timestamp,
  });

  factory TourSegment.fromJson(Map<String, dynamic> json) {
    final placesJson = json['places'] as List<dynamic>;
    return TourSegment(
      narrative: json['narrative'] as String,
      places: placesJson.map((p) => PlaceInfo.fromJson(p)).toList(),
      summary: json['summary'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      heading: json['heading'] as double,
      timestamp: DateTime.now(),
    );
  }

  String get headingDirection {
    if (heading >= 337.5 || heading < 22.5) return 'N';
    if (heading >= 22.5 && heading < 67.5) return 'NE';
    if (heading >= 67.5 && heading < 112.5) return 'E';
    if (heading >= 112.5 && heading < 157.5) return 'SE';
    if (heading >= 157.5 && heading < 202.5) return 'S';
    if (heading >= 202.5 && heading < 247.5) return 'SW';
    if (heading >= 247.5 && heading < 292.5) return 'W';
    return 'NW';
  }
}

class TourGuideScreen extends StatefulWidget {
  @override
  _TourGuideScreenState createState() => _TourGuideScreenState();
}

class _TourGuideScreenState extends State<TourGuideScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final MapController _mapController = MapController();
  final ScrollController _textScrollController = ScrollController();

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isPlaying = false;
  bool _isLoadingAudio = false;
  String? _errorMessage;

  // Location state
  Position? _currentPosition;
  double _heading = 0;
  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<Position>? _positionSubscription;

  // User state
  String? _userId;

  // Tour data - now a list of tour segments
  static const int _maxTours = 4;
  List<TourSegment> _tours = [];
  String? _selectedPlaceName;
  int? _playingTourIndex; // Track which tour's audio is currently playing

  // Text highlighting
  List<String> _words = [];
  List<double> _wordTimestamps = []; // Cumulative time percentages for each word
  int _currentWordIndex = 0;
  Timer? _highlightTimer;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;

  static const String backendUrl = 'http://10.37.93.185:8000';
  static const String elevenLabsApiKey = 'sk_12058f16571ee64072d97b09f5c14ca51aa951c3fdad9fcf';
  static const String elevenLabsVoiceId = '21m00Tcm4TlvDq8ikWAM';
  static const String elevenLabsApiUrl = 'https://api.elevenlabs.io/v1/text-to-speech/$elevenLabsVoiceId';

  @override
  void initState() {
    super.initState();
    _initializeAudio();
    _initializeCompass();
    _initializeLocationTracking();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final userId = await PreferencesService.getUserId();
    setState(() {
      _userId = userId;
    });
  }

  Future<void> _initializeAudio() async {
    try {
      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _currentWordIndex = 0;
          });
          _highlightTimer?.cancel();
        }
      });

      _audioPlayer.onDurationChanged.listen((Duration duration) {
        setState(() {
          _audioDuration = duration;
        });
      });

      _audioPlayer.onPositionChanged.listen((Duration position) {
        setState(() {
          _audioPosition = position;
        });
        _updateHighlightedWord(position);
      });

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print("Audio initialization error: $e");
      setState(() {
        _isInitialized = true;
      });
    }
  }

  void _initializeCompass() {
    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null) {
        setState(() {
          _heading = event.heading!;
        });
      }
    });
  }

  Future<void> _initializeLocationTracking() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      // Start continuous location tracking
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // Update every 5 meters
        ),
      ).listen((Position position) {
        if (mounted) {
          setState(() {
            _currentPosition = position;
          });
        }
      });
    } catch (e) {
      print("Error initializing location tracking: $e");
    }
  }

  // Calculate word timestamps based on word length (longer words take more time)
  void _calculateWordTimestamps(List<String> words) {
    if (words.isEmpty) {
      _wordTimestamps = [];
      return;
    }

    // Weight each word by its character count (approximation of speaking time)
    List<double> wordWeights = words.map((word) {
      // Base weight on character count + punctuation pauses
      double weight = word.length.toDouble();
      // Add extra weight for punctuation (causes pauses)
      if (word.endsWith(',')) weight += 0.5;
      if (word.endsWith('.') || word.endsWith('!') || word.endsWith('?')) weight += 1.0;
      return weight.clamp(1.0, 50.0);
    }).toList();

    double totalWeight = wordWeights.reduce((a, b) => a + b);

    // Calculate cumulative timestamps (as percentage of total duration)
    _wordTimestamps = [];
    double cumulative = 0;
    for (var weight in wordWeights) {
      cumulative += weight / totalWeight;
      _wordTimestamps.add(cumulative);
    }
  }

  void _updateHighlightedWord(Duration position) {
    if (_words.isEmpty || _audioDuration.inMilliseconds == 0 || _wordTimestamps.isEmpty) return;

    // Calculate current position as percentage of total duration
    // Add a small lead time (100ms) to sync better with audio
    final adjustedPosition = position.inMilliseconds + 100;
    final progress = (adjustedPosition / _audioDuration.inMilliseconds).clamp(0.0, 1.0);

    // Find the word index based on timestamps
    int newIndex = 0;
    for (int i = 0; i < _wordTimestamps.length; i++) {
      if (progress >= _wordTimestamps[i]) {
        newIndex = i + 1;
      } else {
        break;
      }
    }
    newIndex = newIndex.clamp(0, _words.length - 1);

    if (newIndex != _currentWordIndex) {
      setState(() {
        _currentWordIndex = newIndex;
      });
      _scrollToCurrentWord();
    }
  }

  void _scrollToCurrentWord() {
    if (_textScrollController.hasClients) {
      final maxScroll = _textScrollController.position.maxScrollExtent;
      final progress = _currentWordIndex / _words.length;
      final targetScroll = maxScroll * progress;

      _textScrollController.animateTo(
        targetScroll,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<bool> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorMessage = 'Location services are disabled. Please enable them.';
        });
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _errorMessage = 'Location permission denied.';
          });
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage = 'Location permissions are permanently denied.';
        });
        return false;
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      print("Location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}, heading: $_heading");
      return true;
    } catch (e) {
      print("Error getting location: $e");
      setState(() {
        _errorMessage = 'Error getting location: $e';
      });
      return false;
    }
  }

  Future<void> _speak(String text) async {
    if (!_isInitialized || text.isEmpty) return;

    try {
      setState(() {
        _isLoadingAudio = true;
        _words = text.split(' ');
        _currentWordIndex = 0;
      });

      // Calculate word timestamps based on word length
      _calculateWordTimestamps(_words);

      await _audioPlayer.stop();

      print("Calling ElevenLabs API...");
      final response = await http.post(
        Uri.parse(elevenLabsApiUrl),
        headers: {
          'Accept': 'audio/mpeg',
          'Content-Type': 'application/json',
          'xi-api-key': elevenLabsApiKey,
        },
        body: json.encode({
          'text': text,
          'model_id': 'eleven_multilingual_v2',
          'voice_settings': {
            'stability': 0.5,
            'similarity_boost': 0.5,
          },
        }),
      );

      print("ElevenLabs response: ${response.statusCode}");

      if (response.statusCode == 200) {
        print("Audio received, saving to file...");
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/tts_audio_${DateTime.now().millisecondsSinceEpoch}.mp3');
        await file.writeAsBytes(response.bodyBytes);

        print("Playing audio file: ${file.path}");
        await _audioPlayer.play(DeviceFileSource(file.path));

        setState(() {
          _isLoadingAudio = false;
          _isPlaying = true;
        });
        print("Audio playing successfully");
      } else {
        final errorBody = response.body;
        print("ElevenLabs API Error: ${response.statusCode}");
        print("Error body: $errorBody");
        setState(() {
          _isLoadingAudio = false;
          _isPlaying = false;
          _errorMessage = 'Audio generation failed: ${response.statusCode}\n$errorBody';
        });
      }
    } catch (e, stackTrace) {
      print("Error in _speak: $e");
      print("Stack trace: $stackTrace");
      setState(() {
        _isLoadingAudio = false;
        _isPlaying = false;
        _errorMessage = 'Audio error: $e';
      });
    }
  }

  Future<void> _togglePlayPause(int tourIndex) async {
    if (_isLoadingAudio) return;
    if (tourIndex >= _tours.length) return;

    // If playing a different tour, stop it first
    if (_playingTourIndex != null && _playingTourIndex != tourIndex) {
      await _audioPlayer.stop();
      setState(() {
        _isPlaying = false;
        _playingTourIndex = null;
        _words = [];
        _currentWordIndex = 0;
      });
    }

    if (_isPlaying && _playingTourIndex == tourIndex) {
      await _audioPlayer.pause();
      setState(() {
        _isPlaying = false;
      });
    } else {
      // If paused on same tour, resume playback
      if (_audioPosition.inMilliseconds > 0 && _playingTourIndex == tourIndex) {
        await _audioPlayer.resume();
        setState(() {
          _isPlaying = true;
        });
      } else {
        // Start from beginning
        await _speakTour(tourIndex);
      }
    }
  }

  Future<void> _speakTour(int tourIndex) async {
    if (tourIndex >= _tours.length) return;
    final tour = _tours[tourIndex];

    setState(() {
      _playingTourIndex = tourIndex;
      _words = tour.narrative.split(' ');
      _currentWordIndex = 0;
    });

    _calculateWordTimestamps(_words);
    await _speak(tour.narrative);
  }

  Future<void> _fetchAndReadMessage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedPlaceName = null;
      _words = [];
      _wordTimestamps = [];
      _currentWordIndex = 0;
    });

    // Stop any playing audio
    if (_isPlaying) {
      await _audioPlayer.stop();
      setState(() {
        _isPlaying = false;
        _playingTourIndex = null;
      });
    }

    bool locationSuccess = await _getCurrentLocation();
    if (!locationSuccess || _currentPosition == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // Make sure we have a userId
      if (_userId == null) {
        await _loadUserId();
      }

      // Get previous summary if we have tours
      final previousSummary = _tours.isNotEmpty ? _tours.first.summary : null;

      final response = await http.post(
        Uri.parse('$backendUrl/tour'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': _userId,
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
          'heading': _heading,
          'previous_summary': previousSummary,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newTour = TourSegment.fromJson(data);

        setState(() {
          // Add new tour at the beginning
          _tours.insert(0, newTour);
          // Keep only max tours
          if (_tours.length > _maxTours) {
            _tours = _tours.sublist(0, _maxTours);
          }
          _isLoading = false;
        });

        if (_currentPosition != null) {
          _mapController.move(
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            15.0,
          );
        }

        // Auto-play the new tour
        await _speakTour(0);
      } else {
        setState(() {
          _errorMessage = 'Failed to fetch tour (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error: $e';
        _isLoading = false;
      });
      print("Error: $e");
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _compassSubscription?.cancel();
    _positionSubscription?.cancel();
    _highlightTimer?.cancel();
    _textScrollController.dispose();
    super.dispose();
  }

  // Build direction cone polygon
  List<LatLng> _buildDirectionCone() {
    if (_currentPosition == null) return [];

    final userLat = _currentPosition!.latitude;
    final userLng = _currentPosition!.longitude;

    // Cone parameters
    final coneLength = 0.0003; // Length in degrees (~33 meters)
    final coneAngle = 22.5; // Half-angle of the cone in degrees

    // Convert heading to radians (heading is in degrees, 0 = North, clockwise)
    final headingRad = (_heading) * (3.14159 / 180.0);

    // Calculate the three points of the triangle cone
    final tipLat = userLat + coneLength * cos(headingRad);
    final tipLng = userLng + coneLength * sin(headingRad) / cos(userLat * 3.14159 / 180.0);

    final leftAngle = headingRad - (coneAngle * 3.14159 / 180.0);
    final rightAngle = headingRad + (coneAngle * 3.14159 / 180.0);

    final leftLat = userLat + (coneLength * 0.7) * cos(leftAngle);
    final leftLng = userLng + (coneLength * 0.7) * sin(leftAngle) / cos(userLat * 3.14159 / 180.0);

    final rightLat = userLat + (coneLength * 0.7) * cos(rightAngle);
    final rightLng = userLng + (coneLength * 0.7) * sin(rightAngle) / cos(userLat * 3.14159 / 180.0);

    return [
      LatLng(userLat, userLng),
      LatLng(leftLat, leftLng),
      LatLng(tipLat, tipLng),
      LatLng(rightLat, rightLng),
    ];
  }

  List<Marker> _buildMarkers() {
    List<Marker> markers = [];

    if (_currentPosition != null) {
      markers.add(
        Marker(
          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withAlpha(76),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              Icons.my_location,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      );
    }

    // Iterate through all tours (newest first), with different styling for older tours
    for (int tourIndex = 0; tourIndex < _tours.length; tourIndex++) {
      final tour = _tours[tourIndex];
      final isCurrentTour = tourIndex == 0;

      for (var place in tour.places) {
        final isSelected = _selectedPlaceName == place.name;

        // Styling based on tour age
        final markerSize = isCurrentTour ? 36.0 : 28.0;
        final iconSize = isCurrentTour ? 20.0 : 16.0;
        final borderWidth = isCurrentTour ? 3.0 : 2.0;
        final baseColor = isCurrentTour
            ? AppColors.mapAccent
            : AppColors.textSecondary.withAlpha(150);

        markers.add(
          Marker(
            point: LatLng(place.latitude, place.longitude),
            width: markerSize,
            height: markerSize,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPlaceName = place.name;
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accent : baseColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: borderWidth),
                  boxShadow: [
                    BoxShadow(
                      color: (isSelected ? AppColors.accent : baseColor).withAlpha(76),
                      blurRadius: isCurrentTour ? 8 : 4,
                      spreadRadius: isCurrentTour ? 2 : 1,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.place,
                  color: Colors.white,
                  size: iconSize,
                ),
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  Widget _buildSelectedPlacePopup() {
    if (_selectedPlaceName == null) return SizedBox.shrink();

    // Find the place across all tours
    PlaceInfo? place;
    for (var tour in _tours) {
      for (var p in tour.places) {
        if (p.name == _selectedPlaceName) {
          place = p;
          break;
        }
      }
      if (place != null) break;
    }
    if (place == null) return SizedBox.shrink();

    return Positioned(
      bottom: _tours.isNotEmpty ? 300 : 40,
      left: 20,
      right: 20,
      child: Card(
        elevation: 8,
        shadowColor: AppColors.primary.withAlpha(51),
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      place.name,
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                    onPressed: () {
                      setState(() {
                        _selectedPlaceName = null;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
              if (place.relativeDirection != null || place.distanceMeters != null) ...[
                SizedBox(height: 12),
                Row(
                  children: [
                    if (place.relativeDirection != null) ...[
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(26),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.navigation, size: 14, color: AppColors.primary),
                            SizedBox(width: 4),
                            Text(
                              place.relativeDirection!,
                              style: GoogleFonts.dmSans(
                                color: AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8),
                    ],
                    if (place.distanceMeters != null) ...[
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withAlpha(26),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.straighten, size: 14, color: AppColors.accent),
                            SizedBox(width: 4),
                            Text(
                              '${place.distanceMeters!.toStringAsFixed(0)}m',
                              style: GoogleFonts.dmSans(
                                color: AppColors.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedText(int tourIndex) {
    if (tourIndex >= _tours.length) return SizedBox.shrink();

    final tour = _tours[tourIndex];
    final words = tour.narrative.split(' ');
    final isThisTourPlaying = _isPlaying && _playingTourIndex == tourIndex;

    return Wrap(
      children: List.generate(words.length, (index) {
        final isHighlighted = isThisTourPlaying && index == _currentWordIndex;
        return Padding(
          padding: EdgeInsets.only(right: 4, bottom: 4),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? AppColors.primary.withAlpha(51)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              words[index],
              style: GoogleFonts.dmSans(
                fontSize: 16,
                height: 1.7,
                color: isHighlighted ? AppColors.primary : AppColors.textPrimary,
                fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final mapHeight = screenHeight * 0.7;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.explore, color: AppColors.primary, size: 20),
            ),
            SizedBox(width: 12),
            Text(
              "Audio Atlas",
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        actions: [
          if (_currentPosition != null)
            Container(
              margin: EdgeInsets.only(right: 6),
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accent.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on, size: 12, color: AppColors.accent),
                  SizedBox(width: 3),
                  Text(
                    '${_currentPosition!.latitude.toStringAsFixed(1)},${_currentPosition!.longitude.toStringAsFixed(1)}',
                    style: GoogleFonts.dmSans(
                      fontSize: 10,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            margin: EdgeInsets.only(right: 6),
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.navigation, size: 12, color: AppColors.primary),
                SizedBox(width: 3),
                Text(
                  '${_heading.toStringAsFixed(0)}°',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.settings, size: 22, color: AppColors.primary),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            height: mapHeight,
            child: _currentPosition == null && !_isLoading
                ? Container(
                    color: AppColors.background,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(26),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.map_outlined,
                              size: 64,
                              color: AppColors.primary,
                            ),
                          ),
                          SizedBox(height: 24),
                          Text(
                            'Ready to explore',
                            style: GoogleFonts.dmSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Tap "Start Tour" to begin',
                            style: GoogleFonts.dmSans(
                              color: AppColors.textSecondary,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _currentPosition != null
                          ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                          : LatLng(41.8303668, -71.4015215),
                      initialZoom: 15.5,
                      minZoom: 10.0,
                      maxZoom: 18.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                        userAgentPackageName: 'com.example.street_guide',
                        subdomains: ['a', 'b', 'c', 'd'],
                        retinaMode: RetinaMode.isHighDensity(context),
                      ),
                      if (_currentPosition != null)
                        PolygonLayer(
                          polygons: [
                            Polygon(
                              points: _buildDirectionCone(),
                              color: AppColors.primary.withAlpha(76),
                              borderColor: AppColors.primary,
                              borderStrokeWidth: 2,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: _buildMarkers(),
                      ),
                    ],
                  ),
          ),
          _buildSelectedPlacePopup(),
          DraggableScrollableSheet(
            initialChildSize: 0.3,
            minChildSize: 0.15,
            maxChildSize: 0.9,
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(26),
                      blurRadius: 20,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 48,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        SizedBox(height: 24),
                        if (_isLoading)
                          Column(
                            children: [
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: AppColors.primary,
                                ),
                              ),
                              SizedBox(height: 20),
                              Text(
                                "Generating your tour...",
                                style: GoogleFonts.dmSans(
                                  color: AppColors.textSecondary,
                                  fontSize: 15,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        if (_errorMessage != null && !_isLoading)
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.error.withAlpha(26),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.error.withAlpha(76),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: AppColors.error, size: 20),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: GoogleFonts.dmSans(
                                      color: AppColors.error,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // New Tour Button at top
                        if (!_isLoading)
                          ElevatedButton.icon(
                            onPressed: _fetchAndReadMessage,
                            icon: Icon(Icons.explore, size: 20),
                            label: Text(
                              _tours.isEmpty ? "Start Tour" : "Continue Tour",
                              style: GoogleFonts.dmSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 18),
                            ),
                          ),
                        if (_tours.isNotEmpty && !_isLoading)
                          SizedBox(height: 24),
                        // Tour feed - display all tours
                        ..._tours.asMap().entries.map((entry) {
                          final tourIndex = entry.key;
                          final tour = entry.value;
                          final isCurrentTour = tourIndex == 0;
                          final isThisTourPlaying = _isPlaying && _playingTourIndex == tourIndex;

                          return Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isCurrentTour ? AppColors.background : AppColors.background.withAlpha(180),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isCurrentTour ? AppColors.border : AppColors.border.withAlpha(100),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Tour header with coordinates, heading, and play button
                                  Container(
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isCurrentTour
                                          ? AppColors.primary.withAlpha(13)
                                          : AppColors.textSecondary.withAlpha(13),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(15),
                                        topRight: Radius.circular(15),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        // Tour label
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isCurrentTour
                                                ? AppColors.primary
                                                : AppColors.textSecondary,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isCurrentTour ? 'Latest' : 'Tour ${_tours.length - tourIndex}',
                                            style: GoogleFonts.dmSans(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        // Coordinates badge
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.accent.withAlpha(26),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.location_on, size: 12, color: AppColors.accent),
                                              SizedBox(width: 4),
                                              Text(
                                                '${tour.latitude.toStringAsFixed(4)}°, ${tour.longitude.toStringAsFixed(4)}°',
                                                style: GoogleFonts.dmSans(
                                                  fontSize: 10,
                                                  color: AppColors.accent,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(width: 6),
                                        // Heading badge
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withAlpha(26),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.navigation, size: 12, color: AppColors.primary),
                                              SizedBox(width: 4),
                                              Text(
                                                '${tour.heading.toStringAsFixed(0)}° ${tour.headingDirection}',
                                                style: GoogleFonts.dmSans(
                                                  fontSize: 10,
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Spacer(),
                                        // Play/Pause button
                                        IconButton(
                                          icon: (_isLoadingAudio && _playingTourIndex == tourIndex)
                                              ? SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.5,
                                                    color: isCurrentTour
                                                        ? AppColors.primary
                                                        : AppColors.textSecondary,
                                                  ),
                                                )
                                              : Icon(
                                                  isThisTourPlaying
                                                      ? Icons.pause_circle_filled
                                                      : Icons.play_circle_filled,
                                                  color: isCurrentTour
                                                      ? AppColors.primary
                                                      : AppColors.textSecondary,
                                                ),
                                          onPressed: _isLoadingAudio
                                              ? null
                                              : () => _togglePlayPause(tourIndex),
                                          iconSize: 32,
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Tour narrative
                                  Padding(
                                    padding: EdgeInsets.all(16),
                                    child: _buildHighlightedText(tourIndex),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
