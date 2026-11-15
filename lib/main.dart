import 'package:flutter_localizations/flutter_localizations.dart' hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

void main() => runApp(const FieldShiftApp());

enum AppLanguage { english, hindi, marathi }
enum Status { dry, okay, wet }

class Plot {
  const Plot({
    required this.id,
    required this.name,
    required this.crop,
    required this.area,
    required this.water,
    required this.health,
    required this.heat,
    required this.recommendation,
    required this.ph,
  });
  final String id;
  final String name;
  final String crop;
  final double area;
  final Status water;
  final Status health;
  final Status heat;
  final String recommendation;
  final double ph;
}

class RotationOption {
  const RotationOption(this.crop, this.score, this.reasons, this.risk, this.water);
  final String crop;
  final double score;
  final List<String> reasons;
  final String risk;
  final String water;
}

const plots = [
  Plot(
    id: 'cotton-dry',
    name: 'Cotton field',
    crop: 'Cotton',
    area: 1.2,
    water: Status.dry,
    health: Status.okay,
    heat: Status.okay,
    recommendation: 'Give water soon. Consider a low-water crop next season.',
    ph: 6.7,
  ),
  Plot(
    id: 'soybean-ok',
    name: 'Soybean field',
    crop: 'Soybean',
    area: 0.9,
    water: Status.okay,
    health: Status.okay,
    heat: Status.okay,
    recommendation: 'Plan the next crop and keep checking the soil.',
    ph: 6.4,
  ),
  Plot(
    id: 'chickpea-wet',
    name: 'Chickpea field',
    crop: 'Chickpea',
    area: 1.0,
    water: Status.wet,
    health: Status.okay,
    heat: Status.wet,
    recommendation: 'Wait for the soil to drain before planting.',
    ph: 7.2,
  ),
  Plot(
    id: 'fallow',
    name: 'Fallow field',
    crop: 'Sorghum',
    area: 0.7,
    water: Status.okay,
    health: Status.okay,
    heat: Status.okay,
    recommendation: 'Plan a crop that restores the soil.',
    ph: 7.0,
  ),
  Plot(
    id: 'mandarin',
    name: 'Mandarin orchard',
    crop: 'Mandarin',
    area: 1.5,
    water: Status.okay,
    health: Status.okay,
    heat: Status.okay,
    recommendation: 'Keep the orchard steady and check leaves for stress.',
    ph: 6.2,
  ),
];

const rotationOptions = [
  RotationOption('Pigeon pea (tur)', 86, ['Breaks the cotton family pattern.', 'Low water need fits a dry outlook.', 'Suits the recorded soil.'], 'Watch pests after cotton.', 'Low'),
  RotationOption('Green gram (moong)', 83, ['Adds a helpful legume break.', 'Short crop with low water need.', 'Good fit for warm weather.'], 'Check the crop after heavy rain.', 'Low'),
  RotationOption('Chickpea (gram)', 79, ['Different from cotton.', 'Low water need.', 'Fits the soil pH.'], 'Protect it from late heat.', 'Low'),
  RotationOption('Sunflower', 73, ['Changes the crop family.', 'Handles heat well.', 'Medium water need.'], 'Watch for heat during flowering.', 'Medium'),
  RotationOption('Soybean', 68, ['A familiar legume crop.', 'Medium water need.', 'Can improve rotation.'], 'Do not repeat if pests remain.', 'Medium'),
];

