import 'dart:convert';

/// One photographed book page paired with its read-aloud script.
class StoryPage {
  const StoryPage({
    required this.imagePath,
    required this.printedText,
    required this.narrationLines,
    required this.tipCn,
  });

  factory StoryPage.fromJson(Map<String, Object?> json) => StoryPage(
    imagePath: json['imagePath'] as String? ?? '',
    printedText: json['printedText'] as String? ?? '',
    narrationLines:
        (json['narrationLines'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toList(growable: false),
    tipCn: json['tipCn'] as String? ?? '',
  );

  /// Absolute path to the photographed page ('' when none was provided).
  final String imagePath;

  /// The text printed on the page (may be empty for wordless pages).
  final String printedText;

  /// 3-5 parentese lines the parent can say while showing this page.
  final List<String> narrationLines;

  /// One short Chinese interaction hint (lift the flap, point, sounds).
  final String tipCn;

  /// Lines worth drilling in a generated practice lesson — the printed
  /// sentence first, then the narration lines.
  List<String> get practiceSentences => <String>[
    if (printedText.trim().isNotEmpty) printedText.trim(),
    ...narrationLines
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty),
  ];

  Map<String, Object?> toJson() => <String, Object?>{
    'imagePath': imagePath,
    'printedText': printedText,
    'narrationLines': narrationLines,
    'tipCn': tipCn,
  };

  StoryPage copyWith({
    String? imagePath,
    String? printedText,
    List<String>? narrationLines,
    String? tipCn,
  }) => StoryPage(
    imagePath: imagePath ?? this.imagePath,
    printedText: printedText ?? this.printedText,
    narrationLines: narrationLines ?? this.narrationLines,
    tipCn: tipCn ?? this.tipCn,
  );
}

/// A saved picture book: ordered pages + read-aloud script.
class StoryRecord {
  const StoryRecord({
    required this.id,
    required this.title,
    required this.childAgeMonths,
    required this.createdAtMs,
    required this.pages,
  });

  factory StoryRecord.fromJson(Map<String, Object?> json) => StoryRecord(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    childAgeMonths: (json['childAgeMonths'] as num?)?.toInt() ?? 14,
    createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    pages: (json['pages'] as List<Object?>? ?? const <Object?>[])
        .whereType<Map<String, Object?>>()
        .map(StoryPage.fromJson)
        .toList(growable: false),
  );

  final String id;
  final String title;

  /// Baby/toddler age in months, used to tune the narration style.
  final int childAgeMonths;
  final int createdAtMs;
  final List<StoryPage> pages;

  /// Every spoken line across the book, page order — input for the
  /// StepFun TTS practice-lesson pipeline.
  List<String> get practiceSentences => <String>[
    for (final StoryPage p in pages) ...p.practiceSentences,
  ];

  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'childAgeMonths': childAgeMonths,
    'createdAtMs': createdAtMs,
    'pages': pages.map((StoryPage p) => p.toJson()).toList(),
  };

  static StoryRecord? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return StoryRecord.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }
}
