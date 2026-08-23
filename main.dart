
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.load();
  runApp(StockManagerApp(store: store));
}

class StockManagerApp extends StatelessWidget {
  final AppStore store;
  const StockManagerApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'StockFlow',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      ),
      home: HomePage(store: store),
    );
  }
}

class StockItem {
  String id;
  String name;
  String unit;
  int stock;
  List<StockEntry> history;

  StockItem({
    required this.id,
    required this.name,
    this.unit = 'pcs',
    this.stock = 0,
    List<StockEntry>? history,
  }) : history = history ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'unit': unit,
        'stock': stock,
        'history': history.map((e) => e.toJson()).toList(),
      };

  factory StockItem.fromJson(Map<String, dynamic> j) => StockItem(
        id: j['id'],
        name: j['name'],
        unit: j['unit'] ?? 'pcs',
        stock: j['stock'] ?? 0,
        history: (j['history'] as List? ?? [])
            .map((e) => StockEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class StockEntry {
  String type;
  int qty;
  DateTime date;

  StockEntry({required this.type, required this.qty, required this.date});

  Map<String, dynamic> toJson() =>
      {'type': type, 'qty': qty, 'date': date.toIso8601String()};

  factory StockEntry.fromJson(Map<String, dynamic> j) => StockEntry(
        type: j['type'],
        qty: j['qty'],
        date: DateTime.parse(j['date']),
      );
}

class AppStore extends ChangeNotifier {
  String firmName = '';
  String address = '';
  String mobile = '';
  List<StockItem> items = [];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    firmName = p.getString('firmName') ?? '';
    address = p.getString('address') ?? '';
    mobile = p.getString('mobile') ?? '';
    final raw = p.getString('items');
    if (raw != null) {
      items = (jsonDecode(raw) as List)
          .map((e) => StockItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('firmName', firmName);
    await p.setString('address', address);
    await p.setString('mobile', mobile);
    await p.setString('items', jsonEncode(items.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Map<String, dynamic> exportBackup() => {
        'backupVersion': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'firmName': firmName,
        'address': address,
        'mobile': mobile,
        'items': items.map((e) => e.toJson()).toList(),
      };

  Future<void> restoreBackup(Map<String, dynamic> data) async {
    final rawItems = data['items'];
    if (rawItems is! List) {
      throw const FormatException('Invalid backup file');
    }
    firmName = (data['firmName'] ?? '').toString();
    address = (data['address'] ?? '').toString();
    mobile = (data['mobile'] ?? '').toString();
    items = rawItems
        .map((e) => StockItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    await save();
  }

  Future<void> setFirm(String n, String a, String m) async {
    firmName = n.trim();
    address = a.trim();
    mobile = m.trim();
    await save();
  }

  Future<void> addItem(String name, String unit) async {
    if (name.trim().isEmpty) return;
    if (items.any((x) => x.name.toLowerCase() == name.trim().toLowerCase())) {
      return;
    }
    items.add(StockItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      unit: unit.trim().isEmpty ? 'pcs' : unit.trim(),
    ));
    await save();
  }

  Future<void> stockIn(StockItem item, int qty) async {
    if (qty <= 0) return;
    item.stock += qty;
    item.history.add(StockEntry(type: 'IN', qty: qty, date: DateTime.now()));
    await save();
  }

  Future<bool> stockOut(StockItem item, int qty) async {
    if (qty <= 0 || qty > item.stock) return false;
    item.stock -= qty;
    item.history.add(StockEntry(type: 'OUT', qty: qty, date: DateTime.now()));
    await save();
    return true;
  }

  Future<void> deleteItem(StockItem item) async {
    items.remove(item);
    await save();
  }

  List<StockItem> get lowStock =>
      items.where((e) => e.stock > 0 && e.stock <= 2).toList();

  List<StockItem> get nilStock => items.where((e) => e.stock == 0).toList();

  int totalIn(StockItem i) =>
      i.history.where((e) => e.type == 'IN').fold(0, (a, b) => a + b.qty);

  int totalOut(StockItem i) =>
      i.history.where((e) => e.type == 'OUT').fold(0, (a, b) => a + b.qty);
}

class HomePage extends StatefulWidget {
  final AppStore store;
  const HomePage({super.key, required this.store});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    store.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(store.firmName.isEmpty ? 'StockFlow' : store.firmName),
        actions: [
          IconButton(
            tooltip: 'Firm Settings',
            onPressed: () => _firmDialog(context),
            icon: const Icon(Icons.business),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.save,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _headerCard(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _statCard('Balance', '${store.items.length}', Colors.indigo)),
                const SizedBox(width: 10),
                Expanded(child: _statCard('Low Stock', '${store.lowStock.length}', Colors.amber.shade700)),
                const SizedBox(width: 10),
                Expanded(child: _statCard('Nill', '${store.nilStock.length}', Colors.red)),
              ],
            ),
            const SizedBox(height: 18),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                _menu(Icons.add_box, 'Stock In', Colors.green, () => _stockPage(context, true)),
                _menu(Icons.indeterminate_check_box, 'Stock Out', Colors.orange, () => _stockPage(context, false)),
                _menu(Icons.inventory_2, 'Balance Stock', Colors.indigo, () => _balancePage(context)),
                _menu(Icons.warning_amber, 'Low Stock', Colors.amber.shade800, () => _statusPage(context, false)),
                _menu(Icons.remove_circle, 'Nill Stock', Colors.red, () => _statusPage(context, true)),
                _menu(Icons.shopping_cart, 'Order', Colors.deepPurple, () => _orderPage(context)),
                _menu(Icons.picture_as_pdf, 'PDF Reports', Colors.blueGrey, () => _reportsPage(context)),
                _menu(Icons.settings, 'Firm Settings', Colors.teal, () => _firmDialog(context)),
                _menu(Icons.edit_note, 'Item Master', Colors.cyan, () => _itemsPage(context)),
                _menu(Icons.backup, 'Backup & Restore', Colors.blueGrey, () => _backupPage(context)),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addItemDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New Item'),
      ),
    );
  }

  Widget _headerCard() => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 27,
                child: const Icon(Icons.storefront),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store.firmName.isEmpty ? 'Set Firm Name' : store.firmName,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    if (store.address.isNotEmpty) Text(store.address),
                    if (store.mobile.isNotEmpty) Text(store.mobile),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _statCard(String title, String value, Color color) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(value, style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: color)),
              Text(title),
            ],
          ),
        ),
      );

  Widget _menu(IconData icon, String title, Color color, VoidCallback tap) => Card(
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 38, color: color),
                const SizedBox(height: 8),
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );

  Future<void> _firmDialog(BuildContext context) async {
    final n = TextEditingController(text: store.firmName);
    final a = TextEditingController(text: store.address);
    final m = TextEditingController(text: store.mobile);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Firm Settings'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: n, decoration: const InputDecoration(labelText: 'Firm Name')),
              TextField(controller: a, decoration: const InputDecoration(labelText: 'Address')),
              TextField(controller: m, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile Number')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await store.setFirm(n.text, a.text, m.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _addItemDialog(BuildContext context) async {
    final n = TextEditingController();
    final u = TextEditingController(text: 'pcs');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: n, decoration: const InputDecoration(labelText: 'Item / Part Name')),
            TextField(controller: u, decoration: const InputDecoration(labelText: 'Unit (pcs, box, meter...)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await store.addItem(n.text, u.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _stockPage(BuildContext context, bool isIn) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => StockEntryPage(store: store, isIn: isIn),
    ));
  }

  void _balancePage(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => BalancePage(store: store)));
  }

  void _statusPage(BuildContext context, bool nil) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => StatusPage(store: store, nil: nil)));
  }

  void _orderPage(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => OrderPage(store: store)));
  }

  void _itemsPage(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ItemsPage(store: store)));
  }

  void _backupPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BackupRestorePage(store: store)),
    );
  }

  void _reportsPage(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReportsPage(store: store)));
  }
}

