/// Rule-based English sentence splitter for pasted social-media / article
/// text. Splits on blank lines and sentence-ending punctuation while
/// protecting abbreviations, initials, decimals, ellipses and domain dots.
/// The result is meant to be reviewed/edited before audio generation.
const String _placeholder = '';

const List<String> _abbreviations = <String>[
  'Mr.',
  'Mrs.',
  'Ms.',
  'Dr.',
  'St.',
  'Mt.',
  'Jr.',
  'Sr.',
  'Prof.',
  'Capt.',
  'Col.',
  'Gen.',
  'Gov.',
  'Lt.',
  'Rep.',
  'Sen.',
  'Sgt.',
  'Adm.',
  'Rev.',
  'Hon.',
  'Pres.',
  'vs.',
  'etc.',
  'e.g.',
  'i.e.',
  'viz.',
  'cf.',
  'al.',
  'No.',
  'Vol.',
  'Fig.',
  'Eq.',
  'Inc.',
  'Ltd.',
  'Corp.',
  'Co.',
  'Assn.',
  'Jan.',
  'Feb.',
  'Mar.',
  'Apr.',
  'Jun.',
  'Jul.',
  'Aug.',
  'Sep.',
  'Sept.',
  'Oct.',
  'Nov.',
  'Dec.',
  'approx.',
  'dept.',
  'est.',
  'min.',
  'max.',
  'Mon.',
  'Tue.',
  'Tues.',
  'Wed.',
  'Thu.',
  'Thur.',
  'Thurs.',
  'Fri.',
  'Sat.',
  'Sun.',
  'a.m.',
  'p.m.',
  'A.M.',
  'P.M.',
];

final RegExp _boundary = RegExp(r'''[.!?…]+["'«»"“”'‘’)\]]*(?=\s|$)''');
final RegExp _initial = RegExp(r'\b([A-Za-z])\.');
final RegExp _decimal = RegExp(r'(\d)\.(\d)');
final RegExp _domainDot = RegExp(
  r'([a-z])\.(com|org|net|io|ai|dev|app|me|cn|us|uk|co|tv|fm|gg)\b',
  caseSensitive: false,
);
final RegExp _hasWordChar = RegExp('[A-Za-z0-9]');

List<String> splitSentences(String raw) {
  final String text = raw
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim();
  if (text.isEmpty) return const <String>[];

  final String protectedText = _protect(text);
  final List<String> fragments = <String>[];
  for (final String para in protectedText.split(RegExp(r'\n+'))) {
    int start = 0;
    for (final RegExpMatch m in _boundary.allMatches(para)) {
      fragments.add(para.substring(start, m.end));
      start = m.end;
    }
    if (start < para.length) {
      fragments.add(para.substring(start));
    }
  }

  final List<String> restored = fragments
      .map((String s) => _restore(s).trim())
      .where((String s) => s.isNotEmpty)
      .toList();

  // Merge junk fragments (lone quotes/parens, 1-2 char stubs) into the
  // previous sentence so every kept line is speakable.
  final List<String> merged = <String>[];
  for (final String s in restored) {
    final bool junk = s.length < 3 || !_hasWordChar.hasMatch(s);
    if (junk && merged.isNotEmpty) {
      merged[merged.length - 1] = '${merged.last} $s';
    } else {
      merged.add(s);
    }
  }
  return merged;
}

String _protect(String s) {
  String out = s;
  for (final String a in _abbreviations) {
    out = out.replaceAll(a, a.replaceAll('.', _placeholder));
  }
  out = out.replaceAllMapped(_initial, (Match m) => '${m[1]}$_placeholder');
  out = out.replaceAllMapped(
    _decimal,
    (Match m) => '${m[1]}$_placeholder${m[2]}',
  );
  out = out.replaceAllMapped(
    _domainDot,
    (Match m) => '${m[1]}$_placeholder${m[2]}',
  );
  return out;
}

String _restore(String s) => s.replaceAll(_placeholder, '.');
