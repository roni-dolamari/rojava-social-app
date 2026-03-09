import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rojava/data/model/call_model.dart';
import 'package:rojava/data/services/call_service.dart';

final callsProvider = FutureProvider.family<List<CallModel>, String?>((
  ref,
  status,
) async {
  return CallService().getAllCalls(status: status);
});

final callStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  return CallService().getCallStats();
});

final callServiceProvider = Provider((ref) => CallService());
