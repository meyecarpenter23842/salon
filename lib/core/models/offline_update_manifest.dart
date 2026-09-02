class OfflineUpdateManifest {
  const OfflineUpdateManifest({
    required this.latestVersion,
    required this.minimumSupportedVersion,
    required this.required,
    required this.title,
    required this.message,
    required this.notes,
    required this.downloadPath,
    required this.releaseNotesPath,
    required this.publishedAt,
    required this.sha256,
  });

  final String latestVersion;
  final String minimumSupportedVersion;
  final bool required;
  final String title;
  final String message;
  final List<String> notes;
  final String downloadPath;
  final String releaseNotesPath;
  final String publishedAt;
  final String sha256;

  factory OfflineUpdateManifest.fromJson(Map<String, dynamic> json) {
    return OfflineUpdateManifest(
      latestVersion: (json['latestVersion'] ?? '').toString().trim(),
      minimumSupportedVersion: (json['minimumSupportedVersion'] ?? '')
          .toString()
          .trim(),
      required: json['required'] == true,
      title: (json['title'] ?? '').toString().trim(),
      message: (json['message'] ?? '').toString().trim(),
      notes: (json['notes'] as List<dynamic>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      downloadPath: (json['downloadPath'] ?? '').toString().trim(),
      releaseNotesPath: (json['releaseNotesPath'] ?? '').toString().trim(),
      publishedAt: (json['publishedAt'] ?? '').toString().trim(),
      sha256: (json['sha256'] ?? '').toString().trim(),
    );
  }
}
