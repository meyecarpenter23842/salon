class CashierShift {
  const CashierShift({required this.id,required this.openingCash,required this.openedAt,this.closedAt,this.countedCash,this.expectedCash,this.variance,this.note='',this.cashSales=0,this.cashIn=0,this.cashOut=0});
  final String id; final int openingCash; final DateTime openedAt; final DateTime? closedAt; final int? countedCash; final int? expectedCash; final int? variance; final String note; final int cashSales; final int cashIn; final int cashOut;
  bool get isOpen=>closedAt==null; int get liveExpectedCash=>openingCash+cashSales+cashIn-cashOut;
}
class CashMovement {
  const CashMovement({required this.id,required this.shiftId,required this.type,required this.amount,required this.reason,required this.createdAt});
  final String id; final String shiftId; final String type; final int amount; final String reason; final DateTime createdAt;
}
