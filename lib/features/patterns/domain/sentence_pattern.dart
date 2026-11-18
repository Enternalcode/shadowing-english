/// A reusable spoken-English sentence pattern extracted from a real
/// sentence, e.g. "accuse sb of doing sth" — saved with its source
/// sentence and progressively generated everyday-spoken examples.
class SentencePattern {
  const SentencePattern({
    required this.id,
    required this.pattern,
    required this.explanation,
    required this.sourceSentence,
    this.episodeId,
    this.courseTitle,
    this.slots = '',
    this.examples = const <String>[],
    required this.createdAt,
  });

  factory SentencePattern.fromJson(Map<String, Object?> json) {
    return SentencePattern(
      id: json['id']! as String,
      pattern: json['pattern']! as String,
      explanation: json['explanation']! as String,
      sourceSentence: json['sourceSentence']! as String,
      episodeId: json['episodeId'] as String?,
      courseTitle: json['courseTitle'] as String?,
      slots: json['slots'] as String? ?? '',
      examples: (json['examples'] as List<Object?>? ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
      createdAt: json['createdAt']! as String,
    );
  }

  final String id;
  final String pattern;
  final String explanation;
  final String sourceSentence;
  final String? episodeId;
  final String? courseTitle;
  final String slots;
  final List<String> examples;
  final String createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'pattern': pattern,
    'explanation': explanation,
    'sourceSentence': sourceSentence,
    'episodeId': episodeId,
    'courseTitle': courseTitle,
    'slots': slots,
    'examples': examples,
    'createdAt': createdAt,
  };

  SentencePattern copyWith({
    String? pattern,
    String? explanation,
    String? slots,
    List<String>? examples,
  }) {
    return SentencePattern(
      id: id,
      pattern: pattern ?? this.pattern,
      explanation: explanation ?? this.explanation,
      sourceSentence: sourceSentence,
      episodeId: episodeId,
      courseTitle: courseTitle,
      slots: slots ?? this.slots,
      examples: examples ?? this.examples,
      createdAt: createdAt,
    );
  }
}
