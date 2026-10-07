
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/models/attendance.dart';
import '../../../../core/models/audit_event.dart';
import '../../../../core/models/entity_id.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../shared/widgets/sensitive_action_authorization.dart';

String _date(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
String _time(DateTime? value) => value == null ? '—' : DateFormat('HH:mm · dd/MM').format(value);
String _duration(int seconds) => '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}p';

class AttendancePage extends ConsumerStatefulWidget {
  const AttendancePage({super.key});
  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  DateTime day = DateTime.now();
  String? employeeId;
  late Future<AttendanceSnapshot> future;
  bool busy = false;
  @override
  void initState() { super.initState(); _reload(); }
  void _reload() { future = ref.read(attendanceRepositoryProvider)!.fetch(day); }
  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(value)));
  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) { setState(_reload); _message('Đã lưu chấm công.'); }
    } catch (e) {
      if (mounted) _message('Không lưu được: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> _plan(AttendanceSnapshot snapshot) async {
    if (busy) return;
    if (!await ensureSensitiveActionAuthorized(context,ref,SensitiveAction.attendance) || !mounted) return;
    final input = await showDialog<_PlanInput>(context:context,
      builder:(_) => _PlanDialog(employees:snapshot.employees,day:day));
    if (input==null || !mounted) return;
    final id = EntityId.create('attendance_request');
    await _run(() => ref.read(attendanceRepositoryProvider)!.plan(
      requestId:id,employeeId:input.employeeId,label:input.label,start:input.start,end:input.end));
  }
  Future<void> _correct(AttendanceShift shift) async {
    if (busy) return;
    if (!await ensureSensitiveActionAuthorized(context,ref,SensitiveAction.attendance) || !mounted) return;
    final input = await showDialog<_CorrectionInput>(context:context,
      builder:(_) => _CorrectionDialog(shift:shift));
    if (input==null || !mounted) return;
    final id = EntityId.create('attendance_request');
    await _run(() => ref.read(attendanceRepositoryProvider)!.correct(
      requestId:id,shift:shift,state:input.state,clockIn:input.start,
      clockOut:input.end,breaks:input.breaks,reason:input.reason));
  }
  Future<void> _stamp(AttendanceShift shift,String operation) async {
    final id = EntityId.create('attendance_request');
    await _run(() => ref.read(attendanceRepositoryProvider)!.stamp(
      requestId:id,shift:shift,operation:operation));
  }
  Future<void> _history(AttendanceShift shift) async {
    await showDialog<void>(context:context,builder:(_) => _HistoryDialog(
      shift:shift,future:ref.read(attendanceRepositoryProvider)!.history(shift.id)));
  }
  Future<void> _chooseDay() async {
    final selected = await showDatePicker(context:context,initialDate:day,
      firstDate:DateTime(2000),lastDate:DateTime(2100));
    if (selected!=null && mounted) {
      setState(() {day=selected; _reload();});
    }
  }
  void _moveDay(int offset) {
    setState(() {day=DateTime(day.year,day.month,day.day+offset); _reload();});
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:const Text('Chấm công'),actions:[
      IconButton(tooltip:'Tải lại',onPressed:busy?null:()=>setState(_reload),icon:const Icon(Icons.refresh)),
    ]),
    body:FutureBuilder<AttendanceSnapshot>(future:future,builder:(context,snapshot) {
      if (snapshot.hasError) {
        return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('Không tải được chấm công'), Text('${snapshot.error}'),
        TextButton(onPressed:()=>setState(_reload),child:const Text('Thử lại')),
      ]));
      }
      if (!snapshot.hasData) return const Center(child:CircularProgressIndicator());
      final data=snapshot.data!;
      final shifts=data.shifts.where((s)=>employeeId==null || s.employeeId==employeeId).toList();
      final seconds=shifts.where((s)=>s.workDay==SqliteDay.key(day))
        .fold<int>(0,(sum,s)=>sum+(s.workedSeconds??0));
      return Column(children:[
        Padding(padding:const EdgeInsets.all(16),child:Wrap(spacing:12,runSpacing:12,crossAxisAlignment:WrapCrossAlignment.center,children:[
          OutlinedButton.icon(onPressed:busy?null:_chooseDay,icon:const Icon(Icons.calendar_month),
            label:Text(_date(day))),
          IconButton(tooltip:'Ngày trước',onPressed:busy?null:()=>_moveDay(-1),icon:const Icon(Icons.chevron_left)),
          IconButton(tooltip:'Ngày sau',onPressed:busy?null:()=>_moveDay(1),icon:const Icon(Icons.chevron_right)),
          SizedBox(width:240,child:DropdownButtonFormField<String>(
            key:ValueKey(employeeId),initialValue:employeeId??'',
            decoration:const InputDecoration(labelText:'Nhân viên'),
            isExpanded:true,items:[
              const DropdownMenuItem(value:'',child:Text('Tất cả nhân viên')),
              ...data.employees.map((e)=>DropdownMenuItem(value:e['id'] as String,
                child:Text(e['full_name'] as String,overflow:TextOverflow.ellipsis))),
            ],onChanged:busy?null:(value)=>setState(()=>employeeId=value==''?null:value))),
          FilledButton.icon(onPressed:busy?null:()=>_plan(data),icon:const Icon(Icons.add),label:const Text('Xếp ca')),
        ])),
        Padding(padding:const EdgeInsets.symmetric(horizontal:20),child:Align(alignment:Alignment.centerLeft,
          child:Text('Giờ làm đã ghi: ${_duration(seconds)} · đã trừ nghỉ\nCa đang mở qua ngày vẫn được hiển thị. Giờ thuộc ngày bắt đầu ca.',
            style:Theme.of(context).textTheme.bodyMedium))),
        const SizedBox(height:12),
        if (busy) const LinearProgressIndicator(),
        Expanded(child:shifts.isEmpty
          ? const Center(child:Text('Chưa có ca. Chọn Xếp ca để bắt đầu.'))
          : ListView.separated(padding:const EdgeInsets.fromLTRB(16,0,16,24),
              itemCount:shifts.length,separatorBuilder:(_,_)=>const SizedBox(height:8),
              itemBuilder:(context,index) {
                final s=shifts[index];
                return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
                  crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Wrap(spacing:12,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
                      Text(s.employeeName,style:Theme.of(context).textTheme.titleMedium),
                      Chip(label:Text(s.statusLabel)),
                      Text(s.label),
                      if(s.workDay!=SqliteDay.key(day)) Text('Ca ngày ${_date(s.plannedStart)}'),
                    ]),
                    const SizedBox(height:8),
                    Text('Lịch ca: ${_time(s.plannedStart)} → ${_time(s.plannedEnd)}'),
                    const SizedBox(height:4),
                    Text('Vào: ${_time(s.clockIn)}    Ra: ${_time(s.clockOut)}    Giờ làm: ${s.workedSeconds==null?'Chưa chốt':_duration(s.workedSeconds!)}'),
                    if(s.breaks.isNotEmpty) Padding(padding:const EdgeInsets.only(top:4),
                      child:Text('Nghỉ: ${s.breaks.map((b)=>'${_time(b.start)} → ${b.end==null?'đang nghỉ':_time(b.end)}').join(' · ')}')),
                    const SizedBox(height:12),
                    Wrap(spacing:8,runSpacing:8,children:[
                      if(s.state=='planned') FilledButton.icon(onPressed:busy?null:()=>_stamp(s,'in'),
                        icon:const Icon(Icons.login),label:const Text('Vào ca')),
                      if(s.state=='working') ...[
                        OutlinedButton.icon(onPressed:busy?null:()=>_stamp(s,s.onBreak?'break_end':'break_start'),
                          icon:const Icon(Icons.coffee_outlined),label:Text(s.onBreak?'Kết thúc nghỉ':'Bắt đầu nghỉ')),
                        FilledButton.icon(onPressed:busy||s.onBreak?null:()=>_stamp(s,'out'),
                          icon:const Icon(Icons.logout),label:const Text('Ra ca')),
                      ],
                      TextButton.icon(onPressed:busy?null:()=>_correct(s),
                        icon:const Icon(Icons.edit_outlined),label:const Text('Sửa công / nghỉ ca')),
                      TextButton.icon(onPressed:busy?null:()=>_history(s),
                        icon:const Icon(Icons.history),label:const Text('Lịch sử')),
                    ]),
                  ])));
              })),
      ]);
    }),
  );
}