class StockEntryPage extends StatelessWidget {
  final AppStore store;
  final bool isIn;
  const StockEntryPage({super.key, required this.store, required this.isIn});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isIn ? 'Stock In' : 'Stock Out')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: store.items.length,
        itemBuilder: (_, i) {
          final item = store.items[i];
          return Card(
            child: ListTile(
              title: Text(item.name),
              subtitle: Text('Balance: ${item.stock} ${item.unit}'),
              trailing: FilledButton(
                onPressed: () => _qtyDialog(context, item),
                child: Text(isIn ? 'IN' : 'OUT'),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _qtyDialog(BuildContext context, StockItem item) async {
    final c = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${isIn ? 'Stock In' : 'Stock Out'} — ${item.name}'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Quantity (${item.unit})'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final q = int.tryParse(c.text) ?? 0;
              if (isIn) {
                await store.stockIn(item, q);
              } else {
                final ok = await store.stockOut(item, q);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Stock Out quantity is greater than available stock.')),
                  );
                  return;
                }
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          )
        ],
      ),
    );
  }
}

class BalancePage extends StatelessWidget {
  final AppStore store;
  const BalancePage({super.key, required this.store});

  Color statusColor(int s) {
    if (s == 0) return Colors.red;
    if (s <= 2) return Colors.amber.shade800;
    return Colors.green;
  }

