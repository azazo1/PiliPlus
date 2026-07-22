abstract final class Em {
  static final _exp = RegExp('<[^>]*>([^<]*)</[^>]*>');
  static final _htmlRegExp = RegExp(
    r'&(#(?:\d+|x[\da-fA-F]+)|lt|gt|quot|apos|nbsp|amp);',
  );

  static String regCate(String origin) {
    Iterable<Match> matches = _exp.allMatches(origin);
    return decodeHtml(matches.lastOrNull?.group(1) ?? origin);
  }

  static String decodeHtml(String origin) {
    String result = origin;
    while (true) {
      final decoded = result.replaceAllMapped(_htmlRegExp, _decodeHtmlEntity);
      if (decoded == result) {
        return decoded;
      }
      result = decoded;
    }
  }

  static String parseHtml(String str) => decodeHtml(str);

  static List<({bool isEm, String text})> regTitle(String origin) {
    List<({bool isEm, String text})> res = [];
    origin.splitMapJoin(
      _exp,
      onMatch: (Match match) {
        res.add((isEm: true, text: parseHtml(match[1] ?? match[0]!)));
        return '';
      },
      onNonMatch: (String str) {
        if (str != '') {
          res.add((
            isEm: false,
            text: decodeHtml(str),
          ));
        }
        return '';
      },
    );
    return res;
  }

  static String _decodeHtmlEntity(Match m) {
    final entity = m.group(1)!;
    final codePoint = switch (entity) {
      'lt' => 60,
      'gt' => 62,
      'quot' => 34,
      'apos' => 39,
      'nbsp' => 32,
      'amp' => 38,
      _ when entity.startsWith('#x') =>
        int.tryParse(entity.substring(2), radix: 16),
      _ when entity.startsWith('#') => int.tryParse(entity.substring(1)),
      _ => null,
    };
    return codePoint == null ? m.group(0)! : String.fromCharCode(codePoint);
  }
}
