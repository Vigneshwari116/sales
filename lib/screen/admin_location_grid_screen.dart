import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/repositories/abstract_repository.dart';

/// Admin main view: today's totals per location in a compact grid.
class AdminLocationGridScreen extends StatefulWidget {
  const AdminLocationGridScreen({super.key});

  @override
  State<AdminLocationGridScreen> createState() =>
      _AdminLocationGridScreenState();
}

class _AdminLocationGridScreenState extends State<AdminLocationGridScreen> {
  static const Color _background = Color(0xFFC5F6C5);
  static const Color _border = Color(0xFF888888);

  Map<String, AbstractSummary> _todayByLocation = {
    for (final code in allLocationCodes)
      displayNameForLocationCode(code): AbstractSummary.zero(),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final today = DateTime.now();
      final summaries = <String, AbstractSummary>{};

      for (final code in allLocationCodes) {
        final name = displayNameForLocationCode(code);
        summaries[name] = await AbstractRepository.getSummaryForLocationCode(
          locationCode: code,
          fromDate: today,
          toDate: today,
        );
      }

      if (!mounted) return;

      setState(() => _todayByLocation = summaries);
    } catch (_) {
      // Keep zeroed placeholders on error.
    }
  }

  String _formatMoney(double value) => NumberFormat('#,##0.00').format(value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'DASHBOARD',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFFE8F5E8),
        foregroundColor: Colors.black,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            for (final code in allLocationCodes)
              _locationCard(displayNameForLocationCode(code)),
          ],
        ),
      ),
    );
  }

  Widget _locationCard(String locationName) {
    final summary = _todayByLocation[locationName];

    return Container(
      key: Key('admin_location_card_${locationName.toLowerCase()}'),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            locationName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text('Today — Total sales', style: TextStyle(fontSize: 12)),
          Text(
            _formatMoney(summary?.totalSaleAmount ?? 0),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          const Text('Today — Total GST', style: TextStyle(fontSize: 12)),
          Text(
            _formatMoney(summary?.totalGst ?? 0),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
