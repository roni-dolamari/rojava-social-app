import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rojava/data/model/call_model.dart';
import 'package:rojava/data/services/call_service.dart';

final callServiceProvider = Provider((ref) => CallService());

final callsProvider = FutureProvider.family<List<CallModel>, String?>((
  ref,
  status,
) async {
  return ref.watch(callServiceProvider).getAllCalls(status: status);
});

final callStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  return ref.watch(callServiceProvider).getCallStats();
});
