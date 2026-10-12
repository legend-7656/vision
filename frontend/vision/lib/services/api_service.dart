
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/detection.dart';

class DetectionResponse {
  final List<Detection> detections;
  final List<String> alerts;

  DetectionResponse({
    required this.detections,
    required this.alerts,
  });
}

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';

  Future<DetectionResponse> detectObjects(XFile imageFile) async {
    final uri = Uri.parse('$baseUrl/detect');

    final request = http.MultipartRequest('POST', uri);
    final bytes = await imageFile.readAsBytes();

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: imageFile.name,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception(
        'Detection request failed: ${response.statusCode}',
      );
    }

    final data =
        jsonDecode(response.body) as Map<String, dynamic>;

    final detectionsJson = data['detections'] as List? ?? [];
    final alertsJson = data['alerts'] as List? ?? [];

    final detections = detectionsJson
        .map(
          (item) => Detection.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList();

    final alerts = alertsJson
        .map((item) =>
            (item as Map<String, dynamic>)['message'] as String?)
        .whereType<String>()
        .toList();

    return DetectionResponse(
      detections: detections,
      alerts: alerts,
    );
  }
}
