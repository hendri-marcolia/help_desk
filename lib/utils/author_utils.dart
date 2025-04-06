import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthorUtils {
  static final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static String? _cachedUserId;
  
  // Cache for author names to avoid repeated string operations
  static final Map<String, String> _authorNameCache = {};
  
  static Future<String> getAuthorName(Map<String, dynamic> data) async {
    // Get author ID
    final authorId = data['created_by']?.toString();
    
    // If no author ID, return unknown
    if (authorId == null || authorId.isEmpty) {
      return 'Unknown';
    }
    
    // Check if we already have this author name in cache
    final cacheKey = '${authorId}_${data['created_by_name']}';
    if (_authorNameCache.containsKey(cacheKey)) {
      return _authorNameCache[cacheKey]!;
    }
    
    // Get current user ID if not already cached
    if (_cachedUserId == null) {
      _cachedUserId = await _storage.read(key: 'user_id') ?? '';
    }
    
    // Determine if this is the current user
    final isLoggedUser = authorId == _cachedUserId;
    
    // Get display name
    final displayName = data['created_by_name'] ?? authorId;
    
    // Create formatted name
    final formattedName = isLoggedUser ? '$displayName (You)' : displayName;
    
    // Cache the result
    _authorNameCache[cacheKey] = formattedName;
    
    return formattedName;
  }

  static Future<void> clearCache() async {
    await _storage.delete(key: 'user_id');
    _cachedUserId = null;
    _authorNameCache.clear();
  }
}
