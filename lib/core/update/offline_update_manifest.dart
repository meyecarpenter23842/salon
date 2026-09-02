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

  factory OfflineUpdateManifest.fromJson(Map<String, Object?> json) {
    return OfflineUpdateManifest(
      latestVersion: json['latestVersion']?.toString() ?? '',
      minimumSupportedVersion:
          json['minimumSupportedVersion']?.toString() ?? '',
      required: json['required'] == true,
      title: json['title']?.toString() ?? 'Có bản cập nhật mới',
      message: json['message']?.toString() ?? '',
      notes: (json['notes'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      downloadPath: json['downloadPath']?.toString() ?? '',
      releaseNotesPath: json['releaseNotesPath']?.toString() ?? '',
      publishedAt: json['publishedAt']?.toString() ?? '',
      sha256: json['sha256']?.toString() ?? '',
    );
  }
}
