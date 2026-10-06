import 'package:flutter/foundation.dart';
import '../../core/lan/lan_contract.dart';
import '../../core/lan/lan_health_client.dart';
import '../../core/lan/lan_pairing.dart';
import '../../core/lan/lan_workflow_client.dart';
import '../../core/lan/lan_workflow_models.dart';
import '../../core/lan/lan_write_contract.dart';
import 'companion_credential_store.dart';

class CompanionCommandController extends ChangeNotifier {
  CompanionCommandController({required this.connection, required this.client,
    required this.store, required CompanionCredential credential, required this.onCredential})
    : _credential = credential;
  final LanConnection connection;
  final LanWorkflowClient client;
  final CompanionCredentialStore store;
  final ValueChanged<CompanionCredential> onCredential;
  CompanionCredential _credential;
  bool _closed = false;
  bool busy = false;
  String? message;
  LanWriteResult? lastResult;
  LanErrorCode? failureCode;
  LanWriteOperation? lastOperation;
  String? lastTargetId;
  bool canRetry = false;
  bool oldEpoch = false;
  LanWriteCommand? get pending => _credential.pendingCommand;
  String get token => _credential.token;
  bool get blocked => busy || pending != null;

  void _changed() { if (!_closed) notifyListeners(); }
  Future<void> _save(LanWriteCommand? command) async {
    final next = _credential.withPending(command);
    if (command != null) { _credential = next; onCredential(next); _changed(); }
    await store.write(next);
    _credential = next;
    onCredential(next);
    _changed();
  }

  Future<LanWriteResult?> submit(LanWriteOperation operation, LanEditorSnapshot snapshot,
      Map<String, dynamic> payload) async {
    if (blocked || _closed) return null;
    busy = true; message = null; lastResult = null; failureCode = null;
    lastOperation = operation; lastTargetId = snapshot.id; canRetry = false; oldEpoch = false; _changed();
    try {
      final command = LanWriteCommand(commandId: newDeviceSecret(), operation: operation,
        expectedEpoch: snapshot.epoch, targetId: operation.creates ? null : snapshot.id,
        expectedRevision: operation.creates ? null : snapshot.revision, payload: payload);
      await _save(command);
      // Losing the UI before sending leaves a durable command for manual review.
      if (_closed) return null;
      return await _send(command);
    } catch (_) {
      message = pending == null ? 'Chưa gửi: không lưu được thao tác an toàn trên điện thoại.'
        : 'Chưa xác định kết quả. Hãy kiểm tra kết quả trên máy salon trước khi thao tác tiếp.';
      return null;
    } finally { busy = false; _changed(); }
  }

  Future<LanWriteResult?> _send(LanWriteCommand command) async {
    try {
      final result = await client.send(connection, token, command);
      await _finish(result);
      return result;
    } catch (error) {
      failureCode = error is PairingFailure ? error.code : LanErrorCode.unavailable;
      if (error is PairingFailure && [
        LanErrorCode.invalidRequest, LanErrorCode.businessRule, LanErrorCode.revisionConflict,
        LanErrorCode.notFound, LanErrorCode.alreadyPaid,
      ].contains(error.code)) {
        // A journal hit precedes these errors, so this exact command did not commit.
        await _save(null);
        message = error.code == LanErrorCode.revisionConflict
          ? 'Dữ liệu đã đổi trên máy salon. Tải lại rồi kiểm tra trước khi lưu.'
          : error.code == LanErrorCode.alreadyPaid ? 'Bill đã thanh toán. Tải lại dữ liệu.'
          : 'Máy salon từ chối thao tác. Kiểm tra thông tin, lịch trùng, quyền và tồn kho rồi tải lại.';
      } else {
        message = 'Chưa xác định kết quả. Không gửi thao tác mới; hãy bấm Kiểm tra kết quả.';
      }
      return null;
    }
  }
  Future<void> _finish(LanWriteResult result) async {
    // Clearing must be durable before any subsequent command is permitted.
    await _save(null);
    lastResult = result; failureCode = null;
    message = result.type == 'invoice' ? 'Đã thanh toán. Mã hóa đơn: ${result.id}' : 'Đã lưu trên máy salon.';
    canRetry = false; oldEpoch = false;
  }

  Future<void> check() async {
    final command = pending;
    if (busy || command == null || _closed) return;
    busy = true; canRetry = false; oldEpoch = false;
    lastOperation = command.operation; lastTargetId = command.targetId; _changed();
    try {
      final result = await client.result(connection, token, command.commandId);
      if (result != null) {
        await _finish(result);
      } else {
        // Also prove the current desktop epoch before offering any retry.
        final current = await client.editor(connection, token, 'customer', null);
        oldEpoch = current.epoch != command.expectedEpoch;
        canRetry = !oldEpoch;
        message = oldEpoch ? 'Máy salon đã khởi động lại và không có kết quả thao tác này. Có thể bỏ thao tác cũ rồi tải dữ liệu mới.'
          : 'Máy salon chưa có kết quả. Có thể gửi lại đúng thao tác đã lưu; mã thao tác được giữ nguyên.';
      }
    } catch (_) {
      message = 'Chưa kiểm tra được kết quả. Giữ thao tác đã lưu và kiểm tra kết nối/quyền với chủ salon.';
    } finally { busy = false; _changed(); }
  }

  Future<void> retry() async {
    if (busy || pending == null || !canRetry || _closed) return;
    busy = true; canRetry = false; _changed();
    try { await _save(pending!); await _send(pending!); }
    catch (_) { message = 'Chưa gửi lại: không lưu được thao tác an toàn. Hãy kiểm tra kết quả sau.'; }
    finally { busy = false; _changed(); }
  }
  Future<void> discardOldEpoch() async {
    if (busy || pending == null || !oldEpoch || _closed) return;
    busy = true; _changed();
    try {
      await _save(null);
      message = 'Đã bỏ thao tác cũ chưa thực hiện. Tải lại dữ liệu trước khi sửa.';
      oldEpoch = false;
    } catch (_) { message = 'Chưa xóa được thao tác đã lưu. Hãy thử lại.'; }
    finally { busy = false; _changed(); }
  }

  Future<void> discardAfterDesktopReview() async {
    if (busy || pending == null || _closed) return;
    busy = true; _changed();
    try {
      await _save(null); canRetry = false; oldEpoch = false;
      message = 'Đã kết thúc yêu cầu sau khi đối chiếu trên máy salon. Không tạo lại thao tác đã được lưu.';
    } catch (_) { message = 'Chưa xóa được yêu cầu đã lưu. Hãy thử lại.'; }
    finally { busy = false; _changed(); }
  }

  @override
  void dispose() { _closed = true; super.dispose(); }
}