/// Local day formatting for the attendance selector.
class SqliteDay {
  static String key(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({required this.label,required this.value,required this.onChanged});
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  Future<void> _pick(BuildContext context) async {
    final date=await showDatePicker(context:context,initialDate:value,
      firstDate:DateTime(2000),lastDate:DateTime(2100));
    if(date==null || !context.mounted) return;
    final time=await showTimePicker(context:context,initialTime:TimeOfDay.fromDateTime(value));
    if(time!=null) onChanged(DateTime(date.year,date.month,date.day,time.hour,time.minute));
  }
  @override
  Widget build(BuildContext context) => Padding(padding:const EdgeInsets.only(bottom:12),
    child:OutlinedButton(onPressed:()=>_pick(context),child:Padding(
      padding:const EdgeInsets.all(10),child:Row(children:[
        const Icon(Icons.schedule,size:18),const SizedBox(width:10),
        Expanded(child:Text('$label: ${DateFormat('HH:mm · dd/MM/yyyy').format(value)}')),
      ]))));
}

class _PlanInput {
  const _PlanInput(this.employeeId,this.label,this.start,this.end);
  final String employeeId,label;
  final DateTime start,end;
}
class _PlanDialog extends StatefulWidget {
  const _PlanDialog({required this.employees,required this.day});
  final List<Map<String,Object?>> employees;
  final DateTime day;
  @override State<_PlanDialog> createState()=>_PlanDialogState();
}
class _PlanDialogState extends State<_PlanDialog> {
  String? employeeId, error;
  final label=TextEditingController();
  late DateTime start,end;
  @override void initState() {super.initState();
    start=DateTime(widget.day.year,widget.day.month,widget.day.day,9);
    end=DateTime(widget.day.year,widget.day.month,widget.day.day,17);
  }
  @override void dispose(){label.dispose();super.dispose();}
  @override Widget build(BuildContext context) => AlertDialog(
    title:const Text('Xếp ca làm'),content:SizedBox(width:480,child:SingleChildScrollView(child:Column(
      mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        DropdownButtonFormField<String>(initialValue:employeeId,isExpanded:true,
          decoration:const InputDecoration(labelText:'Nhân viên'),
          items:widget.employees.where((e)=>!['Tạm nghỉ','Đã nghỉ việc','Nghỉ việc'].contains(e['status']))
            .map((e)=>DropdownMenuItem(value:e['id'] as String,child:Text(e['full_name'] as String))).toList(),
          onChanged:(value)=>employeeId=value),
        const SizedBox(height:12),
        TextField(controller:label,decoration:const InputDecoration(labelText:'Tên ca',hintText:'Ví dụ: Ca sáng')),
        const SizedBox(height:16),
        _DateTimeField(label:'Bắt đầu',value:start,onChanged:(v)=>setState(()=>start=v)),
        _DateTimeField(label:'Kết thúc',value:end,onChanged:(v)=>setState(()=>end=v)),
        const Text('Ca qua đêm: chọn ngày kết thúc là ngày tiếp theo.'),
        if(error!=null) Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      ]))),actions:[
        TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Hủy')),
        FilledButton(onPressed:(){
          if(employeeId==null || label.text.trim().isEmpty || !end.isAfter(start)){
            setState(()=>error='Chọn nhân viên, tên ca và giờ kết thúc sau giờ bắt đầu.');return;
          }
          Navigator.pop(context,_PlanInput(employeeId!,label.text.trim(),start,end));
        },child:const Text('Lưu ca')),
      ]);
}

