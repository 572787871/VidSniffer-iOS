class LocalVideo {
  const LocalVideo({
    required this.path,
    required this.name,
    required this.size,
    required this.modifiedAt,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modifiedAt;
}
