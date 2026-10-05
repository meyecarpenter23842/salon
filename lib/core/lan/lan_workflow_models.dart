import 'lan_contract.dart';

class LanEditorSnapshot {
  const LanEditorSnapshot({required this.kind, required this.epoch,
    required this.revision, required this.values, this.id});
  final String kind;
  final String epoch;
  final String? id;
  final int revision;
  final Map<String, dynamic> values;
  Map<String, Object?> toJson() => {'apiVersion': 1, 'kind': kind, 'epoch': epoch,
    'id': id, 'revision': revision, 'values': values};
  factory LanEditorSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['apiVersion'] != 1 || !['customer', 'appointment', 'session'].contains(json['kind']) ||
        json['epoch'] is! String || json['revision'] is! int ||
        (json['revision'] as int) < 0 || json['values'] is! Map<String, dynamic> ||
        (json['id'] != null && json['id'] is! String)) {
      throw const FormatException('Invalid editor snapshot');
    }
    LanContract.validateIdentity(json['epoch'] as String, 'epoch');
    if (json['id'] != null) LanContract.validateIdentity(json['id'] as String, 'id');
    return LanEditorSnapshot(kind: json['kind'] as String, epoch: json['epoch'] as String,
      id: json['id'] as String?, revision: json['revision'] as int,
      values: Map<String, dynamic>.from(json['values'] as Map));
  }
}

class LanCatalogItem {
  const LanCatalogItem(this.id, this.title, this.subtitle, {this.stockOnHand, this.lowStockThreshold = 5});
  final String id;
  final String title;
  final String subtitle;
  final int? stockOnHand;
  final int lowStockThreshold;
  bool get isNegativeStock => (stockOnHand ?? 0) < 0;
  String get stockLabel => isNegativeStock ? 'Âm kho' : stockOnHand == 0 ? 'Hết hàng' :
      stockOnHand != null && stockOnHand! <= lowStockThreshold ? 'Sắp hết' : 'Còn hàng';
  Map<String, Object?> toJson() => {'id': id, 'title': title, 'subtitle': subtitle,
    if (stockOnHand != null) 'stockOnHand': stockOnHand,
    if (stockOnHand != null) 'lowStockThreshold': lowStockThreshold};
  factory LanCatalogItem.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String || json['title'] is! String || json['subtitle'] is! String ||
        (json['stockOnHand'] != null && json['stockOnHand'] is! int) ||
        (json['lowStockThreshold'] != null && (json['lowStockThreshold'] is! int || (json['lowStockThreshold'] as int) < 0))) {
      throw const FormatException('Invalid catalog item');
    }
    return LanCatalogItem(json['id'] as String, json['title'] as String, json['subtitle'] as String,
      stockOnHand: json['stockOnHand'] as int?, lowStockThreshold: json['lowStockThreshold'] as int? ?? 5);
  }
}

class LanCatalogPage {
  const LanCatalogPage(this.items, this.epoch, this.nextOffset);
  final List<LanCatalogItem> items;
  final String epoch;
  final int? nextOffset;
  Map<String, Object?> toJson() => {'apiVersion': 1, 'items': items.map((i) => i.toJson()).toList(),
    'epoch': epoch, 'nextOffset': nextOffset};
  factory LanCatalogPage.fromJson(Map<String, dynamic> json) {
    if (json['apiVersion'] != 1 || json['items'] is! List || (json['items'] as List).length > 25 ||
        json['epoch'] is! String || (json['nextOffset'] != null && json['nextOffset'] is! int)) {
      throw const FormatException('Invalid catalog page');
    }
    return LanCatalogPage((json['items'] as List).map((v) =>
      LanCatalogItem.fromJson(Map<String, dynamic>.from(v as Map))).toList(),
      json['epoch'] as String, json['nextOffset'] as int?);
  }
}
