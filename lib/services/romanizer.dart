/// Lyrics' Pronunciation, worked out here for the scripts that follow rules: Korean (Revised Romanization, with
/// the sound changes a singer makes), Japanese kana (Hepburn), Cyrillic and Greek. It needs no network, so it
/// still answers when Google's romanization is blocked, and it reads as fans write it ("saranghae", not Google's
/// "salanghae"). Chinese characters and kanji need a dictionary: those stay Google's ([clean] tidies them).
abstract final class Romanizer {
  static final _hangul = RegExp(r'[가-힣]');
  static final _kana = RegExp(r'[぀-ヿ]');
  static final _han = RegExp(r'\p{Script=Han}', unicode: true);
  static final _cyrillic = RegExp(r'\p{Script=Cyrillic}', unicode: true);
  static final _greek = RegExp(r'\p{Script=Greek}', unicode: true);
  static final _letter = RegExp(r'\p{L}', unicode: true);
  static final _latin = RegExp(r'\p{Script=Latin}', unicode: true);

  /// [line] romanized here, or null when one of its scripts needs Google (Chinese characters, kanji, Thai…).
  static String? local(String line) {
    for (final m in _letter.allMatches(line)) {
      final c = m.group(0)!;
      if (_latin.hasMatch(c) ||
          _hangul.hasMatch(c) ||
          _kana.hasMatch(c) ||
          _cyrillic.hasMatch(c) ||
          _greek.hasMatch(c)) {
        continue;
      }
      return null;
    }
    if (_han.hasMatch(line)) return null;
    var out = line;
    if (_hangul.hasMatch(out)) out = hangul(out);
    if (_kana.hasMatch(out)) out = kana(out);
    if (_cyrillic.hasMatch(out)) out = cyrillic(out);
    if (_greek.hasMatch(out)) out = greek(out);
    return out == line ? null : out;
  }

  /// Google's romanization of [line] made readable: the scholarly marks it puts on Thai, Hindi or Arabic
  /// ("C̄hạn rạk") dropped, and a word it wrote in capitals for one capital letter ("YA tebya") in title case.
  /// Chinese keeps its pinyin tones.
  static String clean(String romanized, String line) {
    var out = romanized;
    if (!_han.hasMatch(line)) {
      out = _stripMarks(out);
    }
    if (line.toUpperCase() != line) {
      out = out.replaceAllMapped(
        RegExp(r'\b([A-Z])([A-Z]+)\b'),
        (m) => m.group(2)!.length <= 2 ? '${m.group(1)}${m.group(2)!.toLowerCase()}' : m.group(0)!,
      );
    }
    return out;
  }

