import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'utils/date_utils.dart';
import 'utils/author_utils.dart';
import 'utils/common_utils.dart';
import 'package:help_desk/config.dart';
import 'dio_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TicketDetailsScreen extends StatefulWidget {
  final String ticketId;

  const TicketDetailsScreen({Key? key, required this.ticketId}) : super(key: key);

  @override
  _TicketDetailsScreenState createState() => _TicketDetailsScreenState();
}

class _TicketDetailsScreenState extends State<TicketDetailsScreen> with AutomaticKeepAliveClientMixin {
  late final Dio _dio;
  Map<String, dynamic>? _ticketDetails;
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, String>> _replies = [];
  final TextEditingController _replyController = TextEditingController();
  String? _replyId;
  final Set<String> _expandedReplies = {};
  String? _solutionReplyId;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _facilityController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String? _currentUserId;
  String? _currentUserRole;

  // Add a cache for author names in replies
  final Map<String, String> _replyAuthorCache = {};

  @override
  void initState() {
    super.initState();
    _initializeDio().then((_) {
      _fetchCurrentUserIdAndRole();
      _fetchTicketDetails();
    });
  }

  Future<void> _initializeDio() async {
    _dio = await DioClient.getInstance(context);
  }

  Future<void> _fetchCurrentUserIdAndRole() async {
    try {
      final userId = await _secureStorage.read(key: 'user_id');
      final role = await _secureStorage.read(key: 'role');
      if (mounted) {
        setState(() {
          _currentUserId = userId;
          _currentUserRole = role;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to fetch user details.';
        });
      }
    }
  }

  Future<void> _fetchTicketDetails() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await _dio.get('$API_HOST/tickets/${widget.ticketId}');
      final ticketDetails = response.data;
      final solutionReplyId = ticketDetails['solution_reply_id'];

      // Fetch replies in parallel
      final replies = await Future.wait(
        (ticketDetails['replies'] as List<dynamic>).map((reply) async {
          final replyId = reply['reply_id']?.toString() ?? '';
          final author = await _getReplyAuthorName(reply); // Use cached author name
          return {
            'author': author,
            'message': reply['reply_text']?.toString() ?? '',
            'replyId': replyId,
            'parentReplyId': reply['parent_reply_id']?.toString() ?? '',
            'timestamp': reply['created_at']?.toString() ?? '',
          };
        }),
      );

      final authorDisplay = await AuthorUtils.getAuthorName(ticketDetails);

      if (solutionReplyId != null) {
        final selectedReply = replies.firstWhere(
          (reply) => reply['replyId'] == solutionReplyId,
          orElse: () => <String, String>{},
        );
        if (selectedReply.isNotEmpty) {
          replies.remove(selectedReply);
          replies.insert(0, selectedReply);
        }
      }

