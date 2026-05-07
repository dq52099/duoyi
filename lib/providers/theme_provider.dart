import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_brand.dart';

class ThemeProvider extends ChangeNotifier {
  static const _storageKey = 'active_brand';

  AppBrand _brand = AppBrands.defaultBrand;
  AppBrand get brand => _brand;
  List<AppBrand> get brands => AppBrands.all;

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_storageKey);
    _brand = AppBrands.byId(id);
    notifyListeners();
  }

  Future<void> setBrand(String id) async {
    _brand = AppBrands.byId(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, _brand.id);
    notifyListeners();
  }
}
