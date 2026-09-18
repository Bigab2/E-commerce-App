import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mrbeldi/core/localization/app_strings.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';

class MainScreen extends StatelessWidget {
  final Widget child;
  const MainScreen({super.key, required this.child});

  static const _routes = [
    '/home',
    '/categories',
    '/favourites',
    '/cart',
    '/profile',
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _routes.indexOf(location);
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex(context),
        onTap: (index) => context.go(_routes[index]),
        type:                BottomNavigationBarType.fixed,
        selectedItemColor:   AppColors.primary,
        unselectedItemColor: Colors.grey.shade500,
        selectedLabelStyle:   const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 12, fontFamily: 'Cairo'),
        unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500, fontSize: 12, fontFamily: 'Cairo'),
        elevation: 8,
        items: [
          BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined),
              activeIcon: const Icon(Icons.home_rounded),
              label: context.tr('nav_home')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.category_outlined),
              activeIcon: const Icon(Icons.category_rounded),
              label: context.tr('nav_categories')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.favorite_outline_rounded),
              activeIcon: const Icon(Icons.favorite_rounded),
              label: context.tr('nav_favourites')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.shopping_cart_outlined),
              activeIcon: const Icon(Icons.shopping_cart_rounded),
              label: context.tr('nav_cart')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.person_outline_rounded),
              activeIcon: const Icon(Icons.person_rounded),
              label: context.tr('nav_profile')),
        ],
      ),
    );
  }
}
