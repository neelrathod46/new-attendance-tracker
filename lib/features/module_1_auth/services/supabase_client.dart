import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase publishable credentials are client-side identifiers; database
/// access is restricted by the migration's grants and RLS policies.
class AppSupabase {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ccdskuhduhqzrurngbfg.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_4edtLt5E2lzrWvzO29Mvwg_k2yOQGp8',
  );

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() => Supabase.initialize(
    url: url,
    publishableKey: publishableKey,
  );
}
