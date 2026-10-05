import 'lan_contract.dart';

enum SalonReadKind { customers, invoices, appointments }

/// Bounded presentation projection: no database rows or private machine fields.
class SalonReadRecord {
  const SalonReadRecord({required this.id, required this.title,
    required this.subtitle, this.fields = const {}});
  final String id;
  final String title;
  final String subtitle;
  final Map<String, String> fields;
  Map<String, Object> toJson() => {
    'id': id, 'title': title, 'subtitle': subtitle, 'fields': fields,
  };
  factory SalonReadRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final subtitle = json['subtitle'];
    final fields = json['fields'];
    if (id is! String || title is! String || subtitle is! String ||
        fields is! Map || fields.length > 250 ||
        fields.entries.any((e) => e.key is! String || e.value is! String)) {
      throw const FormatException('Invalid record');
    }
    return SalonReadRecord(id: id, title: title, subtitle: subtitle,
      fields: Map<String, String>.from(fields));
  }
}

class SalonReadQuery {
  SalonReadQuery(this.kind, {this.offset = 0, this.limit = 25,
    this.query = '', this.day, this.id}) {
    if (offset < 0 || offset > 100000 || limit < 1 || limit > 25 ||
        query.length > 80 || (query.isNotEmpty && kind != SalonReadKind.customers) ||
        (day != null && kind != SalonReadKind.appointments) ||
        (id != null && (offset != 0 || query.isNotEmpty || day != null))) {
      throw const FormatException('Invalid read query');
    }
    if (id != null) LanContract.validateIdentity(id!, 'id');
    if (day != null) {
      final parsed = DateTime.tryParse(day!);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day!) ||
          parsed == null || salonDay(parsed) != day) {
        throw const FormatException('Invalid salon day');
      }
    }
  }
  final SalonReadKind kind;
  final int offset;
  final int limit;
  final String query;
  final String? day;
  final String? id;
  Map<String, String> get parameters => {
    if (id != null) 'id': id!,
    if (id == null) 'offset': '$offset',
    if (id == null) 'limit': '$limit',
    if (query.isNotEmpty) 'q': query,
    if (day != null) 'day': day!,
  };
  factory SalonReadQuery.fromUri(SalonReadKind kind, Uri uri) {
    final p = uri.queryParametersAll;
    if (p.keys.any((key) => !['id', 'offset', 'limit', 'q', 'day'].contains(key)) ||
        p.values.any((values) => values.length != 1)) {
      throw const FormatException('Unknown or repeated query');
    }
    int integer(String key, int fallback) {
      if (!p.containsKey(key)) return fallback;
      final value = p[key]!.single;
      if (!RegExp(r'^\d{1,6}$').hasMatch(value)) {
        throw const FormatException('Invalid page');
      }
      return int.parse(value);
    }
    return SalonReadQuery(kind, offset: integer('offset', 0),
      limit: integer('limit', 25), query: p['q']?.single.trim() ?? '',
      day: p['day']?.single, id: p['id']?.single);
  }
}

String salonDay(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class SalonReadPage {
  const SalonReadPage({required this.records, required this.salonDate,
    this.nextOffset});
  final List<SalonReadRecord> records;
  final String salonDate;
  final int? nextOffset;
  Map<String, Object?> toJson() => {
    'apiVersion': 1, 'records': records.map((r) => r.toJson()).toList(),
    'salonDate': salonDate, 'nextOffset': nextOffset,
  };
  factory SalonReadPage.fromJson(Map<String, dynamic> json) {
    final rows = json['records'];
    if (json['apiVersion'] != 1 || rows is! List || rows.length > 25 ||
        json['salonDate'] is! String ||
        (json['nextOffset'] != null && json['nextOffset'] is! int)) {
      throw const FormatException('Invalid read response');
    }
    return SalonReadPage(records: rows.map((r) =>
      SalonReadRecord.fromJson(Map<String, dynamic>.from(r as Map))).toList(),
      salonDate: json['salonDate'] as String, nextOffset: json['nextOffset'] as int?);
  }
}

abstract interface class SalonReadRepository {
  Future<SalonReadPage> read(SalonReadQuery query);
}
