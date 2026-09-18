class ScannedDocument {
  final String id;
  final String title;
  final DateTime createdAt;
  final List<String> pagePaths; // private app storage — reliable for display

  const ScannedDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.pagePaths,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'pagePaths': pagePaths,
      };

  factory ScannedDocument.fromJson(Map<String, dynamic> json) => ScannedDocument(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        pagePaths: (json['pagePaths'] as List).cast<String>(),
      );
}