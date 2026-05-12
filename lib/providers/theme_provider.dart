import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/domain_event_bus.dart';
import '../core/app_brand.dart';

class ThemeProvider extends ChangeNotifier {
  static const _storageKey = 'active_brand';
  static const _switchCountKey = 'theme_switch_count';

  AppBrand _brand = AppBrands.defaultBrand;
  int _switchCount = 0;

  AppBrand get brand => _brand;
  List<AppBrand> get brands => AppBrands.all;
  int get themeSwitchCount => _switchCount;

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_storageKey);
    _brand = AppBrands.byId(id);
    _switchCount = prefs.getInt(_switchCountKey) ?? 0;
    notifyListeners();
  }

  Future<void> setBrand(String id) async {
    final prev = _brand.id;
    _brand = AppBrands.byId(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, _brand.id);
    if (prev != _brand.id) {
      _switchCount++;
      await prefs.setInt(_switchCountKey, _switchCount);
      DomainEventBus.instance.publish(
        DomainEvent(
          type: DomainEventType.themeSwitched,
          objectId: _brand.id,
          metadata: {'count': _switchCount},
        ),
      );
    }
    notifyListeners();
  }
}
