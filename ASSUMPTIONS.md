# Assumptions

1. The initial demo region is limited to five synthetic plots near Nagpur, Maharashtra.
2. The Flutter app's local MockProvider is the default provider so the demo remains deterministic and works offline.
3. A future live provider may be added behind the same Dart data interface; the UI will not call NASA or other external services directly.
4. Plot-level soil moisture is an estimate derived from regional SMAP context and plot attributes, not a direct SMAP plot measurement.
5. The first release uses English, Hindi, and Marathi translation files with English as the default language.
6. This prototype keeps demo data in the Flutter app; a future persistence layer can store custom plots locally without remote account synchronization.
7. Map tiles are optional presentation data; Low-data mode disables map tiles and retains the list experience.
8. “Next season” means the next suitable Kharif, Rabi, or Zaid planting window inferred from the plot's current season.
9. Climate projection values are presented as scenarios/estimated risk, never as guaranteed weather forecasts.
10. Browser speech support is best-effort: the Read aloud control is hidden or disabled when Web Speech is unavailable.

