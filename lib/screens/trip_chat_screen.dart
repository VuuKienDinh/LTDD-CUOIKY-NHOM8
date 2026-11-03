import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';
import '../theme/shadcn_theme.dart';

import 'in_app_call_screen.dart';

class TripChatScreen extends StatefulWidget {
  final int tripId;
  final int? bookingId;
  final String routeName;
  final String plateNumber;
  final String partnerName;
  final String partnerPhone;
  final String partnerRole; // 'Driver' or 'Customer' or 'Staff'

  const TripChatScreen({
    super.key,
    required this.tripId,
    this.bookingId,
    this.routeName = 'TP. Hồ Chí Minh -> Đà Lạt',
    this.plateNumber = '51B-288.99',
    this.partnerName = 'Tài xế Nguyễn Văn Tài',
    this.partnerPhone = '0901000004',
    this.partnerRole = 'Driver',
  });

  @override
  State<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends State<TripChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<dynamic> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _poller;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    // Tự động làm mới tin nhắn mỗi 3.5 giây để trò chuyện theo thời gian thực
    _poller = Timer.periodic(const Duration(milliseconds: 3500), (_) => _fetchMessages(silent: true));
  }

  @override
  void dispose() {
    _poller?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get(
        '/api/trips/${widget.tripId}/messages${widget.bookingId != null ? '?bookingId=${widget.bookingId}' : ''}',
      );
      if (res is List && mounted) {
        final newCount = res.length;
        // Nếu có tin nhắn mới từ đối phương, bắn thông báo
        if (_lastMessageCount > 0 && newCount > _lastMessageCount) {
          final lastMsg = res.last as Map<String, dynamic>;
          final isMine = (lastMsg['senderUserId'] ?? lastMsg['SenderUserId']) ==
              (ApiClient.instance.currentUser?['userId'] ?? ApiClient.instance.currentUser?['UserId']);
          if (!isMine) {
            final sender = (lastMsg['senderName'] ?? lastMsg['SenderName'] ?? widget.partnerName).toString();
            final content = (lastMsg['content'] ?? lastMsg['Content'] ?? '').toString();
            NotificationService.instance.showNewChatMessageNotification(
              senderName: sender,
              messageContent: content,
              tripId: widget.tripId,
            );
          }
        }
        _lastMessageCount = newCount;
        setState(() {
          _messages = res;
          _loading = false;
        });

        // Cuộn xuống tin nhắn mới nhất
        if (!silent || newCount > _messages.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollCtrl.hasClients) {
              _scrollCtrl.animateTo(
                _scrollCtrl.position.maxScrollExtent,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    } catch (_) {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage([String? quickText]) async {
    final text = (quickText ?? _msgCtrl.text).trim();
    if (text.isEmpty) return;

    if (quickText == null) _msgCtrl.clear();
    setState(() => _sending = true);

    try {
      await ApiClient.instance.post('/api/trips/${widget.tripId}/messages', body: {
        'content': text,
        'bookingId': widget.bookingId,
      });

      await _fetchMessages(silent: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gửi tin nhắn thất bại: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ApiClient.instance.currentUser?['userId'] ?? ApiClient.instance.currentUser?['UserId'];
    final isDriverPartner = widget.partnerRole == 'Driver';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F9FF),
      appBar: AppBar(
        backgroundColor: ShadcnTheme.primaryDark,
        foregroundColor: Colors.white,
        elevation: 1,
        titleSpacing: 0,
        title: Row(
          children: [
            // Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: const Color(0xFF38BDF8),
                  child: Icon(
                    isDriverPartner ? LucideIcons.bus : LucideIcons.user,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.partnerName,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${widget.plateNumber} • ${widget.partnerPhone}',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFFBAE6FD)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Nút gọi điện thoại qua App luôn (In-App VoIP Call)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InAppCallScreen(
                      tripId: widget.tripId,
                      partnerName: widget.partnerName,
                      partnerPhone: widget.partnerPhone,
                      partnerRole: widget.partnerRole,
                      plateNumber: widget.plateNumber,
                      routeName: widget.routeName,
                    ),
                  ),
                );
              },
              icon: const Icon(LucideIcons.phoneCall, size: 14),
              label: const Text('Gọi qua App', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header phụ hiển thị tuyến xe
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              color: const Color(0xFFE0F2FE),
              child: Row(
                children: [
                  const Icon(LucideIcons.route, size: 14, color: ShadcnTheme.primaryDark),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Tuyến: ${widget.routeName} (Chuyến #${widget.tripId})',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0369A1)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Trực tuyến', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

            // Danh sách tin nhắn
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? _buildEmptyChatPlaceholder()
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (ctx, i) {
                            final m = _messages[i];
                            final senderId = m['senderUserId'] ?? m['SenderUserId'];
                            final isMine = senderId == currentUserId;
                            final senderName = (m['senderName'] ?? m['SenderName'] ?? '').toString();
                            final senderRole = (m['senderRole'] ?? m['SenderRole'] ?? '').toString();
                            final content = (m['content'] ?? m['Content'] ?? '').toString();
                            final timeStr = _formatMessageTime(m['createdAt'] ?? m['CreatedAt']);

                            final isSystemNotice = content.startsWith('[HỆ THỐNG');

                            if (isSystemNotice) {
                              return _buildSystemNoticeBubble(content, timeStr);
                            }

                            return _buildMessageBubble(
                              isMine: isMine,
                              senderName: senderName,
                              senderRole: senderRole,
                              content: content,
                              timeStr: timeStr,
                            );
                          },
                        ),
            ),

            // Khay tin nhắn mẫu 1-chạm (Quick Reply Chips)
            _buildQuickReplies(isDriverPartner),

            // Khung nhập tin nhắn
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                boxShadow: [
                  BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, -2)),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => NotificationService.makePhoneCall(widget.partnerPhone),
                    icon: const Icon(LucideIcons.phone, color: Color(0xFF0284C7), size: 20),
                    tooltip: 'Gọi điện',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Nhập tin nhắn cho ${widget.partnerName}...',
                        hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _sending ? null : () => _sendMessage(),
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(LucideIcons.send, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyChatPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Color(0xFFE0F2FE),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.messagesSquare, color: Color(0xFF0284C7), size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              'Trò chuyện với ${widget.partnerName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bạn có thể nhắn tin hỏi vị trí xe, hẹn điểm đón hoặc bấm "Gọi điện" để liên lạc nhanh.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: ShadcnTheme.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemNoticeBubble(String content, String timeStr) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.megaphone, size: 16, color: Color(0xFFD97706)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'THÔNG BÁO ĐIỀU HÀNH TỰ ĐỘNG',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: Color(0xFFB45309)),
                ),
              ),
              Text(timeStr, style: const TextStyle(fontSize: 10, color: Color(0xFF92400E))),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            content.replaceAll('[HỆ THỐNG PHÁT THÔNG BÁO ĐẨY] ', ''),
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF78350F), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required bool isMine,
    required String senderName,
    required String senderRole,
    required String content,
    required String timeStr,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: senderRole == 'Driver' ? const Color(0xFF0284C7) : Colors.grey.shade400,
              child: Icon(
                senderRole == 'Driver' ? LucideIcons.bus : LucideIcons.user,
                size: 14,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine ? const Color(0xFF0284C7) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMine ? 16 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 16),
                ),
                border: Border.all(
                  color: isMine ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMine)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          senderName,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF0369A1)),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            senderRole == 'Driver' ? 'Tài xế' : 'Khách',
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                          ),
                        ),
                      ],
                    ),
                  if (!isMine) const SizedBox(height: 3),
                  Text(
                    content,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: isMine ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: isMine ? Colors.white70 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickReplies(bool isDriverPartner) {
    // Nếu người dùng đang chat với tài xế -> mẫu câu của khách
    // Nếu là tài xế đang chat với khách -> mẫu câu của tài xế
    final currentRole = ApiClient.instance.roles.contains('Driver') ? 'Driver' : 'Customer';
    final List<String> quickTexts = currentRole == 'Driver'
        ? [
            '🚌 Xe đang đến gần điểm đón, khoảng 5-10 phút nữa!',
            '📍 Xe đã tới bến/sảnh đón, đang bật đèn khẩn cấp.',
            '🧳 Bác tài đã sẵn sàng, mời bạn ra xe nhé!',
            '📞 Bạn gọi cho mình nếu chưa tìm thấy xe nhé.',
          ]
        : [
            '🚌 Bác tài ơi xe sắp tới điểm đón chưa ạ?',
            '📍 Em đang đứng chờ tại sảnh đón/cổng chính.',
            '🧳 Em mặc áo khoác sẫm màu, có 2 kiện vali ạ.',
            '⏱️ Xe dự kiến tới lúc mấy giờ vậy bác tài?',
          ];

    return Container(
      height: 38,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        scrollDirection: Axis.horizontal,
        itemCount: quickTexts.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final t = quickTexts[i];
          return ActionChip(
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFBAE6FD)),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            label: Text(
              t,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0369A1)),
            ),
            onPressed: () => _sendMessage(t),
          );
        },
      ),
    );
  }

  String _formatMessageTime(dynamic dt) {
    if (dt == null) return '';
    try {
      final parsed = DateTime.parse(dt.toString()).toLocal();
      final h = parsed.hour.toString().padLeft(2, '0');
      final m = parsed.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }
}
