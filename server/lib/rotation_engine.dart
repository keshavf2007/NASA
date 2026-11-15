class CropProfile {
  const CropProfile({
    required this.name,
    required this.family,
    required this.seasons,
    required this.waterNeed,
    required this.nitrogenEffect,
    required this.heatTolerance,
    required this.phMin,
    required this.phMax,
    required this.pestFamilies,
    this.perennial = false,
  });

  final String name;
  final String family;
  final List<String> seasons;
  final String waterNeed;
  final String nitrogenEffect;
  final double heatTolerance;
  final double phMin;
  final double phMax;
  final List<String> pestFamilies;
  final bool perennial;
}

class RotationEngine {
  static const weights = {
    'rotation_benefit': 0.35,
    'water_fit': 0.25,
    'soil_fit': 0.20,
    'climate_risk': 0.15,
    'season_fit': 0.05,
  };

  static const crops = <CropProfile>[
    CropProfile(
      name: 'Pigeon pea (tur)',
      family: 'legume',
      seasons: ['Kharif'],
      waterNeed: 'low',
      nitrogenEffect: 'fixer',
      heatTolerance: 0.85,
      phMin: 6.0,
      phMax: 7.8,
      pestFamilies: ['legume'],
    ),
    CropProfile(
      name: 'Green gram (moong)',
      family: 'legume',
      seasons: ['Kharif', 'Zaid'],
      waterNeed: 'low',
      nitrogenEffect: 'fixer',
      heatTolerance: 0.90,
      phMin: 6.0,
      phMax: 7.5,
      pestFamilies: ['legume'],
    ),
    CropProfile(
      name: 'Chickpea (gram)',
      family: 'legume',
      seasons: ['Rabi'],
      waterNeed: 'low',
      nitrogenEffect: 'fixer',
      heatTolerance: 0.55,
      phMin: 6.0,
      phMax: 8.0,
      pestFamilies: ['legume'],
    ),
    CropProfile(
      name: 'Soybean',
      family: 'legume',
      seasons: ['Kharif'],
      waterNeed: 'medium',
      nitrogenEffect: 'fixer',
      heatTolerance: 0.70,
      phMin: 6.0,
      phMax: 7.5,
      pestFamilies: ['legume'],
    ),
    CropProfile(
      name: 'Sorghum (jowar)',
      family: 'cereal',
      seasons: ['Kharif', 'Rabi'],
      waterNeed: 'low',
      nitrogenEffect: 'heavy_feeder',
      heatTolerance: 0.90,
      phMin: 5.5,
      phMax: 8.0,
      pestFamilies: ['cereal'],
    ),
    CropProfile(
      name: 'Maize',
      family: 'cereal',
      seasons: ['Kharif', 'Rabi'],
      waterNeed: 'high',
      nitrogenEffect: 'heavy_feeder',
      heatTolerance: 0.65,
      phMin: 5.8,
      phMax: 7.5,
      pestFamilies: ['cereal'],
    ),
    CropProfile(
      name: 'Wheat',
      family: 'cereal',
      seasons: ['Rabi'],
      waterNeed: 'medium',
      nitrogenEffect: 'heavy_feeder',
      heatTolerance: 0.45,
      phMin: 6.0,
      phMax: 7.5,
      pestFamilies: ['cereal'],
    ),
    CropProfile(
      name: 'Sunflower',
      family: 'oilseed',
      seasons: ['Kharif', 'Rabi'],
      waterNeed: 'medium',
      nitrogenEffect: 'neutral',
      heatTolerance: 0.85,
      phMin: 6.0,
      phMax: 7.8,
      pestFamilies: ['oilseed'],
    ),
    CropProfile(
      name: 'Rice',
      family: 'cereal',
      seasons: ['Kharif'],
      waterNeed: 'high',
      nitrogenEffect: 'heavy_feeder',
      heatTolerance: 0.75,
      phMin: 5.5,
      phMax: 7.5,
      pestFamilies: ['cereal'],
    ),
    CropProfile(
      name: 'Cotton',
      family: 'fibre',
      seasons: ['Kharif'],
      waterNeed: 'medium',
      nitrogenEffect: 'heavy_feeder',
      heatTolerance: 0.85,
      phMin: 5.5,
      phMax: 8.0,
      pestFamilies: ['fibre'],
    ),
    CropProfile(
      name: 'Mandarin orchard',
      family: 'citrus',
      seasons: ['perennial'],
      waterNeed: 'medium',
      nitrogenEffect: 'heavy_feeder',
      heatTolerance: 0.75,
      phMin: 5.5,
      phMax: 7.5,
      pestFamilies: ['citrus'],
      perennial: true,
    ),
  ];

