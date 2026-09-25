class Detection {
  final int classId;
  final String className;
  final double confidence;
  final List<double> bbox;

  Detection({
    required this.classId,
    required this.className,
    required this.confidence,
    required this.bbox,
  });

  factory Detection.fromJson(Map<String, dynamic> json) {
    return Detection(
      classId: json['class_id'],
      className: json['class_name'],
      confidence: (json['confidence'] as num).toDouble(),
      bbox: List<double>.from(
        (json['bbox'] as List).map(
          (value) => (value as num).toDouble(),
        ),
      ),
    );
  }
}