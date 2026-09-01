import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:sales/services/printer_settings_service.dart';
import 'package:sales/theme/app_theme.dart';

/// Staff-only thermal printer picker — live OS list, thermal devices only.
class StaffThermalPrinterScreen extends StatefulWidget {
  const StaffThermalPrinterScreen({super.key});

  @override
  State<StaffThermalPrinterScreen> createState() =>
      _StaffThermalPrinterScreenState();
}

class _StaffThermalPrinterScreenState extends State<StaffThermalPrinterScreen> {
  bool _loading = true;
  String? _error;
  List<Printer> _thermalPrinters = [];
  String? _selected;
  String? _saved;
  bool _saving = false;

  static bool _isThermalPrinter(Printer printer) {
    final name = printer.name.toLowerCase();
    final url = printer.url.toLowerCase();
    const thermalHints = [
      'thermal',
      'tvs',
      'epson tm',
      'star ',
      'bixolon',
      'pos-',
      'receipt',
      'rp 32',
      'rp-32',
    ];
    for (final hint in thermalHints) {
      if (name.contains(hint) || url.contains(hint)) {
        return true;
      }
    }
    return false;
  }

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
      final thermal = all.where(_isThermalPrinter).toList();
      final saved =
          await PrinterSettingsService.getDefaultPrinter(PrinterType.thermal);

      if (!mounted) return;

      setState(() {
        _thermalPrinters = thermal;
        _saved = saved;
        _selected = _matchSaved(saved, thermal);
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
        const SnackBar(content: Text('Select a thermal printer first')),
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
      SnackBar(content: Text('Thermal printer saved: $_selected')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'THERMAL PRINTER',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTextSizes.appBarTitle,
          ),
        ),
        backgroundColor: AppColors.headerBand,
        foregroundColor: AppColors.navy,
        automaticallyImplyLeading: false,
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
                    'Installed thermal printers on this computer (live OS list). '
                    'A4 and fast printers are not shown here.',
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
                    child: _thermalPrinters.isEmpty
                        ? const Center(
                            child: Text('No thermal printers detected.'),
                          )
                        : ListView.builder(
                            itemCount: _thermalPrinters.length,
                            itemBuilder: (context, index) {
                              final printer = _thermalPrinters[index];
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