class _CorrectionInput {
  const _CorrectionInput(this.state,this.start,this.end,this.breaks,this.reason);
  final String state,reason;
  final DateTime? start,end;
  final List<AttendanceBreak> breaks;
}
class _CorrectionDialog extends StatefulWidget {
  const _CorrectionDialog({required this.shift});
  final AttendanceShift shift;
  @override State<_CorrectionDialog> createState()=>_CorrectionDialogState();
}
class _CorrectionDialogState extends State<_CorrectionDialog> {
  late String state;
  late DateTime start,end;
  late List<AttendanceBreak> breaks;
  final reason=TextEditingController();
  String? error;
  @override void initState(){super.initState();final s=widget.shift;
    state=s.state;start=s.clockIn??s.plannedStart;end=s.clockOut??DateTime.now();breaks=s.breaks;
  }
  @override void dispose(){reason.dispose();super.dispose();}
  bool get hasTime=>['working','completed'].contains(state);
  @override Widget build(BuildContext context)=>AlertDialog(title:Text('Sửa công · ${widget.shift.employeeName}'),
    content:SizedBox(width:560,child:SingleChildScrollView(child:Column(
      mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Text('Mọi thay đổi đều lưu người sửa, lý do và công trước/sau.'),
        const SizedBox(height:12),
        DropdownButtonFormField<String>(initialValue:state,isExpanded:true,
          decoration:const InputDecoration(labelText:'Trạng thái'),
          items:const [
            DropdownMenuItem(value:'planned',child:Text('Chưa vào ca')),
            DropdownMenuItem(value:'working',child:Text('Đang làm / đang nghỉ')),
            DropdownMenuItem(value:'completed',child:Text('Đã ra ca')),
            DropdownMenuItem(value:'leave',child:Text('Nghỉ ca')),
            DropdownMenuItem(value:'cancelled',child:Text('Hủy ca')),
          ],onChanged:(v)=>setState(()=>state=v!)),
        const SizedBox(height:12),
        if(hasTime) ...[
          _DateTimeField(label:'Giờ vào',value:start,onChanged:(v)=>setState(()=>start=v)),
          if(state=='completed') _DateTimeField(label:'Giờ ra',value:end,onChanged:(v)=>setState(()=>end=v)),
          const Text('Các lần nghỉ (trừ khỏi giờ làm)'),
          const SizedBox(height:8),
          for(var i=0;i<breaks.length;i++) _breakEditor(i),
          TextButton.icon(onPressed:()=>setState(()=>breaks.add(AttendanceBreak(start,start))),
            icon:const Icon(Icons.add),label:const Text('Thêm lần nghỉ')),
        ] else if(widget.shift.clockIn!=null)
          const Text('Giờ vào/ra và các lần nghỉ sẽ được bỏ khỏi công hiện tại; bản cũ vẫn nằm trong lịch sử.'),
        const SizedBox(height:12),
        TextField(controller:reason,maxLines:2,decoration:const InputDecoration(labelText:'Lý do sửa (bắt buộc)')),
        if(error!=null) Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      ]))),actions:[
        TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Hủy')),
        FilledButton(onPressed:_save,child:const Text('Lưu sửa công')),
      ]);
  Widget _breakEditor(int i) {
    final b=breaks[i];
    return Card(child:Padding(padding:const EdgeInsets.all(8),child:Column(children:[
      Row(children:[Expanded(child:Text('Lần nghỉ ${i+1}')),
        IconButton(tooltip:'Xóa lần nghỉ',onPressed:()=>setState(()=>breaks.removeAt(i)),icon:const Icon(Icons.delete_outline))]),
      _DateTimeField(label:'Bắt đầu nghỉ',value:b.start,
        onChanged:(v)=>setState(()=>breaks[i]=AttendanceBreak(v,b.end))),
      if(b.end!=null) _DateTimeField(label:'Kết thúc nghỉ',value:b.end!,
        onChanged:(v)=>setState(()=>breaks[i]=AttendanceBreak(b.start,v))),
      if(state=='working') CheckboxListTile(title:const Text('Lần nghỉ đang mở'),
        value:b.end==null,onChanged:(v)=>setState(()=>breaks[i]=AttendanceBreak(b.start,v==true?null:b.start))),
    ])));
  }
  void _save() {
    if(reason.text.trim().isEmpty){setState(()=>error='Nhập lý do sửa công.');return;}
    final now=DateTime.now();
    if(hasTime) {
      if(start.isAfter(now) || (state=='completed' && (end.isBefore(start)||end.isAfter(now)))) {
        setState(()=>error='Giờ vào/ra không hợp lệ hoặc nằm trong tương lai.');return;
      }
      var previous=start;
      for(var i=0;i<breaks.length;i++) {
        final b=breaks[i];
        if(b.start.isBefore(previous)||b.start.isAfter(state=='completed'?end:now)||
          (b.end==null&&(state=='completed'||i!=breaks.length-1))||
          (b.end!=null&&(b.end!.isBefore(b.start)||b.end!.isAfter(state=='completed'?end:now)))) {
          setState(()=>error='Sửa các lần nghỉ theo thứ tự, trong giờ vào/ra, không chồng nhau.');return;
        }
        previous=b.end??b.start;
      }
    }
    Navigator.pop(context,_CorrectionInput(state,hasTime?start:null,
      state=='completed'?end:null,hasTime?breaks:[],reason.text.trim()));
  }
}