class FieldShiftApp extends StatelessWidget {
  const FieldShiftApp({this.loadLiveOnStart = true, super.key});
  final bool loadLiveOnStart;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Field Shift',
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('hi', 'IN'),
          Locale('mr', 'IN'),
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffe43e98), brightness: Brightness.light),
          scaffoldBackgroundColor: const Color(0xfff8f9fd),
          fontFamily: 'Arial',
        ),
        home: HomeShell(loadLiveOnStart: loadLiveOnStart),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({this.loadLiveOnStart = true, super.key});
  final bool loadLiveOnStart;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppLanguage language = AppLanguage.english;
  int tab = 0;
  Plot? selectedPlot;
  bool liveConnected = false;
  bool liveLoading = true;
  String? liveError;
  bool locating = false;
  int liveGranuleCount = 0;
  bool refreshing = false;
  double timeOffset = 0;
  String activeDataset = 'SMAP Moisture';
  DateTime? liveDate;
  Map<String, dynamic>? liveDashboard;
  List<RotationOption> liveRotationOptions = rotationOptions;
  List<Map<String, dynamic>> twoSeasonPlan = const [];
  List<Map<String, dynamic>> liveRisks = const [];
  Map<String, dynamic>? processedData;
  String selectedCurrentCrop = 'Cotton';
  String? selectedSoilType;
  List<String> selectedPriorities = const ['less_water'];
  Map<String, double> selectedPriorityWeights = const {'less_water': 0.8};
  bool applyingPreferences = false;
  double? latitude;
  double? longitude;
  String locationLabel = 'Nagpur, MH';
  final api = DashboardApi();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  String t(String key) => translations[language]![key] ?? translations[AppLanguage.english]![key]!;

  @override
  void initState() {
    super.initState();
    if (widget.loadLiveOnStart) {
      _loadLiveDashboard();
    } else {
      liveLoading = false;
      liveConnected = true;
    }
  }

  Future<void> _loadLiveDashboard({
    double latitude = 21.1458,
    double longitude = 79.0882,
    DateTime? date,
  }) async {
    final initialLoad = liveDashboard == null;
    setState(() {
      liveLoading = initialLoad;
      refreshing = !initialLoad;
      liveError = null;
    });
    final dashboard = await api.loadDashboard(latitude: latitude, longitude: longitude, date: date);
    if (!mounted) return;
    final provider = dashboard?['provider'];
    if (dashboard == null || (provider != 'nasa-gateway' && provider != 'field-shift-python')) {
      setState(() {
        liveLoading = false;
        refreshing = false;
        if (initialLoad) {
          liveConnected = false;
          liveError = 'Live NASA data is unavailable. Start the Dart gateway and try again.';
        }
      });
      if (!initialLoad) {
        messengerKey.currentState?.showSnackBar(const SnackBar(content: Text('No live NASA data was returned for that date.')));
      }
      return;
    }
    {
      final granules = dashboard['granules'];
      final count = granules is List
          ? granules.fold<int>(0, (total, dataset) => total + ((dataset as Map)['count'] as int? ?? 0))
          : 0;
      setState(() {
        liveLoading = false;
        refreshing = false;
        liveConnected = true;
        liveGranuleCount = count;
        liveDate = date ?? DateTime.now().toUtc();
        liveDashboard = dashboard;
        processedData = dashboard['processed'] is Map<String, dynamic> ? dashboard['processed'] as Map<String, dynamic> : null;
        final analysis = dashboard['rotation_analysis'];
        if (analysis is Map<String, dynamic>) {
          _applyRotationAnalysis(analysis);
        }
      });
    }

  }

  List<RotationOption> _parseRotationOptions(dynamic value) {
    if (value is! List) return rotationOptions;
    final parsed = value.whereType<Map<String, dynamic>>().map((item) {
      return RotationOption(
        item['crop'] as String? ?? 'Unknown crop',
        (item['score'] as num?)?.toDouble() ?? 0,
        (item['reasons'] as List<dynamic>? ?? const []).whereType<String>().toList(),
        item['risk'] as String? ?? 'Confirm with a local agriculture officer.',
        item['water_need'] as String? ?? 'Medium',
      );
    }).toList();
    return parsed.isEmpty ? rotationOptions : parsed;
  }

  void _applyRotationAnalysis(Map<String, dynamic> analysis) {
    liveRotationOptions = _parseRotationOptions(analysis['recommendations']);
    twoSeasonPlan = (analysis['two_season_plan'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    liveRisks = (analysis['risks'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<void> _collectFieldInformation() async {
    try {
      final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) {
        var crop = selectedCurrentCrop;
        String? soil = selectedSoilType;
        final priorityWeights = <String, double>{
          'less_water': selectedPriorityWeights['less_water'] ?? 0.0,
          'better_income': selectedPriorityWeights['better_income'] ?? 0.0,
          'soil_fit': selectedPriorityWeights['soil_fit'] ?? 0.0,
          'climate_resilience': selectedPriorityWeights['climate_resilience'] ?? 0.0,
        };
        const cropNames = ['Cotton', 'Soybean', 'Chickpea (gram)', 'Sorghum (jowar)', 'Maize', 'Mandarin orchard'];
        const soilTypes = ['black soil', 'red soil', 'sandy soil', 'clay soil'];
        final priorityLabels = {
          'less_water': t('priority_less_water'),
          'better_income': t('priority_income'),
          'soil_fit': t('priority_soil'),
          'climate_resilience': t('priority_climate'),
        };
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('tell_field'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(t('field_form_help')),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: crop,
                    decoration: InputDecoration(labelText: t('current_crop'), border: const OutlineInputBorder()),
                    items: cropNames.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                    onChanged: (value) => setSheetState(() => crop = value ?? crop),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: soil,
                    decoration: InputDecoration(labelText: t('soil_type'), hintText: t('soil_unknown'), border: const OutlineInputBorder()),
                    items: soilTypes.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                    onChanged: (value) => setSheetState(() => soil = value),
                  ),
                  const SizedBox(height: 16),
                  Text(t('set_priorities'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(t('priority_help')),
                  const SizedBox(height: 8),
                  ...priorityLabels.entries.map((entry) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(child: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w700))),
                            Text('${(priorityWeights[entry.key]! * 100).round()}%'),
                          ]),
                          Slider(
                            value: priorityWeights[entry.key]!,
                            min: 0,
                            max: 1,
                            divisions: 10,
                            label: '${(priorityWeights[entry.key]! * 100).round()}%',
                            onChanged: (value) => setSheetState(() => priorityWeights[entry.key] = value),
                          ),
                        ],
                      )),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, {
                        'crop': crop,
                        'soil': soil,
                        'priorityWeights': Map<String, double>.from(priorityWeights),
                      }),
                      child: Text(t('analyze_field')),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
        },
      );
      if (result == null || !mounted) return;
      setState(() {
        selectedCurrentCrop = result['crop'] as String;
        selectedSoilType = result['soil'] as String?;
        selectedPriorityWeights = (result['priorityWeights'] as Map).map(
          (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
        );
        selectedPriorities = selectedPriorityWeights.entries.where((entry) => entry.value > 0).map((entry) => entry.key).toList();
        applyingPreferences = true;
      });
      final analysis = await api.loadRecommendations(
        currentCrop: selectedCurrentCrop,
        season: 'Rabi',
        soilPh: selectedPlot?.ph ?? 6.7,
        soilType: selectedSoilType,
        priorities: selectedPriorities,
        priorityWeights: selectedPriorityWeights,
        weather: processedData,
      );
      if (!mounted) return;
      setState(() {
        applyingPreferences = false;
        if (analysis != null) _applyRotationAnalysis(analysis);
      });
      messengerKey.currentState?.showSnackBar(SnackBar(
        content: Text(analysis == null ? 'Could not analyze the field. Is the NASA gateway running?' : 'Recommendations updated for your priorities.'),
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() => applyingPreferences = false);
      messengerKey.currentState?.showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('Field analysis failed: ${error.toString().replaceFirst('Bad state: ', '')}'),
      ));
    }
  }

  DateTime get _selectedDate => DateTime.now().toUtc().add(Duration(days: timeOffset.round()));

  String get _timeLabel {
    if (timeOffset == 0) return 'Live';
    final days = timeOffset.round().abs();
    return timeOffset < 0 ? '-$days Days' : '+$days Days • Estimated';
  }

  Future<void> _detectLocation() async {
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Turn on location services and try again.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was not granted.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _loadLiveDashboard(latitude: position.latitude, longitude: position.longitude);
      if (!mounted) return;
      setState(() {
        latitude = position.latitude;
        longitude = position.longitude;
        locationLabel = '${position.latitude.toStringAsFixed(3)}, ${position.longitude.toStringAsFixed(3)}';
      });
      messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Field location detected and sent to NASA gateway.')),
      );
    } catch (error) {
      messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: messengerKey,
      child: Scaffold(
        body: SafeArea(
          child: selectedPlot == null ? _liveBody() : PlotDetail(plot: selectedPlot!, options: liveRotationOptions, language: language, t: t, onBack: () => setState(() => selectedPlot = null)),
        ),
        bottomNavigationBar: selectedPlot == null ? _navigation() : null,
      ),
    );
  }

  Widget _liveBody() {
    if (liveLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xffe43e98)));
    }
    if (liveError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 52, color: Color(0xffe43e98)),
            const SizedBox(height: 14),
            Text(t('live_required'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(liveError!, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              DashboardApi.baseUrl,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xff68748b)),
            ),
            const SizedBox(height: 18),
            const SelectableText(
              './scripts/run_live.sh',
              style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(t('gateway_hint'), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loadLiveDashboard,
              icon: const Icon(Icons.refresh),
              label: Text(t('retry_live')),
            ),
          ]),
        ),
      );
    }
    return _mainContent();
  }

  Widget _mainContent() {
    final pages = [_mapPage(), _plotsPage(), _nextSeasonPage(), _detailsPage()];
    return Column(children: [
      _header(),
      Expanded(child: pages[tab]),
    ]);
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xff09234b), Color(0xff4d1f58), Color(0xff9b185a)]),
          ),
          child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xff15335a), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xff315384))),
            child: const Icon(Icons.satellite_alt, color: Color(0xff36b8f5), size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Field Shift', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xffe33a91), borderRadius: BorderRadius.circular(8)),
                child: const Text('NASA LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            ]),
            Row(children: [
              Icon(Icons.circle, size: 8, color: liveConnected ? const Color(0xff50d8ff) : const Color(0xffffc34f)),
              const SizedBox(width: 5),
              Text(
                'NASA POWER + $liveGranuleCount live granules',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            SizedBox(
              height: 36,
              child: OutlinedButton.icon(
                onPressed: locating ? null : _detectLocation,
                icon: locating
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.my_location, size: 15),
                label: Text(locationLabel, overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: .35)),
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                ),
              ),
            ),
            SizedBox(
              height: 28,
              child: DropdownButton<AppLanguage>(
            value: language,
            underline: const SizedBox(),
            dropdownColor: const Color(0xff182a4b),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            onChanged: (value) => setState(() => language = value!),
            items: const [
              DropdownMenuItem(value: AppLanguage.english, child: Text('EN')),
              DropdownMenuItem(value: AppLanguage.hindi, child: Text('हि')),
              DropdownMenuItem(value: AppLanguage.marathi, child: Text('मर')),
            ],
              ),
            ),
          ]),
        ]),
        ),
      );

  Widget _plotsPage() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(t('plots'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(t('answer_first'), style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: applyingPreferences ? null : _collectFieldInformation,
              icon: const Icon(Icons.tune),
              label: Text(t('tell_field')),
            ),
          ),
          const SizedBox(height: 16),
          ...plots.map((plot) => PlotCard(
                plot: plot,
                t: t,
                onOpen: () => setState(() => selectedPlot = plot),
              )),
        ],
      );

  Widget _mapPage() => ListView(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _datasetPill(t('smap_moisture'), 'SMAP Moisture', Icons.water_drop, activeDataset == 'SMAP Moisture'),
                _datasetPill(t('landsat_ndvi'), 'Landsat NDVI', Icons.spa, activeDataset == 'Landsat NDVI'),
                _datasetPill(t('thermal_stress'), 'Thermal Stress', Icons.thermostat, activeDataset == 'Thermal Stress'),
              ],
            ),
          ),
          Card(
            color: const Color(0xff0c1d42),
            margin: const EdgeInsets.only(top: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Color(0xff234575))),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_datasetLabel(activeDataset)} ${t('overlay')}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    Text('NASA live granules • ${liveDate == null ? 'waiting' : _shortDate(liveDate!)}', style: const TextStyle(color: Color(0xffff5cae), fontSize: 12, fontWeight: FontWeight.w700)),
                  ])),
                  Chip(label: Text(_timeLabel), backgroundColor: const Color(0xff123c7d)),
                ]),
                const SizedBox(height: 10),
                SizedBox(height: 270, child: CustomPaint(painter: DashboardMapPainter(dataset: activeDataset))),
                const SizedBox(height: 10),
                const Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    LegendDot(color: Color(0xffd32f5c), label: 'Dry (<18%)'),
                    LegendDot(color: Color(0xff31b9ee), label: 'Moderate (24%)'),
                    LegendDot(color: Color(0xff2e65e8), label: 'Optimal (31%)'),
                    LegendDot(color: Color(0xff8c3d66), label: 'Saturated (>36%)'),
                  ],
                ),
              ]),
            ),
          ),
          Card(
            color: const Color(0xff101b31),
            margin: const EdgeInsets.only(top: 14),
            child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 8), child: Column(children: [
              Row(children: [
                const Icon(Icons.sync, color: Color(0xffff52a7)),
                const SizedBox(width: 8),
                Expanded(child: Text(t('forecast_scrubber'), style: const TextStyle(fontWeight: FontWeight.w800))),
                Text('-14 Days', style: TextStyle(color: const Color(0xffff5cae), fontWeight: FontWeight.w800)),
              ]),
              Slider(
                value: timeOffset,
                min: -14,
                max: 7,
                divisions: 21,
                label: _timeLabel,
                onChanged: (value) => setState(() => timeOffset = value),
                onChangeEnd: (_) => _loadLiveDashboard(date: _selectedDate),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('-14d', style: TextStyle(color: Color(0xffff5cae))),
                const Text('-7d'), const Text('Live'), const Text('+3d'), const Text('+7d'),
              ]),
              if (refreshing) const LinearProgressIndicator(color: Color(0xffe43e98)),
            ])),
          ),
          const SizedBox(height: 14),
          _dashboardPlotCard(plots.first),
        ],
      );

  Widget _nextSeasonPage() => ListView(padding: const EdgeInsets.all(16), children: [
        Text(t('next_season'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(t('ranked_for_dry')),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: applyingPreferences ? null : _collectFieldInformation,
            icon: applyingPreferences ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.tune),
            label: Text(applyingPreferences ? t('analyzing_field') : t('tell_field')),
          ),
        ),
        const SizedBox(height: 14),
        if (twoSeasonPlan.isNotEmpty) ...[
          Text(t('two_season_plan'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...twoSeasonPlan.asMap().entries.map((entry) {
            final item = entry.value;
            final reasons = (item['reasons'] as List<dynamic>? ?? const []).whereType<String>().take(2).join(' ');
            return Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${entry.key + 1}')),
                title: Text('${item['season'] ?? 'Next season'}: ${item['crop'] ?? 'Review locally'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('$reasons\nRisk: ${item['risk'] ?? 'Confirm locally'} · Confidence: ${item['confidence'] ?? 'Low'}'),
                isThreeLine: true,
                trailing: Text((item['score'] as num?)?.toStringAsFixed(0) ?? '—', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xff176b50))),
              ),
            );
          }),
          const SizedBox(height: 12),
          Text(t('next_options'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
        ],
        ...liveRotationOptions.asMap().entries.map((entry) => RotationTile(rank: entry.key + 1, option: entry.value, language: language)),
        if (liveRisks.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(t('risk_analysis'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...liveRisks.map((risk) => Card(
                child: ListTile(
                  leading: Icon(
                    risk['level'] == 'high' ? Icons.warning_amber : Icons.info_outline,
                    color: risk['level'] == 'high' ? Colors.red : const Color(0xff9a5c00),
                  ),
                  title: Text(risk['title'] as String? ?? 'Field risk'),
                  subtitle: Text(risk['action'] as String? ?? ''),
                ),
              )),
        ],
        const SizedBox(height: 12),
        _disclaimer(),
      ]);

  Widget _detailsPage() => ListView(padding: const EdgeInsets.all(16), children: [
        Text(t('details'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        _sourceCard(t('water'), 'SMAP L4', 'Regional context, about 9 km', 'Updated 12 Nov · Medium confidence · Estimated'),
        _sourceCard(t('crop_health'), 'Landsat 8/9', '30 m · Last clear image', 'Updated 9 Nov · High confidence'),
        _sourceCard(t('heat'), 'NASA POWER + climate scenarios', 'Weather context, about 50 km', 'Updated 12 Nov · Medium confidence · Estimated'),
        _sourceCard('Soil', 'SoilGrids + SRTM', 'About 250 m soil baseline · 30 m terrain', 'Baseline data · Medium confidence'),
        const SizedBox(height: 12),
        _disclaimer(),
      ]);

  Widget _navigation() => NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) => setState(() => tab = index),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.layers), label: t('map_layers')),
          NavigationDestination(icon: const Icon(Icons.auto_awesome), label: t('adaptations')),
          NavigationDestination(icon: const Icon(Icons.monitor_heart), label: t('telemetry')),
          NavigationDestination(icon: const Icon(Icons.info_outline), label: t('details')),
        ],
      );

  Widget _datasetPill(String label, String datasetKey, IconData icon, bool selected) => GestureDetector(
        onTap: () => setState(() => activeDataset = datasetKey),
        child: Container(
        margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: selected ? const LinearGradient(colors: [Color(0xff2856e8), Color(0xffe43e98)]) : null,
          color: selected ? null : const Color(0xfff4f6fb),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: selected ? Colors.white : const Color(0xff18263d)),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(color: selected ? Colors.white : const Color(0xff18263d), fontWeight: FontWeight.w800)),
        ]),
      ));

  String _shortDate(DateTime value) => '${value.day.toString().padLeft(2, '0')} ${_month(value.month)}';
  String _datasetLabel(String value) => value == 'SMAP Moisture'
      ? t('smap_moisture')
      : value == 'Landsat NDVI'
          ? t('landsat_ndvi')
          : t('thermal_stress');
  String _month(int value) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][value - 1];

  Widget _dashboardPlotCard(Plot plot) => Card(
        color: const Color(0xfffbf9fd),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xffe34a9d))),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Plot A-1 • ${plot.name}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xff14213d))),
                const Text('Nagpur Mandarin Citrus • 14.2 ha', style: TextStyle(color: Color(0xff68748b))),
            ])),
            const Chip(label: Text('Optimal'), backgroundColor: Color(0xff2e65e8)),
          ]),
          const SizedBox(height: 15),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          Metric(label: 'MOISTURE', value: processedData == null ? '—' : '${(((processedData!['soil_moisture_outlook'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(0)}%', color: const Color(0xff31b9ee)),
          Metric(label: 'RAINFALL', value: processedData == null ? '—' : '${processedData!['rainfall_mm']} mm', color: const Color(0xffff5cae)),
          Metric(label: 'TEMPERATURE', value: processedData == null ? '—' : '${processedData!['temperature_c']}°C', color: const Color(0xffa9b5ff)),
          ]),
          const SizedBox(height: 12),
          Text('Updated 12 Nov • Medium confidence • Estimated', style: TextStyle(color: Color(0xff68748b), fontSize: 12)),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, height: 44, child: FilledButton(onPressed: () => setState(() => selectedPlot = plot), child: const Text('Open plot details'))),
        ])),
      );

  Widget _sourceCard(String title, String source, String resolution, String update) => Card(
        child: ListTile(
          leading: const Icon(Icons.public, color: Color(0xff176b50)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('$source\n$resolution\n$update'),
          isThreeLine: true,
        ),
      );
  Widget _disclaimer() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xfffff4d6), borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: Color(0xff765600)),
          const SizedBox(width: 10),
          Expanded(child: Text(t('disclaimer'), style: const TextStyle(color: Color(0xff5d4700)))),
        ]),
      );
}

