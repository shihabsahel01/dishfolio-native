import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

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
          surface: Color(0xFF080808),
          onSurface: Color(0xFFFFFFFF),
        ),
        sliderTheme: SliderThemeData(
          trackHeight: 5.0,
          activeTrackColor: Colors.white,
          inactiveTrackColor: const Color(0xFF222222),
          thumbColor: Colors.white,
          overlayColor: Colors.white.withOpacity(0.12),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentTab = 0; // 0: Journal, 1: Want to Go, 2: Rankings, 3: Stats, 4: Vault
  final ImagePicker _picker = ImagePicker();

  // Master Data Structures
  List<Map<String, dynamic>> _visits = [];
  List<Map<String, dynamic>> _places = [];

  // Journal State
  String _journalSearch = '';
  String _journalCategory = 'All';
  final List<String> _categories = ['All', 'Friends', 'Solo', 'Family', 'Date', 'Takeout'];
  final Set<String> _expandedPlaces = {};

  // Want to Go State
  String _wtgSearch = '';
  String _wtgFilter = 'Want to Go'; // 'Want to Go' or 'Visited'
  String _wtgSort = 'Newest'; // 'Newest', 'Oldest', 'A-Z'

  // Rankings State
  String _rankType = 'Dishes'; // 'Dishes' or 'Places'
  String _rankMetric = 'Score'; // 'Score', 'Taste', 'Value', 'Portion', 'Appearance', 'Order Again'

  // Stats State
  String _statsTimeframe = 'All-Time'; // 'All-Time', 'This Month', 'Last 30 Days', 'Last 3 Months'
  String? _expandedStatPlace;

  // Vault State
  String _importMode = 'Merge';
  final TextEditingController _rawJsonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? visitsStr = prefs.getString('dishfolio_v2_visits');
    final String? placesStr = prefs.getString('dishfolio_v2_places');

    setState(() {
      if (visitsStr != null && placesStr != null) {
        _visits = List<Map<String, dynamic>>.from(jsonDecode(visitsStr));
        _places = List<Map<String, dynamic>>.from(jsonDecode(placesStr));
      } else {
        // Check legacy v1 data or initialize clean empty state
        final String? oldVisits = prefs.getString('dishfolio_visits');
        if (oldVisits != null) {
          _visits = List<Map<String, dynamic>>.from(jsonDecode(oldVisits));
          _syncPlacesFromVisits();
        }
      }
    });
  }

  void _syncPlacesFromVisits() {
    for (var v in _visits) {
      final rName = (v['restaurant'] ?? '').toString().trim();
      if (rName.isEmpty) continue;
      final exists = _places.any((p) => p['name'].toString().toLowerCase() == rName.toLowerCase());
      if (!exists) {
        _places.add({
          'id': DateTime.now().millisecondsSinceEpoch.toString() + rName,
          'name': rName,
          'area': v['area'] ?? '',
          'mustTry': '',
          'status': 'Visited',
          'addedAt': DateTime.now().millisecondsSinceEpoch,
          'menuImages': <String>[],
        });
      } else {
        final idx = _places.indexWhere((p) => p['name'].toString().toLowerCase() == rName.toLowerCase());
        _places[idx]['status'] = 'Visited';
      }
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dishfolio_v2_visits', jsonEncode(_visits));
    await prefs.setString('dishfolio_v2_places', jsonEncode(_places));
  }

  // --- Date & Score Helpers ---
  DateTime _parseDate(String dateStr) {
    try {
      return DateTime.parse(dateStr);
    } catch (_) {}
    try {
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        return DateTime(int.parse(parts[2]), int.parse(parts[0]), int.parse(parts[1]));
      }
    } catch (_) {}
    return DateTime.now();
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  // Weighted Dish Score: Taste 45%, Value 25%, Portion 15%, Appearance 15%
  double _calcDishScore(Map<String, dynamic> d) {
    final double taste = (d['taste'] as num?)?.toDouble() ?? 8.0;
    final double value = (d['value'] as num?)?.toDouble() ?? 8.0;
    final double portion = (d['portion'] as num?)?.toDouble() ?? 8.0;
    final double appearance = (d['appearance'] as num?)?.toDouble() ?? (d['crave'] as num?)?.toDouble() ?? 8.0;
    return (taste * 0.45) + (value * 0.25) + (portion * 0.15) + (appearance * 0.15);
  }

  int _calcVisitTotal(Map<String, dynamic> v) {
    if (v['totalBill'] != null && (v['totalBill'] as num) > 0) {
      return (v['totalBill'] as num).toInt();
    }
    int sum = 0;
    for (var d in (v['dishes'] as List? ?? [])) {
      sum += (d['price'] as num?)?.toInt() ?? 0;
    }
    return sum;
  }

  // --- Global Metrics ---
  int get _actualWantToGoCount {
    return _places.where((p) => p['status'] == 'Want to Go').length;
  }

  int get _totalVisitsCount => _visits.length;

  int get _totalDishesCount {
    int count = 0;
    for (var v in _visits) {
      count += (v['dishes'] as List? ?? []).length;
    }
    return count;
  }

  int get _monthlySpent {
    final now = DateTime.now();
    int sum = 0;
    for (var v in _visits) {
      final dt = _parseDate(v['date']?.toString() ?? '');
      if (dt.year == now.year && dt.month == now.month) {
        sum += _calcVisitTotal(v);
      }
    }
    return sum;
  }

  Future<String?> _pickBase64Image() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 75,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      return null;
    }
  }

  Future<List<String>> _pickMultipleBase64Images() async {
    try {
      final List<XFile> files = await _picker.pickMultiImage(
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 75,
      );
      List<String> results = [];
      for (var f in files) {
        final bytes = await f.readAsBytes();
        results.add(base64Encode(bytes));
      }
      return results;
    } catch (e) {
      final single = await _pickBase64Image();
      return single != null ? [single] : [];
    }
  }

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
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
                // ONLY show header buttons on Journal tab (_currentTab == 0)
                if (_currentTab == 0)
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
      body: _buildCurrentTab(),
      bottomNavigationBar: Container(
        height: 66,
        decoration: const BoxDecoration(
          color: Color(0xFF000000),
          border: Border(top: BorderSide(color: Color(0xFF1A1A1A), width: 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(0, Icons.book_outlined, 'Journal'),
            _navItem(1, Icons.bookmark_border, 'Want to Go'),
            _navItem(2, Icons.emoji_events_outlined, 'Rankings'),
            _navItem(3, Icons.bar_chart_rounded, 'Stats'),
            _navItem(4, Icons.shield_outlined, 'Vault'),
          ],
        ),
      ),
    );
  }

  Widget _headerButton(String label, VoidCallback onTap, {bool isPrimary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFF141414) : const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isPrimary ? const Color(0xFF383838) : const Color(0xFF222222)),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF121212) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: active ? Border.all(color: const Color(0xFF2C2C2C)) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: active ? Colors.white : const Color(0xFF666666)),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: active ? Colors.white : const Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentTab) {
      case 0:
        return _buildJournalTab();
      case 1:
        return _buildWantToGoTab();
      case 2:
        return _buildRankingsTab();
      case 3:
        return _buildStatsTab();
      case 4:
        return _buildVaultTab();
      default:
        return _buildJournalTab();
    }
  }

  // ===========================================================================
  // TAB 0: JOURNAL (Unified Restaurant Cards + History + Menu Viewer)
  // ===========================================================================
  Widget _buildJournalTab() {
    // Filter visits by category and search query
    final filteredVisits = _visits.where((v) {
      final matchesCat = _journalCategory == 'All' || v['category'] == _journalCategory;
      final q = _journalSearch.toLowerCase();
      final matchesRest = (v['restaurant'] ?? '').toString().toLowerCase().contains(q) ||
          (v['area'] ?? '').toString().toLowerCase().contains(q);
      final matchesDish = (v['dishes'] as List? ?? [])
          .any((d) => (d['name'] ?? '').toString().toLowerCase().contains(q));
      return matchesCat && (matchesRest || matchesDish);
    }).toList();

    // Group visits by Restaurant Name into Unified Restaurant Cards
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var v in filteredVisits) {
      final rName = (v['restaurant'] ?? 'Unknown').toString().trim();
      grouped.putIfAbsent(rName, () => []).add(v);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Top Bento Row (Journal: Want to Go count, Visits, Dishes, Total Visits)
        Row(
          children: [
            _statCard('WANT TO GO', '$_actualWantToGoCount'),
            const SizedBox(width: 8),
            _statCard('VISITS', '$_totalVisitsCount'),
            const SizedBox(width: 8),
            _statCard('DISHES', '$_totalDishesCount'),
            const SizedBox(width: 8),
            _statCard('TOTAL VISITS', '$_totalVisitsCount'),
          ],
        ),
        const SizedBox(height: 14),
        // Search Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF090909),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1F1F1F)),
          ),
          child: TextField(
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: const InputDecoration(
              icon: Icon(Icons.search, size: 18, color: Color(0xFF666666)),
              hintText: 'Search restaurants or dishes...',
              hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 13),
              border: InputBorder.none,
            ),
            onChanged: (val) => setState(() => _journalSearch = val),
          ),
        ),
        const SizedBox(height: 12),
        // Category Filter Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _categories.map((cat) {
              final active = _journalCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _journalCategory = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF1A1A1A) : const Color(0xFF080808),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active ? Colors.white : const Color(0xFF1F1F1F),
                      ),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
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
        if (grouped.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            child: const Text(
              'No visits logged yet.\nTap "Log Visit" at the top right to start your journal.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF666666), fontSize: 13),
            ),
          ),
        ...grouped.entries.map((entry) => _buildUnifiedRestaurantCard(entry.key, entry.value)),
      ],
    );
  }

  Widget _buildUnifiedRestaurantCard(String restaurantName, List<Map<String, dynamic>> visits) {
    // Sort visits newest first
    visits.sort((a, b) => _parseDate(b['date'] ?? '').compareTo(_parseDate(a['date'] ?? '')));

    final String area = visits.first['area'] ?? '';
    double totalExp = 0;
    int totalSpentHere = 0;
    final List<Map<String, dynamic>> allDishesWithMeta = [];

    for (var v in visits) {
      totalExp += (v['expRating'] as num?)?.toDouble() ?? 8.0;
      totalSpentHere += _calcVisitTotal(v);
      for (var d in (v['dishes'] as List? ?? [])) {
        final copy = Map<String, dynamic>.from(d);
        copy['_visitDate'] = v['date'];
        copy['_visitId'] = v['id'];
        copy['_score'] = _calcDishScore(d);
        allDishesWithMeta.add(copy);
      }
    }

    // Order dishes by score highest to lowest
    allDishesWithMeta.sort((a, b) => (b['_score'] as double).compareTo(a['_score'] as double));

    final double avgExp = visits.isEmpty ? 0 : totalExp / visits.length;
    final double avgDishScore = allDishesWithMeta.isEmpty
        ? 0
        : allDishesWithMeta.map((d) => d['_score'] as double).reduce((a, b) => a + b) /
            allDishesWithMeta.length;

    // Find associated place for menu images
    final placeObj = _places.firstWhere(
      (p) => p['name'].toString().toLowerCase() == restaurantName.toLowerCase(),
      orElse: () => <String, dynamic>{},
    );
    final List<String> menuImgs = List<String>.from(placeObj['menuImages'] ?? []);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF080808),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F1F1F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                if (_expandedPlaces.contains(restaurantName)) {
                  _expandedPlaces.remove(restaurantName);
                } else {
                  _expandedPlaces.add(restaurantName);
                }
              });
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            restaurantName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          _microBadge('${visits.length} ${visits.length == 1 ? "Visit" : "Visits"}'),
                          if (menuImgs.isNotEmpty)
                            GestureDetector(
                              onTap: () => _openMenuGalleryModal(restaurantName, menuImgs),
                              child: _microBadge('${menuImgs.length} Menu', highlight: true),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$area • Last: ${visits.first['date']} • ৳$totalSpentHere total',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    _microBadge('Exp ${avgExp.toStringAsFixed(1)}', highlight: true),
                    const SizedBox(width: 6),
                    if (allDishesWithMeta.isNotEmpty)
                      _microBadge(avgDishScore.toStringAsFixed(1), highlight: true),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // All Dishes Ordered by Score
          const Text(
            'DISHES (RANKED)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 6),
          ...allDishesWithMeta.map((d) => _buildDishSubCard(d)),

          // Visit History Timeline Section
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0C0C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1A1A1A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VISIT HISTORY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Color(0xFF777777),
                  ),
                ),
                const SizedBox(height: 8),
                ...visits.map((v) {
                  final vBill = _calcVisitTotal(v);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    v['date'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _microBadge(v['category'] ?? 'Friends'),
                                  const SizedBox(width: 6),
                                  Text(
                                    '★ ${v['expRating']} • ৳$vBill',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                                  ),
                                ],
                              ),
                              if ((v['notes'] ?? '').toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    v['notes'],
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF777777)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _openVisitModal(existingVisit: v),
                          child: _microBadge('Edit', highlight: true),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          // Bottom Action Bar
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  if (menuImgs.isNotEmpty) {
                    _openMenuGalleryModal(restaurantName, menuImgs);
                  } else {
                    _addMenuImagesToRestaurant(restaurantName, area);
                  }
                },
                child: _microBadge(
                  menuImgs.isEmpty ? '+ Add Menu' : 'View / Edit Menu (${menuImgs.length})',
                  highlight: menuImgs.isNotEmpty,
                ),
              ),
              GestureDetector(
                onTap: () => _openVisitModal(prefillRestaurant: restaurantName, prefillArea: area),
                child: _microBadge('+ Add Date', highlight: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDishSubCard(Map<String, dynamic> dish) {
    final double score = (dish['_score'] as num?)?.toDouble() ?? _calcDishScore(dish);
    final String? photoB64 = dish['photo'];
    final double appearance =
        (dish['appearance'] as num?)?.toDouble() ?? (dish['crave'] as num?)?.toDouble() ?? 8.0;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photoB64 != null && photoB64.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => _showFullImageDialog(photoB64, dish['name'] ?? 'Dish'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(photoB64),
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        dish['name'] ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _microBadge(score.toStringAsFixed(1), highlight: true),
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
                    _microBadge('Appearance $appearance'),
                    _microBadge(
                      dish['repeat'] == true ? 'Repeat' : 'Skip',
                      highlight: dish['repeat'] == true,
                    ),
                  ],
                ),
                if ((dish['notes'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    dish['notes'],
                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: WANT TO GO (Fixed ratio, Monthly Spent, 2 Filters + Sort Button)
  // ===========================================================================
  Widget _buildWantToGoTab() {
    // Sync any visited places
    _syncPlacesFromVisits();

    List<Map<String, dynamic>> filtered = _places.where((p) {
      final matchesStatus = p['status'] == _wtgFilter;
      final q = _wtgSearch.toLowerCase();
      final matchesSearch = (p['name'] ?? '').toString().toLowerCase().contains(q) ||
          (p['area'] ?? '').toString().toLowerCase().contains(q) ||
          (p['mustTry'] ?? '').toString().toLowerCase().contains(q);
      return matchesStatus && matchesSearch;
    }).toList();

    if (_wtgSort == 'Newest') {
      filtered.sort((a, b) => ((b['addedAt'] ?? 0) as int).compareTo((a['addedAt'] ?? 0) as int));
    } else if (_wtgSort == 'Oldest') {
      filtered.sort((a, b) => ((a['addedAt'] ?? 0) as int).compareTo((b['addedAt'] ?? 0) as int));
    } else if (_wtgSort == 'A-Z') {
      filtered.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Top Bento Row (Want to Go count, Visits, Dishes, Monthly Spent)
        Row(
          children: [
            _statCard('WANT TO GO', '$_actualWantToGoCount'),
            const SizedBox(width: 8),
            _statCard('VISITS', '$_totalVisitsCount'),
            const SizedBox(width: 8),
            _statCard('DISHES', '$_totalDishesCount'),
            const SizedBox(width: 8),
            _statCard('MONTHLY SPENT', '৳$_monthlySpent'),
          ],
        ),
        const SizedBox(height: 14),
        // Search + Add Button
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF090909),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1F1F1F)),
                ),
                child: TextField(
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  decoration: const InputDecoration(
                    icon: Icon(Icons.search, size: 18, color: Color(0xFF666666)),
                    hintText: 'Search places...',
                    hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 13),
                    border: InputBorder.none,
                  ),
                  onChanged: (val) => setState(() => _wtgSearch = val),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _openAddPlaceModal(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF333333)),
                ),
                child: const Text(
                  'Add',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Only "Want to Go" and "Visited" on Left + Sort Button on Right
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: ['Want to Go', 'Visited'].map((status) {
                final active = _wtgFilter == status;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _wtgFilter = status),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF181818) : const Color(0xFF080808),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active ? Colors.white : const Color(0xFF1F1F1F),
                        ),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                          color: active ? Colors.white : const Color(0xFF888888),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            // Sort Dropdown Pill
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_wtgSort == 'Newest') {
                    _wtgSort = 'Oldest';
                  } else if (_wtgSort == 'Oldest') {
                    _wtgSort = 'A-Z';
                  } else {
                    _wtgSort = 'Newest';
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D0D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF262626)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sort, size: 14, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      'Sort: $_wtgSort',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                'No places in "$_wtgFilter" yet.',
                style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
              ),
            ),
          ),
        ...filtered.map((place) => _buildPlaceCard(place)),
      ],
    );
  }

  Widget _buildPlaceCard(Map<String, dynamic> place) {
    final String name = place['name'] ?? '';
    final placeVisits = _visits
        .where((v) => (v['restaurant'] ?? '').toString().toLowerCase() == name.toLowerCase())
        .toList();

    int dishCount = 0;
    int spent = 0;
    double expSum = 0;
    double dishScoreSum = 0;

    for (var v in placeVisits) {
      spent += _calcVisitTotal(v);
      expSum += (v['expRating'] as num?)?.toDouble() ?? 8.0;
      for (var d in (v['dishes'] as List? ?? [])) {
        dishCount++;
        dishScoreSum += _calcDishScore(d);
      }
    }

    final int menuCount = (place['menuImages'] as List? ?? []).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF080808),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F1F1F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    _microBadge(
                      placeVisits.isEmpty
                          ? 'Want to Go'
                          : '${placeVisits.length} ${placeVisits.length == 1 ? "Visit" : "Visits"}',
                    ),
                  ],
                ),
              ),
              if (placeVisits.isNotEmpty)
                Row(
                  children: [
                    _microBadge('Exp ${(expSum / placeVisits.length).toStringAsFixed(1)}', highlight: true),
                    if (dishCount > 0) ...[
                      const SizedBox(width: 6),
                      _microBadge((dishScoreSum / dishCount).toStringAsFixed(1), highlight: true),
                    ],
                  ],
                )
              else
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _places.removeWhere((p) => p['id'] == place['id']);
                      _saveData();
                    });
                  },
                  child: _microBadge('—'),
                ),
            ],
          ),
          if ((place['area'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              place['area'],
              style: const TextStyle(fontSize: 12, color: Color(0xFF777777)),
            ),
          ],
          if ((place['mustTry'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Must Try: ${place['mustTry']}',
              style: const TextStyle(fontSize: 12, color: Color(0xFFAAAAAA)),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF161616), height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$menuCount Menu • $dishCount Dishes • ৳$spent',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF888888)),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _openAddPlaceModal(existingPlace: place),
                    child: _microBadge('Edit'),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _openVisitModal(
                      prefillRestaurant: name,
                      prefillArea: place['area'] ?? '',
                    ),
                    child: _microBadge('+ Add Date', highlight: true),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 2: RANKINGS (No top bar, Top 3 Podium Highlighted in Pure White)
  // ===========================================================================
  Widget _buildRankingsTab() {
    final metrics = ['Score', 'Taste', 'Value', 'Portion', 'Appearance', 'Order Again'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Dishes vs Places Segmented Toggle
        Row(
          children: ['Dishes', 'Places'].map((t) {
            final active = _rankType == t;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: t == 'Dishes' ? 6 : 0, left: t == 'Places' ? 6 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _rankType = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF161616) : const Color(0xFF080808),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: active ? Colors.white : const Color(0xFF1F1F1F),
                      ),
                    ),
                    child: Text(
                      t,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : const Color(0xFF777777),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        if (_rankType == 'Dishes') ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: metrics.map((m) {
                final active = _rankMetric == m;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _rankMetric = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF1A1A1A) : const Color(0xFF080808),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active ? Colors.white : const Color(0xFF1F1F1F),
                        ),
                      ),
                      child: Text(
                        m,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                          color: active ? Colors.white : const Color(0xFF888888),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          ..._buildRankedDishesList(),
        ] else ...[
          const SizedBox(height: 4),
          ..._buildRankedPlacesList(),
        ],
      ],
    );
  }

  List<Widget> _buildRankedDishesList() {
    List<Map<String, dynamic>> allDishes = [];
    for (var v in _visits) {
      for (var d in (v['dishes'] as List? ?? [])) {
        final copy = Map<String, dynamic>.from(d);
        copy['restaurant'] = v['restaurant'];
        copy['score'] = _calcDishScore(d);
        copy['appearance'] = (d['appearance'] as num?)?.toDouble() ?? (d['crave'] as num?)?.toDouble() ?? 8.0;
        allDishes.add(copy);
      }
    }

    if (_rankMetric == 'Order Again') {
      allDishes = allDishes.where((d) => d['repeat'] == true).toList();
    }

    allDishes.sort((a, b) {
      if (_rankMetric == 'Taste') return ((b['taste'] ?? 0) as num).compareTo((a['taste'] ?? 0) as num);
      if (_rankMetric == 'Value') return ((b['value'] ?? 0) as num).compareTo((a['value'] ?? 0) as num);
      if (_rankMetric == 'Portion') return ((b['portion'] ?? 0) as num).compareTo((a['portion'] ?? 0) as num);
      if (_rankMetric == 'Appearance') {
        return ((b['appearance'] ?? 0) as num).compareTo((a['appearance'] ?? 0) as num);
      }
      return (b['score'] as double).compareTo(a['score'] as double);
    });

    if (allDishes.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(28),
          child: Center(
            child: Text('No ranked dishes yet.', style: TextStyle(color: Color(0xFF666666))),
          ),
        )
      ];
    }

    return allDishes.asMap().entries.map((entry) {
      final int rank = entry.key + 1;
      final bool isTop3 = rank <= 3;
      final d = entry.value;
      final String? photo = d['photo'];

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF080808),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isTop3 ? const Color(0xFF383838) : const Color(0xFF1A1A1A),
          ),
        ),
        child: Row(
          children: [
            // Rank Badge (Top 3 highlighted in Pure White)
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isTop3 ? Colors.white : const Color(0xFF141414),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isTop3 ? Colors.white : const Color(0xFF262626)),
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isTop3 ? Colors.black : const Color(0xFF888888),
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (photo != null && photo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    base64Decode(photo),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          d['name'] ?? '',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      _microBadge((d['score'] as double).toStringAsFixed(1), highlight: true),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    d['restaurant'] ?? '',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _microBadge('৳${d['price']}', highlight: true),
                      _microBadge('Taste ${d['taste']}'),
                      _microBadge('Value ${d['value']}'),
                      _microBadge('Portion ${d['portion']}'),
                      _microBadge('Appearance ${d['appearance']}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  List<Widget> _buildRankedPlacesList() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var v in _visits) {
      final rName = (v['restaurant'] ?? 'Unknown').toString().trim();
      grouped.putIfAbsent(rName, () => []).add(v);
    }

    final List<Map<String, dynamic>> placesRank = [];
    grouped.forEach((rName, vList) {
      double expSum = 0;
      double dishSum = 0;
      int dishCount = 0;
      int spent = 0;
      for (var v in vList) {
        expSum += (v['expRating'] as num?)?.toDouble() ?? 8.0;
        spent += _calcVisitTotal(v);
        for (var d in (v['dishes'] as List? ?? [])) {
          dishCount++;
          dishSum += _calcDishScore(d);
        }
      }
      final double avgExp = expSum / vList.length;
      final double avgDish = dishCount > 0 ? dishSum / dishCount : avgExp;
      final double overallScore = (avgExp * 0.4) + (avgDish * 0.6);

      placesRank.add({
        'name': rName,
        'area': vList.first['area'] ?? '',
        'visits': vList.length,
        'dishes': dishCount,
        'spent': spent,
        'avgExp': avgExp,
        'score': overallScore,
      });
    });

    placesRank.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    if (placesRank.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(28),
          child: Center(
            child: Text('No ranked places yet.', style: TextStyle(color: Color(0xFF666666))),
          ),
        )
      ];
    }

    return placesRank.asMap().entries.map((entry) {
      final int rank = entry.key + 1;
      final bool isTop3 = rank <= 3;
      final p = entry.value;

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF080808),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isTop3 ? const Color(0xFF383838) : const Color(0xFF1A1A1A),
          ),
        ),
        child: Row(
          children: [
            // Top 3 Podium Highlighted in Pure White
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isTop3 ? Colors.white : const Color(0xFF141414),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isTop3 ? Colors.white : const Color(0xFF262626)),
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isTop3 ? Colors.black : const Color(0xFF888888),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          p['name'],
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      _microBadge((p['score'] as double).toStringAsFixed(1), highlight: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${p['area']} • ${p['visits']} Visits • ${p['dishes']} Dishes',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      _microBadge('Exp ${(p['avgExp'] as double).toStringAsFixed(1)}'),
                      _microBadge('Spent ৳${p['spent']}', highlight: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // ===========================================================================
  // TAB 3: STATS (Timeframe Filters, Interactive Place Drill-Down, Analytics)
  // ===========================================================================
  Widget _buildStatsTab() {
    final timeframes = ['All-Time', 'This Month', 'Last 30 Days', 'Last 3 Months'];
    final now = DateTime.now();

    final filteredVisits = _visits.where((v) {
      final dt = _parseDate(v['date']?.toString() ?? '');
      if (_statsTimeframe == 'This Month') {
        return dt.year == now.year && dt.month == now.month;
      } else if (_statsTimeframe == 'Last 30 Days') {
        return now.difference(dt).inDays <= 30;
      } else if (_statsTimeframe == 'Last 3 Months') {
        return now.difference(dt).inDays <= 90;
      }
      return true;
    }).toList();

    int totalSpent = 0;
    int highestSingleBill = 0;
    String bestValuePlace = '—';
    double bestValueRatio = -1;

    final Map<String, int> spendByMonth = {};
    final Map<String, Map<String, dynamic>> placeStats = {};
    final Map<String, int> spendByCategory = {};

    for (var v in filteredVisits) {
      final int bill = _calcVisitTotal(v);
      totalSpent += bill;
      if (bill > highestSingleBill) highestSingleBill = bill;

      final dt = _parseDate(v['date']?.toString() ?? '');
      final mKey = '${dt.month.toString().padLeft(2, '0')}/${dt.year.toString().substring(2)}';
      spendByMonth[mKey] = (spendByMonth[mKey] ?? 0) + bill;

      final cat = (v['category'] ?? 'Friends').toString();
      spendByCategory[cat] = (spendByCategory[cat] ?? 0) + bill;

      final rName = (v['restaurant'] ?? 'Unknown').toString();
      placeStats.putIfAbsent(
        rName,
        () => {'visits': 0, 'spent': 0, 'expSum': 0.0, 'dishes': <String>[]},
      );
      placeStats[rName]!['visits'] = (placeStats[rName]!['visits'] as int) + 1;
      placeStats[rName]!['spent'] = (placeStats[rName]!['spent'] as int) + bill;
      placeStats[rName]!['expSum'] =
          (placeStats[rName]!['expSum'] as double) + ((v['expRating'] as num?)?.toDouble() ?? 8.0);

      for (var d in (v['dishes'] as List? ?? [])) {
        (placeStats[rName]!['dishes'] as List<String>).add(d['name'] ?? 'Dish');
        final valScore = (d['value'] as num?)?.toDouble() ?? 8.0;
        if (valScore > bestValueRatio) {
          bestValueRatio = valScore;
          bestValuePlace = rName;
        }
      }
    }

    final int avgPerVisit = filteredVisits.isEmpty ? 0 : (totalSpent / filteredVisits.length).round();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Time-Filter Bar at the Very Top
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: timeframes.map((tf) {
              final active = _statsTimeframe == tf;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _statsTimeframe = tf),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? Colors.white : const Color(0xFF0A0A0A),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active ? Colors.white : const Color(0xFF222222),
                      ),
                    ),
                    child: Text(
                      tf,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.black : const Color(0xFF888888),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // Overview Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF080808),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1F1F1F)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Overview',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  _microBadge('৳ BDT', highlight: true),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _statCard('TOTAL SPENT', '৳$totalSpent'),
                  const SizedBox(width: 8),
                  _statCard('AVG / VISIT', '৳$avgPerVisit'),
                  const SizedBox(width: 8),
                  _statCard('HIGHEST MEAL', '৳$highestSingleBill'),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C0C0C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1A1A1A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BEST VALUE SPOT',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF666666)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bestValuePlace,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Monthly Spend Bar Chart
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF080808),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1F1F1F)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Monthly Spend',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 16),
              if (spendByMonth.isEmpty)
                const Text('No data in this timeframe.', style: TextStyle(color: Color(0xFF666666), fontSize: 12))
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: spendByMonth.entries.map((e) {
                    final int maxMonth = spendByMonth.values.reduce(max);
                    final double ratio = maxMonth == 0 ? 0 : e.value / maxMonth;
                    return Column(
                      children: [
                        Text(
                          '৳${e.value}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 28,
                          height: 90,
                          alignment: Alignment.bottomCenter,
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF222222)),
                          ),
                          child: Container(
                            width: 28,
                            height: max(8, 88 * ratio),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          e.key,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF777777)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Interactive "By Place" Spend Breakdown (Tap to Drill-Down)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF080808),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1F1F1F)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'By Place (Tap for Details)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (placeStats.isEmpty)
                const Text('No places logged.', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
              ...() {
                final entries = placeStats.entries.toList()
                  ..sort((a, b) => (b.value['spent'] as int).compareTo(a.value['spent'] as int));
                final int maxPlaceSpend =
                    entries.isEmpty ? 1 : entries.first.value['spent'] as int;

                return entries.map((e) {
                  final String pName = e.key;
                  final int pSpent = e.value['spent'] as int;
                  final int pVisits = e.value['visits'] as int;
                  final double avgExp = (e.value['expSum'] as double) / pVisits;
                  final List<String> dishesTried = e.value['dishes'] as List<String>;
                  final bool isExpanded = _expandedStatPlace == pName;

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _expandedStatPlace = isExpanded ? null : pName;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '$pName ($pVisits)',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Text(
                                '৳$pSpent',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: maxPlaceSpend == 0 ? 0 : pSpent / maxPlaceSpend,
                              minHeight: 5,
                              backgroundColor: const Color(0xFF181818),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          if (isExpanded) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF101010),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF222222)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Avg Experience: ★ ${avgExp.toStringAsFixed(1)} / 10  •  Avg/Visit: ৳${(pSpent / pVisits).round()}',
                                    style: const TextStyle(fontSize: 11, color: Colors.white),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Dishes: ${dishesTried.join(", ")}',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList();
              }(),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Spend by Occasion Category
        if (spendByCategory.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF080808),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1F1F1F)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'By Occasion',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: spendByCategory.entries
                      .map((e) => _microBadge('${e.key}: ৳${e.value}', highlight: true))
                      .toList(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // TAB 4: VAULT (File Picker Import & Direct File Export)
  // ===========================================================================
  Widget _buildVaultTab() {
    final String currentJson = jsonEncode({
      'visits': _visits,
      'places': _places,
    });
    final double kbSize = utf8.encode(currentJson).length / 1024.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Backup & Restore Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF080808),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1F1F1F)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Backup & Restore',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  _microBadge('${kbSize.toStringAsFixed(1)} KB', highlight: true),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _vaultButton('Export JSON File', () async {
                      final String fileName =
                          'dishfolio_backup_${DateTime.now().millisecondsSinceEpoch}.json';
                      try {
                        String? selectedDirectory =
                            await FilePicker.platform.getDirectoryPath(
                          dialogTitle: 'Select folder to save Dishfolio backup',
                        );

                        if (selectedDirectory != null) {
                          try {
                            final file = File('$selectedDirectory/$fileName');
                            await file.writeAsString(currentJson);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Backup saved: $fileName')),
                            );
                            return;
                          } catch (_) {
                            // If folder permission restricted, fall through to Downloads folder
                          }
                        }

                        final downloadDir = Directory('/storage/emulated/0/Download');
                        if (await downloadDir.exists()) {
                          final fallbackFile = File('${downloadDir.path}/$fileName');
                          await fallbackFile.writeAsString(currentJson);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Saved to Downloads: $fileName')),
                          );
                          return;
                        }

                        throw Exception('File write fallback');
                      } catch (e) {
                        Clipboard.setData(ClipboardData(text: currentJson));
                        _rawJsonCtrl.text = currentJson;
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Backup copied to clipboard & Raw JSON box!'),
                          ),
                        );
                      }
                    }),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _vaultButton('Import JSON File', () async {
                      try {
                        FilePickerResult? result = await FilePicker.platform.pickFiles(
                          type: FileType.any,
                          withData: true,
                        );
                        if (result != null && result.files.isNotEmpty) {
                          final pickedFile = result.files.single;
                          String? jsonString;
                          if (pickedFile.bytes != null) {
                            jsonString = utf8.decode(pickedFile.bytes!);
                          } else if (pickedFile.path != null) {
                            jsonString = await File(pickedFile.path!).readAsString();
                          }

                          if (jsonString != null && jsonString.trim().isNotEmpty) {
                            _rawJsonCtrl.text = jsonString;
                            _restoreFromJsonString(jsonString);
                          }
                        }
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Could not read the selected JSON file.')),
                        );
                      }
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(color: Color(0xFF181818), height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Import Mode',
                    style: TextStyle(fontSize: 13, color: Color(0xFF888888)),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _importMode = _importMode == 'Merge' ? 'Replace' : 'Merge';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2A2A2A)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _importMode,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Raw JSON Card
        ContainerI completely understand the frustration—going back and forth on small snippets is exhausting. 

Here is your **entire, complete `lib/main.dart` file** from top to bottom with the `bytes` error fixed[cite: 8], `dart:io` added, and both Android File Export and File Import (`Merge` / `Replace`) properly wired up.

### What to do:
1. Open `lib/main.dart` on GitHub and click the **Edit** (pencil) icon.
2. Press **`Ctrl + A`** inside the code editor to select everything, and press **Backspace** to delete it all.
3. Copy the entire code block below, paste it in, and click **Commit changes...**:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

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
          surface: Color(0xFF080808),
          onSurface: Color(0xFFFFFFFF),
        ),
        sliderTheme: SliderThemeData(
          trackHeight: 5.0,
          activeTrackColor: Colors.white,
          inactiveTrackColor: const Color(0xFF222222),
          thumbColor: Colors.white,
          overlayColor: Colors.white.withOpacity(0.12),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentTab = 0; // 0: Journal, 1: Want to Go, 2: Rankings, 3: Stats, 4: Vault
  final ImagePicker _picker = ImagePicker();

  // Master Data Structures
  List<Map<String, dynamic>> _visits = [];
  List<Map<String, dynamic>> _places = [];

  // Journal State
  String _journalSearch = '';
  String _journalCategory = 'All';
  final List<String> _categories = ['All', 'Friends', 'Solo', 'Family', 'Date', 'Takeout'];
  final Set<String> _expandedPlaces = {};

  // Want to Go State
  String _wtgSearch = '';
  String _wtgFilter = 'Want to Go'; // 'Want to Go' or 'Visited'
  String _wtgSort = 'Newest'; // 'Newest', 'Oldest', 'A-Z'

  // Rankings State
  String _rankType = 'Dishes'; // 'Dishes' or 'Places'
  String _rankMetric = 'Score'; // 'Score', 'Taste', 'Value', 'Portion', 'Appearance', 'Order Again'

  // Stats State
  String _statsTimeframe = 'All-Time'; // 'All-Time', 'This Month', 'Last 30 Days', 'Last 3 Months'
  String? _expandedStatPlace;

  // Vault State
  String _importMode = 'Merge';
  final TextEditingController _rawJsonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? visitsStr = prefs.getString('dishfolio_v2_visits');
    final String? placesStr = prefs.getString('dishfolio_v2_places');

    setState(() {
      if (visitsStr != null && placesStr != null) {
        _visits = List<Map<String, dynamic>>.from(jsonDecode(visitsStr));
        _places = List<Map<String, dynamic>>.from(jsonDecode(placesStr));
      } else {
        // Check legacy v1 data or initialize clean empty state
        final String? oldVisits = prefs.getString('dishfolio_visits');
        if (oldVisits != null) {
          _visits = List<Map<String, dynamic>>.from(jsonDecode(oldVisits));
          _syncPlacesFromVisits();
        }
      }
    });
  }

  void _syncPlacesFromVisits() {
    for (var v in _visits) {
      final rName = (v['restaurant'] ?? '').toString().trim();
      if (rName.isEmpty) continue;
      final exists = _places.any((p) => p['name'].toString().toLowerCase() == rName.toLowerCase());
      if (!exists) {
        _places.add({
          'id': DateTime.now().millisecondsSinceEpoch.toString() + rName,
          'name': rName,
          'area': v['area'] ?? '',
          'mustTry': '',
          'status': 'Visited',
          'addedAt': DateTime.now().millisecondsSinceEpoch,
          'menuImages': <String>[],
        });
      } else {
        final idx = _places.indexWhere((p) => p['name'].toString().toLowerCase() == rName.toLowerCase());
        _places[idx]['status'] = 'Visited';
      }
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dishfolio_v2_visits', jsonEncode(_visits));
    await prefs.setString('dishfolio_v2_places', jsonEncode(_places));
  }

  // --- Date & Score Helpers ---
  DateTime _parseDate(String dateStr) {
    try {
      return DateTime.parse(dateStr);
    } catch (_) {}
    try {
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        return DateTime(int.parse(parts[2]), int.parse(parts[0]), int.parse(parts[1]));
      }
    } catch (_) {}
    return DateTime.now();
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  // Weighted Dish Score: Taste 45%, Value 25%, Portion 15%, Appearance 15%
  double _calcDishScore(Map<String, dynamic> d) {
    final double taste = (d['taste'] as num?)?.toDouble() ?? 8.0;
    final double value = (d['value'] as num?)?.toDouble() ?? 8.0;
    final double portion = (d['portion'] as num?)?.toDouble() ?? 8.0;
    final double appearance = (d['appearance'] as num?)?.toDouble() ?? (d['crave'] as num?)?.toDouble() ?? 8.0;
    return (taste * 0.45) + (value * 0.25) + (portion * 0.15) + (appearance * 0.15);
  }

  int _calcVisitTotal(Map<String, dynamic> v) {
    if (v['totalBill'] != null && (v['totalBill'] as num) > 0) {
      return (v['totalBill'] as num).toInt();
    }
    int sum = 0;
    for (var d in (v['dishes'] as List? ?? [])) {
      sum += (d['price'] as num?)?.toInt() ?? 0;
    }
    return sum;
  }

  // --- Global Metrics ---
  int get _actualWantToGoCount {
    return _places.where((p) => p['status'] == 'Want to Go').length;
  }

  int get _totalVisitsCount => _visits.length;

  int get _totalDishesCount {
    int count = 0;
    for (var v in _visits) {
      count += (v['dishes'] as List? ?? []).length;
    }
    return count;
  }

  int get _monthlySpent {
    final now = DateTime.now();
    int sum = 0;
    for (var v in _visits) {
      final dt = _parseDate(v['date']?.toString() ?? '');
      if (dt.year == now.year && dt.month == now.month) {
        sum += _calcVisitTotal(v);
      }
    }
    return sum;
  }

  Future<String?> _pickBase64Image() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 75,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      return null;
    }
  }

  Future<List<String>> _pickMultipleBase64Images() async {
    try {
      final List<XFile> files = await _picker.pickMultiImage(
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 75,
      );
      List<String> results = [];
      for (var f in files) {
        final bytes = await f.readAsBytes();
        results.add(base64Encode(bytes));
      }
      return results;
    } catch (e) {
      final single = await _pickBase64Image();
      return single != null ? [single] : [];
    }
  }

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
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
                // ONLY show header buttons on Journal tab (_currentTab == 0)
                if (_currentTab == 0)
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
      body: _buildCurrentTab(),
      bottomNavigationBar: Container(
        height: 66,
        decoration: const BoxDecoration(
          color: Color(0xFF000000),
          border: Border(top: BorderSide(color: Color(0xFF1A1A1A), width: 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(0, Icons.book_outlined, 'Journal'),
            _navItem(1, Icons.bookmark_border, 'Want to Go'),
            _navItem(2, Icons.emoji_events_outlined, 'Rankings'),
            _navItem(3, Icons.bar_chart_rounded, 'Stats'),
            _navItem(4, Icons.shield_outlined, 'Vault'),
          ],
        ),
      ),
    );
  }

  Widget _headerButton(String label, VoidCallback onTap, {bool isPrimary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFF141414) : const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isPrimary ? const Color(0xFF383838) : const Color(0xFF222222)),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF121212) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: active ? Border.all(color: const Color(0xFF2C2C2C)) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: active ? Colors.white : const Color(0xFF666666)),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: active ? Colors.white : const Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentTab) {
      case 0:
        return _buildJournalTab();
      case 1:
        return _buildWantToGoTab();
      case 2:
        return _buildRankingsTab();
      case 3:
        return _buildStatsTab();
      case 4:
        return _buildVaultTab();
      default:
        return _buildJournalTab();
    }
  }

  // ===========================================================================
  // TAB 0: JOURNAL (Unified Restaurant Cards + History + Menu Viewer)
  // ===========================================================================
  Widget _buildJournalTab() {
    // Filter visits by category and search query
    final filteredVisits = _visits.where((v) {
      final matchesCat = _journalCategory == 'All' || v['category'] == _journalCategory;
      final q = _journalSearch.toLowerCase();
      final matchesRest = (v['restaurant'] ?? '').toString().toLowerCase().contains(q) ||
          (v['area'] ?? '').toString().toLowerCase().contains(q);
      final matchesDish = (v['dishes'] as List? ?? [])
          .any((d) => (d['name'] ?? '').toString().toLowerCase().contains(q));
      return matchesCat && (matchesRest || matchesDish);
    }).toList();

    // Group visits by Restaurant Name into Unified Restaurant Cards
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var v in filteredVisits) {
      final rName = (v['restaurant'] ?? 'Unknown').toString().trim();
      grouped.putIfAbsent(rName, () => []).add(v);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Top Bento Row (Journal: Want to Go count, Visits, Dishes, Total Visits)
        Row(
          children: [
            _statCard('WANT TO GO', '$_actualWantToGoCount'),
            const SizedBox(width: 8),
            _statCard('VISITS', '$_totalVisitsCount'),
            const SizedBox(width: 8),
            _statCard('DISHES', '$_totalDishesCount'),
            const SizedBox(width: 8),
            _statCard('TOTAL VISITS', '$_totalVisitsCount'),
          ],
        ),
        const SizedBox(height: 14),
        // Search Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF090909),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1F1F1F)),
          ),
          child: TextField(
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: const InputDecoration(
              icon: Icon(Icons.search, size: 18, color: Color(0xFF666666)),
              hintText: 'Search restaurants or dishes...',
              hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 13),
              border: InputBorder.none,
            ),
            onChanged: (val) => setState(() => _journalSearch = val),
          ),
        ),
        const SizedBox(height: 12),
        // Category Filter Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _categories.map((cat) {
              final active = _journalCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _journalCategory = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF1A1A1A) : const Color(0xFF080808),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active ? Colors.white : const Color(0xFF1F1F1F),
                      ),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
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
        if (grouped.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            child: const Text(
              'No visits logged yet.\nTap "Log Visit" at the top right to start your journal.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF666666), fontSize: 13),
            ),
          ),
        ...grouped.entries.map((entry) => _buildUnifiedRestaurantCard(entry.key, entry.value)),
      ],
    );
  }

  Widget _buildUnifiedRestaurantCard(String restaurantName, List<Map<String, dynamic>> visits) {
    // Sort visits newest first
    visits.sort((a, b) => _parseDate(b['date'] ?? '').compareTo(_parseDate(a['date'] ?? '')));

    final String area = visits.first['area'] ?? '';
    double totalExp = 0;
    int totalSpentHere = 0;
    final List<Map<String, dynamic>> allDishesWithMeta = [];

    for (var v in visits) {
      totalExp += (v['expRating'] as num?)?.toDouble() ?? 8.0;
      totalSpentHere += _calcVisitTotal(v);
      for (var d in (v['dishes'] as List? ?? [])) {
        final copy = Map<String, dynamic>.from(d);
        copy['_visitDate'] = v['date'];
        copy['_visitId'] = v['id'];
        copy['_score'] = _calcDishScore(d);
        allDishesWithMeta.add(copy);
      }
    }

    // Order dishes by score highest to lowest
    allDishesWithMeta.sort((a, b) => (b['_score'] as double).compareTo(a['_score'] as double));

    final double avgExp = visits.isEmpty ? 0 : totalExp / visits.length;
    final double avgDishScore = allDishesWithMeta.isEmpty
        ? 0
        : allDishesWithMeta.map((d) => d['_score'] as double).reduce((a, b) => a + b) /
            allDishesWithMeta.length;

    // Find associated place for menu images
    final placeObj = _places.firstWhere(
      (p) => p['name'].toString().toLowerCase() == restaurantName.toLowerCase(),
      orElse: () => <String, dynamic>{},
    );
    final List<String> menuImgs = List<String>.from(placeObj['menuImages'] ?? []);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF080808),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F1F1F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                if (_expandedPlaces.contains(restaurantName)) {
                  _expandedPlaces.remove(restaurantName);
                } else {
                  _expandedPlaces.add(restaurantName);
                }
              });
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            restaurantName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          _microBadge('${visits.length} ${visits.length == 1 ? "Visit" : "Visits"}'),
                          if (menuImgs.isNotEmpty)
                            GestureDetector(
                              onTap: () => _openMenuGalleryModal(restaurantName, menuImgs),
                              child: _microBadge('${menuImgs.length} Menu', highlight: true),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$area • Last: ${visits.first['date']} • ৳$totalSpentHere total',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    _microBadge('Exp ${avgExp.toStringAsFixed(1)}', highlight: true),
                    const SizedBox(width: 6),
                    if (allDishesWithMeta.isNotEmpty)
                      _microBadge(avgDishScore.toStringAsFixed(1), highlight: true),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // All Dishes Ordered by Score
          const Text(
            'DISHES (RANKED)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 6),
          ...allDishesWithMeta.map((d) => _buildDishSubCard(d)),

          // Visit History Timeline Section
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0C0C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1A1A1A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VISIT HISTORY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Color(0xFF777777),
                  ),
                ),
                const SizedBox(height: 8),
                ...visits.map((v) {
                  final vBill = _calcVisitTotal(v);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    v['date'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _microBadge(v['category'] ?? 'Friends'),
                                  const SizedBox(width: 6),
                                  Text(
                                    '★ ${v['expRating']} • ৳$vBill',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                                  ),
                                ],
                              ),
                              if ((v['notes'] ?? '').toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    v['notes'],
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF777777)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _openVisitModal(existingVisit: v),
                          child: _microBadge('Edit', highlight: true),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          // Bottom Action Bar
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  if (menuImgs.isNotEmpty) {
                    _openMenuGalleryModal(restaurantName, menuImgs);
                  } else {
                    _addMenuImagesToRestaurant(restaurantName, area);
                  }
                },
                child: _microBadge(
                  menuImgs.isEmpty ? '+ Add Menu' : 'View / Edit Menu (${menuImgs.length})',
                  highlight: menuImgs.isNotEmpty,
                ),
              ),
              GestureDetector(
                onTap: () => _openVisitModal(prefillRestaurant: restaurantName, prefillArea: area),
                child: _microBadge('+ Add Date', highlight: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDishSubCard(Map<String, dynamic> dish) {
    final double score = (dish['_score'] as num?)?.toDouble() ?? _calcDishScore(dish);
    final String? photoB64 = dish['photo'];
    final double appearance =
        (dish['appearance'] as num?)?.toDouble() ?? (dish['crave'] as num?)?.toDouble() ?? 8.0;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photoB64 != null && photoB64.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => _showFullImageDialog(photoB64, dish['name'] ?? 'Dish'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(photoB64),
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        dish['name'] ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _microBadge(score.toStringAsFixed(1), highlight: true),
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
                    _microBadge('Appearance $appearance'),
                    _microBadge(
                      dish['repeat'] == true ? 'Repeat' : 'Skip',
                      highlight: dish['repeat'] == true,
                    ),
                  ],
                ),
                if ((dish['notes'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    dish['notes'],
                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: WANT TO GO (Fixed ratio, Monthly Spent, 2 Filters + Sort Button)
  // ===========================================================================
  Widget _buildWantToGoTab() {
    // Sync any visited places
    _syncPlacesFromVisits();

    List<Map<String, dynamic>> filtered = _places.where((p) {
      final matchesStatus = p['status'] == _wtgFilter;
      final q = _wtgSearch.toLowerCase();
      final matchesSearch = (p['name'] ?? '').toString().toLowerCase().contains(q) ||
          (p['area'] ?? '').toString().toLowerCase().contains(q) ||
          (p['mustTry'] ?? '').toString().toLowerCase().contains(q);
      return matchesStatus && matchesSearch;
    }).toList();

    if (_wtgSort == 'Newest') {
      filtered.sort((a, b) => ((b['addedAt'] ?? 0) as int).compareTo((a['addedAt'] ?? 0) as int));
    } else if (_wtgSort == 'Oldest') {
      filtered.sort((a, b) => ((a['addedAt'] ?? 0) as int).compareTo((b['addedAt'] ?? 0) as int));
    } else if (_wtgSort == 'A-Z') {
      filtered.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Top Bento Row (Want to Go count, Visits, Dishes, Monthly Spent)
        Row(
          children: [
            _statCard('WANT TO GO', '$_actualWantToGoCount'),
            const SizedBox(width: 8),
            _statCard('VISITS', '$_totalVisitsCount'),
            const SizedBox(width: 8),
            _statCard('DISHES', '$_totalDishesCount'),
            const SizedBox(width: 8),
            _statCard('MONTHLY SPENT', '৳$_monthlySpent'),
          ],
        ),
        const SizedBox(height: 14),
        // Search + Add Button
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF090909),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1F1F1F)),
                ),
                child: TextField(
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  decoration: const InputDecoration(
                    icon: Icon(Icons.search, size: 18, color: Color(0xFF666666)),
                    hintText: 'Search places...',
                    hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 13),
                    border: InputBorder.none,
                  ),
                  onChanged: (val) => setState(() => _wtgSearch = val),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _openAddPlaceModal(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF333333)),
                ),
                child: const Text(
                  'Add',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Only "Want to Go" and "Visited" on Left + Sort Button on Right
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: ['Want to Go', 'Visited'].map((status) {
                final active = _wtgFilter == status;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _wtgFilter = status),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF181818) : const Color(0xFF080808),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active ? Colors.white : const Color(0xFF1F1F1F),
                        ),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                          color: active ? Colors.white : const Color(0xFF888888),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            // Sort Dropdown Pill
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_wtgSort == 'Newest') {
                    _wtgSort = 'Oldest';
                  } else if (_wtgSort == 'Oldest') {
                    _wtgSort = 'A-Z';
                  } else {
                    _wtgSort = 'Newest';
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D0D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF262626)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sort, size: 14, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      'Sort: $_wtgSort',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                'No places in "$_wtgFilter" yet.',
                style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
              ),
            ),
          ),
        ...filtered.map((place) => _buildPlaceCard(place)),
      ],
    );
  }

  Widget _buildPlaceCard(Map<String, dynamic> place) {
    final String name = place['name'] ?? '';
    final placeVisits = _visits
        .where((v) => (v['restaurant'] ?? '').toString().toLowerCase() == name.toLowerCase())
        .toList();

    int dishCount = 0;
    int spent = 0;
    double expSum = 0;
    double dishScoreSum = 0;

    for (var v in placeVisits) {
      spent += _calcVisitTotal(v);
      expSum += (v['expRating'] as num?)?.toDouble() ?? 8.0;
      for (var d in (v['dishes'] as List? ?? [])) {
        dishCount++;
        dishScoreSum += _calcDishScore(d);
      }
    }

    final int menuCount = (place['menuImages'] as List? ?? []).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF080808),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F1F1F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    _microBadge(
                      placeVisits.isEmpty
                          ? 'Want to Go'
                          : '${placeVisits.length} ${placeVisits.length == 1 ? "Visit" : "Visits"}',
                    ),
                  ],
                ),
              ),
              if (placeVisits.isNotEmpty)
                Row(
                  children: [
                    _microBadge('Exp ${(expSum / placeVisits.length).toStringAsFixed(1)}', highlight: true),
                    if (dishCount > 0) ...[
                      const SizedBox(width: 6),
                      _microBadge((dishScoreSum / dishCount).toStringAsFixed(1), highlight: true),
                    ],
                  ],
                )
              else
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _places.removeWhere((p) => p['id'] == place['id']);
                      _saveData();
                    });
                  },
                  child: _microBadge('—'),
                ),
            ],
          ),
          if ((place['area'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              place['area'],
              style: const TextStyle(fontSize: 12, color: Color(0xFF777777)),
            ),
          ],
          if ((place['mustTry'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Must Try: ${place['mustTry']}',
              style: const TextStyle(fontSize: 12, color: Color(0xFFAAAAAA)),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF161616), height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$menuCount Menu • $dishCount Dishes • ৳$spent',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF888888)),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _openAddPlaceModal(existingPlace: place),
                    child: _microBadge('Edit'),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _openVisitModal(
                      prefillRestaurant: name,
                      prefillArea: place['area'] ?? '',
                    ),
                    child: _microBadge('+ Add Date', highlight: true),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 2: RANKINGS (No top bar, Top 3 Podium Highlighted in Pure White)
  // ===========================================================================
  Widget _buildRankingsTab() {
    final metrics = ['Score', 'Taste', 'Value', 'Portion', 'Appearance', 'Order Again'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Dishes vs Places Segmented Toggle
        Row(
          children: ['Dishes', 'Places'].map((t) {
            final active = _rankType == t;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: t == 'Dishes' ? 6 : 0, left: t == 'Places' ? 6 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _rankType = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF161616) : const Color(0xFF080808),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: active ? Colors.white : const Color(0xFF1F1F1F),
                      ),
                    ),
                    child: Text(
                      t,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : const Color(0xFF777777),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        if (_rankType == 'Dishes') ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: metrics.map((m) {
                final active = _rankMetric == m;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _rankMetric = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF1A1A1A) : const Color(0xFF080808),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active ? Colors.white : const Color(0xFF1F1F1F),
                        ),
                      ),
                      child: Text(
                        m,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                          color: active ? Colors.white : const Color(0xFF888888),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          ..._buildRankedDishesList(),
        ] else ...[
          const SizedBox(height: 4),
          ..._buildRankedPlacesList(),
        ],
      ],
    );
  }

  List<Widget> _buildRankedDishesList() {
    List<Map<String, dynamic>> allDishes = [];
    for (var v in _visits) {
      for (var d in (v['dishes'] as List? ?? [])) {
        final copy = Map<String, dynamic>.from(d);
        copy['restaurant'] = v['restaurant'];
        copy['score'] = _calcDishScore(d);
        copy['appearance'] = (d['appearance'] as num?)?.toDouble() ?? (d['crave'] as num?)?.toDouble() ?? 8.0;
        allDishes.add(copy);
      }
    }

    if (_rankMetric == 'Order Again') {
      allDishes = allDishes.where((d) => d['repeat'] == true).toList();
    }

    allDishes.sort((a, b) {
      if (_rankMetric == 'Taste') return ((b['taste'] ?? 0) as num).compareTo((a['taste'] ?? 0) as num);
      if (_rankMetric == 'Value') return ((b['value'] ?? 0) as num).compareTo((a['value'] ?? 0) as num);
      if (_rankMetric == 'Portion') return ((b['portion'] ?? 0) as num).compareTo((a['portion'] ?? 0) as num);
      if (_rankMetric == 'Appearance') {
        return ((b['appearance'] ?? 0) as num).compareTo((a['appearance'] ?? 0) as num);
      }
      return (b['score'] as double).compareTo(a['score'] as double);
    });

    if (allDishes.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(28),
          child: Center(
            child: Text('No ranked dishes yet.', style: TextStyle(color: Color(0xFF666666))),
          ),
        )
      ];
    }

    return allDishes.asMap().entries.map((entry) {
      final int rank = entry.key + 1;
      final bool isTop3 = rank <= 3;
      final d = entry.value;
      final String? photo = d['photo'];

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF080808),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isTop3 ? const Color(0xFF383838) : const Color(0xFF1A1A1A),
          ),
        ),
        child: Row(
          children: [
            // Rank Badge (Top 3 highlighted in Pure White)
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isTop3 ? Colors.white : const Color(0xFF141414),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isTop3 ? Colors.white : const Color(0xFF262626)),
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isTop3 ? Colors.black : const Color(0xFF888888),
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (photo != null && photo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    base64Decode(photo),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          d['name'] ?? '',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      _microBadge((d['score'] as double).toStringAsFixed(1), highlight: true),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    d['restaurant'] ?? '',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _microBadge('৳${d['price']}', highlight: true),
                      _microBadge('Taste ${d['taste']}'),
                      _microBadge('Value ${d['value']}'),
                      _microBadge('Portion ${d['portion']}'),
                      _microBadge('Appearance ${d['appearance']}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  List<Widget> _buildRankedPlacesList() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var v in _visits) {
      final rName = (v['restaurant'] ?? 'Unknown').toString().trim();
      grouped.putIfAbsent(rName, () => []).add(v);
    }

    final List<Map<String, dynamic>> placesRank = [];
    grouped.forEach((rName, vList) {
      double expSum = 0;
      double dishSum = 0;
      int dishCount = 0;
      int spent = 0;
      for (var v in vList) {
        expSum += (v['expRating'] as num?)?.toDouble() ?? 8.0;
        spent += _calcVisitTotal(v);
        for (var d in (v['dishes'] as List? ?? [])) {
          dishCount++;
          dishSum += _calcDishScore(d);
        }
      }
      final double avgExp = expSum / vList.length;
      final double avgDish = dishCount > 0 ? dishSum / dishCount : avgExp;
      final double overallScore = (avgExp * 0.4) + (avgDish * 0.6);

      placesRank.add({
        'name': rName,
        'area': vList.first['area'] ?? '',
        'visits': vList.length,
        'dishes': dishCount,
        'spent': spent,
        'avgExp': avgExp,
        'score': overallScore,
      });
    });

    placesRank.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    if (placesRank.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(28),
          child: Center(
            child: Text('No ranked places yet.', style: TextStyle(color: Color(0xFF666666))),
          ),
        )
      ];
    }

    return placesRank.asMap().entries.map((entry) {
      final int rank = entry.key + 1;
      final bool isTop3 = rank <= 3;
      final p = entry.value;

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF080808),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isTop3 ? const Color(0xFF383838) : const Color(0xFF1A1A1A),
          ),
        ),
        child: Row(
          children: [
            // Top 3 Podium Highlighted in Pure White
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isTop3 ? Colors.white : const Color(0xFF141414),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isTop3 ? Colors.white : const Color(0xFF262626)),
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isTop3 ? Colors.black : const Color(0xFF888888),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          p['name'],
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      _microBadge((p['score'] as double).toStringAsFixed(1), highlight: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${p['area']} • ${p['visits']} Visits • ${p['dishes']} Dishes',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      _microBadge('Exp ${(p['avgExp'] as double).toStringAsFixed(1)}'),
                      _microBadge('Spent ৳${p['spent']}', highlight: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // ===========================================================================
  // TAB 3: STATS (Timeframe Filters, Interactive Place Drill-Down, Analytics)
  // ===========================================================================
  Widget _buildStatsTab() {
    final timeframes = ['All-Time', 'This Month', 'Last 30 Days', 'Last 3 Months'];
    final now = DateTime.now();

    final filteredVisits = _visits.where((v) {
      final dt = _parseDate(v['date']?.toString() ?? '');
      if (_statsTimeframe == 'This Month') {
        return dt.year == now.year && dt.month == now.month;
      } else if (_statsTimeframe == 'Last 30 Days') {
        return now.difference(dt).inDays <= 30;
      } else if (_statsTimeframe == 'Last 3 Months') {
        return now.difference(dt).inDays <= 90;
      }
      return true;
    }).toList();

    int totalSpent = 0;
    int highestSingleBill = 0;
    String bestValuePlace = '—';
    double bestValueRatio = -1;

    final Map<String, int> spendByMonth = {};
    final Map<String, Map<String, dynamic>> placeStats = {};
    final Map<String, int> spendByCategory = {};
    final List<Map<String, dynamic>> allDishes = [];

    for (var v in filteredVisits) {
      final int bill = _calcVisitTotal(v);
      totalSpent += bill;
      if (bill > highestSingleBill) highestSingleBill = bill;

      final dt = _parseDate(v['date']?.toString() ?? '');
      final mKey = '${dt.month.toString().padLeft(2, '0')}/${dt.year.toString().substring(2)}';
      spendByMonth[mKey] = (spendByMonth[mKey] ?? 0) + bill;

      final cat = (v['category'] ?? 'Friends').toString();
      spendByCategory[cat] = (spendByCategory[cat] ?? 0) + bill;

      final rName = (v['restaurant'] ?? 'Unknown').toString();
      placeStats.putIfAbsent(
        rName,
        () => {'visits': 0, 'spent': 0, 'expSum': 0.0, 'dishes': <String>[]},
      );
      placeStats[rName]!['visits'] = (placeStats[rName]!['visits'] as int) + 1;
      placeStats[rName]!['spent'] = (placeStats[rName]!['spent'] as int) + bill;
      placeStats[rName]!['expSum'] =
          (placeStats[rName]!['expSum'] as double) + ((v['expRating'] as num?)?.toDouble() ?? 8.0);

      for (var d in (v['dishes'] as List? ?? [])) {
        (placeStats[rName]!['dishes'] as List<String>).add(d['name'] ?? 'Dish');
        final valScore = (d['value'] as num?)?.toDouble() ?? 8.0;
        if (valScore > bestValueRatio) {
          bestValueRatio = valScore;
          bestValuePlace = rName;
        }
        allDishes.add(d);
      }
    }

    final int avgPerVisit = filteredVisits.isEmpty ? 0 : (totalSpent / filteredVisits.length).round();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Time-Filter Bar at the Very Top
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: timeframes.map((tf) {
              final active = _statsTimeframe == tf;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _statsTimeframe = tf),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? Colors.white : const Color(0xFF0A0A0A),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active ? Colors.white : const Color(0xFF222222),
                      ),
                    ),
                    child: Text(
                      tf,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.black : const Color(0xFF888888),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // Overview Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF080808),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1F1F1F)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Overview',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  _microBadge('৳ BDT', highlight: true),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _statCard('TOTAL SPENT', '৳$totalSpent'),
                  const SizedBox(width: 8),
                  _statCard('AVG / VISIT', '৳$avgPerVisit'),
                  const SizedBox(width: 8),
                  _statCard('HIGHEST MEAL', '৳$highestSingleBill'),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C0C0C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1A1A1A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BEST VALUE SPOT',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF666666)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bestValuePlace,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Monthly Spend Bar Chart
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF080808),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1F1F1F)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Monthly Spend',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 16),
              if (spendByMonth.isEmpty)
                const Text('No data in this timeframe.', style: TextStyle(color: Color(0xFF666666), fontSize: 12))
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: spendByMonth.entries.map((e) {
                    final int maxMonth = spendByMonth.values.reduce(max);
                    final double ratio = maxMonth == 0 ? 0 : e.value / maxMonth;
                    return Column(
                      children: [
                        Text(
                          '৳${e.value}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 28,
                          height: 90,
                          alignment: Alignment.bottomCenter,
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF222222)),
                          ),
                          child: Container(
                            width: 28,
                            height: max(8, 88 * ratio),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          e.key,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF777777)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Interactive "By Place" Spend Breakdown (Tap to Drill-Down)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF080808),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1F1F1F)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'By Place (Tap for Details)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (placeStats.isEmpty)
                const Text('No places logged.', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
              ...() {
                final entries = placeStats.entries.toList()
                  ..sort((a, b) => (b.value['spent'] as int).compareTo(a.value['spent'] as int));
                final int maxPlaceSpend =
                    entries.isEmpty ? 1 : entries.first.value['spent'] as int;

                return entries.map((e) {
                  final String pName = e.key;
                  final int pSpent = e.value['spent'] as int;
                  final int pVisits = e.value['visits'] as int;
                  final double avgExp = (e.value['expSum'] as double) / pVisits;
                  final List<String> dishesTried = e.value['dishes'] as List<String>;
                  final bool isExpanded = _expandedStatPlace == pName;

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _expandedStatPlace = isExpanded ? null : pName;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '$pName ($pVisits)',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Text(
                                '৳$pSpent',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: maxPlaceSpend == 0 ? 0 : pSpent / maxPlaceSpend,
                              minHeight: 5,
                              backgroundColor: const Color(0xFF181818),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          if (isExpanded) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF101010),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF222222)),