class _HistoryDialog extends StatelessWidget {
  const _HistoryDialog({required this.shift,required this.future});
  final AttendanceShift shift;
  final Future<List<Map<String,Object?>>> future;
  String _snapshot(String value) {
    final s=AttendanceShift(Map<String,Object?>.from(jsonDecode(value) as Map));
    return '${s.statusLabel} · Vào ${_time(s.clockIn)} · Ra ${_time(s.clockOut)}\n'
      'Nghỉ: ${s.breaks.isEmpty?'Không':s.breaks.map((b)=>'${_time(b.start)} → ${_time(b.end)}').join('; ')}\n'
      'Giờ làm: ${s.workedSeconds==null?'Chưa chốt':_duration(s.workedSeconds!)}';
  }
  @override Widget build(BuildContext context)=>AlertDialog(
    title:Text('Lịch sử công · ${shift.employeeName}'),
    content:SizedBox(width:650,height:460,child:FutureBuilder<List<Map<String,Object?>>>(
      future:future,builder:(context,snapshot){
        if(snapshot.hasError) return Text('Không tải được lịch sử: ${snapshot.error}');
        if(!snapshot.hasData) return const Center(child:CircularProgressIndicator());
        return ListView.separated(itemCount:snapshot.data!.length,
          separatorBuilder:(_,_)=>const Divider(),itemBuilder:(context,index){
            final e=snapshot.data![index];
            final operation=switch(e['operation']){
              'plan'=>'Xếp ca','in'=>'Vào ca','out'=>'Ra ca',
              'break_start'=>'Bắt đầu nghỉ','break_end'=>'Kết thúc nghỉ',_=>'Sửa công',
            };
            return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('$operation · lần ${e['revision']}',style:Theme.of(context).textTheme.titleSmall),
              Text('${e['actor']} · ${_time(DateTime.parse(e['created_at'] as String))}'),
              Text('Lý do: ${e['reason']}'),
              if(e['before_json']!=null) ...[
                const SizedBox(height:8),const Text('Trước:'),Text(_snapshot(e['before_json'] as String))],
              const SizedBox(height:8),const Text('Sau:'),Text(_snapshot(e['after_json'] as String)),
            ]);
          });
      })),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Đóng'))],
  );
}