  String status(int s) => s == 0 ? 'NILL STOCK' : s <= 2 ? 'LOW STOCK' : 'NORMAL';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Balance Stock')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: store.items.length,
        itemBuilder: (_, i) {
          final x = store.items[i];
          final c = statusColor(x.stock);
          return Card(
            color: x.stock == 0 ? Colors.red.shade50 : x.stock <= 2 ? Colors.amber.shade50 : Colors.green.shade50,
            child: ListTile(
              title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(status(x.stock)),
              trailing: Text('${x.stock} ${x.unit}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c)),
            ),
          );
        },
      ),
    );
  }
}

class StatusPage extends StatelessWidget {
  final AppStore store;
  final bool nil;
  const StatusPage({super.key, required this.store, required this.nil});

  @override
  Widget build(BuildContext context) {
    final list = nil ? store.nilStock : store.lowStock;
    return Scaffold(
      appBar: AppBar(
        title: Text(nil ? 'Nill Stock' : 'Low Stock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () => PdfReports.statusPdf(store, nil ? 'NILL STOCK' : 'LOW STOCK', list),
          )
        ],
      ),
      body: list.isEmpty
          ? Center(child: Text(nil ? 'No nill stock items' : 'No low stock items'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final x = list[i];
                return Card(
                  color: nil ? Colors.red.shade50 : Colors.amber.shade50,
                  child: ListTile(
                    title: Text(x.name),
                    trailing: Text('${x.stock} ${x.unit}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: nil ? Colors.red : Colors.amber.shade900)),
                  ),
                );
              },
            ),
    );
  }
}

class OrderPage extends StatefulWidget {
  final AppStore store;
  const OrderPage({super.key, required this.store});

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  final Map<String, bool> selected = {};
  final Map<String, TextEditingController> qty = {};

  @override
  void initState() {
    super.initState();
    for (final x in widget.store.lowStock + widget.store.nilStock) {
      qty[x.id] = TextEditingController();
      selected[x.id] = false;
    }
  }

  @override
  void dispose() {
    for (final c in qty.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = [...widget.store.lowStock, ...widget.store.nilStock];
    final unique = <String, StockItem>{for (final x in list) x.id: x}.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order'),
        actions: [
          IconButton(
            tooltip: 'Generate & Share Order PDF',
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () => _pdf(unique),
          )
        ],
      ),
      body: unique.isEmpty
          ? const Center(child: Text('No Low/Nill Stock items'))
          : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: unique.length,
              itemBuilder: (_, i) {
                final x = unique[i];
                final isNil = x.stock == 0;
                return Card(
                  color: isNil ? Colors.red.shade50 : Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: selected[x.id] ?? false,
                          onChanged: (v) => setState(() => selected[x.id] = v ?? false),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(x.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(isNil ? 'NILL STOCK' : 'LOW STOCK (${x.stock} ${x.unit})'),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: qty[x.id],
                            enabled: selected[x.id] ?? false,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Order Qty'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () => _pdf(unique),
            icon: const Icon(Icons.share),
            label: const Text('Generate / Share Order PDF'),
          ),
        ),
      ),
    );
  }

  Future<void> _pdf(List<StockItem> list) async {
    final rows = <OrderRow>[];
    for (final x in list) {
      if (selected[x.id] == true) {
        final q = int.tryParse(qty[x.id]?.text ?? '') ?? 0;
        if (q > 0) rows.add(OrderRow(x.name, q, x.stock == 0 ? 'NILL' : 'LOW'));
      }
    }
    if (rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check item and enter order quantity.')));
      }
      return;
    }
    await PdfReports.orderPdf(widget.store, rows);
  }
}

class OrderRow {
  final String name;
  final int qty;
  final String status;
  OrderRow(this.name, this.qty, this.status);
}