class PlotCard extends StatelessWidget {
  const PlotCard({required this.plot, required this.t, required this.onOpen, super.key});
  final Plot plot;
  final String Function(String) t;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(plot.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              Text('${plot.area.toStringAsFixed(1)} ha', style: Theme.of(context).textTheme.bodySmall),
            ]),
            Text(plot.crop, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              StatusChip(label: t('water'), status: plot.water, translate: t),
              StatusChip(label: t('crop_health'), status: plot.health, translate: t),
              StatusChip(label: t('heat'), status: plot.heat, translate: t),
            ]),
            const SizedBox(height: 12),
            Text(plot.recommendation, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(onPressed: onOpen, icon: const Icon(Icons.open_in_new), label: Text(t('open'))),
            ),
          ]),
        ),
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip({required this.label, required this.status, this.translate, super.key});
  final String label;
  final Status status;
  final String Function(String)? translate;
  @override
  Widget build(BuildContext context) {
    final (icon, key, color) = switch (status) {
      Status.dry => (Icons.water_drop_outlined, 'needs_water', const Color(0xff9a5c00)),
      Status.okay => (Icons.check_circle_outline, 'okay', const Color(0xff176b50)),
      Status.wet => (Icons.water, 'too_wet', const Color(0xff155a91)),
    };
    final text = translate?.call(key) ?? const {'needs_water': 'Needs water', 'okay': 'OK', 'too_wet': 'Too wet'}[key]!;
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text('$label: $text'),
      side: BorderSide(color: color.withValues(alpha: .3)),
      backgroundColor: color.withValues(alpha: .08),
    );
  }
}

