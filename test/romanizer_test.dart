import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/lyrics_translation.dart';
import 'package:riflay/services/romanizer.dart';
import 'package:riflay/ui/debug_switches.dart';

void main() {
  test('Korean in Revised Romanization, with the sound changes a singer makes', () {
    for (final (hangul, roman) in const [
      ('사랑해요 너를', 'saranghaeyo neoreul'), // ㄹ between vowels is r; the final ㄹ moves onto 을
      ('오늘 밤 같이 있어줘', 'oneul bam gachi isseojwo'), // 같이 palatalizes; ㅆ carries over
      ('감사합니다', 'gamsahamnida'), // ㅂ before ㄴ turns m
      ('좋다', 'jota'), // ㅎ breathes into ㄷ
      ('별로', 'byeollo'),
      ('한국어 노래', 'hangugeo norae'),
      ('읽어', 'ilgeo'), // a double final: one stays, one moves
      ('사랑해 baby', 'saranghae baby'),
    ]) {
      expect(Romanizer.local(hangul), roman, reason: hangul);
    }
  });

  test('kana in Hepburn: small kana, the small tsu, the long-vowel mark, n before a vowel', () {
    for (final (kana, roman) in const [
      ('ありがとう', 'arigatou'),
      ('きゃりーぱみゅぱみゅ', 'kyariipamyupamyu'),
      ('ちょっと', 'chotto'),
      ('マッチ', 'matchi'),
      ('こんにちは', 'konnichiha'),
      ('きんえん', "kin'en"),
      ('シャンプー', 'shanpuu'),
    ]) {
      expect(Romanizer.local(kana), roman, reason: kana);
    }
  });

  test('Cyrillic and Greek letter for letter, capitals kept as one capital', () {
    expect(Romanizer.local('Я тебя люблю'), 'Ya tebya lyublyu');
    expect(Romanizer.local('Щука и ёж'), 'Shchuka i yozh');
    expect(Romanizer.local('Привіт, Київ'), 'Privit, Kiyiv');
    expect(Romanizer.local('Σ\'αγαπώ'), "S'agapo");
  });

  test('scripts that need a dictionary are left to Google, which is tidied', () {
    expect(Romanizer.local('君の名は'), isNull, reason: 'kanji');
    expect(Romanizer.local('我爱你'), isNull);
    expect(Romanizer.local('ฉันรักเธอ'), isNull);
    expect(Romanizer.local('just English'), isNull, reason: 'nothing to do');
    expect(Romanizer.clean('C̄hạn rạk ṭhex', 'ฉันรักเธอ'), 'Chan rak thex');
    expect(Romanizer.clean('Maiṁ tumasē pyāra karatā hūm̐', 'मैं तुमसे प्यार करता हूँ'), 'Maim tumase pyara karata hum');
    expect(Romanizer.clean('Wǒ ài nǐ', '我爱你'), 'Wǒ ài nǐ', reason: 'pinyin keeps its tones');
    expect(Romanizer.clean('YA tebya', 'Я тебя'), 'Ya tebya');
  });

  test('lyrics prefer the local romanization, and the off switch keeps Google\'s', () {
    expect(LyricsTranslation.romanizedOf('사랑해', 'salanghae'), 'saranghae');
    expect(LyricsTranslation.romanizedOf('ฉันรักเธอ', 'C̄hạn rạk ṭhex'), 'Chan rak thex');
    DebugSwitches.googleRomanization = true;
    addTearDown(() => DebugSwitches.googleRomanization = false);
    expect(LyricsTranslation.romanizedOf('사랑해', 'salanghae'), 'salanghae');
  });
}
