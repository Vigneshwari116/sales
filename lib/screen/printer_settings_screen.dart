import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:sales/services/printer_settings_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  static const Color _background = Color(0xFFC5F6C5);
  static const Color _border = Color(0xFF888888);
  static const Color _header = Color(0xFFFFF5C5);

  bool _loading = true;
  String? _error;
  List<Printer> _printers = [];

  final Map<PrinterType, String?> _savedPrinters = {};
  final Map<PrinterType, String?> _selectedPrinters = {};
  final Map<PrinterType, bool> _saving = {
    PrinterType.thermal: false,
    PrinterType.a4: false,
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
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'PRINTER SETTINGS',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFFD5D8D5),
        foregroundColor: Colors.black,
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
                        style: const TextStyle(color: Colors.red),
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
        color: Colors.white,
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: _header,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              type.settingsTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                if (_printers.isEmpty)
                  const Text(
                    'No printers found on this system.',
                    style: TextStyle(fontSize: 12),
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
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: printer.url.isNotEmpty
                          ? Text(
                              printer.url,
                              style: const TextStyle(fontSize: 10),
                            )
                          : null,
                    );
                  }),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: saving ? null : () => _saveSelection(type),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9D1717),
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