class PlotDetail extends StatefulWidget {
  const PlotDetail({required this.plot, required this.options, required this.language, required this.t, required this.onBack, super.key});
  final Plot plot;
  final List<RotationOption> options;
  final AppLanguage language;
  final String Function(String) t;
  final VoidCallback onBack;
  @override
  State<PlotDetail> createState() => _PlotDetailState();
}

class _PlotDetailState extends State<PlotDetail> {
  final tts = FlutterTts();
  bool whyOpen = false;

  Future<void> readAloud() async {
    await tts.setLanguage('en-IN');
    await tts.speak('${widget.plot.name}. ${widget.plot.recommendation} Water is ${widget.plot.water.name}. Crop health is ${widget.plot.health.name}.');
  }

  Future<void> share() async {
    final text = 'Field Shift: ${widget.plot.name}. ${widget.plot.recommendation} Top next crop: ${rotationOptions.first.crop}.';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.plot.name),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
          actions: [
            IconButton(tooltip: 'Read aloud', icon: const Icon(Icons.volume_up), onPressed: readAloud),
            IconButton(tooltip: 'Share on WhatsApp', icon: const Icon(Icons.share), onPressed: share),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(localizedPhrase(widget.language, widget.plot.crop), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text('${widget.plot.area.toStringAsFixed(1)} ${widget.t('hectares')} · ${widget.t('updated_date')}'),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.plot.recommendation, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            StatusChip(label: widget.t('water'), status: widget.plot.water, translate: widget.t),
            StatusChip(label: widget.t('crop_health'), status: widget.plot.health, translate: widget.t),
            StatusChip(label: widget.t('heat'), status: widget.plot.heat, translate: widget.t),
          ]))),
          const SizedBox(height: 14),
          Card(child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.t('water_trend'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SizedBox(height: 110, child: CustomPaint(painter: TrendPainter(widget.plot.water))),
            Text(widget.t('updated_estimated'), style: Theme.of(context).textTheme.bodySmall),
          ]))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Text(widget.t('next_season'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            TextButton(onPressed: () {}, child: Text(widget.t('view_all'))),
          ]),
          ...widget.options.take(3).map((option) => RotationTile(rank: widget.options.indexOf(option) + 1, option: option, language: widget.language)),
          const SizedBox(height: 8),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.help_outline),
              title: Text(widget.t('why')),
              initiallyExpanded: whyOpen,
              onExpansionChanged: (value) => setState(() => whyOpen = value),
              children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text(widget.t('ranking_explanation')))],
            ),
          ),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(14), color: const Color(0xfff1f5ef), child: Text(widget.t('disclaimer'))),
        ]),
      );
}

