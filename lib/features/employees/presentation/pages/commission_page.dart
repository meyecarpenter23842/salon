import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/models/audit_event.dart';
import '../../../../core/models/entity_id.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/repositories/commission_ledger.dart';
import '../../../../core/repositories/sqlite_commission_repository.dart';
import '../../../../shared/widgets/sensitive_action_authorization.dart';

String _money(int value) => NumberFormat.currency(locale:'vi_VN',symbol:'đ',decimalDigits:0).format(value);

class CommissionPage extends ConsumerStatefulWidget {
  const CommissionPage({super.key});
  @override ConsumerState<CommissionPage> createState()=>_CommissionPageState();
}
class _CommissionPageState extends ConsumerState<CommissionPage> {
  late Future<CommissionSnapshot> future;
  String? period, employeeId;
  bool busy=false;
  @override void initState(){super.initState();_reload();}
  void _reload(){future=ref.read(commissionRepositoryProvider)!.fetch();}
  Future<void> _close(String month) async {
    if(busy) return;
    final confirm=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text('Chốt hoa hồng tháng $month?'),
      content:const Text('Xác nhận toàn bộ phát sinh tháng này. Số đã chốt được giữ nguyên; thao tác này chưa trả tiền cho nhân viên.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Hủy')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Chốt tháng'))]));
    if(confirm!=true || !mounted) return;
    if(!await ensureSensitiveActionAuthorized(context,ref,SensitiveAction.commission)||!mounted) return;
    setState(()=>busy=true);
    try {
      await ref.read(commissionRepositoryProvider)!.closePeriod(month);
      if(mounted){setState(_reload);_message('Đã chốt tháng $month.');}
    }catch(e){if(mounted)_message('Không chốt được: $e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  void _message(String text)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));
  Future<void> _pay(CommissionAccount? account) async {
    if(busy) return;
    if(!await ensureSensitiveActionAuthorized(context,ref,SensitiveAction.commission)||!mounted) return;
    setState(()=>busy=true);
    try {
      final repository=ref.read(commissionRepositoryProvider)!;
      final pending=await repository.pendingPayout();
      if(!mounted) return;
      if(pending==null && (account==null||account.balance<=0)) {_message('Chọn nhân viên còn tiền phải trả đã chốt.');return;}
      final latest=await repository.fetch();
      if(!mounted) return;
      final id=pending?['employeeId']?.toString()??account!.id;
      final selected=latest.accounts.where((a)=>a.id==id).firstOrNull;
      if(selected==null){_message('Không tìm thấy nhân viên của khoản trả.');return;}
      await showDialog<void>(context:context,barrierDismissible:false,
        builder:(_)=>_PayoutDialog(repository:repository,account:selected,pending:pending));
      if(mounted)setState(_reload);
    }catch(e){if(mounted)_message('Không mở được khoản trả: $e');}
    finally{if(mounted)setState(()=>busy=false);}
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Hoa hồng và chi trả'),actions:[
      IconButton(tooltip:'Tải lại sổ',onPressed:busy?null:()=>setState(_reload),icon:const Icon(Icons.refresh))]),
    body:FutureBuilder<CommissionSnapshot>(future:future,builder:(context,state){
      if(state.hasError)return Center(child:Text('Không tải được sổ: ${state.error}'));
      if(!state.hasData)return const Center(child:CircularProgressIndicator());
      final data=state.data!;
      final selectedPeriod=data.periods.contains(period)?period:(data.periods.isEmpty?null:data.periods.first);
      final selectedEmployee=data.accounts.where((a)=>a.id==employeeId).firstOrNull;
      final entries=data.entries.where((r)=>(selectedPeriod==null||r['period']==selectedPeriod)
        &&(employeeId==null||r['employee_id']==employeeId)).toList();
      final payouts=data.payouts.where((r)=>employeeId==null||r['employee_id']==employeeId).toList();
      return ListView(padding:const EdgeInsets.all(20),children:[
        const Text('Tỷ lệ nhân viên × tiền dịch vụ sau giảm giá. Chốt theo tháng; chưa tính bán sản phẩm. '
          'Hoàn/hủy ghi giảm ở tháng kế tiếp. Hóa đơn trước khi có sổ này chỉ có báo cáo ước tính.'),
        const SizedBox(height:16),
        Wrap(spacing:12,runSpacing:12,crossAxisAlignment:WrapCrossAlignment.center,children:[
          SizedBox(width:190,child:DropdownButtonFormField<String>(
            key:ValueKey('period-$selectedPeriod'),initialValue:selectedPeriod,
            decoration:const InputDecoration(labelText:'Tháng phát sinh'),
            items:data.periods.map((p)=>DropdownMenuItem(value:p,child:Text('$p ${data.closed.contains(p)?'· Đã chốt':''}'))).toList(),
            onChanged:busy?null:(v)=>setState(()=>period=v))),
          OutlinedButton.icon(onPressed:busy||selectedPeriod==null||data.closed.contains(selectedPeriod)
            ||selectedPeriod.compareTo(CommissionLedger.month(DateTime.now()))>=0?null:()=>_close(selectedPeriod),
            icon:const Icon(Icons.lock_outline),label:const Text('Chốt tháng')),
          SizedBox(width:260,child:DropdownButtonFormField<String>(
            key:ValueKey('employee-$employeeId'),initialValue:employeeId,isExpanded:true,
            decoration:const InputDecoration(labelText:'Nhân viên'),
            items:[const DropdownMenuItem<String>(value:null,child:Text('Tất cả nhân viên')),
              ...data.accounts.map((a)=>DropdownMenuItem(value:a.id,child:Text(a.name,overflow:TextOverflow.ellipsis)))],
            onChanged:busy?null:(v)=>setState(()=>employeeId=v))),
          FilledButton.icon(onPressed:busy?null:()=>_pay(selectedEmployee),icon:const Icon(Icons.payments_outlined),
            label:const Text('Trả / đối chiếu khoản chờ')),
        ]),
        const SizedBox(height:20),
        const Text('Tổng đối soát tất cả tháng · số còn lại đã trừ khoản hoàn/hủy của các tháng đã chốt'),
        const SizedBox(height:8),
        if(data.accounts.isEmpty)const Padding(padding:EdgeInsets.all(24),
          child:Text('Chưa có phát sinh hoa hồng. Sổ bắt đầu ghi nhận từ các lần thanh toán mới có gán nhân viên.')),
        _table(['Nhân viên','Phát sinh (mọi kỳ)','Đã chốt','Đã trả','Còn phải trả / bù trừ'],[
          for(final a in data.accounts) if(employeeId==null||a.id==employeeId)
            [a.name,_money(a.earned),_money(a.settled),_money(a.paid),_money(a.balance)]
        ]),
        const SizedBox(height:20),
        Text('Chi tiết tháng ${selectedPeriod??'—'}',style:Theme.of(context).textTheme.titleLarge),
        _table(['Ngày ghi','Nhân viên','Dịch vụ / hóa đơn','Cơ sở sau giảm giá','Tỷ lệ','Hoa hồng','Loại'],[
          for(final r in entries)[r['created_at'].toString().substring(0,10),r['employee_name'].toString(),
            '${r['title']}\n${r['invoice_id']}',_money(r['basis'] as int),
            '${(r['rate_bps'] as int)/100}%',_money(r['amount'] as int),
            r['kind']=='earned'?'Phát sinh':'Hoàn/hủy · kỳ sau']
        ]),
        const SizedBox(height:20),
        Text('Chứng từ đã trả · mọi tháng',style:Theme.of(context).textTheme.titleLarge),
        _table(['Ngày trả','Nhân viên','Số tiền','Phương thức','Chứng từ / tham chiếu','Người ghi'],[
          for(final r in payouts)[r['created_at'].toString().substring(0,10),r['employee_name'].toString(),
            _money(r['amount'] as int),r['method']=='cash'?'Tiền mặt':'Chuyển khoản',
            '${r['id']}\n${r['cash_movement_id']??r['reference']}',r['actor'].toString()]
        ]),
      ]);
    }));
  Widget _table(List<String> headers,List<List<String>> rows)=>SingleChildScrollView(
    scrollDirection:Axis.horizontal,child:DataTable(
      columns:headers.map((h)=>DataColumn(label:Text(h))).toList(),
      rows:rows.map((r)=>DataRow(cells:r.map((s)=>DataCell(SelectableText(s))).toList())).toList()));
}

class _PayoutDialog extends StatefulWidget {
  const _PayoutDialog({required this.repository,required this.account,this.pending});
  final SqliteCommissionRepository repository;
  final CommissionAccount account;
  final Map<String,Object?>? pending;
  @override State<_PayoutDialog> createState()=>_PayoutDialogState();
}
class _PayoutDialogState extends State<_PayoutDialog> {
  late final TextEditingController amount,reference,note;
  late String requestId,method;
  bool busy=false,submitted=false;
  String? error;
  @override void initState(){
    super.initState();
    final p=widget.pending;
    requestId=p?['requestId']?.toString()??EntityId.create('commission-payout');
    method=p?['method']?.toString()??'transfer';
    amount=TextEditingController(text:(p?['amount']??widget.account.balance).toString());
    reference=TextEditingController(text:p?['reference']?.toString()??'');
    note=TextEditingController(text:p?['note']?.toString()??'');
    submitted=p!=null;
  }
  @override void dispose(){amount.dispose();reference.dispose();note.dispose();super.dispose();}
  Future<void> _submit() async{
    final value=int.tryParse(amount.text);
    if(value==null||value<=0||(method=='transfer'&&reference.text.trim().isEmpty)){
      setState(()=>error='Nhập số tiền dương và mã chuyển khoản (nếu chuyển khoản).');return;
    }
    if(!submitted){
      final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Ghi nhận đã trả hoa hồng?'),
        content:Text('${widget.account.name}: ${_money(value)}\n'
          '${method=='cash'?'Sẽ ghi phiếu chi trong ca thu ngân đang mở.':'Chỉ ghi nhận khoản đã chuyển; ứng dụng không chuyển tiền.'}'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Hủy')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Đã trả · ghi chứng từ'))]));
      if(confirmed!=true||!mounted)return;
    }
    setState((){busy=true;submitted=true;error=null;});
    try{
      await widget.repository.pay(requestId:requestId,employeeId:widget.account.id,
        amount:value,method:method,reference:reference.text,note:note.text);
      if(mounted)Navigator.pop(context);
    }catch(e){if(mounted)setState(()=>error='Chưa xác nhận khoản trả: $e. Giữ mã yêu cầu; thử đối chiếu hoặc bỏ yêu cầu sau khi kiểm tra sổ.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _resolve() async {
    setState(()=>busy=true);
    try{await widget.repository.resolvePendingPayout(requestId);if(mounted)Navigator.pop(context);}
    catch(e){if(mounted)setState(()=>error='$e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>PopScope(canPop:!busy,child:AlertDialog(
    title:Text('Trả hoa hồng · ${widget.account.name}'),
    content:SizedBox(width:460,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text('Còn phải trả đã chốt: ${_money(widget.account.balance)}. Có thể trả từng phần.'),
      const SizedBox(height:12),
      TextField(controller:amount,enabled:!busy&&!submitted,keyboardType:TextInputType.number,
        inputFormatters:[FilteringTextInputFormatter.digitsOnly],decoration:const InputDecoration(labelText:'Số tiền (đ)')),
      DropdownButtonFormField<String>(initialValue:method,
        decoration:const InputDecoration(labelText:'Phương thức'),
        items:const [DropdownMenuItem(value:'transfer',child:Text('Chuyển khoản')),DropdownMenuItem(value:'cash',child:Text('Tiền mặt'))],
        onChanged:busy||submitted?null:(v)=>setState(()=>method=v!)),
      TextField(controller:reference,enabled:!busy&&!submitted,decoration:const InputDecoration(labelText:'Mã giao dịch chuyển khoản / tham chiếu')),
      TextField(controller:note,enabled:!busy&&!submitted,decoration:const InputDecoration(labelText:'Ghi chú')),
      const SizedBox(height:12),SelectableText('Mã yêu cầu: $requestId'),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
    ]))),
    actions:[
      TextButton(onPressed:busy?null:()=>Navigator.pop(context),child:Text(submitted?'Đóng · giữ khoản chờ':'Hủy')),
      if(submitted)TextButton(onPressed:busy?null:_resolve,child:const Text('Kiểm tra sổ và bỏ yêu cầu')),
      FilledButton(onPressed:busy?null:_submit,child:Text(busy?'Đang xử lý…':submitted?'Đối chiếu cùng mã':'Ghi nhận đã trả')),
    ],
  ));
}