      if (mounted) {
        setState(() {
          _ticketDetails = ticketDetails..['author_display'] = authorDisplay;
          _solutionReplyId = solutionReplyId;
          _replies = replies.cast<Map<String, String>>();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to fetch ticket details. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  // Helper function to get author name from cache or fetch if not available
  Future<String> _getReplyAuthorName(Map<String, dynamic> reply) async {
    final replyId = reply['reply_id']?.toString() ?? '';
    if (_replyAuthorCache.containsKey(replyId)) {
      return _replyAuthorCache[replyId]!;
    } else {
      final authorName = await AuthorUtils.getAuthorName(reply);
      _replyAuthorCache[replyId] = authorName; // Cache the author name
      return authorName;
    }
  }

  Future<void> _submitReply() async {
    if (_replyController.text.trim().isEmpty) return;

    final replyText = _replyController.text.trim();
    final parentReplyId = _replyId;

    if (mounted) {
      setState(() {
        _replyController.clear();
        _replyId = null;
      });
    }

    try {
      final data = {
        'reply_text': replyText,
        if (parentReplyId != null) 'parent_reply_id': parentReplyId,
      };

      await _dio.post(
        '$API_HOST/tickets/${widget.ticketId}/reply',
        data: jsonEncode(data),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      // Clear the reply author cache to reflect the new reply
      _replyAuthorCache.clear();

      await _fetchTicketDetails();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to submit reply. Please try again.';
        });
      }
    }
  }

  Future<void> _updateTicketDetails() async {
    if (_titleController.text.trim().isEmpty || _descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and Description cannot be empty.')),
      );
      return;
    }

    try {
      final data = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'facility': _facilityController.text.trim(),
        'category': _categoryController.text.trim(),
      };

      final response = await _dio.patch(
        '$API_HOST/tickets/${widget.ticketId}',
        data: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ticket updated successfully.')),
        );
        await _fetchTicketDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update ticket. Please try again.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An error occurred. Please try again.')),
      );
    }
  }

  Future<void> _markAsSolution(String replyId) async {
    try {
      final data = {'reply_id': replyId};

      final response = await _dio.patch(
        '$API_HOST/tickets/${widget.ticketId}/solution',
        data: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reply marked as solution successfully.')),
        );
        await _fetchTicketDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to mark reply as solution. Please try again.')),
        );
      }
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An error occurred. Please try again.')),
      );
    }
  }

  Future<void> _confirmMarkAsSolution(String replyId) async {
    final shouldMark = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Solution'),
        content: const Text('Are you sure you want to mark this reply as the solution?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark as Solution'),
          ),
        ],
      ),
    );

    if (shouldMark == true) {
      _markAsSolution(replyId);
    }
  }

  Future<void> _reopenTicket() async {
    try {
      final data = {'reply_id': null};

      final response = await _dio.patch(
        '$API_HOST/tickets/${widget.ticketId}/solution',
        data: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ticket re-opened successfully.')),
        );
        await _fetchTicketDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to re-open ticket. Please try again.')),
        );
      }
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An error occurred. Please try again.')),
      );
    }
  }

  Future<void> _confirmReopenTicket() async {
    final shouldReopen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-open Ticket'),
        content: const Text('Are you sure you want to re-open this ticket?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Re-open'),
          ),
        ],
      ),
    );

    if (shouldReopen == true) {
      _reopenTicket();
    }
  }

  Future<void> _confirmUpdateTicketDetails() async {
    final shouldUpdate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Ticket'),
        content: const Text('Are you sure you want to update this ticket?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (shouldUpdate == true) {
      _updateTicketDetails();
    }
  }

 void _showEditDialog() {
    showTicketModal(
      context: context,
      title: 'Edit Ticket',
      initialTitle: _ticketDetails?['title'],
      initialDescription: _ticketDetails?['description'],
      initialFacility: _ticketDetails?['facility'],
      initialCategory: _ticketDetails?['category'],
      facilityList: facilityList,
      categoryList: categoryList,
      onSave: (String title, String description, String facility, String category) {
        _titleController.text = title;
        _descriptionController.text = description;
        _facilityController.text = facility;
        _categoryController.text = category;
        _confirmUpdateTicketDetails();
      },
    );
  }

  Widget _buildThreadedReplies(List<Map<String, String>> replies, {String? parentReplyId, int depth = 0}) {
    const int maxDepth = 2; // Limit the depth of visible replies
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: replies
          .where((reply) => reply['parentReplyId'] == (parentReplyId ?? ''))
          .map((reply) => Padding(
                padding: EdgeInsets.only(left: depth * 16.0, top: 8.0),
                child: Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: reply['replyId'] == _solutionReplyId
                        ? Colors.green.withOpacity(0.2) // Highlight selected answer
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.0),
                    border: reply['replyId'] == _solutionReplyId
                        ? Border.all(color: Colors.green, width: 2.0) // Add border for selected answer
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${reply['author']} • ${formatTimestamp(reply['timestamp'])}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reply['message']!,
                        style: const TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                      if (reply['replyId'] == _solutionReplyId)
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Selected Answer',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                          ),
                        ),
                      if ((_ticketDetails?['created_by'] == _currentUserId || _currentUserRole == 'admin') && _ticketDetails?['solution_reply_id']  == null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => _confirmMarkAsSolution(reply['replyId']!), // Use confirmation dialog
                            child: const Text(
                              'Mark as Solution',
                              style: TextStyle(color: Colors.blueAccent),
                            ),
                          ),
                        )
                      else Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox.shrink(), // Keeps the layout but hides the button
                      ),
                      if (depth < maxDepth || _expandedReplies.contains(reply['replyId']))
                        _buildThreadedReplies(replies, parentReplyId: reply['replyId'], depth: depth + 1)
                      else
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () {
                              setState(() {
                                _expandedReplies.add(reply['replyId']!); // Mark this reply as expanded
                              });
                            },
                            child: const Text(
                              'View More Replies',
                              style: TextStyle(color: Colors.blueAccent),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Ticket Details',
          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1B2A49), // Solid background color for better readability
        elevation: 2, // Slight shadow for better separation
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_ticketDetails != null &&
              (_ticketDetails?['created_by'] == _currentUserId || _currentUserRole == 'admin')) // Use _currentUserRole
            Row(
              children: [
                if (_ticketDetails?['status'] == 'closed') // Show Re-open button only for closed tickets
                  IconButton(
                    icon: const Icon(Icons.replay, color: Colors.white),
                    onPressed: _confirmReopenTicket, // Use confirmation dialog
                  ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white),
                  onPressed: _showEditDialog, // Triggers the edit dialog
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _fetchTicketDetails(),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E1E2C), Color(0xFF232946)], // Previous gradient colors
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _ticketDetails == null
                                  ? [const Center(child: Text('No ticket details available', style: TextStyle(color: Colors.white)))]
                                  : [
                                      Text(
                                        _ticketDetails?['title'] ?? 'No Title',
                                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                                        decoration: BoxDecoration(
                                          color: Colors.tealAccent.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(12.0),
                                          border: Border.all(color: Colors.tealAccent),
                                        ),
                                        child: Text(
                                          'Ticket #: ${_ticketDetails?['ticket_number'] ?? 'N/A'}', // Highlight ticket number
                                          style: const TextStyle(color: Colors.tealAccent, fontSize: 14, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _ticketDetails?['author_display'] ?? 'Unknown',
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        formatTimestamp(_ticketDetails?['created_at']),
                                        style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.white70),
                                      ),
                                      const SizedBox(height: 8),
                                      if (_ticketDetails?['updated_at'] != null)
                                        Text(
                                          'Last updated by: ${_ticketDetails?['updated_by_name'] ?? 'Unknown'} on ${formatTimestamp(_ticketDetails?['updated_at'])}',
                                          style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.white70),
                                        ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _ticketDetails?['description'] ?? 'No Description',
                                        style: const TextStyle(fontSize: 16, color: Colors.white70, height: 1.5),
                                      ),
                                      const SizedBox(height: 24),
                                      Wrap(
                                        spacing: 12.0,
                                        runSpacing: 8.0,
                                        children: [
                                          _buildBadge('Category', _ticketDetails?['category'] ?? 'N/A', Colors.blue),
                                          _buildBadge('Facility', _ticketDetails?['facility'] ?? 'N/A', Colors.orange),
                                          _buildBadge(
                                            'Status',
                                            _ticketDetails?['status'] == 'open' ? 'ACTIVE' : 'CLOSED',
                                            _ticketDetails?['status'] == 'open' ? Colors.green : Colors.red,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 24),
                                      const Text(
                                        'Replies:',
                                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                      const SizedBox(height: 12),
                                      _buildThreadedReplies(_replies),
                                    ],
                            ),
                          ),
                        ),
                      ),
                      if (_replyId != null)
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          color: Colors.blueAccent.withOpacity(0.2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Replying to: ${_replies.firstWhere((reply) => reply['replyId'] == _replyId)['message']}',
                                  style: const TextStyle(color: Colors.blueAccent, fontSize: 14),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.blueAccent),
                                onPressed: () {
                                  setState(() {
                                    _replyId = null;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1B2A49),
                          border: Border(top: BorderSide(color: Colors.white24)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _replyController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: _replyId == null ? 'Write a reply...' : 'Replying to a reply...',
                                  hintStyle: const TextStyle(color: Colors.white54),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                    borderSide: const BorderSide(color: Colors.white24),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF0A0F24),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.send, color: Colors.blueAccent),
                              onPressed: _submitReply,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: color),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _facilityController.dispose();
    _categoryController.dispose();
    _replyController.dispose();
    super.dispose();
  }
}
