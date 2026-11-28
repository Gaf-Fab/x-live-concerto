# Changelog

The version number is shown in the app's bottom bar. / Il numero di versione si vede nella barra in basso dell'app.

## 1.1 – 2026-11-28
- **Fixed**: the first marker is placed as soon as the console is recording (it could be ~12 s late): the app now asks the
  console for the recorder state instead of waiting for updates the console never sends.
- **Fixed**: false "markers don't match" banner; the marker count is now asked to the console.
- **Fixed**: total / song timers now advance during recording (state, time and markers are read every second).
- **New**: marker times (`marker_ms`) are written in the log.
- **New**: **END SONG (BREAK)** button: closes the song and starts a break; **START NEXT SONG** starts the next one.
  **UNDO** cancels a break.
- **New**: venue line at the top of the setlist (`Venue: …` / `Locale: …`), shown in the app and saved in the log (`venue`).
- **New**: version number in the bottom bar.
- Tested on X32 Rack (fw 4.15) with an X-LIVE card.

## 1.0 – 2026-11-13
- First version, used at a live show on 2026-11-14.
