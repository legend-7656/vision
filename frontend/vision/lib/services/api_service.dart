import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/detection.dart';

class DetectionResponse {
  final List<Detection> detections;
  final List<String> alerts;
  final List<String> urgentAlerts;
  final List<String> recognizedText;

  DetectionResponse({
    required this.detections,
    required this.alerts,
    required this.urgentAlerts,
    required this.recognizedText,
  });
}

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';

  Future<DetectionResponse> detectObjects(XFile imageFile, {bool ocr = false}) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/detect?ocr=$ocr'),
    );

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        await imageFile.readAsBytes(),
        filename: imageFile.name,
      ),
    );

    final streamedResponse = await request.send().timeout(const Duration(seconds: 40));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception(
        'Detection request failed: ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    final detectionsJson = data['detections'] as List? ?? [];
    final alertsJson = data['alerts'] as List? ?? [];
    final textJson = data['recognized_text'] as List? ?? [];

    final detections = detectionsJson
        .map(
          (item) => Detection.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList();

    final alerts = <String>[];
    final urgentAlerts = <String>[];

    for (final item in alertsJson) {
      final alert = item as Map<String, dynamic>;
      final message = alert['message'] as String?;
      final priority = alert['priority'] as String?;

      if (message != null && message.isNotEmpty) {
        alerts.add(message);

        if (priority == 'high') {
          urgentAlerts.add(message);
        }
      }
    }

    final recognizedText = textJson
        .map(
          (item) =>
              (item as Map<String, dynamic>)['text'] as String?,
        )
        .whereType<String>()
        .map((text) => text.trim())
        .where((text) => text.isNotEmpty)
        .toSet()
        .toList();

    return DetectionResponse(
      detections: detections,
      alerts: alerts,
      urgentAlerts: urgentAlerts,
      recognizedText: recognizedText,
    );
  }

  Future<String> describeScene(XFile imageFile) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/describe'),
    );

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        await imageFile.readAsBytes(),
        filename: imageFile.name,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception(
        'Scene description failed: ${response.statusCode}${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['scene_description'] as String? ?? '').trim();
  }
}