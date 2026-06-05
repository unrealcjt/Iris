class GrammarEntry {
  final int? id;
  final String title;
  final String meaning;
  final String structure;
  final String examples;
  final DateTime addTime;
  final String? note;
  final String? tags;

  GrammarEntry({
    this.id,
    required this.title,
    required this.meaning,
    required this.structure,
    required this.examples,
    required this.addTime,
    this.note,
    this.tags,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'meaning': meaning,
      'structure': structure,
      'examples': examples,
      'addTime': addTime.toIso8601String(),
      'note': note,
      'tags': tags,
    };
  }

  factory GrammarEntry.fromMap(Map<String, dynamic> map) {
    return GrammarEntry(
      id: map['id'],
      title: map['title'],
      meaning: map['meaning'],
      structure: map['structure'],
      examples: map['examples'],
      addTime: DateTime.parse(map['addTime']),
      note: map['note'],
      tags: map['tags'],
    );
  }
}
