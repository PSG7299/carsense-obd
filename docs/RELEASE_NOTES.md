## CarSense OBD v1.0.0

A read-only car health checker for **Windows** and **Android**, tuned for the **Tata Nexon (petrol)** and the
**Maruti Suzuki Swift (petrol)**. Plug a USB OBD-II adapter into the car, and CarSense detects the car's sensors,
checks them, reads fault codes, tests the battery and alternator, and shows a dashboard with charts.
It never changes or clears anything in the car.

### Downloads

| File | For | How to install |
|---|---|---|
| `CarSense-windows.zip` | Windows 10/11 (64-bit) | Unzip and run `carsense_obd.exe`. If SmartScreen warns, click **More info → Run anyway**. |
| `CarSense-android.apk` | Android 5.0+ with USB-OTG | Open the file on the phone and allow **Install unknown apps** when asked. |
| `CarSense-how-to.mp4` | Everyone | A 4-minute tutorial video for Windows and Android. |

### You also need

* A USB OBD-II adapter (ELM327 v1.5 USB, vLinker FS USB or OBDLink EX)
* For Android: a USB-OTG adapter (USB-A female to USB-C)

### Features

* Detects which sensors the car has, and checks each one against normal ranges for the Nexon or Swift
* Stored, pending and permanent fault codes with plain-English meanings; check-engine light and emissions self-tests
* Battery and charging test (resting, cranking and charging voltage)
* Health score dashboard, live charts, scan history with trends, PDF report
* Demo cars and 18 MATLAB-simulated fault scenarios to try the app without a car

Not yet tested on a real car. Please report problems on the repository's Issues page.
