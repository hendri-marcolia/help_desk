import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import 'login_screen.dart';
import 'config.dart';
import 'ticket_details_screen.dart';
import 'utils/date_utils.dart'; // Import the utility file
import 'dio_client.dart';
import 'utils/author_utils.dart'; // Import the author_util file
import 'utils/common_utils.dart'; // Import the shared modal function
import 'widgets/custom_dropdown.dart';
import 'widgets/ticket_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late final Dio _dio;
  late TabController _tabController;
  List<dynamic> _tickets = [];
  bool _isLoading = true;
  bool _isFetchingMore = false;
  String? _errorMessage;
  dynamic _nextStartKey;
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  String? _categoryFilter;
  String? _facilityFilter;
  String? _searchQuery;
  final String _sortOrder = "desc";
  final int _limit = 20;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeDio().then((_) {
      _fetchTickets(); // Call fetchTickets after Dio is initialized
    });
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initializeDio() async {
    _dio = await DioClient.getInstance(context); // Use DioClient
  }

  @override
  void dispose() {
    _tabController.dispose();
    _debounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchTickets({bool loadMore = false}) async {
    if (loadMore && (_isFetchingMore || _nextStartKey == null)) return;

    setState(() {
      if (loadMore) {
        _isFetchingMore = true;
      } else {
        _isLoading = true;
        _nextStartKey = null; // Reset start key for new fetch
      }
    });

    try {
      final response = await _dio.get(
        '$API_HOST/tickets',
        queryParameters: {
          'status': _tabController.index == 0 ? 'open' : 'closed',
          if (_categoryFilter != null) 'category': _categoryFilter,
          if (_facilityFilter != null) 'facility': _facilityFilter,
          if (_searchQuery != null) 'search': _searchQuery,
          'sort': _sortOrder,
          'limit': _limit,
          if (loadMore && _nextStartKey != null) 
            'start_key': jsonEncode(_nextStartKey),
        },
      );

      setState(() {
        _errorMessage = null; // Clear error message on success
        if (loadMore) {
          _tickets.addAll(response.data['tickets']);
        } else {
          _tickets = response.data['tickets'];
        }
        _nextStartKey = response.data['next_start_key']; // Update start key
        _isLoading = false;
        _isFetchingMore = false;
        print("Ticket size ${_tickets.length}"); // Debugging line
      
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
        _isLoading = false;
        _isFetchingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _fetchTickets(loadMore: true);
    }
  }

  Future<void> _logout() async {
    await _storage.deleteAll();
    _dio.interceptors.clear(); // Clear interceptors to avoid token issues
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = value.isEmpty ? null : value;
        _tickets = [];
        _nextStartKey = null; // Reset start key for new search
      });
      _fetchTickets();
    });
  }

  void _showCreateTicketDialog() {
    showTicketModal(
      context: context,
      title: 'Create Ticket',
      initialTitle: null,
      initialDescription: null,
      initialFacility: null,
      initialCategory: null,
      facilityList: facilityList,
      categoryList: categoryList,
      onSave: (title, description, facility, category) async {
        try {
          final response = await _dio.post(
            '$API_HOST/tickets/create',
            data: {
              'title': title,
              'description': description,
              'facility': facility,
              'category': category,
            },
          );
          _fetchTickets(); // Refresh tickets
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TicketDetailsScreen(
                ticketId: response.data['ticket_id'],
              ),
            ),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to create ticket')),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Home',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A0F24), Color(0xFF1B2A49)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              child: Text('Open Tickets', style: TextStyle(color: Colors.white)),
            ),
            Tab(
              child: Text('Closed Tickets', style: TextStyle(color: Colors.white)),
            ),
          ],
          onTap: (index) {
            setState(() {
              _isLoading = true;
              _tickets = [];
              _nextStartKey = null; // Reset start key when switching tabs
            });
            _fetchTickets();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _fetchTickets(),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem(
                  value: 'logout',
                  child: Text('Logout'),
                ),
              ];
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0F24), Color(0xFF1B2A49)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 600) {
                    // Landscape: All components in one line
                    return Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildSearchBar(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: CustomDropdown(
                            value: _categoryFilter,
                            hint: 'Category',
                            items: ['All', ...categoryList],
                            onChanged: (value) {
                              setState(() {
                                _categoryFilter = value == 'All' ? null : value;
                                _fetchTickets();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: CustomDropdown(
                            value: _facilityFilter,
                            hint: 'Facility',
                            items: ['All', ...facilityList],
                            onChanged: (value) {
                              setState(() {
                                _facilityFilter = value == 'All' ? null : value;
                                _fetchTickets();
                              });
                            },
                          ),
                        ),
                      ],
                    );
                  } else {
                    // Portrait: Components stacked vertically
                    return Column(
                      children: [
                        _buildSearchBar(),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: CustomDropdown(
                                value: _categoryFilter,
                                hint: 'Category',
                                items: ['All', ...categoryList],
                                onChanged: (value) {
                                  setState(() {
                                    _categoryFilter = value == 'All' ? null : value;
                                    _fetchTickets();
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: CustomDropdown(
                                value: _facilityFilter,
                                hint: 'Facility',
                                items: ['All', ...facilityList],
                                onChanged: (value) {
                                  setState(() {
                                    _facilityFilter = value == 'All' ? null : value;
                                    _fetchTickets();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  }
                },
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRefreshableTicketList(), // Open Tickets
                  _buildRefreshableTicketList(), // Closed Tickets
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 10), // Add some margin for better positioning
        child: FloatingActionButton(
          onPressed: _showCreateTicketDialog,
          backgroundColor: Colors.tealAccent,
          foregroundColor: Colors.black,
          child: const Icon(Icons.note_add, size: 28), // Changed to a ticket-related icon
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Search tickets...',
        prefixIcon: const Icon(Icons.search, color: Colors.black),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value ?? 'All',
      decoration: InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        filled: true,
        fillColor: Colors.white,
      ),
      items: items
          .map((item) => DropdownMenuItem(
                value: item,
                child: Text(
                  item,
                  style: const TextStyle(color: Colors.black),
                ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildRefreshableTicketList() {
    final ScrollController localScrollController = ScrollController(); // Use a local ScrollController
    localScrollController.addListener(() {
      if (localScrollController.position.pixels >= localScrollController.position.maxScrollExtent - 200) {
        _fetchTickets(loadMore: true);
      }
    });

    return GestureDetector(
      onHorizontalDragEnd: (details) async {
        if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
          // Swiped right
          if (_tabController.index > 0) {
            setState(() {
              _tabController.index -= 1;
              _isLoading = true;
              _tickets = [];
              _nextStartKey = null;
            });
            await _fetchTickets();
          }
        } else if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
          // Swiped left
          if (_tabController.index < _tabController.length - 1) {
            setState(() {
              _tabController.index += 1;
              _isLoading = true;
              _tickets = [];
              _nextStartKey = null;
            });
            await _fetchTickets();
          }
        }
      },
      child: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _isLoading = true;
            _tickets = [];
            _nextStartKey = null;
          });
          await _fetchTickets();
        },
        child: _buildTicketList(localScrollController),
      ),
    );
  }

  Widget _buildTicketList(ScrollController localScrollController) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: const TextStyle(color: Colors.redAccent, fontSize: 16),
        ),
      );
    }
     if (_tickets.isEmpty && !_isFetchingMore) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.inbox, size: 80, color: Colors.white70), // Placeholder icon
            SizedBox(height: 16),
            Text(
              'No tickets available.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
          controller: localScrollController, // Use the local ScrollController
          padding: const EdgeInsets.all(12),
          itemCount: _tickets.length + (_isFetchingMore ? 1 : 0),
          // Use a key for each item to help Flutter optimize rebuilds
          key: PageStorageKey('ticket_list_${_tabController.index}'),
          // Use addAutomaticKeepAlives to maintain state when scrolling
          addAutomaticKeepAlives: true,
          // Use addRepaintBoundaries to optimize painting
          addRepaintBoundaries: true,
          itemBuilder: (context, index) {
            if (index >= _tickets.length) {
              return const Center(child: CircularProgressIndicator()); // Show loading indicator at the end
            }
            final ticket = _tickets[index];
            return TicketCard(
              key: ValueKey('ticket_${ticket['ticket_id']}'),
              ticket: ticket,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TicketDetailsScreen(
                      ticketId: ticket['ticket_id'],
                    ),
                  ),
                );
              },
            );
          },
        );
  }
}
