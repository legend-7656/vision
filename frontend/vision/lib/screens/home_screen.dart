import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

import '../models/detection.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  final ApiService _apiService = ApiService();

  XFile? _image;
  List<Detection> _detections = [];

  bool _isLoading = false;
  String? _error;

  Future<void> _captureImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
      );

      if (image == null) {
        return;
      }

      setState(() {
        _image = image;
        _detections = [];
        _error = null;
      });

      await _runDetection(image);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _runDetection(XFile image) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final detections = await _apiService.detectObjects(image);

      setState(() {
        _detections = detections;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ContextAid'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: _image == null
                  ? const Center(
                      child: Text(
                        'Capture an image to begin',
                        style: TextStyle(fontSize: 18),
                      ),
                    )
                  : FutureBuilder<Uint8List>(
                      future: _image!.readAsBytes(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        return Image.memory(
                          snapshot.data!,
                          fit: BoxFit.contain,
                        );
                      },
                    ),
            ),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.red,
                  ),
                ),
              ),

            if (_detections.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _detections.length,
                  itemBuilder: (context, index) {
                    final detection = _detections[index];

                    return ListTile(
                      leading: const Icon(
                        Icons.visibility,
                      ),
                      title: Text(
                        detection.className,
                      ),
                      subtitle: Text(
                        'Confidence: '
                        '${(detection.confidence * 100).toStringAsFixed(1)}%',
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading
                    ? null
                    : _captureImage,
                icon: const Icon(
                  Icons.camera_alt,
                ),
                label: const Text(
                  'Capture & Detect',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}