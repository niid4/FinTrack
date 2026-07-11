import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';
import '../models/merchant_rule.dart';
import 'hive_service.dart';

class MerchantResolutionService {
  final HiveService hiveService;
  bool _emulatorConfigured = false;
  
  MerchantResolutionService(this.hiveService);

  final List<Map<String, String>> keywordRules = [
    {'keyword': 'salon', 'category': 'Personal'},
    {'keyword': 'spa', 'category': 'Personal'},
    {'keyword': 'kirana', 'category': 'Groceries'},
    {'keyword': 'dhaba', 'category': 'Food'},
    {'keyword': 'garage', 'category': 'Transportation'},
    {'keyword': 'clinic', 'category': 'Personal'},
    {'keyword': 'pharmacy', 'category': 'Personal'},
    {'keyword': 'hospital', 'category': 'Personal'},
    {'keyword': 'mart', 'category': 'Groceries'},
    {'keyword': 'cafe', 'category': 'Food'},
    {'keyword': 'coffee', 'category': 'Food'},
    {'keyword': 'restaurant', 'category': 'Food'},
    {'keyword': 'petrol', 'category': 'Transportation'},
    {'keyword': 'auto', 'category': 'Transportation'},
    {'keyword': 'uber', 'category': 'Transportation'},
    {'keyword': 'ola', 'category': 'Transportation'},
    {'keyword': 'swiggy', 'category': 'Food'},
    {'keyword': 'zomato', 'category': 'Food'},
    {'keyword': 'gym', 'category': 'Personal'},
    {'keyword': 'movie', 'category': 'Entertainment'},
    {'keyword': 'cinema', 'category': 'Entertainment'},
  ];

  Future<void> init() async {
    if (hiveService.merchantRuleBox.isEmpty) {
      try {
        final String jsonString = await rootBundle.loadString('assets/merchant_dictionary.json');
        final Map<String, dynamic> jsonMap = json.decode(jsonString);
        
        for (var entry in jsonMap.entries) {
          final rule = MerchantRule()
            ..merchantName = entry.key.toLowerCase()
            ..category = entry.value['category']
            ..resolvedBy = entry.value['resolvedBy'];
          await hiveService.saveMerchantRule(rule);
        }
      } catch (e) {
        print("Error loading merchant dictionary: $e");
      }
    }
  }

  /// Strips common noise suffixes from merchant names for better matching.
  static final _noiseSuffixes = RegExp(
    r'\b(pay|india|online|pvt|ltd|limited|private|payments?|technologies|tech|apps?|inc|llp|digital)\b',
    caseSensitive: false,
  );

  String _normalize(String s) {
    return s
        .replaceAll(_noiseSuffixes, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<MerchantRule?> resolveMerchant(String rawName) async {
    final name = rawName.toLowerCase().trim();
    
    // 1a. Exact dictionary lookup
    final existing = hiveService.getMerchantRule(name);
    if (existing != null) {
      return existing;
    }

    // 1b. Fuzzy / substring dictionary lookup — covers cases like
    //     "amazon pay" matching dictionary entry "amazon", or
    //     "swiggy dineout" matching "swiggy".
    final normalized = _normalize(name);
    for (final rule in hiveService.merchantRuleBox.values) {
      final dictName = rule.merchantName;
      if (name.contains(dictName) || dictName.contains(name)) {
        // Save a specific rule so next time it's an exact hit
        final newRule = MerchantRule()
          ..merchantName = name
          ..category = rule.category
          ..resolvedBy = 'dictionary_fuzzy';
        await hiveService.saveMerchantRule(newRule);
        return newRule;
      }
      // Also try after normalizing both sides
      final dictNorm = _normalize(dictName);
      if (dictNorm.isNotEmpty && normalized.isNotEmpty) {
        if (normalized.contains(dictNorm) || dictNorm.contains(normalized)) {
          final newRule = MerchantRule()
            ..merchantName = name
            ..category = rule.category
            ..resolvedBy = 'dictionary_fuzzy';
          await hiveService.saveMerchantRule(newRule);
          return newRule;
        }
      }
    }
    
    // 2. Keyword Rules
    for (var rule in keywordRules) {
      if (name.contains(rule['keyword']!)) {
        final newRule = MerchantRule()
          ..merchantName = name
          ..category = rule['category']!
          ..resolvedBy = 'keyword';
        await hiveService.saveMerchantRule(newRule);
        return newRule;
      }
    }
    
    // 3. Google Places API & Ollama LLM (Server-side)
    try {
      double? lat;
      double? lng;
      
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        // Check-only: never pop a permission dialog from a background
        // capture path. Location is an optional enrichment.
        final LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          // geolocator 14 removed `desiredAccuracy` — use locationSettings.
          final Position position = await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(accuracy: LocationAccuracy.low),
          );
          lat = position.latitude;
          lng = position.longitude;
        }
      }
      
      final functionsInstance = FirebaseFunctions.instance;
      if (kDebugMode && !_emulatorConfigured) {
        // Point to the local machine running the emulator.
        // Use '10.0.2.2' for Android emulator, or '10.9.0.140' / '192.168.137.1' for physical devices.
        functionsInstance.useFunctionsEmulator('10.9.0.140', 5001);
        _emulatorConfigured = true;
      }
      final HttpsCallable callable = functionsInstance.httpsCallable('resolveMerchant');
      final result = await callable.call({
        'merchantName': name,
        'lat': lat,
        'lng': lng,
      });
      
      final data = result.data;
      if (data['category'] != null && data['category'] != 'Other') {
        final newRule = MerchantRule()
          ..merchantName = name
          ..category = data['category']
          ..resolvedBy = data['resolvedBy'];
        await hiveService.saveMerchantRule(newRule);
        return newRule;
      }
    } catch (e) {
      print("Firebase Function resolveMerchant error: $e");
    }
    
    return null;
  }
}
