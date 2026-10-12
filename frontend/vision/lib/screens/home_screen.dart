
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
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

  CameraController? _cameraController;
  Timer? _timer;

  List<Detection> _detections = [];
  String? _error;
  bool _initializing = true;
  bool _scanning = false;
  bool _processing = false;

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

  
  
  Future<void> _speakAlert(String message) async {
    final now = DateTime.now();
    final lastSpoken = _spokenAlerts[message];

    // Don't repeat the same alert within 10 seconds.
    if (lastSpoken != null &&  now.difference(lastSpoken).inSeconds < 10) {
    return;
    }

    _spokenAlerts[message] = now;

    await _flutterTts.speak(message);
  }


  
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
      final response = await _apiService.detectObjects(image);

      if (!mounted) return;

      setState(() {
        _detections = response.detections;
        _error = null;
      });
      if (response.alerts.isNotEmpty && _scanning) {
      await _speakAlert(response.alerts.first);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Detection failed: $e';
      });
    } finally {
      _processing = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _flutterTts.setLanguage("en-US");
    _initializeCamera();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ContextAid'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Center(
                child: _initializing
                    ? const CircularProgressIndicator()
                    : controller != null &&
                            controller.value.isInitialized
                        ? AspectRatio(
                            aspectRatio:
                                controller.value.aspectRatio,
                            child: CameraPreview(controller),
                          )
                        : Text(
                            _error ?? 'Camera unavailable',
                          ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _scanning
                  ? (_processing
                      ? 'Analyzing scene...'
                      : 'Live detection running')
                  : 'Detection paused',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            Expanded(
              flex: 2,
              child: _detections.isEmpty
                  ? const Center(
                      child: Text('No objects detected yet'),
                    )
                  : ListView.builder(
                      itemCount: _detections.length,
                      itemBuilder: (context, index) {
                        final d = _detections[index];

                        return ListTile(
                          leading: const Icon(Icons.visibility),
                          title: Text(d.className),
                          subtitle: Text(
                            'Confidence: '
                            '${(d.confidence * 100).toStringAsFixed(1)}%'
                            '${d.priority == null ? "" : "\nPriority: ${d.priority}"}'
                            '${d.position == null ? "" : " • ${d.position}"}'
                            '${d.trackId == null ? "" : "\nTrack ID: ${d.trackId}"}',
                          ),
                        );
                      },
                    ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _initializing
                    ? null
                    : (_scanning
                        ? _stopScanning
                        : _startScanning),
                icon: Icon(
                  _scanning ? Icons.pause : Icons.play_arrow,
                ),
                label: Text(
                  _scanning ? 'Pause Detection' : 'Start Detection',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
