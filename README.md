# Raft Pressure

A Flutter app (Android first, iOS-ready) that reads a BLE beacon pressure sensor
(e.g. Holyiot nRF52810 tags) sealed inside a packraft. It:

- shows **live gauge pressure** (psi / mbar / kPa / bar) with a scrolling graph;
- fires **high ("fully inflated")** and **low ("losing air")** alerts, plus a
  **"sensor signal lost"** alert. Each one can use a continuous alarm or a short
  beep, vibration, and a notification;
- records **trips**: pressure plus your **GPS track**, with the track drawn on a
  map and **coloured by raft pressure**. Touch the graph to see where you were;
- exports trips as **GPX** (with pressure in a `<extensions>` block per point)
  or **CSV**, and can **import a GPX** from a watch to overlay pressure on it;
- has a **demo mode**: a simulated sensor and GPS track that runs through
  inflate → paddle → slow leak, so you can try everything before the tags arrive.

## Install

Every push builds an APK with GitHub Actions. Go to **Actions → Test & build APK
→ latest run → Artifacts → raft-pressure-apk**, unzip it, copy
`app-release.apk` to the phone and open it (allow "install unknown apps").

To build yourself: install Flutter 3.47+, then `flutter run` with the phone
plugged in, or `flutter build apk --release`.

## Getting your tags working

Neither Holyiot nor NexBeacon publish how pressure is packed into the broadcast,
and the two apps' firmwares probably differ. So the app doesn't assume a format:

1. Configure the tag in its vendor app (Holyiot app / NexBeacon Pro) so its
   sensor broadcast is **on**, with the shortest advertising interval you can
   accept (shorter means faster updates but shorter battery life).
2. In Raft Pressure tap **Find sensor**. Holy-IOT / NexBeacon names are listed
   first; the strongest signal (closest to 0 dBm) is the tag next to your phone.
3. The **inspector** opens. It shows every byte the tag broadcasts, and bytes
   that change are highlighted.
   - If the tag uses a known open format (BTHome), pressure appears straight away.
   - Otherwise choose **Custom byte layout**, then **Find** next to Pressure.
     With the tag in open air next to the phone, the app tries every plausible
     encoding (uint16/24/32, either byte order, Pa, 0.1 hPa, hPa, float…)
     against your **phone's barometer**, or against the value the vendor app
     shows (type it in and use a small tolerance). Pick the top match, then
     squeeze or breathe on the sensor and check the value moves.
   - Do the same for temperature if you want it. Battery can be set by hand.
4. **Use this sensor**, then tap **Zero** while the sensor is still at outside
   pressure (before you seal the raft, or with the valve open).

If nothing matches, tap the copy icon in the inspector to copy a log of the raw
packets. Paste it somewhere and the layout can usually be worked out by eye.

## Things worth knowing

- **Sensor range:** many cheap barometric chips (BMP280, SPL06, BME280) are only
  specified to **1100 hPa absolute**. At sea level that leaves ~87 hPa (≈1.26 psi)
  of headroom; typical packraft pressure is 1–2.5 psi. Above that they may clip
  or read inaccurately. Check which chip your tags use (it's usually printed on
  the chip; the LPS22HB goes to 1260 hPa). If readings flatten out while you're
  still pumping, this is why.
- **Gauge vs absolute:** the tag measures absolute pressure, and the app subtracts
  an ambient reference. The reference is either the captured **Zero**, your
  **phone's barometer** (offset-calibrated at Zero, so it follows weather and
  altitude changes on long trips), or a fixed 1013.25 hPa.
- **Temperature:** a raft in the sun gains pressure and one in cold water loses
  it. That's real, not a leak, which is why temperature is logged too.
- **Screen off (Android):** while a trip is recording with GPS on, the app runs a
  foreground service (persistent notification), so readings, alerts and the
  track keep going with the phone locked. Without a trip, keep the app open; by
  default the screen stays on in the live view.
- **iOS:** the code is cross-platform, but iOS heavily restricts background BLE
  scanning, so on an iPhone the app is best used in the foreground. Building
  for iOS needs a Mac and Xcode.
- **Maps** use OpenStreetMap tiles and need data signal; a GPX export opens in
  any mapping app.

## Code layout

```
lib/
  ble/        advertisement model, BTHome decoder, configurable field decoder,
              field finder (byte-layout search)
  models/     units, alerts, sensor config, trips/readings/track points
  services/   BLE scanner, live monitor (gauge + alerts), trip recorder (GPS),
              SQLite storage, GPX/CSV, phone barometer, demo simulation
  ui/         home (live), find sensor, inspector, alerts, trips, trip detail,
              settings; chart and pressure-coloured map widgets
test/         decoders, field finder, alert logic, GPX, database, demo timeline,
              and a smoke test that drives every main screen in demo mode
```

Run the tests with `flutter test`. Run
`SCREENSHOT_DIR=/some/dir flutter test test/app_smoke_test.dart` to also save
PNG screenshots of the main screens.
