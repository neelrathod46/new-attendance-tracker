import 'package:flutter/material.dart';

import '../services/supabase_client.dart';

class IdentityApprovalsScreen extends StatefulWidget {
  const IdentityApprovalsScreen({super.key});

  @override
  State<IdentityApprovalsScreen> createState() =>
      _IdentityApprovalsScreenState();
}

class _IdentityApprovalsScreenState extends State<IdentityApprovalsScreen> {
  late Future<List<Map<String, dynamic>>> _requests;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _requests = _loadRequests();
  }

  Future<List<Map<String, dynamic>>> _loadRequests() async {
    final result = await AppSupabase.client.rpc('list_pending_identity_changes');
    if (result is! List) return const [];
    return result
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    setState(() {
      _actionError = null;
      _requests = _loadRequests();
    });
    await _requests;
  }

  Future<void> _review(Map<String, dynamic> request, bool approve) async {
    final action = approve ? 'Approve this identity change?' : 'Reject this request?';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action),
        content: Text(
          approve
              ? 'The approved roll number, name, or face enrollment becomes active immediately.'
              : 'The student’s current identity remains unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AppSupabase.client.rpc(
        'review_identity_change',
        params: {
          'p_request_id': request['id'],
          'p_approve': approve,
          'p_review_note': null,
        },
      );
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _actionError = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Identity change requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh requests',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _requests,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _message('Could not load approval requests: ${snapshot.error}');
          }
          final requests = snapshot.data ?? const [];
          if (requests.isEmpty) return _message('No pending identity changes.');
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Approved changes update the official student record. Each decision is written to the audit history.',
                style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
              ),
              if (_actionError != null) ...[
                const SizedBox(height: 12),
                Text(_actionError!, style: const TextStyle(color: Color(0xFFEF4444))),
              ],
              const SizedBox(height: 12),
              for (final request in requests) _requestCard(request),
            ],
          );
        },
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> request) {
    final requestedRoll = request['requested_roll_no'] as String?;
    final requestedName = request['requested_full_name'] as String?;
    final faceChange = request['face_change'] == true;
    final changes = <String>[
      if (requestedRoll != null) 'Roll number: $requestedRoll',
      if (requestedName != null) 'Name: $requestedName',
      if (faceChange) 'Face enrollment replacement',
    ];
    return Card(
      color: const Color(0xFF1E293B),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request['full_name']} · ${request['roll_no']}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            for (final change in changes) Text(change),
            const SizedBox(height: 8),
            Text(
              'Reason: ${request['reason']}',
              style: const TextStyle(color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _review(request, false),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _review(request, true),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
