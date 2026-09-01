import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:sales/services/printer_settings_service.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

/// Staff printer picker — live OS list of all installed printers.
class StaffThermalPrinterScreen extends StatefulWidget {
  const StaffThermalPrinterScreen({super.key});

  @override
  State<StaffThermalPrinterScreen> createState() =>
      _StaffThermalPrinterScreenState();
}

class _StaffThermalPrinterScreenState extends State<StaffThermalPrinterScreen> {
  bool _loading = true;
  String? _error;
  List<Printer> _printers = [];
  String? _selected;
  String? _saved;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final all = await Printing.listPrinters();
      final saved =
          await PrinterSettingsService.getDefaultPrinter(PrinterType.thermal);

      if (!mounted) return;

      setState(() {
        _printers = all;
        _saved = saved;
        _selected = _matchSaved(saved, all);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load printers: $e';
        _loading = false;
      });
    }
  }

  String? _matchSaved(String? saved, List<Printer> printers) {
    if (saved == null || saved.isEmpty) return null;
    for (final printer in printers) {
      final key = printer.url.isNotEmpty ? printer.url : printer.name;
      if (key == saved || printer.name == saved) {
        return key;
      }
    }
    return saved;
  }

  Future<void> _save() async {
    if (_selected == null || _selected!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a printer first')),
      );
      return;
    }

    setState(() => _saving = true);
    await PrinterSettingsService.setDefaultPrinter(
      PrinterType.thermal,
      _selected!,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = _selected;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Printer saved: $_selected')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(
        'PRINTER',
        actions: [
          IconButton(
            tooltip: 'Refresh printer list',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'All printers installed on this computer (live OS list). '
                    'Select the printer you want to use for bills and receipts.',
                    style: TextStyle(fontSize: AppTextSizes.listSubtitle),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: _printers.isEmpty
                        ? const Center(
                            child: Text('No printers detected on this system.'),
                          )
                        : ListView.builder(
                            itemCount: _printers.length,
                            itemBuilder: (context, index) {
                              final printer = _printers[index];
                              final key = printer.url.isNotEmpty
                                  ? printer.url
                                  : printer.name;
                              return RadioListTile<String>(
                                title: Text(printer.name),
                                subtitle: printer.url.isNotEmpty
                                    ? Text(
                                        printer.url,
                                        style: const TextStyle(
                                          fontSize: AppTextSizes.listSubtitle,
                                        ),
                                      )
                                    : null,
                                value: key,
                                groupValue: _selected,
                                onChanged: (value) {
                                  setState(() => _selected = value);
                                },
                              );
                            },
                          ),
                  ),
                  if (_saved != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Current: $_saved',
                      style: const TextStyle(fontSize: AppTextSizes.listSubtitle),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ElevatedButton(
                    key: const Key('staff_save_thermal_printer'),
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_saving ? 'SAVING...' : 'SAVE PRINTER'),
                  ),
                ],
              ),
            ),
    );
  }
}
