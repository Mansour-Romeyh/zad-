import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/html_text.dart';

void main() {
  group('htmlToBlocks', () {
    test('paragraphs become blocks', () {
      expect(
        htmlToBlocks('<p>First</p><p>Second</p>'),
        ['First', 'Second'],
      );
    });

    test('<br> splits within a paragraph', () {
      expect(
        htmlToBlocks('<p>Line one<br>Line two<br/>Line three</p>'),
        ['Line one', 'Line two', 'Line three'],
      );
    });

    test('<li> items get a bullet prefix', () {
      expect(
        htmlToBlocks('<ul><li>One</li><li class="x">Two</li></ul>'),
        ['• One', '• Two'],
      );
    });

    test('headings, divs and inline tags are handled', () {
      expect(
        htmlToBlocks('<h2>Title</h2><div>Body with <strong>bold</strong> text</div>'),
        ['Title', 'Body with bold text'],
      );
    });

    test('entities are decoded', () {
      expect(
        htmlToBlocks('<p>Fish &amp; Chips &lt;fresh&gt;&nbsp;&#39;daily&#39; &#x2713;</p>'),
        ["Fish & Chips <fresh> 'daily' ✓"],
      );
    });

    test('Arabic content survives untouched', () {
      expect(
        htmlToBlocks('<p>نجمع بياناتك لتحسين الخدمة.</p><li>العنوان</li>'),
        ['نجمع بياناتك لتحسين الخدمة.', '• العنوان'],
      );
    });

    test('plain text without tags passes through as one block', () {
      expect(htmlToBlocks('سيصلك الطلب قريباً'), ['سيصلك الطلب قريباً']);
    });

    test('out-of-range numeric entities pass through instead of throwing', () {
      // String.fromCharCode throws above 0x10FFFF — a typo'd entity in
      // admin content must never crash the page build.
      expect(htmlToBlocks('<p>&#x110000; و &#999999999; و &#x1F600;</p>'),
          ['&#x110000; و &#999999999; و 😀']);
    });

    test('empty/whitespace input yields no blocks', () {
      expect(htmlToBlocks(''), isEmpty);
      expect(htmlToBlocks('<p>  </p><br>'), isEmpty);
    });
  });

  group('htmlToPlainText', () {
    test('joins blocks with newlines', () {
      expect(
        htmlToPlainText('<p>تم تعديل طلبك</p><p>الطماطم: 1 → 0.5</p>'),
        'تم تعديل طلبك\nالطماطم: 1 → 0.5',
      );
    });
  });
}