class RotationTile extends StatelessWidget {
  const RotationTile({required this.rank, required this.option, required this.language, super.key});
  final int rank;
  final RotationOption option;
  final AppLanguage language;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: CircleAvatar(child: Text('$rank')),
          title: Text(localizedPhrase(language, option.crop), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${option.reasons.take(2).map((reason) => localizedPhrase(language, reason)).join(' ')}\n${localizedPhrase(language, 'Risk')}: ${localizedPhrase(language, option.risk)} · ${localizedPhrase(language, 'Water')}: ${localizedPhrase(language, option.water)}'),
          isThreeLine: true,
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${option.score.toInt()}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xff176b50))),
            Text(localizedPhrase(language, 'score')),
          ]),
        ),
      );
}

class FieldMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final fields = [
      (Offset(size.width * .12, size.height * .18), const Color(0xffd6a64a)),
      (Offset(size.width * .54, size.height * .16), const Color(0xff62a675)),
      (Offset(size.width * .28, size.height * .55), const Color(0xff4b91bd)),
      (Offset(size.width * .70, size.height * .58), const Color(0xff7cba72)),
      (Offset(size.width * .52, size.height * .78), const Color(0xff72a86c)),
    ];
    for (final (offset, color) in fields) {
      paint.color = color;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: offset, width: 110, height: 75), const Radius.circular(12)), paint);
      paint.color = Colors.white;
      canvas.drawCircle(offset, 5, paint);
    }
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class DashboardMapPainter extends CustomPainter {
  DashboardMapPainter({required this.dataset});
  final String dataset;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xff08152b);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)), background);
    final grid = Paint()
      ..color = const Color(0xff173052)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final fields = [
      (Rect.fromLTWH(size.width * .08, size.height * .12, size.width * .42, size.height * .32), const Color(0xff35b9e8), 'PLOT A-1\nLIVE'),
      (Rect.fromLTWH(size.width * .54, size.height * .12, size.width * .38, size.height * .30), const Color(0xffc72d55), 'PLOT B-2\nLIVE'),
      (Rect.fromLTWH(size.width * .08, size.height * .52, size.width * .42, size.height * .32), const Color(0xff2b9bc8), 'PLOT C-3\nLIVE'),
      (Rect.fromLTWH(size.width * .55, size.height * .53, size.width * .36, size.height * .31), const Color(0xffc52c56), 'PLOT D-4\nLIVE'),
    ];
    for (final (rect, color, label) in fields) {
      canvas.drawPath(
        Path()..addPolygon([rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft], true),
        Paint()..color = color,
      );
      final border = Paint()
        ..color = const Color(0xffff4ea7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawPath(
        Path()..addPolygon([rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft], true),
        border,
      );
      final text = TextPainter(
        text: TextSpan(text: '$label\n$dataset', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      final badge = Rect.fromCenter(center: rect.center, width: 78, height: 36);
      canvas.drawRRect(RRect.fromRectAndRadius(badge, const Radius.circular(9)), Paint()..color = const Color(0xff12234d));
      text.paint(canvas, Offset(badge.center.dx - text.width / 2, badge.center.dy - text.height / 2));
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class LegendDot extends StatelessWidget {
  const LegendDot({required this.color, required this.label, super.key});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);
}

class Metric extends StatelessWidget {
  const Metric({required this.label, required this.value, required this.color, super.key});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
      ]);
}

class TrendPainter extends CustomPainter {
  TrendPainter(this.status);
  final Status status;
  @override
  void paint(Canvas canvas, Size size) {
    final color = status == Status.dry ? const Color(0xffc07b20) : status == Status.wet ? const Color(0xff3983b5) : const Color(0xff2e896a);
    final paint = Paint()..color = color..strokeWidth = 4..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final path = Path();
    for (var i = 0; i < 14; i++) {
      final x = i * size.width / 13;
      final y = size.height * (.55 + (i % 4 - 1.5) * .07 + (status == Status.dry ? i * .008 : status == Status.wet ? -i * .006 : 0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

String localizedPhrase(AppLanguage language, String value) {
  const hindi = {
    'Pigeon pea (tur)': 'अरहर (तूर)',
    'Green gram (moong)': 'मूंग',
    'Chickpea (gram)': 'चना',
    'Soybean': 'सोयाबीन',
    'Sorghum (jowar)': 'ज्वार',
    'Maize': 'मक्का',
    'Wheat': 'गेहूं',
    'Sunflower': 'सूरजमुखी',
    'Rice': 'चावल',
    'Cotton': 'कपास',
    'Mandarin orchard': 'संतरा बाग',
    'Low': 'कम',
    'Medium': 'मध्यम',
    'High': 'अधिक',
    'Risk': 'जोखिम',
    'Water': 'पानी',
    'score': 'स्कोर',
    'Changes the crop family and helps restore soil nitrogen.': 'फसल परिवार बदलता है और मिट्टी में नाइट्रोजन सुधारने में मदद करता है।',
    'Breaks the previous crop family pattern.': 'पिछली फसल के परिवार को बदलता है।',
    'Low water need fits the drier outlook.': 'कम पानी की जरूरत सूखे अनुमान के अनुकूल है।',
    'The recorded soil pH is in its suitable range.': 'दर्ज मिट्टी का pH इसके लिए उपयुक्त है।',
    'Not the strongest fit for the next season; confirm the sowing window.': 'अगले मौसम के लिए यह सबसे अच्छा विकल्प नहीं है; बुवाई का समय जांचें।',
    'Monitor pests and confirm the local soil test before planting.': 'कीटों पर नजर रखें और बुवाई से पहले स्थानीय मिट्टी जांच कराएं।',
    'Pests and diseases can carry over in the same crop family.': 'एक ही फसल परिवार में कीट और रोग बने रह सकते हैं।',
  };
  const marathi = {
    'Pigeon pea (tur)': 'तूर',
    'Green gram (moong)': 'मूग',
    'Chickpea (gram)': 'हरभरा',
    'Soybean': 'सोयाबीन',
    'Sorghum (jowar)': 'ज्वारी',
    'Maize': 'मका',
    'Wheat': 'गहू',
    'Sunflower': 'सूर्यफूल',
    'Rice': 'भात',
    'Cotton': 'कापूस',
    'Mandarin orchard': 'संत्र्याची बाग',
    'Low': 'कमी',
    'Medium': 'मध्यम',
    'High': 'जास्त',
    'Risk': 'जोखीम',
    'Water': 'पाणी',
    'score': 'गुण',
    'Changes the crop family and helps restore soil nitrogen.': 'पीक कुटुंब बदलते आणि जमिनीतील नायट्रोजन सुधारण्यास मदत करते.',
    'Breaks the previous crop family pattern.': 'मागील पीक कुटुंबाचा क्रम बदलते.',
    'Low water need fits the drier outlook.': 'कमी पाण्याची गरज कोरड्या अंदाजासाठी योग्य आहे.',
    'The recorded soil pH is in its suitable range.': 'नोंदवलेला मातीचा pH यासाठी योग्य आहे.',
    'Not the strongest fit for the next season; confirm the sowing window.': 'पुढील हंगामासाठी हा सर्वोत्तम पर्याय नाही; पेरणीची वेळ तपासा.',
    'Monitor pests and confirm the local soil test before planting.': 'कीटकांवर लक्ष ठेवा आणि पेरणीपूर्वी स्थानिक माती तपासणी करा.',
    'Pests and diseases can carry over in the same crop family.': 'त्याच पीक कुटुंबातील कीड आणि रोग पुढे राहू शकतात.',
  };
  if (language == AppLanguage.hindi) return hindi[value] ?? value;
  if (language == AppLanguage.marathi) return marathi[value] ?? value;
  return value;
}

const translations = <AppLanguage, Map<String, String>>{
  AppLanguage.english: {
    'region': 'Nagpur district, Maharashtra',
    'plots': 'Plots',
    'map': 'Map',
    'next_season': 'Next season',
    'details': 'Details',
    'water': 'Water',
    'crop_health': 'Crop health',
    'heat': 'Heat stress',
    'open': 'Open plot',
    'answer_first': 'Here is what to do next for each field.',
    'low_data_map': 'Low-data view: no map tiles are loaded.',
    'demo_map': 'Demo field map',
    'time_window': 'Time: 14 days ago to 7 days ahead',
    'estimated_note': 'Future values are estimated and shown with a dashed line.',
    'ranked_for_dry': 'Ranked options for the selected dry plot.',
    'view_all': 'View all',
    'why': 'Why this advice?',
    'tell_field': 'Tell us about your field',
    'field_form_help': 'This helps personalize the two-season recommendation. Soil type is optional.',
    'set_priorities': 'Set your priorities',
    'priority_help': 'Move the bars higher for what matters most to you.',
    'analyze_field': 'Analyze my field',
    'live_required': 'NASA LIVE DATA REQUIRED',
    'gateway_hint': 'This starts the NASA gateway and Flutter together.',
    'retry_live': 'Retry live connection',
    'analyzing_field': 'Analyzing field...',
    'two_season_plan': 'Two-season plan',
    'next_options': 'Next-season options',
    'risk_analysis': 'Risk analysis',
    'priority_less_water': 'Less water',
    'priority_income': 'Better income',
    'priority_soil': 'Fit my soil',
    'priority_climate': 'Climate resilience',
    'current_crop': 'Current or last crop',
    'soil_type': 'Soil type (optional)',
    'soil_unknown': 'Choose if known',
    'needs_water': 'Needs water',
    'okay': 'OK',
    'too_wet': 'Too wet',
    'smap_moisture': 'SMAP Moisture',
    'landsat_ndvi': 'Landsat NDVI',
    'thermal_stress': 'Thermal Stress',
    'overlay': 'Overlay',
    'forecast_scrubber': 'Forecast Shift Scrubber',
    'map_layers': 'Map & Layers',
    'adaptations': 'Adaptations',
    'telemetry': 'Telemetry',
    'hectares': 'ha',
    'updated_date': 'Updated 12 Nov',
    'water_trend': '14-day water trend',
    'updated_estimated': 'Updated 12 Nov · Medium confidence · Estimated',
    'ranking_explanation': 'The ranking compares crop family, water fit, soil fit, seasonal heat risk, and season fit.',
    'disclaimer': 'Estimates from satellite and climate data. Confirm with a local soil test and your agriculture officer.',
  },
  AppLanguage.hindi: {
    'region': 'नागपुर जिला, महाराष्ट्र',
    'plots': 'खेत',
    'map': 'नक्शा',
    'next_season': 'अगला मौसम',
    'details': 'विवरण',
    'water': 'पानी',
    'crop_health': 'फसल स्वास्थ्य',
    'heat': 'गर्मी का तनाव',
    'open': 'खेत खोलें',
    'answer_first': 'हर खेत के लिए अगला काम यहां देखें।',
    'low_data_map': 'कम डेटा दृश्य: नक्शे की टाइलें लोड नहीं होंगी।',
    'demo_map': 'डेमो खेत नक्शा',
    'time_window': 'समय: 14 दिन पहले से 7 दिन आगे',
    'estimated_note': 'आगे के मान अनुमानित हैं और टूटी रेखा में दिखाए गए हैं।',
    'ranked_for_dry': 'सूखे खेत के लिए सबसे अच्छे विकल्प।',
    'view_all': 'सभी देखें',
    'why': 'यह सलाह क्यों?',
    'tell_field': 'अपने खेत के बारे में बताएं',
    'field_form_help': 'इससे दो मौसम की सलाह आपकी जरूरत के अनुसार बनेगी। मिट्टी का प्रकार देना जरूरी नहीं है।',
    'set_priorities': 'अपनी प्राथमिकताएं चुनें',
    'priority_help': 'जिस बात का महत्व अधिक है, उसका बार ऊपर करें।',
    'analyze_field': 'मेरे खेत का विश्लेषण करें',
    'live_required': 'NASA लाइव डेटा आवश्यक है',
    'gateway_hint': 'यह NASA गेटवे और Flutter दोनों शुरू करता है।',
    'retry_live': 'लाइव कनेक्शन फिर कोशिश करें',
    'analyzing_field': 'खेत का विश्लेषण हो रहा है...',
    'two_season_plan': 'दो मौसम की योजना',
    'next_options': 'अगले मौसम के विकल्प',
    'risk_analysis': 'जोखिम विश्लेषण',
    'priority_less_water': 'कम पानी',
    'priority_income': 'बेहतर आय',
    'priority_soil': 'मेरी मिट्टी के अनुसार',
    'priority_climate': 'जलवायु सहनशीलता',
    'current_crop': 'वर्तमान या पिछली फसल',
    'soil_type': 'मिट्टी का प्रकार (वैकल्पिक)',
    'soil_unknown': 'यदि पता हो तो चुनें',
    'needs_water': 'पानी चाहिए',
    'okay': 'ठीक',
    'too_wet': 'बहुत गीला',
    'smap_moisture': 'SMAP नमी',
    'landsat_ndvi': 'Landsat NDVI',
    'thermal_stress': 'गर्मी का तनाव',
    'overlay': 'परत',
    'forecast_scrubber': 'पूर्वानुमान समय पट्टी',
    'map_layers': 'नक्शा और परतें',
    'adaptations': 'अनुकूलन',
    'telemetry': 'माप',
    'hectares': 'हेक्टेयर',
    'updated_date': '12 नवंबर को अपडेट',
    'water_trend': '14 दिनों की पानी की स्थिति',
    'updated_estimated': '12 नवंबर को अपडेट · मध्यम भरोसा · अनुमानित',
    'ranking_explanation': 'यह रैंकिंग फसल परिवार, पानी, मिट्टी, मौसम के खतरे और मौसम के अनुसार बनाई गई है।',
    'disclaimer': 'उपग्रह और जलवायु डेटा के अनुमान। स्थानीय मिट्टी जांच और कृषि अधिकारी से पुष्टि करें।',
  },
  AppLanguage.marathi: {
    'region': 'नागपूर जिल्हा, महाराष्ट्र',
    'plots': 'शेत',
    'map': 'नकाशा',
    'next_season': 'पुढील हंगाम',
    'details': 'तपशील',
    'water': 'पाणी',
    'crop_health': 'पिकाचे आरोग्य',
    'heat': 'उष्णतेचा ताण',
    'open': 'शेत उघडा',
    'answer_first': 'प्रत्येक शेतासाठी पुढील काम येथे पहा.',
    'low_data_map': 'कमी डेटा दृश्य: नकाशाच्या टाइल्स लोड होणार नाहीत.',
    'demo_map': 'डेमो शेत नकाशा',
    'time_window': 'वेळ: 14 दिवस मागे ते 7 दिवस पुढे',
    'estimated_note': 'पुढील मूल्ये अंदाजे आहेत आणि तुटक रेषेत दाखवली आहेत.',
    'ranked_for_dry': 'कोरड्या शेतासाठी सर्वोत्तम पर्याय.',
    'view_all': 'सर्व पहा',
    'why': 'हा सल्ला का?',
    'tell_field': 'तुमच्या शेताबद्दल सांगा',
    'field_form_help': 'यामुळे दोन हंगामांचा सल्ला तुमच्या गरजेनुसार मिळेल. मातीचा प्रकार ऐच्छिक आहे.',
    'set_priorities': 'तुमच्या प्राधान्यक्रमांची निवड करा',
    'priority_help': 'ज्याला जास्त महत्त्व आहे तो बार वर करा.',
    'analyze_field': 'माझ्या शेताचे विश्लेषण करा',
    'live_required': 'NASA लाईव्ह डेटा आवश्यक आहे',
    'gateway_hint': 'यामुळे NASA गेटवे आणि Flutter दोन्ही सुरू होतात.',
    'retry_live': 'लाईव्ह कनेक्शन पुन्हा प्रयत्न करा',
    'analyzing_field': 'शेताचे विश्लेषण सुरू आहे...',
    'two_season_plan': 'दोन हंगामांची योजना',
    'next_options': 'पुढील हंगामाचे पर्याय',
    'risk_analysis': 'जोखीम विश्लेषण',
    'priority_less_water': 'कमी पाणी',
    'priority_income': 'चांगले उत्पन्न',
    'priority_soil': 'माझ्या मातीसाठी योग्य',
    'priority_climate': 'हवामान सहनशीलता',
    'current_crop': 'सध्याचे किंवा मागील पीक',
    'soil_type': 'मातीचा प्रकार (ऐच्छिक)',
    'soil_unknown': 'माहित असल्यास निवडा',
    'needs_water': 'पाण्याची गरज',
    'okay': 'ठीक',
    'too_wet': 'खूप ओले',
    'smap_moisture': 'SMAP ओलावा',
    'landsat_ndvi': 'Landsat NDVI',
    'thermal_stress': 'उष्णतेचा ताण',
    'overlay': 'थर',
    'forecast_scrubber': 'अंदाज वेळ पट्टी',
    'map_layers': 'नकाशा आणि थर',
    'adaptations': 'अनुकूलन',
    'telemetry': 'मोजमाप',
    'hectares': 'हेक्टर',
    'updated_date': '12 नोव्हेंबरला अपडेट',
    'water_trend': '14 दिवसांचा पाण्याचा कल',
    'updated_estimated': '12 नोव्हेंबरला अपडेट · मध्यम विश्वास · अंदाजे',
    'ranking_explanation': 'ही क्रमवारी पीक कुटुंब, पाणी, माती, हंगामी हवामानाचा धोका आणि हंगामावर आधारित आहे.',
    'disclaimer': 'उपग्रह आणि हवामान डेटावर आधारित अंदाज. स्थानिक माती तपासणी आणि कृषी अधिकाऱ्यांकडून खात्री करा.',
  },
};
