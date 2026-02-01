import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Street Guide',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: TtsDemo(),
    );
  }
}

class TtsDemo extends StatefulWidget {
  @override
  _TtsDemoState createState() => _TtsDemoState();
}

class _TtsDemoState extends State<TtsDemo> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isPlaying = false;
  String? _lastMessage;
  String? _errorMessage;

  // Location state
  Position? _currentPosition;
  double _heading = 0;
  
  // Update this URL based on your setup:
  // - Android Emulator: http://10.0.2.2:8000
  // - iOS Simulator: http://localhost:8000
  // - Physical Device: http://YOUR_COMPUTER_IP:8000
  static const String backendUrl = 'http://10.37.93.185:8000'; // Default for Android emulator
  
  // ElevenLabs API Configuration
  // TODO: Replace with your ElevenLabs API key
  // Get your API key from: https://elevenlabs.io/app/settings/api-keys
  static const String elevenLabsApiKey = 'sk_7d0df78e3d0b8ff57c62208db8cd292cc6361b70546d03ac'; //sk_634beb92c7183acf82b286664257f06574002780cc1f4caf
  static const String elevenLabsVoiceId = '21m00Tcm4TlvDq8ikWAM'; // Default voice (Rachel)
  static const String elevenLabsApiUrl = 'https://api.elevenlabs.io/v1/text-to-speech/$elevenLabsVoiceId';

  @override
  void initState() {
    super.initState();
    _initializeAudio();
  }

  Future<void> _initializeAudio() async {
    try {
      // Set up audio completion listener
      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _isPlaying = false;
          });
        }
      });
      
      // Audio player is ready to use immediately
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

  Future<bool> _getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorMessage = 'Location services are disabled. Please enable them.';
        });
        return false;
      }

      // Check permissions
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
          _errorMessage = 'Location permissions are permanently denied. Please enable them in settings.';
        });
        return false;
      }

      // Get current position
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Get heading (compass direction)
      _heading = _currentPosition!.heading;

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
    if (!_isInitialized) {
      print("Audio not initialized yet");
      return;
    }
    
    if (text.isEmpty) {
      print("TTS: Empty text, nothing to speak");
      return;
    }
    
    if (elevenLabsApiKey == 'YOUR_ELEVENLABS_API_KEY_HERE') {
      print("Error: Please set your ElevenLabs API key in the code");
      setState(() {
        _errorMessage = 'Please configure your ElevenLabs API key in the code';
        _isPlaying = false;
      });
      return;
    }
    
    try {
      setState(() {
        _isPlaying = true;
      });
      
      // Stop any ongoing audio
      await _audioPlayer.stop();
      
      // Call ElevenLabs API
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
      
      if (response.statusCode == 200) {
        // Save audio to temporary file
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/tts_audio_${DateTime.now().millisecondsSinceEpoch}.mp3');
        await file.writeAsBytes(response.bodyBytes);
        
        // Play the audio
        await _audioPlayer.play(DeviceFileSource(file.path));
        
        print("TTS: Audio started successfully");
      } else {
        setState(() {
          _isPlaying = false;
        });
        print("TTS: API error - ${response.statusCode}: ${response.body}");
        setState(() {
          _errorMessage = 'Error generating audio: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _isPlaying = false;
      });
      print("TTS speak error: $e");
      setState(() {
        _errorMessage = 'Error: $e';
      });
    }
  }

  Future<void> _fetchAndReadMessage() async {
    setState(() {
      _isLoading = true;
      _lastMessage = null;
      _errorMessage = null;
    });

    // Get user's current location first
    bool locationSuccess = await _getCurrentLocation();
    if (!locationSuccess || _currentPosition == null) {
      setState(() {
        _isLoading = false;
      });
      await _speak('Unable to get your location. Please check your location settings.');
      return;
    }

    try {
      // Send location to backend via POST
      final response = await http.post(
        Uri.parse('$backendUrl/tour'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
          'heading': _heading,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final message = data['message'] as String;

        setState(() {
          _lastMessage = message;
          _isLoading = false;
        });

        // Read the message using TTS
        await _speak(message);
      } else {
        setState(() {
          _lastMessage = 'Error: Failed to fetch message (${response.statusCode})';
          _isLoading = false;
        });
        await _speak('Failed to fetch message from backend');
      }
    } catch (e) {
      setState(() {
        _lastMessage = 'Error: $e';
        _isLoading = false;
      });
      print("Error fetching message: $e");
      await _speak('Error connecting to backend. Make sure the server is running.');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.explore, color: Colors.white),
            SizedBox(width: 8),
            Text("Street Guide"),
          ],
        ),
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.05),
              Colors.white,
            ],
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 20),
                // Header Section
                if (!_isInitialized)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            "Initializing...",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Loading State
                if (_isLoading)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          CircularProgressIndicator(
                            strokeWidth: 3,
                          ),
                          SizedBox(height: 20),
                          Text(
                            "Fetching tour guide information...",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[700],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                // Error Message
                if (_errorMessage != null && !_isLoading)
                  Card(
                    color: Colors.red[50],
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red[700]),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red[900]),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, size: 20),
                            onPressed: () {
                              setState(() {
                                _errorMessage = null;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                // Message Card
                if (_lastMessage != null && !_isLoading) ...[
                  Card(
                    elevation: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.blue.shade50,
                            Colors.blue.shade100.withOpacity(0.3),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      color: Colors.blue[700],
                                      size: 24,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "Tour Guide",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                        color: Colors.blue[900],
                                      ),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  icon: _isPlaying 
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
                                          ),
                                        )
                                      : Icon(Icons.replay_rounded),
                                  onPressed: _isPlaying ? null : () => _speak(_lastMessage!),
                                  tooltip: _isPlaying ? "Playing..." : "Replay audio",
                                  color: Colors.blue[700],
                                  iconSize: 28,
                                ),
                              ],
                            ),
                            SizedBox(height: 16),
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _lastMessage!,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.6,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                ],
                // Action Buttons
                SizedBox(height: 20),
                if (_isInitialized && !_isLoading)
                  ElevatedButton.icon(
                    onPressed: _fetchAndReadMessage,
                    icon: Icon(Icons.explore, size: 20),
                    label: Text(
                      "Get Tour Guide",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (_lastMessage != null && !_isLoading && _isInitialized) ...[
                  SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isPlaying ? null : () => _speak(_lastMessage!),
                    icon: _isPlaying
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          )
                        : Icon(Icons.volume_up, size: 20),
                    label: Text(
                      _isPlaying ? "Playing..." : "Replay Audio",
                      style: TextStyle(fontSize: 16),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ],
                SizedBox(height: 32),
                // Footer Info
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                      SizedBox(width: 8),
                      Text(
                        "Backend: $backendUrl",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
