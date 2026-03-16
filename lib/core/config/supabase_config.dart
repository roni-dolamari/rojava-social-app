import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://bjstjhjyqrqdysikbdhs.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJqc3RqaGp5cXJxZHlzaWtiZGhzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0NzM5OTEsImV4cCI6MjA4NjA0OTk5MX0.EYvn_bqZWgwO8mIY2246jB-XaKk5ko4TMC6ca0BwIVU';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => Supabase.instance.client.auth;
}
