import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF000000),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const DishfolioApp());
}

class DishfolioApp extends StatelessWidget {
  const DishfolioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dishfolio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000),
        primaryColor: const Color(0xFFFFFFFF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFFFFF),
          surface: Color(0xFF0A0A0A),
          onSurface: Color(0xFFFFFFFF),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0; // 0: Journal, 1: Want to Go, 2: Vault
  List<Map<String, dynamic>> _visits = [];
  List<Map<String, dynamic>> _wantToGo = [];
  String _searchQuery = '';
  String _selectedCategory = 'All';
  final List<String> _categories = ['All', 'Friends', 'Solo', 'Family', 'Date', 'Takeout'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? visitsStr = prefs.getString('dishfolio_visits');
    final String? wtgStr = prefs.getString('dishfolio_wtg');

    setState(() {
      if (visitsStr != null) {
        _visits = List<Map<String, dynamic>>.from(jsonDecode(visitsStr));
      } else {
        _visits = [
          {
            'id': '1',
            'restaurant': "Sultan's Dine",
            'area': 'Uttara',
            'date': 'Oct 14, 2026',
            'category': 'Friends',
            'expRating': 9.5,
            'notes': 'Fast service.',
            'dishes': [
              {
                'name': 'Bashmati Kacchi (Half)',
                'price': 450,
                'taste': 9.2,
                'value': 9.5,
                'portion': 9.5,
                'repeat': true,
                'notes': 'Tender mutton, fragrant rice.'
              },
              {
                'name': 'Zafrani Borhani',
                'price': 90,
                'taste': 8.8,
                'value': 9.0,
                'portion': 8.5,
                'repeat': true,
                'notes': 'Balanced spice.'
              }
            ]
          }
        ];
        _saveData();
      }

      if (wtgStr != null) {
        _wantToGo = List<Map<String, dynamic>>.from(jsonDecode(wtgStr));
      } else {
        _wantToGo = [
          {'name': 'Kacchi Bhai', 'area': 'Dhanmondi', 'dish': 'Kacchi', 'visited': true},
          {'name': 'Peyala Cafe', 'area': 'Gulshan', 'dish': 'Chicken Shawarma', 'visited': false},
        ];
        _saveData();
      }
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dishfolio_visits', jsonEncode(_visits));
    await prefs.setString('dishfolio_wtg', jsonEncode(_wantToGo));
  }

  int get _totalDishes {
    int count = 0;
    for (var v in _visits) {
      count += (v['dishes'] as List).length;
    }
    return count;
  }

  int get _totalSpent {
    int sum = 0;
    for (var v in _visits) {
      for (var d in (v['dishes'] as List)) {
        sum += (d['price'] as num).toInt();
      }
    }
    return sum;
  }

  int get _wtgVisitedCount => _wantToGo.where((w) => w['visited'] == true).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A), width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Dishfolio',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
                Row(
                  children: [
                    _headerButton('Want to Go', () => setState(() => _currentTab = 1)),
                    const SizedBox(width: 8),
                    _headerButton('Log Visit', () => _openVisitModal(), isPrimary: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: Container(
        height: 64,
        decoration: const BoxDecoration(
          color: Color(0xFF000000),
          border: Border(top: BorderSide(color: Color(0xFF1A1A1A), width: 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(0, Icons.menu_book_outlined, 'Journal'),
            _navItem(1, Icons.bookmark_border, 'Want to Go'),
            _navItem(2, Icons.import_export, 'Vault'),
          ],
        ),
      ),
    );
  }

  Widget _headerButton(String label, VoidCallback onTap, {bool isPrimary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFF141414) : const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isPrimary ? const Color(0xFF333333) : const Color(0xFF222222)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final bool active = _currentTab == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF121212) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: active ? Border.all(color: const Color(0xFF2A2A2A)) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: active ? Colors.white : const Color(0xFF666666)),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? Colors.white : const Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_currentTab == 1) return _buildWantToGoTab();
    if (_currentTab == 2) return _buildVaultTab();
    return _buildJournalTab();
  }

  Widget _buildJournalTab() {
    final filtered = _visits.where((v) {
      final matchesCat = _selectedCategory == 'All' || v['category'] == _selectedCategory;
      final q = _searchQuery.toLowerCase();
      final matchesRest = v['restaurant'].toString().toLowerCase().contains(q) ||
          v['area'].toString().toLowerCase().contains(q);
      final matchesDish = (v['dishes'] as List)
          .any((d) => d['name'].toString().toLowerCase().contains(q));
      return matchesCat && (matchesRest || matchesDish);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _statCard('WANT TO GO', '$_wtgVisitedCount / ${_wantToGo.length}'),
            const SizedBox(width: 8),
            _statCard('VISITS', '${_visits.length}'),
            const SizedBox(width: 8),
            _statCard('DISHES', '$_totalDishes'),
            const SizedBox(width: 8),
            _statCard('SPENT', '৳$_totalSpent'),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1F1F1F)),
          ),
          child: TextField(
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: const InputDecoration(
              icon: Icon(Icons.search, size: 18, color: Color(0xFF666666)),
              hintText: 'Search visits or dishes...',
              hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 13),
              border: InputBorder.none,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _categories.map((cat) {
              final active = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF181818) : const Color(0xFF080808),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active ? const Color(0xFF444444) : const Color(0xFF1C1C1C),
                      ),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? Colors.white : const Color(0xFF888888),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        ...filtered.asMap().entries.map((entry) => _visitCard(entry.value, entry.key)),
      ],
    );
  }

  Widget _statCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF080808),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1A1A1A)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: Color(0xFF666666),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _visitCard(Map<String, dynamic> visit, int index) {
    final dishes = List<Map<String, dynamic>>.from(visit['dishes'] ?? []);
    int visitTotal = 0;
    for (var d in dishes) {
      visitTotal += (d['price'] as num).toInt();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1C1C1C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      visit['restaurant'] ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    _microBadge(visit['category'] ?? 'Friends'),
                  ],
                ),
              ),
              Row(
                children: [
                  _microBadge('Exp ${visit['expRating']}', highlight: true),
                  const SizedBox(width: 6),
                  _microBadge('৳$visitTotal', highlight: true),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _visits.removeAt(index);
                        _saveData();
                      });
                    },
                    child: _microBadge('Del'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${visit['area']} • ${visit['date']}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF777777)),
          ),
          if ((visit['notes'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              visit['notes'],
              style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
          ],
          const SizedBox(height: 12),
          ...dishes.map((d) => _dishSubCard(d)),
        ],
      ),
    );
  }

  Widget _dishSubCard(Map<String, dynamic> dish) {
    final double avg = (((dish['taste'] as num) + (dish['value'] as num) + (dish['portion'] as num)) / 3.0);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E0E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  dish['name'] ?? '',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
              _microBadge(avg.toStringAsFixed(1), highlight: true),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _microBadge('৳${dish['price']}', highlight: true),
              _microBadge('Taste ${dish['taste']}'),
              _microBadge('Value ${dish['value']}'),
              _microBadge('Portion ${dish['portion']}'),
              if (dish['repeat'] == true) _microBadge('Repeat'),
            ],
          ),
          if ((dish['notes'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              dish['notes'],
              style: const TextStyle(fontSize: 12, color: Color(0xFF777777)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _microBadge(String text, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFF161616) : const Color(0xFF111111),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: highlight ? const Color(0xFF2C2C2C) : const Color(0xFF202020)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
          color: highlight ? Colors.white : const Color(0xFF888888),
        ),
      ),
    );
  }

  Widget _buildWantToGoTab() {
    final nameCtrl = TextEditingController();
    final areaCtrl = TextEditingController();
    final dishCtrl = TextEditingController();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Bucket List (Want to Go)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1C1C1C)),
          ),
          child: Column(
            children: [
              _darkInput(nameCtrl, 'Restaurant Name'),
              const SizedBox(height: 8),
              _darkInput(areaCtrl, 'Area (e.g. Banani)'),
              const SizedBox(height: 8),
              _darkInput(dishCtrl, 'Must-Try Dish'),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) return;
                    setState(() {
                      _wantToGo.add({
                        'name': nameCtrl.text.trim(),
                        'area': areaCtrl.text.trim(),
                        'dish': dishCtrl.text.trim(),
                        'visited': false,
                      });
                      _saveData();
                    });
                  },
                  child: const Text('Add to Bucket List', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._wantToGo.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final done = item['visited'] == true;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1C1C1C)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'] ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: done ? const Color(0xFF666666) : Colors.white,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item['area']} • Try: ${item['dish']}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF777777)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _wantToGo[idx]['visited'] = !done;
                          _saveData();
                        });
                      },
                      child: _microBadge(done ? 'Visited' : 'Mark Done', highlight: !done),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _wantToGo.removeAt(idx);
                          _saveData();
                        });
                      },
                      child: _microBadge('X'),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildVaultTab() {
    final jsonCtrl = TextEditingController(
      text: jsonEncode({'visits': _visits, 'wantToGo': _wantToGo}),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Data Vault (Offline JSON Backup)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 6),
        const Text(
          'Copy this JSON to back up your data, or paste a backup below to restore.',
          style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1F1F1F)),
          ),
          child: TextField(
            controller: jsonCtrl,
            maxLines: 8,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white),
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: jsonCtrl.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied JSON backup to clipboard!')),
                  );
                },
                child: const Text('Copy Backup'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  try {
                    final parsed = jsonDecode(jsonCtrl.text);
                    setState(() {
                      _visits = List<Map<String, dynamic>>.from(parsed['visits'] ?? []);
                      _wantToGo = List<Map<String, dynamic>>.from(parsed['wantToGo'] ?? []);
                      _saveData();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Data restored successfully!')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invalid JSON format.')),
                    );
                  }
                },
                child: const Text('Import / Restore', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openVisitModal() {
    final restCtrl = TextEditingController();
    final areaCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: 'Oct 16, 2026');
    final expCtrl = TextEditingController(text: '9.0');
    final notesCtrl = TextEditingController();
    final dishNameCtrl = TextEditingController();
    final dishPriceCtrl = TextEditingController();
    final dishTasteCtrl = TextEditingController(text: '9.0');
    final dishValueCtrl = TextEditingController(text: '9.0');
    final dishPortionCtrl = TextEditingController(text: '9.0');
    final dishNotesCtrl = TextEditingController();
    String cat = 'Friends';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF050505),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Log New Visit',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 12),
                _darkInput(restCtrl, 'Restaurant Name (e.g. Sultan\'s Dine)'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _darkInput(areaCtrl, 'Area (e.g. Uttara)')),
                    const SizedBox(width: 8),
                    Expanded(child: _darkInput(dateCtrl, 'Date')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _darkInput(expCtrl, 'Overall Exp (1-10)', isNum: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _darkInput(notesCtrl, 'Visit Notes')),
                  ],
                ),
                const Divider(color: Color(0xFF222222), height: 24),
                const Text('Dish Details',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(flex: 2, child: _darkInput(dishNameCtrl, 'Dish Name')),
                    const SizedBox(width: 8),
                    Expanded(child: _darkInput(dishPriceCtrl, 'Price (৳)', isNum: true)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _darkInput(dishTasteCtrl, 'Taste', isNum: true)),
                    const SizedBox(width: 6),
                    Expanded(child: _darkInput(dishValueCtrl, 'Value', isNum: true)),
                    const SizedBox(width: 6),
                    Expanded(child: _darkInput(dishPortionCtrl, 'Portion', isNum: true)),
                  ],
                ),
                const SizedBox(height: 8),
                _darkInput(dishNotesCtrl, 'Dish Notes'),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      if (restCtrl.text.trim().isEmpty) return;
                      setState(() {
                        _visits.insert(0, {
                          'id': DateTime.now().millisecondsSinceEpoch.toString(),
                          'restaurant': restCtrl.text.trim(),
                          'area': areaCtrl.text.trim(),
                          'date': dateCtrl.text.trim(),
                          'category': cat,
                          'expRating': double.tryParse(expCtrl.text) ?? 9.0,
                          'notes': notesCtrl.text.trim(),
                          'dishes': [
                            {
                              'name': dishNameCtrl.text.trim().isEmpty ? 'Dish' : dishNameCtrl.text.trim(),
                              'price': int.tryParse(dishPriceCtrl.text) ?? 0,
                              'taste': double.tryParse(dishTasteCtrl.text) ?? 9.0,
                              'value': double.tryParse(dishValueCtrl.text) ?? 9.0,
                              'portion': double.tryParse(dishPortionCtrl.text) ?? 9.0,
                              'repeat': true,
                              'notes': dishNotesCtrl.text.trim(),
                            }
                          ]
                        });
                        _saveData();
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save Visit', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _darkInput(TextEditingController ctrl, String hint, {bool isNum = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E0E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontSize: 12, color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF555555)),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
