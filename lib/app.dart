import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mrbeldi/core/localization/app_locale_service.dart';
import 'package:mrbeldi/core/theme/theme.dart';
import 'package:mrbeldi/core/reviews/review_prompt_manager.dart';
import 'package:mrbeldi/routes/app_routes.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: AppLocaleService.localeNotifier,
      builder: (context, locale, _) {
        return MaterialApp.router(
          title: 'MrBeldi',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          locale: locale,
          supportedLocales: AppLocaleService.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: AppRoutes.router,
          // الحفاظ على اتجاه تخطيط الواجهة العام لمنع انعكاس الشاشات المربك
          builder: (context, child) => Directionality(
            textDirection: TextDirection.ltr,
            child: ReviewPromptManager(
              child: child ?? const SizedBox(),
            ),
          ),
        );
      },
    );
  }
}