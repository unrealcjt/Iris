class VocabularyEntry {
  final int? id;
  final int entSeq;
  final String word;
  final String kana;
  final DateTime addTime;
  final int familiarity; // 0~5
  final DateTime reviewTime;
  final String? note;
  final String? tags;

  VocabularyEntry({
    this.id,
    required this.entSeq,
    required this.word,
    required this.kana,
    required this.addTime,
    this.familiarity = 0,
    required this.reviewTime,
    this.note,
    this.tags,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entSeq': entSeq,
      'word': word,
      'kana': kana,
      'addTime': addTime.toIso8601String(),
      'familiarity': familiarity,
      'reviewTime': reviewTime.toIso8601String(),
      'note': note,
      'tags': tags,
    };
  }

  factory VocabularyEntry.fromMap(Map<String, dynamic> map) {
    return VocabularyEntry(
      id: map['id'],
      entSeq: map['entSeq'],
      word: map['word'],
      kana: map['kana'],
      addTime: DateTime.parse(map['addTime']),
      familiarity: map['familiarity'],
      reviewTime: DateTime.parse(map['reviewTime']),
      note: map['note'],
      tags: map['tags'],
    );
  }
}
