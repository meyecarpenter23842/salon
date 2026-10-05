part of 'invoices_pos_page.dart';
Future<void> _showCashierShiftDialog(BuildContext context,WidgetRef ref) async {
  var shift=await ref.read(cashierShiftRepositoryProvider).fetchOpenShift();
  if(!context.mounted)return;
  final amount=TextEditingController(), reason=TextEditingController();
  await showAppDialog<void>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(context,setState){
    int money()=>int.tryParse(amount.text.replaceAll(RegExp(r'[^0-9]'),''))??0;
    Future<void> refresh() async { shift=await ref.read(cashierShiftRepositoryProvider).fetchOpenShift(); ref.invalidate(activeCashierShiftProvider); ref.invalidate(cashierShiftHistoryProvider); if(context.mounted)setState((){}); }
    return AlertDialog(title:Text(shift==null?'Mở ca thu ngân':'Ca thu ngân'),content:SizedBox(width:adaptiveDialogWidth(dialogContext,460),child:Column(mainAxisSize:MainAxisSize.min,children:[
      if(shift!=null)...[ListTile(title:const Text('Tiền đầu ca'),trailing:Text(_currency(shift!.openingCash))),ListTile(title:const Text('Tiền mặt bán hàng'),trailing:Text(_currency(shift!.cashSales))),ListTile(title:const Text('Thu / Chi'),trailing:Text('${_currency(shift!.cashIn)} / ${_currency(shift!.cashOut)}')),ListTile(title:const Text('Tiền mặt kỳ vọng'),trailing:Text(_currency(shift!.liveExpectedCash)))],
      TextField(controller:amount,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:shift==null?'Tiền đầu ca':'Số tiền')),
      if(shift!=null)TextField(controller:reason,decoration:const InputDecoration(labelText:'Lý do / ghi chú')),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Đóng')),
      if(shift==null)FilledButton(onPressed:()async{await ref.read(cashierShiftRepositoryProvider).openShift(openingCash:money());await refresh();},child:const Text('Mở ca'))
      else ...[
        TextButton(onPressed:()async{await ref.read(cashierShiftRepositoryProvider).recordCashMovement(type:'in',amount:money(),reason:reason.text);amount.clear();reason.clear();await refresh();},child:const Text('Thu tiền')),
        TextButton(onPressed:()async{await ref.read(cashierShiftRepositoryProvider).recordCashMovement(type:'out',amount:money(),reason:reason.text);amount.clear();reason.clear();await refresh();},child:const Text('Chi tiền')),
        FilledButton(onPressed:()async{await ref.read(cashierShiftRepositoryProvider).closeShift(countedCash:money(),note:reason.text);await refresh();if(context.mounted)Navigator.pop(dialogContext);},child:const Text('Chốt ca'))
      ]]);
  }));
}
