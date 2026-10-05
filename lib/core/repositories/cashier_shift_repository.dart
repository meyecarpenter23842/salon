import '../models/cashier_shift.dart';
abstract class CashierShiftRepository {
  Future<CashierShift?> fetchOpenShift();
  Future<List<CashierShift>> fetchShiftHistory({int limit=30});
  Future<List<CashMovement>> fetchMovements(String shiftId);
  Future<CashierShift> openShift({required int openingCash,String note=''});
  Future<CashMovement> recordCashMovement({required String type,required int amount,required String reason});
  Future<CashierShift> closeShift({required int countedCash,String note=''});
}