class ItemsPage extends StatefulWidget {
  final AppStore store;
  const ItemsPage({super.key, required this.store});
  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Master'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _addItem)],
      ),
      body: widget.store.items.isEmpty
          ? const Center(child: Text('अभी कोई item नहीं है।'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.store.items.length,
              itemBuilder: (_, i) {
                final x = widget.store.items[i];
                final c = x.stock == 0 ? Colors.red : x.stock <= 2 ? Colors.amber.shade800 : Colors.green;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(Icons.inventory_2, color: c)),
                    title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Balance: ${x.stock} ${x.unit}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(tooltip: 'Update Item', icon: const Icon(Icons.edit), onPressed: () => _editItem(x)),
                      IconButton(tooltip: 'Delete Item', icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteItem(x)),
                    ]),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem, icon: const Icon(Icons.add), label: const Text('Add Item'),
      ),
    );
  }

  Future<void> _addItem() async {
    final n=TextEditingController(); final u=TextEditingController(text:'pcs');
    await showDialog(context: context, builder: (dc)=>AlertDialog(
      title: const Text('Add Item'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller:n, autofocus:true, decoration:const InputDecoration(labelText:'Item / Part Name')),
        TextField(controller:u, decoration:const InputDecoration(labelText:'Unit')),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dc), child:const Text('Cancel')),
        FilledButton(onPressed:() async {
          final name=n.text.trim(); if(name.isEmpty) return;
          final exact=widget.store.items.any((x)=>x.name.toLowerCase()==name.toLowerCase());
          if(exact){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('यह item पहले से बना हुआ है।')));return;}
          final similar=widget.store.items.where((x){final a=x.name.toLowerCase(),b=name.toLowerCase();return a.contains(b)||b.contains(a);}).toList();
          if(similar.isNotEmpty){
            final ok=await showDialog<bool>(context:context,builder:(wc)=>AlertDialog(
              title:const Text('Similar Item Found'),
              content:Text('Similar item: ${similar.map((x)=>x.name).join(', ')}\n\nफिर भी नया item बनाना है?'),
              actions:[TextButton(onPressed:()=>Navigator.pop(wc,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(wc,true),child:const Text('Create'))],
            ));
            if(ok!=true)return;
          }
          await widget.store.addItem(name,u.text); if(dc.mounted)Navigator.pop(dc); setState((){});
        }, child:const Text('Add')),
      ],
    ));
  }

  Future<void> _editItem(StockItem item) async {
    final n=TextEditingController(text:item.name); final u=TextEditingController(text:item.unit);
    await showDialog(context:context,builder:(dc)=>AlertDialog(
      title:const Text('Update Item'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:n,decoration:const InputDecoration(labelText:'Item / Part Name')),
        TextField(controller:u,decoration:const InputDecoration(labelText:'Unit')),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dc),child:const Text('Cancel')),
        FilledButton(onPressed:()async{
          final name=n.text.trim(); if(name.isEmpty)return;
          final dup=widget.store.items.any((o)=>o!=item&&o.name.toLowerCase()==name.toLowerCase());
          if(dup){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('यह नाम पहले से मौजूद है।')));return;}
          item.name=name; item.unit=u.text.trim().isEmpty?'pcs':u.text.trim(); await widget.store.save(); if(dc.mounted)Navigator.pop(dc); setState((){});
        },child:const Text('Update')),
      ],
    ));
  }

  Future<void> _deleteItem(StockItem item) async {
    final ok=await showDialog<bool>(context:context,builder:(dc)=>AlertDialog(
      title:const Text('Delete Item'),
      content:Text('क्या “${item.name}” को delete करना है?\n\nइसका stock और history भी delete हो जाएगी।'),
      actions:[TextButton(onPressed:()=>Navigator.pop(dc,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dc,true),child:const Text('Delete'))],
    ));
    if(ok==true){await widget.store.deleteItem(item);setState((){});}
  }
}

class BackupRestorePage extends StatefulWidget {
  final AppStore store;
  const BackupRestorePage({super.key, required this.store});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  bool busy = false;

