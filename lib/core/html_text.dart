/// Minimal, dependency-free HTML → text conversion for backend-authored
/// content (PRD F2 `content.get_page` `body_html`, notification bodies).
///
/// This is NOT an HTML renderer: it turns the small tag vocabulary the
/// backend actually produces (`<p>`, `<br>`, `<li>`, `<div>`, headings)
/// into plain-text blocks and strips everything else, so the app renders
/// server content without an HTML package (binding no-new-packages rule).
library;

final RegExp _brTag = RegExp(r'<br\s*/?>', caseSensitive: false);
final RegExp _liOpenTag = RegExp(r'<li[^>]*>', caseSensitive: false);
final RegExp _blockCloseTag = RegExp(
  r'</\s*(p|div|li|ul|ol|h[1-6]|tr|table|blockquote)\s*>',
  caseSensitive: false,
);
final RegExp _anyTag = RegExp(r'<[^>]*>');
final RegExp _numericEntity = RegExp(r'&#(x?)([0-9a-fA-F]+);');

const Map<String, String> _namedEntities = {
  '&nbsp;': ' ',
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
  '&#39;': "'",
};

/// Splits [html] into display blocks: one entry per paragraph / list item /
/// heading, `<li>` items prefixed with a bullet. Blank blocks are dropped.
List<String> htmlToBlocks(String html) {
  var text = html
      .replaceAll(_brTag, '\n')
      .replaceAll(_liOpenTag, '\n• ')
      .replaceAll(_blockCloseTag, '\n')
      .replaceAll(_anyTag, '');
  text = _decodeEntities(text);
  return [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
}

/// Flattens [html] to a single plain-text string (blocks joined with
/// newlines) — used where content renders as one `Text` (e.g. notification
/// bodies).
String htmlToPlainText(String html) => htmlToBlocks(html).join('\n');

String _decodeEntities(String text) {
  var out = text;
  _namedEntities.forEach((entity, replacement) {
    out = out.replaceAll(entity, replacement);
  });
  return out.replaceAllMapped(_numericEntity, (match) {
    final code = int.tryParse(
      match.group(2)!,
      radix: match.group(1)!.isEmpty ? 10 : 16,
    );
    // Range-guard: String.fromCharCode throws above 0x10FFFF, and a typo'd
    // entity in admin content must not crash the page build.
    return (code == null || code < 0 || code > 0x10FFFF)
        ? match.group(0)!
        : String.fromCharCode(code);
  });
}