  List<Map<String, dynamic>> rank({
    required String currentCrop,
    required String season,
    required double soilPh,
    required double soilMoisture,
    required double rainfallMm,
    required double temperatureC,
    required bool weatherValid,
    List<String> priorities = const [],
    Map<String, double> priorityWeights = const {},
    String? soilType,
  }) {
    final previous = _findCrop(currentCrop);
    final climateHeat = _clamp((temperatureC - 30) / 10);
    final wetness = _clamp((rainfallMm - 5) / 20);
    final waterOutlook = _clamp((soilMoisture * 0.7) + (wetness * 0.3));

    return crops
        .where((crop) => crop.name != currentCrop && !crop.perennial)
        .map((crop) {
          final rotation = _rotationScore(crop, previous);
          final water = _waterScore(crop.waterNeed, waterOutlook);
          final soil = _soilScore(crop, soilPh);
          final climate = _clamp(1 - (climateHeat * (1 - crop.heatTolerance)));
          final seasonFit = crop.seasons.contains(season) ? 1.0 : 0.35;
          final baseScore = (rotation * weights['rotation_benefit']! +
                  water * weights['water_fit']! +
                  soil * weights['soil_fit']! +
                  climate * weights['climate_risk']! +
                  seasonFit * weights['season_fit']!) *
              100;
          final preferenceBonus = _preferenceBonus(
            crop: crop,
            priorities: priorities,
            priorityWeights: priorityWeights,
            soilType: soilType,
            water: water,
            climate: climate,
          );
          final score = _clamp((baseScore + preferenceBonus) / 100) * 100;
          final reasons = <String>[
            _rotationReason(crop, previous),
            _waterReason(crop.waterNeed, waterOutlook),
            _soilReason(crop, soilPh),
          ];
          return {
            'crop': crop.name,
            'score': double.parse(score.toStringAsFixed(1)),
            'confidence': _confidence(rainfallMm, temperatureC, weatherValid),
            'water_need': _label(crop.waterNeed),
            'priority_effect': _round(preferenceBonus),
            'reasons': reasons,
            'risk': _risk(crop, previous, climateHeat, waterOutlook, seasonFit),
            'components': {
              'rotation_benefit': _round(rotation * 100),
              'water_fit': _round(water * 100),
              'soil_fit': _round(soil * 100),
              'climate_risk': _round(climate * 100),
              'season_fit': _round(seasonFit * 100),
            },
          };
        })
        .toList()
      ..sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
  }

