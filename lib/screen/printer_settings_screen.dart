import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:sales/services/printer_settings_service.dart';
import 'package:sales/theme/app_theme.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  bool _loading = true;
  String? _error;
  List<Printer> _printers = [];

  final Map<PrinterType, String?> _savedPrinters = {};
  final Map<PrinterType, String?> _selectedPrinters = {};
  final Map<PrinterType, bool> _saving = {
    for (final type in PrinterType.values) type: false,
  };

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final printers = await Printing.listPrinters();

      for (final type in PrinterType.values) {
        final saved = await PrinterSettingsService.getDefaultPrinter(type);
        _savedPrinters[type] = saved;
        _selectedPrinters[type] = _matchSavedPrinter(saved, printers);
      }

      if (!mounted) return;

      setState(() {
        _printers = printers;
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

  String? _matchSavedPrinter(String? saved, List<Printer> printers) {
    if (saved == null || saved.isEmpty) {
      return null;
    }

    for (final printer in printers) {
      final key = _printerKey(printer);
      if (key == saved || printer.name == saved) {
        return key;
      }
    }

    return saved;
  }

  Future<void> _saveSelection(PrinterType type) async {
    final selected = _selectedPrinters[type];
    if (selected == null || selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Select a ${type.label.toLowerCase()} printer first')),
      );
      return;
    }

    setState(() => _saving[type] = true);

    await PrinterSettingsService.setDefaultPrinter(type, selected);

    if (!mounted) return;

    setState(() {
      _savedPrinters[type] = selected;
      _saving[type] = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${type.label} printer saved: $selected')),
    );
  }

  String _printerLabel(Printer printer) => printer.name;

  String _printerKey(Printer printer) {
    return printer.url.isNotEmpty ? printer.url : printer.name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'PRINTER SETTINGS',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTextSizes.appBarTitle,
          ),
        ),
        backgroundColor: AppColors.headerBand,
        foregroundColor: AppColors.navy,
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadPrinters,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh printers',
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
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final type in PrinterType.values) ...[
                          _buildTypeSection(type),
                          if (type != PrinterType.values.last)
                            const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTypeSection(PrinterType type) {
    final saved = _savedPrinters[type];
    final selected = _selectedPrinters[type];
    final saving = _saving[type] ?? false;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.tableHeader,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              type.settingsTitle,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTextSizes.listTitle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  saved != null && saved.isNotEmpty
                      ? 'Current: $saved'
                      : 'No ${type.label.toLowerCase()} printer selected',
                  style: const TextStyle(
                    fontSize: AppTextSizes.listTitle,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                if (_printers.isEmpty)
                  const Text(
                    'No printers found on this system.',
                    style: TextStyle(fontSize: AppTextSizes.listTitle),
                  )
                else
                  ..._printers.map((printer) {
                    final key = _printerKey(printer);

                    return RadioListTile<String>(
                      value: key,
                      groupValue: selected,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setState(() => _selectedPrinters[type] = value);
                      },
                      title: Text(
                        _printerLabel(printer),
                        style: const TextStyle(fontSize: AppTextSizes.fieldText),
                      ),
                      subtitle: printer.url.isNotEmpty
                          ? Text(
                              printer.url,
                              style: const TextStyle(
                                fontSize: AppTextSizes.listSubtitle,
                              ),
                            )
                          : null,
                    );
                  }),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: saving ? null : () => _saveSelection(type),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'SAVE ${type.settingsTitle}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
