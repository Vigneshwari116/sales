import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/theme/app_theme.dart';

/// Compact from/to range picker — small dialog with month calendar grid.
Future<DateTimeRange?> showCompactDateRangePicker(
  BuildContext context, {
  required DateTime fromDate,
  required DateTime toDate,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (context) => _CompactDateRangeDialog(
      initialFrom: fromDate,
      initialTo: toDate,
    ),
  );
}

class _CompactDateRangeDialog extends StatefulWidget {
  final DateTime initialFrom;
  final DateTime initialTo;

  const _CompactDateRangeDialog({
    required this.initialFrom,
    required this.initialTo,
  });

  @override
  State<_CompactDateRangeDialog> createState() =>
      _CompactDateRangeDialogState();
}

class _CompactDateRangeDialogState extends State<_CompactDateRangeDialog> {
  static final DateTime _firstDate = DateTime(2020);
  static final DateTime _lastDate = DateTime(2100);

  late DateTime _from;
  late DateTime _to;
  late DateTime _focusedMonth;
  bool _editingFrom = true;

  @override
  void initState() {
    super.initState();
    _from = _dateOnly(widget.initialFrom);
    _to = _dateOnly(widget.initialTo);
    _focusedMonth = DateTime(_from.year, _from.month);
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime get _activeDate => _editingFrom ? _from : _to;

  void _setActiveDate(DateTime value) {
    setState(() {
      final picked = _dateOnly(value);
      if (_editingFrom) {
        _from = picked;
        if (_to.isBefore(_from)) {
          _to = _from;
        }
      } else {
        _to = picked;
        if (_to.isBefore(_from)) {
          _from = _to;
        }
      }
      _focusedMonth = DateTime(picked.year, picked.month);
    });
  }

  void _shiftMonth(int delta) {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    });
  }

  void _confirm() {
    Navigator.of(context).pop(DateTimeRange(start: _from, end: _to));
  }

  String _format(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'DATE RANGE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppTextSizes.sectionHeader,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 12),
              _rangeSelector(
                label: 'From date',
                value: _format(_from),
                selected: _editingFrom,
                onTap: () => setState(() => _editingFrom = true),
              ),
              const SizedBox(height: 8),
              _rangeSelector(
                label: 'To date',
                value: _format(_to),
                selected: !_editingFrom,
                onTap: () => setState(() => _editingFrom = false),
              ),
              const SizedBox(height: 12),
              _monthHeader(),
              const SizedBox(height: 6),
              _calendarGrid(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('CANCEL'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _confirm,
                      child: const Text('OK'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rangeSelector({
    required String label,
    required String value,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppColors.headerBand : AppColors.cardWhite,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? AppColors.navy : AppColors.border,
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSizes.listTitle,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.navy : AppColors.mutedBlue,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  fontSize: AppTextSizes.fieldText,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthHeader() {
    final label = DateFormat('MMMM yyyy').format(_focusedMonth);
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left, color: AppColors.navy),
          onPressed: () => _shiftMonth(-1),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: AppTextSizes.sectionHeader,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right, color: AppColors.navy),
          onPressed: () => _shiftMonth(1),
        ),
      ],
    );
  }

  Widget _calendarGrid() {
    const weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final firstOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final leading = firstOfMonth.weekday % 7;

    return Column(
      children: [
        Row(
          children: weekdayLabels
              .map(
                (label) => Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.mutedBlue,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leading + daysInMonth,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemBuilder: (context, index) {
            if (index < leading) {
              return const SizedBox.shrink();
            }
            final day = index - leading + 1;
            final date = DateTime(_focusedMonth.year, _focusedMonth.month, day);
            final disabled =
                date.isBefore(_firstDate) || date.isAfter(_lastDate);
            final isActive = _sameDay(date, _activeDate);
            final inRange = !date.isBefore(_from) && !date.isAfter(_to);

            return Material(
              color: isActive
                  ? AppColors.navy
                  : inRange
                      ? AppColors.headerBand
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                onTap: disabled ? null : () => _setActiveDate(date),
                borderRadius: BorderRadius.circular(4),
                child: Center(
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500,
                      color: disabled
                          ? AppColors.border
                          : isActive
                              ? Colors.white
                              : AppColors.navy,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