  Map<String, dynamic> analyze({
    required String currentCrop,
    required String season,
    required double soilPh,
    required double soilMoisture,
    required double rainfallMm,
    required double temperatureC,
    required bool weatherValid,
    List<String> priorities = const [],
    Map<String, double> priorityWeights = const {},
    String? soilType,
  }) {
    final recommendations = rank(
      currentCrop: currentCrop,
      season: season,
      soilPh: soilPh,
      soilMoisture: soilMoisture,
      rainfallMm: rainfallMm,
      temperatureC: temperatureC,
      weatherValid: weatherValid,
      priorities: priorities,
      priorityWeights: priorityWeights,
      soilType: soilType,
    );
    final first = recommendations.isEmpty ? null : recommendations.first;
    final secondCrop = first?['crop'] as String? ?? currentCrop;
    final secondSeason = _followingSeason(season);
    final secondRecommendations = rank(
      currentCrop: secondCrop,
      season: secondSeason,
      soilPh: soilPh,
      soilMoisture: soilMoisture,
      rainfallMm: rainfallMm,
      temperatureC: temperatureC,
      weatherValid: weatherValid,
      priorities: priorities,
      priorityWeights: priorityWeights,
      soilType: soilType,
    );
    final risks = <Map<String, dynamic>>[];
    if (!weatherValid) {
      risks.add({'level': 'medium', 'title': 'Weather input unavailable', 'action': 'Use a local rain and soil check before acting on this ranking.'});
    } else if (soilMoisture < 0.35) {
      risks.add({'level': 'high', 'title': 'Dry soil outlook', 'action': 'Check field moisture before sowing and prefer a low-water crop.'});
    } else if (soilMoisture > 0.75) {
      risks.add({'level': 'medium', 'title': 'Wet soil outlook', 'action': 'Wait for drainage and avoid planting into standing water.'});
    }
    if (temperatureC > 34) {
      risks.add({'level': 'high', 'title': 'Heat stress risk', 'action': 'Prefer heat-tolerant crops and protect seedlings during hot days.'});
    }
    if (risks.isEmpty) {
      risks.add({'level': 'low', 'title': 'No major weather signal', 'action': 'Continue field checks and confirm soil condition locally.'});
    }
    return {
      'method': 'Explainable rule-based crop rotation and risk analysis',
      'weights': weights,
      'inputs': {
        'current_crop': currentCrop,
        'season': season,
        'soil_ph': soilPh,
        'soil_moisture_outlook': soilMoisture,
        'rainfall_mm': rainfallMm,
        'temperature_c': temperatureC,
        'priorities': priorities,
        'priority_weights': priorityWeights,
        'soil_type': soilType,
      },
      'recommendations': recommendations.take(5).toList(),
      'two_season_plan': [
        {
          'season': season,
          'crop': first?['crop'],
          'score': first?['score'],
          'reasons': first?['reasons'] ?? const [],
          'risk': first?['risk'],
          'confidence': first?['confidence'],
        },
        if (secondRecommendations.isNotEmpty)
          {
            'season': secondSeason,
            'crop': secondRecommendations.first['crop'],
            'score': secondRecommendations.first['score'],
            'reasons': secondRecommendations.first['reasons'],
            'risk': secondRecommendations.first['risk'],
            'confidence': secondRecommendations.first['confidence'],
          },
      ],
      'risks': risks,
    };
  }

  double _preferenceBonus({
    required CropProfile crop,
    required List<String> priorities,
    required Map<String, double> priorityWeights,
    required String? soilType,
    required double water,
    required double climate,
  }) {
    var bonus = 0.0;
    for (final priority in priorities) {
      final strength = (priorityWeights[priority] ?? 1).clamp(0.0, 1.0).toDouble();
      switch (priority) {
        case 'less_water':
          bonus += (crop.waterNeed == 'low' ? 12 : crop.waterNeed == 'medium' ? 5 : 0) * strength;
        case 'better_income':
          bonus += _incomeIndex(crop) * 10 * strength;
        case 'climate_resilience':
          bonus += climate * 8 * strength;
        case 'soil_fit':
          bonus += (soilType == null || soilType.isEmpty
              ? 2
              : _soilTypeFit(crop, soilType) * 6) * strength;
      }
    }
    return bonus;
  }

  double _incomeIndex(CropProfile crop) {
    switch (crop.name) {
      case 'Cotton':
      case 'Mandarin orchard':
        return 1.0;
      case 'Soybean':
      case 'Maize':
      case 'Sunflower':
        return 0.8;
      case 'Pigeon pea (tur)':
      case 'Chickpea (gram)':
        return 0.75;
      default:
        return 0.6;
    }

  }

  double _soilTypeFit(CropProfile crop, String soilType) {
    final type = soilType.toLowerCase();
    if (type.contains('black')) {
      return ['Cotton', 'Soybean', 'Pigeon pea (tur)', 'Sorghum (jowar)'].contains(crop.name) ? 1 : 0.6;
    }
    if (type.contains('sandy')) {
      return ['Pigeon pea (tur)', 'Green gram (moong)', 'Sunflower'].contains(crop.name) ? 1 : 0.6;
    }
    if (type.contains('clay')) {
      return ['Rice', 'Soybean', 'Chickpea (gram)'].contains(crop.name) ? 1 : 0.6;
    }
    return ['Sorghum (jowar)', 'Chickpea (gram)', 'Sunflower'].contains(crop.name) ? 1 : 0.6;
  }

  String _followingSeason(String season) {
    switch (season) {
      case 'Kharif':
        return 'Rabi';
      case 'Rabi':
        return 'Zaid';
      default:
        return 'Kharif';
    }
  }

  CropProfile _findCrop(String name) => crops.firstWhere(
        (crop) => crop.name.toLowerCase() == name.toLowerCase(),
        orElse: () => crops.firstWhere((crop) => crop.name == 'Cotton'),
      );

