// services/youtube_service.dart

class YoutubeService {
  final String _apiKey = 'YOUR_YOUTUBE_API_KEY'; // استبدل بـ API Key الخاص بك

  /// Check if the URL is a YouTube video part of a playlist
  bool isPlaylistUrl(String url) {
    return url.contains('list=') &&
        url.contains('youtube.com') &&
        url.contains('v=');
  }

  /// Extract playlist and video details from URL
}