  static String _stripMarks(String s) {
    const pairs = {
      'ā': 'a', 'á': 'a', 'à': 'a', 'ǎ': 'a', 'ạ': 'a', 'ă': 'a', 'â': 'a', 'ä': 'a', //
      'ē': 'e', 'é': 'e', 'è': 'e', 'ě': 'e', 'ẹ': 'e', 'ê': 'e', 'ë': 'e',
      'ī': 'i', 'í': 'i', 'ì': 'i', 'ǐ': 'i', 'ị': 'i', 'î': 'i', 'ï': 'i',
      'ō': 'o', 'ó': 'o', 'ò': 'o', 'ǒ': 'o', 'ọ': 'o', 'ô': 'o', 'ö': 'o',
      'ū': 'u', 'ú': 'u', 'ù': 'u', 'ǔ': 'u', 'ụ': 'u', 'û': 'u', 'ü': 'u', 'ů': 'u',
      'ṭ': 't', 'ḍ': 'd', 'ṇ': 'n', 'ṅ': 'n', 'ñ': 'n', 'ṁ': 'm', 'ṃ': 'm', 'ḥ': 'h', 'ṣ': 's', 'ś': 's',
      'ẓ': 'z', 'ḷ': 'l', 'ṛ': 'r', 'ġ': 'g', 'ḳ': 'k', 'ç': 'c', 'š': 'sh', 'ž': 'zh', 'č': 'ch',
      'Ā': 'A', 'Á': 'A', 'Ē': 'E', 'É': 'E', 'Ī': 'I', 'Í': 'I', 'Ō': 'O', 'Ó': 'O', 'Ū': 'U', 'Ú': 'U',
      'Ṭ': 'T', 'Ḍ': 'D', 'Ṇ': 'N', 'Ś': 'S', 'Ṣ': 'S', 'Ḥ': 'H', 'Š': 'Sh', 'Ž': 'Zh', 'Č': 'Ch',
    };
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      // Combining marks (Thai's tone and vowel signs under ISO 11940) go; letters with marks become plain.
      if ((r >= 0x0300 && r <= 0x036F) || (r >= 0x1AB0 && r <= 0x1AFF) || (r >= 0x1DC0 && r <= 0x1DFF)) continue;
      b.write(pairs[c] ?? c);
    }
    return b.toString();
  }

  // ── Korean: Revised Romanization, with liaison, nasalization, palatalization and aspiration ──

  static const _initials = [
    'g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp', 's', 'ss', '', 'j', 'jj', 'ch', 'k', 't', 'p', 'h', //
  ];
  static const _vowels = [
    'a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa', 'wae', 'oe', 'yo', 'u', 'wo', 'we', 'wi', 'yu', //
    'eu', 'ui', 'i',
  ];

  /// A final consonant before a pause or consonant ([_finalSound]), and what moves onto a following vowel
  /// ([_carry]: what stays as the final, then the new initial).
  static const _finalSound = [
    '', 'k', 'k', 'k', 'n', 'n', 'n', 't', 'l', 'k', 'm', 'l', 'l', 'l', 'p', 'l', 'm', 'p', 'p', 't', 't', //
    'ng', 't', 't', 'k', 't', 'p', 't',
  ];
  static const _carry = [
    ('', ''), ('', 'g'), ('', 'kk'), ('k', 's'), ('', 'n'), ('n', 'j'), ('n', ''), ('', 'd'), ('', 'r'), //
    ('l', 'g'), ('l', 'm'), ('l', 'b'), ('l', 's'), ('l', 't'), ('l', 'p'), ('l', ''), ('', 'm'), ('', 'b'),
    ('p', 's'), ('', 's'), ('', 'ss'), ('ng', ''), ('', 'j'), ('', 'ch'), ('', 'k'), ('', 't'), ('', 'p'), ('', ''),
  ];

  static String hangul(String text) {
    final out = StringBuffer();
    final runes = text.runes.toList();
    (int, int, int)? jamo(int i) {
      if (i >= runes.length) return null;
      final c = runes[i] - 0xAC00;
      if (c < 0 || c > 11171) return null;
      return (c ~/ 588, (c % 588) ~/ 28, c % 28);
    }

    // The initial each syllable is read with, after the one before it has had its say.
    String? nextInitial;
    for (var i = 0; i < runes.length; i++) {
      final s = jamo(i);
      if (s == null) {
        out.writeCharCode(runes[i]);
        nextInitial = null;
        continue;
      }
      final (l, v, t) = s;
      out
        ..write(nextInitial ?? _initials[l])
        ..write(_vowels[v]);
      nextInitial = null;
      if (t == 0) continue;
      final next = jamo(i + 1);
      if (next == null) {
        out.write(_finalSound[t]);
        continue;
      }
      final (nl, nv, _) = next;
      if (nl == 11) {
        // A vowel follows: the consonant moves onto it (ㄷ / ㅌ before 이 soften to j / ch).
        final (stay, move) = _carry[t];
        out.write(stay);
        nextInitial = nv == 20 && (t == 7 || t == 25) ? (t == 7 ? 'j' : 'ch') : move;
      } else if (t == 27 && (nl == 0 || nl == 3 || nl == 12)) {
        // ㅎ before ㄱ / ㄷ / ㅈ breathes into it: 좋다 is "jota".
        nextInitial = const {0: 'k', 3: 't', 12: 'ch'}[nl];
      } else if ((nl == 2 || nl == 6) && const {'k': 'ng', 't': 'n', 'p': 'm'}.containsKey(_finalSound[t])) {
        // Before ㄴ / ㅁ a stop turns nasal: 합니다 is "hamnida".
        out.write(const {'k': 'ng', 't': 'n', 'p': 'm'}[_finalSound[t]]);
      } else if (nl == 5 && _finalSound[t] == 'l') {
        out.write('l');
        nextInitial = 'l';
      } else if (nl == 5 && (_finalSound[t] == 'n')) {
        out.write('l');
        nextInitial = 'l';
      } else {
        out.write(_finalSound[t]);
      }
    }
    return out.toString();
  }

  // ── Japanese kana: Hepburn ──

  static const _kanaTable = {
    'あ': 'a', 'い': 'i', 'う': 'u', 'え': 'e', 'お': 'o', //
    'か': 'ka', 'き': 'ki', 'く': 'ku', 'け': 'ke', 'こ': 'ko', 'が': 'ga', 'ぎ': 'gi', 'ぐ': 'gu', 'げ': 'ge', 'ご': 'go',
    'さ': 'sa', 'し': 'shi', 'す': 'su', 'せ': 'se', 'そ': 'so', 'ざ': 'za', 'じ': 'ji', 'ず': 'zu', 'ぜ': 'ze', 'ぞ': 'zo',
    'た': 'ta', 'ち': 'chi', 'つ': 'tsu', 'て': 'te', 'と': 'to', 'だ': 'da', 'ぢ': 'ji', 'づ': 'zu', 'で': 'de', 'ど': 'do',
    'な': 'na', 'に': 'ni', 'ぬ': 'nu', 'ね': 'ne', 'の': 'no',
    'は': 'ha', 'ひ': 'hi', 'ふ': 'fu', 'へ': 'he', 'ほ': 'ho', 'ば': 'ba', 'び': 'bi', 'ぶ': 'bu', 'べ': 'be', 'ぼ': 'bo',
    'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pu', 'ぺ': 'pe', 'ぽ': 'po',
    'ま': 'ma', 'み': 'mi', 'む': 'mu', 'め': 'me', 'も': 'mo', 'や': 'ya', 'ゆ': 'yu', 'よ': 'yo',
    'ら': 'ra', 'り': 'ri', 'る': 'ru', 'れ': 're', 'ろ': 'ro', 'わ': 'wa', 'ゐ': 'i', 'ゑ': 'e', 'を': 'o', 'ん': 'n',
    'ゔ': 'vu', 'ぁ': 'a', 'ぃ': 'i', 'ぅ': 'u', 'ぇ': 'e', 'ぉ': 'o', 'ゎ': 'wa',
  };
  static const _small = {'ゃ': 'a', 'ゅ': 'u', 'ょ': 'o'};

  static String kana(String text) {
    // Katakana as hiragana (the long-vowel mark stays).
    final chars = [for (final r in text.runes) String.fromCharCode(r >= 0x30A1 && r <= 0x30F6 ? r - 0x60 : r)];
    final out = StringBuffer();
    var double = false;
    String last = '';
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      if (c == 'っ') {
        double = true;
        continue;
      }
      if (c == 'ー') {
        final vowel = RegExp(r'[aeiou]$').firstMatch(last)?.group(0);
        if (vowel != null) out.write(vowel);
        continue;
      }
      var syllable = _kanaTable[c];
      if (syllable == null) {
        out.write(c);
        last = c;
        double = false;
        continue;
      }
      // きゃ kya, しゃ sha, ちゃ cha, じゃ ja…
      if (i + 1 < chars.length && _small.containsKey(chars[i + 1]) && syllable.endsWith('i') && syllable != 'i') {
        final stem = syllable.substring(0, syllable.length - 1);
        syllable = (stem == 'sh' || stem == 'ch' || stem == 'j')
            ? '$stem${_small[chars[i + 1]]}'
            : '${stem}y${_small[chars[i + 1]]}';
        i++;
      }
      if (double) {
        out.write(syllable.startsWith('ch') ? 't' : syllable[0]);
        double = false;
      }
      // ん before a vowel or y: n' (kan'i, not kani).
      if (last == 'n' && RegExp(r'^[aeiouy]').hasMatch(syllable) && out.toString().endsWith('n')) out.write("'");
      out.write(syllable);
      last = syllable;
    }
    return out.toString();
  }

  // ── Cyrillic (Russian, Ukrainian, Belarusian…) and Greek ──

  static const _cyrillicTable = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo', 'ж': 'zh', 'з': 'z', 'и': 'i', //
    'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
    'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch', 'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e',
    'ю': 'yu', 'я': 'ya', 'і': 'i', 'ї': 'yi', 'є': 'ye', 'ґ': 'g', 'ў': 'w', 'ђ': 'dj', 'ј': 'j', 'љ': 'lj',
    'њ': 'nj', 'ћ': 'c', 'џ': 'dz',
  };

  static const _greekTable = {
    'α': 'a', 'β': 'v', 'γ': 'g', 'δ': 'd', 'ε': 'e', 'ζ': 'z', 'η': 'i', 'θ': 'th', 'ι': 'i', 'κ': 'k', //
    'λ': 'l', 'μ': 'm', 'ν': 'n', 'ξ': 'x', 'ο': 'o', 'π': 'p', 'ρ': 'r', 'σ': 's', 'ς': 's', 'τ': 't', 'υ': 'y',
    'φ': 'f', 'χ': 'ch', 'ψ': 'ps', 'ω': 'o', 'ά': 'a', 'έ': 'e', 'ή': 'i', 'ί': 'i', 'ό': 'o', 'ύ': 'y', 'ώ': 'o',
    'ϊ': 'i', 'ϋ': 'y', 'ΐ': 'i', 'ΰ': 'y',
  };

  static String _table(String text, Map<String, String> table) {
    final out = StringBuffer();
    for (final r in text.runes) {
      final c = String.fromCharCode(r);
      final lower = c.toLowerCase();
      final t = table[lower];
      if (t == null) {
        out.write(c);
      } else if (c != lower && t.isNotEmpty) {
        out.write('${t[0].toUpperCase()}${t.substring(1)}');
      } else {
        out.write(t);
      }
    }
    return out.toString();
  }

  static String cyrillic(String text) => _table(text, _cyrillicTable);
  static String greek(String text) => _table(text, _greekTable);
}
