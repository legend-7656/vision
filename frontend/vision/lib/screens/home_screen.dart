import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/detection.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  final ApiService _apiService = ApiService();

  final Map<String, DateTime> _spokenAlerts = {};
  final Set<String> _spokenTexts = {};

  CameraController? _cameraController;
  Timer? _timer;

  List<Detection> _detections = [];

  String? _error;
  String? _latestUrgent; // newest high-priority alert, shown as a red banner
  String? _lastDescription; // newest scene description, shown on screen

  XFile? _latestFrame;

  bool _initializing = true;
  bool _scanning = false;
  bool _processing = false;
  bool _aiAssistEnabled = false;
  bool _describingScene = false;
  bool _urgentSpeaking = false;
  bool _offlineAnnounced = false;

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('No camera was found.');
      }

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _initializing = false;
      });

      _startScanning();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Camera initialization failed: $e';
        _initializing = false;
      });
    }
  }

  void _startScanning() {
    if (_cameraController == null || _scanning) return;

    setState(() {
      _scanning = true;
      _error = null;
    });

    _timer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _processFrame(),
    );

    _processFrame();
  }

  void _stopScanning() {
    _timer?.cancel();
    _timer = null;

    if (!mounted) return;

    setState(() {
      _scanning = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Speech
  // ---------------------------------------------------------------------------

  /// Speaks [text] but never lets a stuck speech engine freeze the app.
  Future<void> _speakSafely(String text) async {
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text).timeout(const Duration(seconds: 25));
    } catch (e) {
      debugPrint('TTS error or timeout: $e');
    }
  }

  Future<void> _speakAlert(String message) async {
    final now = DateTime.now();
    final lastSpoken = _spokenAlerts[message];

    if (lastSpoken != null && now.difference(lastSpoken).inSeconds < 10) {
      return;
    }

    _spokenAlerts[message] = now;

    // Urgent warnings take priority over ordinary speech.
    _urgentSpeaking = true;

    try {
      await _speakSafely(message);
    } finally {
      _urgentSpeaking = false;
    }
  }

  Future<void> _speakRecognizedText(List<String> texts) async {
    if (!_aiAssistEnabled || _urgentSpeaking) return;

    for (final text in texts) {
      if (!_aiAssistEnabled || _urgentSpeaking) return;

      final normalized = text.toLowerCase().trim();

      if (normalized.isEmpty || _spokenTexts.contains(normalized)) {
        continue;
      }

      _spokenTexts.add(normalized);

      // Prevent the history from growing indefinitely.
      if (_spokenTexts.length > 200) {
        _spokenTexts.clear();
        _spokenTexts.add(normalized);
      }

      try {
        await _flutterTts
            .speak('Text detected: $text')
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('TTS error or timeout: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Describe scene (Gemini)
  // ---------------------------------------------------------------------------

  Future<void> _describeAndSpeak(XFile image) async {
    if (_describingScene || !_scanning) return;

    setState(() {
      _describingScene = true;
      _error = null;
    });

    String message;

    try {
      final description = await _apiService.describeScene(image);

      if (description.trim().isEmpty) {
        throw Exception('Gemini returned an empty description.');
      }
      message = description;
    } catch (e, stackTrace) {
      debugPrint('Describe Scene error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _error = 'Describe Scene failed: $e';
        });
      }

      // Spoken fallback so the user is never left in silence.
      final seen = _detections
          .map((d) => d.className)
          .toSet()
          .take(5)
          .join(', ');

      message = seen.isEmpty
          ? 'Scene description is unavailable right now. Please try again.'
          : 'Detailed description is busy. I can see: $seen.';
    }

    // Release the button now, before speaking.
    if (mounted) {
      setState(() {
        _describingScene = false;
        _lastDescription = message;
      });
    } else {
      _describingScene = false;
    }

    await _speakSafely(message);
  }

  // ---------------------------------------------------------------------------
  // Live detection loop (YOLO)
  // ---------------------------------------------------------------------------

  Future<void> _processFrame() async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        _processing ||
        !_scanning) {
      return;
    }

    _processing = true;

    try {
      final image = await controller.takePicture();
      _latestFrame = image;

      // OCR is slow, so only ask the server for it when AI Assist is on.
      final response = await _apiService.detectObjects(
        image,
        ocr: _aiAssistEnabled,
      );

      if (!mounted) return;

      setState(() {
        _detections = response.detections;
        _latestUrgent =
            response.urgentAlerts.isNotEmpty ? response.urgentAlerts.first : null;
        _error = null;
        _offlineAnnounced = false;
      });

      // Urgent object alerts work whether AI Assist is on or off.
      if (response.urgentAlerts.isNotEmpty && _scanning) {
        HapticFeedback.heavyImpact();
        await _speakAlert(response.urgentAlerts.first);
      } else if (_aiAssistEnabled && response.alerts.isNotEmpty && _scanning) {
        await _speakAlert(response.alerts.first);
      }

      // Optional text reading.
      if (_aiAssistEnabled && _scanning) {
        await _speakRecognizedText(response.recognizedText);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Detection failed: $e';
      });

      // Tell the user once per outage instead of every 1.5 seconds.
      if (!_offlineAnnounced) {
        _offlineAnnounced = true;
        _speakSafely('Detection is unavailable. Check the connection.');
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _toggleAiAssist() async {
    final enabled = !_aiAssistEnabled;

    setState(() {
      _aiAssistEnabled = enabled;
      _error = null;
    });

    if (!enabled) {
      // Stop optional speech immediately when AI Assist is switched off.
      await _flutterTts.stop();
      _spokenTexts.clear();
      return;
    }

    await _speakSafely(
      'AI Assist on. Text reading and extra alerts are enabled.',
    );
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _flutterTts.setLanguage('en-US');
    _flutterTts.awaitSpeakCompletion(true);
    _initializeCamera();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cameraController?.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    final cameraReady = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'ContextAid',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              Expanded(
                flex: 5,
                child: _buildCameraArea(controller, cameraReady),
              ),
              const SizedBox(height: 12),
              if (_latestUrgent != null) _buildUrgentBanner(_latestUrgent!),
              if (_error != null) _buildErrorText(_error!),
              if (_lastDescription != null) _buildDescriptionCard(),
              Expanded(
                flex: 3,
                child: _buildDetectionList(),
              ),
              const SizedBox(height: 12),
              _buildDescribeButton(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildAssistButton()),
                  const SizedBox(width: 8),
                  Expanded(child: _buildScanButton()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraArea(CameraController? controller, bool ready) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Colors.grey.shade900,
              child: Center(
                child: _initializing
                    ? const CircularProgressIndicator()
                    : ready
                        ? AspectRatio(
                            aspectRatio: controller!.value.aspectRatio,
                            child: CameraPreview(controller),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error ?? 'Camera unavailable',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Semantics(
            liveRegion: true,
            label: _scanning ? 'Live detection running' : 'Detection paused',
            child: ExcludeSemantics(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 12,
                      color: _scanning ? Colors.greenAccent : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _scanning ? 'LIVE' : 'PAUSED',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUrgentBanner(String message) {
    return Semantics(
      liveRegion: true,
      label: 'Warning: $message',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.red.shade700,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorText(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.redAccent, fontSize: 15),
      ),
    );
  }

  Widget _buildDescriptionCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 110),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber, width: 1.5),
      ),
      child: SingleChildScrollView(
        child: Semantics(
          label: 'Scene description: $_lastDescription',
          child: ExcludeSemantics(
            child: Text(
              _lastDescription!,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetectionList() {
    if (_detections.isEmpty) {
      return Center(
        child: Text(
          _scanning ? 'Nothing detected yet' : 'Detection paused',
          style: const TextStyle(color: Colors.white70, fontSize: 18),
        ),
      );
    }

    return ListView.builder(
      itemCount: _detections.length,
      itemBuilder: (context, index) {
        final d = _detections[index];
        final isHigh = '${d.priority}' == 'high';

        final details = [
          if (d.position != null) '${d.position}',
          if (d.priority != null) 'Priority: ${d.priority}',
          '${(d.confidence * 100).toStringAsFixed(0)}%',
        ].join(' • ');

        return Card(
          color: isHigh ? Colors.red.shade900 : Colors.grey.shade900,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: Icon(
              isHigh ? Icons.warning_amber_rounded : Icons.visibility,
              color: Colors.white,
              size: 28,
            ),
            title: Text(
              d.className,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              details,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDescribeButton() {
    final enabled = _scanning && _latestFrame != null && !_describingScene;

    return SizedBox(
      width: double.infinity,
      height: 72,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber,
          foregroundColor: Colors.black,
          disabledBackgroundColor: Colors.grey.shade800,
          disabledForegroundColor: Colors.white54,
          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: enabled ? () => _describeAndSpeak(_latestFrame!) : null,
        icon: _describingScene
            ? const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : const Icon(Icons.record_voice_over, size: 30),
        label: Text(
          _describingScene ? 'Describing...' : 'Describe Scene',
        ),
      ),
    );
  }

  Widget _buildAssistButton() {
    return Semantics(
      hint: 'Reads text and non-urgent alerts aloud. '
          'Urgent warnings are always spoken.',
      child: SizedBox(
        height: 60,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _aiAssistEnabled ? Colors.green.shade700 : Colors.grey.shade800,
            foregroundColor: Colors.white,
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _initializing ? null : _toggleAiAssist,
          icon: Icon(
            _aiAssistEnabled ? Icons.volume_up : Icons.volume_off,
          ),
          label: Text(_aiAssistEnabled ? 'AI Assist: ON' : 'AI Assist: OFF'),
        ),
      ),
    );
  }

  Widget _buildScanButton() {
    return SizedBox(
      height: 60,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white54, width: 1.5),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: _initializing
            ? null
            : (_scanning ? _stopScanning : _startScanning),
        icon: Icon(_scanning ? Icons.pause : Icons.play_arrow),
        label: Text(_scanning ? 'Pause' : 'Start'),
      ),
    );
  }
}