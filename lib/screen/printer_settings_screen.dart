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

  bool _loading = true;
  bool _saving = false;
  String? _savedPrinter;
  String? _selectedPrinter;
  List<Printer> _printers = [];
  String? _error;

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
      final saved = await PrinterSettingsService.getDefaultPrinter();
      final printers = await Printing.listPrinters();
      String? matchedSelection;

      if (saved != null && saved.isNotEmpty) {
        for (final printer in printers) {
          final key = _printerKey(printer);
          if (key == saved || printer.name == saved) {
            matchedSelection = key;
            break;
          }
        }
        matchedSelection ??= saved;
      }

      if (!mounted) return;

      setState(() {
        _savedPrinter = saved;
        _selectedPrinter = matchedSelection;
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

  Future<void> _saveSelection() async {
    final selected = _selectedPrinter;
    if (selected == null || selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a printer first')),
      );
      return;
    }

    setState(() => _saving = true);

    await PrinterSettingsService.setDefaultPrinter(selected);

    if (!mounted) return;

    setState(() {
      _savedPrinter = selected;
      _saving = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Default printer saved: $selected')),
    );
  }

  String _printerLabel(Printer printer) {
    return printer.name;
  }

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
                  if (_savedPrinter != null && _savedPrinter!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _border),
                      ),
                      child: Text(
                        'Current default: $_savedPrinter',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (_savedPrinter != null && _savedPrinter!.isNotEmpty)
                    const SizedBox(height: 12),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  Expanded(
                    child: _printers.isEmpty
                        ? const Center(
                            child: Text(
                              'No printers found on this system.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: _border),
                            ),
                            child: ListView.separated(
                              itemCount: _printers.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final printer = _printers[index];
                                final key = _printerKey(printer);

                                return RadioListTile<String>(
                                  value: key,
                                  groupValue: _selectedPrinter,
                                  onChanged: (value) {
                                    setState(() => _selectedPrinter = value);
                                  },
                                  title: Text(_printerLabel(printer)),
                                  subtitle: printer.url.isNotEmpty
                                      ? Text(
                                          printer.url,
                                          style: const TextStyle(fontSize: 11),
                                        )
                                      : null,
                                );
                              },
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _saving ? null : _saveSelection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9D1717),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'SAVE DEFAULT PRINTER',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
