abstract interface class DatabaseClient {
  bool get isInitialized;

  Future<void> initialize();

  Future<void> close();
}
