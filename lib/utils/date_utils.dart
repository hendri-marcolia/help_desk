import 'package:intl/intl.dart';

// Cache DateFormat instances to avoid recreating them
final _timeFormat = DateFormat('hh:mm a');
final _fullDateFormat = DateFormat('MMM d, yyyy at hh:mm a');

// Cache for formatted timestamps
final Map<String, _CachedTimestamp> _timestampCache = {};

class _CachedTimestamp {
  final String formattedString;
  final DateTime timestamp;
  final DateTime cacheTime;

  _CachedTimestamp(this.formattedString, this.timestamp)
      : cacheTime = DateTime.now();

  // Check if cache is still valid (less than 1 minute old)
  bool get isValid {
    return DateTime.now().difference(cacheTime).inMinutes < 1;
  }
}

String formatTimestamp(String? timestamp) {
  if (timestamp == null || timestamp.isEmpty) return 'Unknown';
  
  try {
    // Check cache first
    final cachedResult = _timestampCache[timestamp];
    if (cachedResult != null && cachedResult.isValid) {
      return cachedResult.formattedString;
    }
    
    // Normalize timestamp
    final normalizedTimestamp = timestamp.contains('Z') || timestamp.contains('+')
        ? timestamp
        : '${timestamp}Z';

    final dateTime = DateTime.parse(normalizedTimestamp).toUtc().toLocal();
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    String result;
    if (difference.inMinutes < 1) {
      result = 'Just now';
    } else if (difference.inMinutes < 60) {
      result = '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      result = '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      result = 'Yesterday at ${_timeFormat.format(dateTime)}';
    } else if (difference.inDays < 7) {
      result = '${difference.inDays} days ago at ${_timeFormat.format(dateTime)}';
    } else {
      result = _fullDateFormat.format(dateTime);
    }
    
    // Cache the result
    _timestampCache[timestamp] = _CachedTimestamp(result, dateTime);
    
    return result;
  } catch (e) {
    return 'Invalid date';
  }
}

// Call this periodically to clean up old cache entries
void cleanDateCache() {
  final now = DateTime.now();
  _timestampCache.removeWhere((key, value) => 
    now.difference(value.cacheTime).inMinutes > 10);
}