  double _rotationScore(CropProfile crop, CropProfile previous) {
    if (crop.family != previous.family && crop.nitrogenEffect == 'fixer') return 1.0;
    if (crop.family != previous.family) return 0.82;
    return 0.25;
  }

  double _waterScore(String need, double outlook) {
    final target = {'low': 0.3, 'medium': 0.55, 'high': 0.8}[need]!;
    return _clamp(1 - ((target - outlook).abs() / 0.7));
  }

  double _soilScore(CropProfile crop, double ph) {
    if (ph >= crop.phMin && ph <= crop.phMax) return 1.0;
    final distance = ph < crop.phMin ? crop.phMin - ph : ph - crop.phMax;
    return _clamp(1 - (distance / 1.5));
  }

  String _rotationReason(CropProfile crop, CropProfile previous) {
    if (crop.family != previous.family && crop.nitrogenEffect == 'fixer') return 'Changes the crop family and helps restore soil nitrogen.';
    if (crop.family != previous.family) return 'Breaks the previous crop family pattern.';
    return 'Repeats the crop family, so pest carryover needs close checking.';
  }

  String _waterReason(String need, double outlook) {
    if (need == 'low' && outlook < 0.45) return 'Low water need fits the drier outlook.';
    if (need == 'high' && outlook > 0.65) return 'The wetter outlook can support its higher water need.';
    return '${_label(need)} water need is close to the estimated field outlook.';
  }

  String _soilReason(CropProfile crop, double ph) {
    return ph >= crop.phMin && ph <= crop.phMax ? 'The recorded soil pH is in its suitable range.' : 'The soil pH is outside its preferred range.';
  }

  String _risk(CropProfile crop, CropProfile previous, double heat, double water, double seasonFit) {
    if (seasonFit < 1) return 'Not the strongest fit for the next season; confirm the sowing window.';
    if (heat > 0.5 && crop.heatTolerance < 0.65) return 'Heat may reduce flowering or grain filling.';
    if (water < 0.3 && crop.waterNeed == 'high') return 'High water need may be difficult if rain is late.';
    if (crop.family == previous.family) return 'Pests and diseases can carry over in the same crop family.';
    return 'Monitor pests and confirm the local soil test before planting.';
  }

  String _confidence(double rainfall, double temperature, bool weatherValid) {
    if (weatherValid && rainfall >= 0 && temperature > -20) return 'Medium';
    return 'Low';
  }

  String _label(String value) => '${value[0].toUpperCase()}${value.substring(1)}';
  double _clamp(double value) => value.clamp(0.0, 1.0).toDouble();
  double _round(double value) => double.parse(value.toStringAsFixed(1));
}

class NasaDataProcessor {
  Map<String, dynamic> summarize(Map<String, dynamic> power, List<Map<String, dynamic>> granules) {
    final parameters = (power['properties']?['parameter'] as Map<String, dynamic>?) ?? const {};
    final temperature = _latest(parameters['T2M']);
    final rainfall = _latest(parameters['PRECTOTCORR']);
    final solar = _latest(parameters['ALLSKY_SFC_SW_DWN']);
    final weatherValid = _hasValid(parameters['T2M']) && _hasValid(parameters['PRECTOTCORR']);
    final granuleCount = granules.fold<int>(0, (total, item) => total + ((item['count'] as num?)?.toInt() ?? 0));
    final moisture = weatherValid ? _clamp((rainfall / 12) + 0.25) : 0.5;
    return {
      'temperature_c': _round(temperature),
      'rainfall_mm': _round(rainfall),
      'solar_kwh_m2': _round(solar),
      'soil_moisture_outlook': _round(moisture),
      'weather_valid': weatherValid,
      'granule_count': granuleCount,
      'quality': weatherValid && granuleCount > 0 ? 'live observations found' : 'some live values are unavailable',
    };
  }

  double _latest(dynamic values) {
    if (values is! Map || values.isEmpty) return 0;
    final value = values.values.last;
    return value is num && value.isFinite && value > -900 ? value.toDouble() : 0;
  }

  bool _hasValid(dynamic values) {
    if (values is! Map || values.isEmpty) return false;
    final value = values.values.last;
    return value is num && value.isFinite && value > -900;
  }
  double _clamp(double value) => value.clamp(0.0, 1.0).toDouble();
  double _round(double value) => double.parse(value.toStringAsFixed(2));
}
