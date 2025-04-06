import 'package:flutter/material.dart';
import '../utils/author_utils.dart';
import 'package:intl/intl.dart';

class TicketCard extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final VoidCallback onTap;

  const TicketCard({
    Key? key,
    required this.ticket,
    required this.onTap,
  }) : super(key: key);

  @override
  _TicketCardState createState() => _TicketCardState();
}

class _TicketCardState extends State<TicketCard> with AutomaticKeepAliveClientMixin {
  String? _authorName;
  bool _isLoadingAuthor = true;

  @override
  void initState() {
    super.initState();
    _loadAuthorName();
  }

  Future<void> _loadAuthorName() async {
    try {
      final name = await AuthorUtils.getAuthorName(widget.ticket);
      if (mounted) {
        setState(() {
          _authorName = name;
          _isLoadingAuthor = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _authorName = 'Error';
          _isLoadingAuthor = false;
        });
      }
    }
  }

  String formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dateTime = DateTime.parse(timestamp.toString());
      return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
    } catch (_) {
      return timestamp.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final ticket = widget.ticket;

    return Card(
      color: const Color(0xFF162447),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 5,
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                ticket['title'],
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.tealAccent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Ticket #: ${ticket['ticket_number']}',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              ticket['description'],
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              'Created: ${formatTimestamp(ticket['created_at'])}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              'Author: ${_isLoadingAuthor ? 'Loading...' : _authorName}',
              style: TextStyle(
                color: _isLoadingAuthor ? Colors.white54 : (_authorName == 'Error' ? Colors.redAccent : Colors.white54),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (ticket['category'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      ticket['category'],
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                if (ticket['facility'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: Colors.lightBlueAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      ticket['facility'],
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: ticket['status'] == 'open' ? Colors.orangeAccent : Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    ticket['status'] == 'open' ? 'ACTIVE' : 'CLOSED',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: widget.onTap,
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