  Future<void> _createBackup() async {
    setState(() => busy = true);
    try {
      final jsonText = const JsonEncoder.withIndent('  ')
          .convert(widget.store.exportBackup());

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/stockflow_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      );

      await file.writeAsString(jsonText);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        text: 'StockFlow Backup - keep this file safe for restore',
        subject: 'StockFlow Backup',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _downloadBackup() async {
    setState(() => busy = true);
    try {
      final jsonText = const JsonEncoder.withIndent('  ')
          .convert(widget.store.exportBackup());

      final fileName =
          'stockflow_backup_${DateTime.now().millisecondsSinceEpoch}.json';

      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save StockFlow Backup',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(jsonText),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              savedPath == null
                  ? 'Backup download cancelled.'
                  : 'Backup downloaded successfully.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    setState(() => busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null) return;

      final picked = result.files.single;
      final bytes = picked.bytes;

      String text;
      if (bytes != null) {
        text = utf8.decode(bytes);
      } else if (picked.path != null) {
        text = await File(picked.path!).readAsString();
      } else {
        throw const FormatException('Could not read selected backup');
      }

      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const FormatException('Invalid backup');
      }

      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restore Backup?'),
          content: const Text(
            'Restore करने से वर्तमान firm details, items, stock और history backup वाले data से replace हो जाएंगे.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );

      if (ok == true) {
        await widget.store.restoreBackup(
          Map<String, dynamic>.from(decoded),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup successfully restored.')),
          );
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Icon(Icons.backup, size: 70),
            const SizedBox(height: 12),
            const Text(
              'Backup में firm details, सभी items, current stock और पूरी stock history save होगी.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : _createBackup,
                icon: const Icon(Icons.upload_file),
                label: const Text('Create Backup & Share'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : _downloadBackup,
                icon: const Icon(Icons.download),
                label: const Text('Download Backup'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : _restoreBackup,
                icon: const Icon(Icons.restore),
                label: const Text('Restore Backup'),
              ),
            ),
            if (busy) ...[
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
            ],
            const SizedBox(height: 20),
            const Text(
              'Tip: Backup file को WhatsApp, Google Drive या किसी सुरक्षित जगह पर रख सकते हैं। APK uninstall करने से पहले backup जरूर लें.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class ReportsPage extends StatelessWidget {
  final AppStore store;
  const ReportsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Reports')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _reportButton(context, 'Stock Summary PDF', Icons.inventory, () => PdfReports.summaryPdf(store)),
          _reportButton(context, 'Low Stock PDF', Icons.warning_amber, () => PdfReports.statusPdf(store, 'LOW STOCK', store.lowStock)),
          _reportButton(context, 'Nill Stock PDF', Icons.remove_circle, () => PdfReports.statusPdf(store, 'NILL STOCK', store.nilStock)),
          _reportButton(context, 'Complete Stock History PDF', Icons.history, () => PdfReports.historyPdf(store)),
        ],
      ),
    );
  }

  Widget _reportButton(BuildContext context, String title, IconData icon, VoidCallback tap) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: const Icon(Icons.picture_as_pdf),
          onTap: tap,
        ),
      );
}

class PdfReports {
  static pw.Widget header(AppStore s, String title) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(s.firmName.isEmpty ? 'StockFlow' : s.firmName,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          if (s.address.isNotEmpty) pw.Text(s.address),
          if (s.mobile.isNotEmpty) pw.Text('Mobile: ${s.mobile}'),
          pw.SizedBox(height: 8),
          pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text('Date: ${fmt(DateTime.now())}'),
          pw.SizedBox(height: 12),
        ],
      );

  static Future<void> summaryPdf(AppStore s) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        header(s, 'STOCK SUMMARY'),
        pw.Table.fromTextArray(
          headers: ['Item', 'Total IN', 'Total OUT', 'Balance', 'Status'],
          data: s.items.map((x) {
            final status = x.stock == 0 ? 'NILL' : x.stock <= 2 ? 'LOW' : 'NORMAL';
            return [x.name, s.totalIn(x).toString(), s.totalOut(x).toString(), '${x.stock} ${x.unit}', status];
          }).toList(),
        ),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'stock_summary.pdf');
  }

  static Future<void> statusPdf(AppStore s, String title, List<StockItem> list) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        header(s, title),
        pw.Table.fromTextArray(
          headers: ['Item', 'Current Stock', 'Unit'],
          data: list.map((x) => [x.name, x.stock.toString(), x.unit]).toList(),
        ),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: '${title.toLowerCase().replaceAll(' ', '_')}.pdf');
  }

  static Future<void> historyPdf(AppStore s) async {
    final doc = pw.Document();
    final rows = <List<String>>[];
    for (final x in s.items) {
      for (final h in x.history) {
        rows.add([x.name, fmt(h.date), h.type, h.qty.toString(), x.unit]);
      }
    }
    rows.sort((a, b) => b[1].compareTo(a[1]));
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        header(s, 'DATE-WISE STOCK HISTORY'),
        pw.Table.fromTextArray(
          headers: ['Item', 'Date', 'Type', 'Qty', 'Unit'],
          data: rows,
        ),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'stock_history.pdf');
  }

  static Future<void> orderPdf(AppStore s, List<OrderRow> rows) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        header(s, 'PURCHASE ORDER'),
        pw.Table.fromTextArray(
          headers: ['Item', 'Status', 'Order Qty'],
          data: rows.map((x) => [x.name, x.status, x.qty.toString()]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Text('Total Items: ${rows.length}'),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'purchase_order.pdf');
  }

  static String fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
