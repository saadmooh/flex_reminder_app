
class NoValidSubscriptionException implements Exception {
  final String message;
  
  NoValidSubscriptionException(this.message);
  
  @override
  String toString() => message;
}