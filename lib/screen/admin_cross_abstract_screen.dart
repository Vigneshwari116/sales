import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/repositories/abstract_repository.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

/// Admin abstract with per-location filter (or all locations combined).
class AdminCrossAbstractScreen extends StatefulWidget {
  const AdminCrossAbstractScreen({super.key});

  @override
  State<AdminCrossAbstractScreen> createState() =>
      _AdminCrossAbstractScreenState();
}

class _AdminCrossAbstractScreenState extends State<AdminCrossAbstractScreen> {
  static const _allLocationsKey = '__all__';

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  String _selectedLocationKey = displayNameForLocationCode('win1');
  bool _loading = true;
  String? _dateRangeError;
  AbstractSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  bool get _isDateRangeValid {
    final from = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
    final to = DateTime(_toDate.year, _toDate.month, _toDate.day);
    return !to.isBefore(from);
  }

  Future<void> _loadSummary() async {
    if (!_isDateRangeValid) {
      setState(() {
        _loading = false;
        _dateRangeError = 'To Date cannot be before From Date';
        _summary = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _dateRangeError = null;
    });

    final AbstractSummary summary;
    if (_selectedLocationKey == _allLocationsKey) {
      summary = await AbstractRepository.getCrossLocationSummary(
        fromDate: _fromDate,
        toDate: _toDate,
      );
    } else {
      summary = await AbstractRepository.getSummaryForDateRange(
        location: _selectedLocationKey,
        fromDate: _fromDate,
        toDate: _toDate,
      );
    }

    if (!mounted) return;

    setState(() {
      _summary = summary;
      _loading = false;
    });
  }

  void _setToday() {
    final now = DateTime.now();
    setState(() {
      _fromDate = now;
      _toDate = now;
    });
    _loadSummary();
  }

  String _formatMoney(double value) => NumberFormat('#,##0.00').format(value);

  String get _appBarTitle => 'SALES ABSTRACT';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(_appBarTitle),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CenteredContent(
              maxWidth: 1100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          key: const Key('admin_abstract_location'),
                          value: _selectedLocationKey,
                          isExpanded: true,
                          isDense: true,
                          decoration: const InputDecoration(
                            labelText: 'Location',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: _allLocationsKey,
                              child: Text('All locations'),
                            ),
                            for (final code in allLocationCodes)
                              DropdownMenuItem(
                                value: displayNameForLocationCode(code),
                                child: Text(displayNameForLocationCode(code)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _selectedLocationKey = value);
                            _loadSummary();
                          },
                        ),
                      ),
                      DateRangeButton(
                        fromDate: _fromDate,
                        toDate: _toDate,
                        onChanged: (range) {
                          setState(() {
                            _fromDate = range.start;
                            _toDate = range.end;
                          });
                          _loadSummary();
                        },
                      ),
                      OutlinedButton(
                        onPressed: _setToday,
                        child: const Text('TODAY'),
                      ),
                    ],
                  ),
                  if (_dateRangeError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _dateRangeError!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: AppTextSizes.listTitle,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  CompactAbstractSummary(
                    totalSalesLabel: 'Total sales',
                    totalGstLabel: 'Total GST',
                    totalSalesValue:
                        _formatMoney(_summary?.totalSaleAmount ?? 0),
                    totalGstValue: _formatMoney(_summary?.totalGst ?? 0),
                  ),
                ],
              ),
            ),
    );
  }
}
