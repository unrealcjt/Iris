import 'dart:convert';

class JmEntry {
  final int entSeq;
  final List<Written> kanji;
  final List<Written> kana;

  JmEntry({required this.entSeq, required this.kanji, required this.kana});

  factory JmEntry.fromMap(Map<String, dynamic> map) {
    return JmEntry(
      entSeq: map['ent_seq'],
      // 处理 JSON 字符串，如果是 null 则返回空数组
      kanji: map['kanji'] != null
          ? (jsonDecode(map['kanji']) as List).map((i) => Written.fromJson(i)).toList()
          : [],
      kana: (jsonDecode(map['kana']) as List).map((i) => Written.fromJson(i)).toList(),
    );
  }
}

class JmSense {
  final int id;
  final int entSeq;
  final int sortOrder;
  final String? lang;
  final String? note;
  final List<String> glosses;
  final List<String> pos;
  final List<String>? fields;
  final List<String>? tags;
  final List<JmRef>? refs;

  JmSense({
    required this.id, required this.entSeq, required this.sortOrder,
    this.lang, this.note, required this.glosses, required this.pos,
    this.fields, this.tags, this.refs,
  });

  factory JmSense.fromMap(Map<String, dynamic> map) {
    return JmSense(
      id: map['id'],
      entSeq: map['ent_seq'],
      sortOrder: map['sort_order'],
      lang: map['lang'],
      note: map['note'],
      glosses: List<String>.from(jsonDecode(map['glosses'])),
      pos: List<String>.from(jsonDecode(map['pos'])),
      fields: map['fields'] != null ? List<String>.from(jsonDecode(map['fields'])) : null,
      tags: map['tags'] != null ? List<String>.from(jsonDecode(map['tags'])) : null,
      refs: map['refs'] != null
          ? (jsonDecode(map['refs']) as List).map((i) => JmRef.fromJson(i)).toList()
          : null,
    );
  }
}

class Written {
  final String written;
  final List<String>? tags;
  final List<String>? restr;

  Written({required this.written, this.tags, this.restr});

  factory Written.fromJson(Map<String, dynamic> json) {
    return Written(
      written: json['written'],
      tags: json['tags'] != null ? List<String>.from(json['tags']) : null,
      restr: json['restr'] != null ? List<String>.from(json['restr']) : null,
    );
  }
}

class JmRef {
  final String type; // 'see' | 'ant'
  final int entSeq;
  final int senseId;
  final String written;

  JmRef({required this.type, required this.entSeq, required this.senseId, required this.written});

  factory JmRef.fromJson(Map<String, dynamic> json) => JmRef(
    type: json['type'],
    entSeq: json['ent_seq'],
    senseId: json['sense_id'],
    written: json['written'],
  );
}

class KanjiCharacter {
  final String literal;
  final Map<String, dynamic> codepoint;
  final Map<String, dynamic> radical;
  final ReadingMeaning? readingMeaning;
  final Map<String, dynamic>? misc;

  KanjiCharacter({
    required this.literal,
    required this.codepoint,
    required this.radical,
    this.readingMeaning,
    this.misc,
  });

  factory KanjiCharacter.fromMap(Map<String, dynamic> map) {
    return KanjiCharacter(
      literal: map['literal'],
      codepoint: jsonDecode(map['codepoint']),
      radical: jsonDecode(map['radical']),
      readingMeaning: map['reading_meaning'] != null
          ? ReadingMeaning.fromJson(jsonDecode(map['reading_meaning']))
          : null,
      misc: map['misc'] != null ? jsonDecode(map['misc']) : null,
    );
  }
}

class ReadingMeaning {
  final List<Reading> readings;
  final List<Meaning> meanings;
  final List<String>? nanori;

  ReadingMeaning({required this.readings, required this.meanings, this.nanori});

  factory ReadingMeaning.fromJson(Map<String, dynamic> json) {
    var rmGroups = json['rmgroups'];
    return ReadingMeaning(
      readings: (rmGroups['readings'] as List).map((i) => Reading.fromJson(i)).toList(),
      meanings: (rmGroups['meanings'] as List).map((i) => Meaning.fromJson(i)).toList(),
      nanori: json['nanori'] != null ? List<String>.from(json['nanori']) : null,
    );
  }
}

class Reading {
  final String type; // 'ja_on', 'ja_kun', etc.
  final String value;
  Reading({required this.type, required this.value});
  factory Reading.fromJson(Map<String, dynamic> json) => Reading(type: json['r_type'], value: json['value']);
}

class Meaning {
  final String? lang;
  final String value;
  Meaning({this.lang, required this.value});
  factory Meaning.fromJson(Map<String, dynamic> json) => Meaning(lang: json['m_lang'], value: json['value']);
}