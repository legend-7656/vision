import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/detection.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';

  Future<List<Detection>> detectObjects(XFile imageFile) async {
    final uri = Uri.parse('$baseUrl/detect');

    final request = http.MultipartRequest(
      'POST',
      uri,
    );

    final bytes = await imageFile.readAsBytes();

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: imageFile.name,
      ),
    );

    final streamedResponse = await request.send();

    final response = await http.Response.fromStream(
      streamedResponse,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Detection request failed: ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body);

    final detectionsJson = data['detections'] as List;

    return detectionsJson
        .map(
          (item) => Detection.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList();
  }
}