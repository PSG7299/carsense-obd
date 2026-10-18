import 'vehicle_profile.dart';

const nexonPetrol = VehicleProfile(
  id: 'tata_nexon_petrol',
  name: 'Tata Nexon (petrol)',
  make: 'Tata Motors',
  engine: '1.2 L Revotron turbo-petrol, 3-cylinder',
  turbo: true,
  // Revotron 3-cylinder idles a little higher when cold / with A/C.
  idleRpm: Range(700, 1000, warnLow: 600, warnHigh: 1200),
  idleMap: Range(25, 50, warnLow: 18, warnHigh: 65),
  maxBoostKpa: 120,
  expectedSensors: [
    'Crankshaft position sensor (CKP)',
    'Camshaft position sensors (intake / exhaust)',
    'Manifold absolute pressure + air temp sensor (T-MAP)',
    'Turbo boost pressure sensor',
    'Electronic throttle body (TPS A/B)',
    'Accelerator pedal position sensor (APP D/E)',
    'Engine coolant temperature sensor (ECT)',
    'Upstream O2 sensor (B1S1)',
    'Downstream O2 sensor (B1S2)',
    'Knock sensor',
    'Vehicle speed (from ABS)',
    'Battery / charging system',
  ],
  notes: [
    'Turbo engine: MAP above barometric pressure under load is normal (boost).',
    'Knock and cam sensors are not visible over generic OBD – they show up only as fault codes.',
  ],
);

const swiftPetrol = VehicleProfile(
  id: 'maruti_swift_petrol',
  name: 'Maruti Suzuki Swift (petrol)',
  make: 'Maruti Suzuki',
  engine: '1.2 L K12M / K12N DualJet or Z12E, naturally aspirated',
  turbo: false,
  idleRpm: Range(650, 900, warnLow: 550, warnHigh: 1100),
  expectedSensors: [
    'Crankshaft position sensor (CKP)',
    'Camshaft position sensor (CMP)',
    'Manifold absolute pressure sensor (MAP)',
    'Intake air temperature sensor (IAT)',
    'Electronic throttle body (TPS A/B)',
    'Accelerator pedal position sensor (APP)',
    'Engine coolant temperature sensor (ECT)',
    'Upstream O2 sensor (B1S1)',
    'Downstream O2 sensor (B1S2)',
    'Knock sensor',
    'Vehicle speed sensor',
    'Battery / charging system',
  ],
  notes: [
    'Some Swift variants use a smart alternator (and SHVS mild-hybrid on older DualJet) – charging voltage may drop to ~12.6–13.2 V while cruising; that is normal.',
  ],
);

const genericPetrol = VehicleProfile(
  id: 'generic_petrol',
  name: 'Generic petrol car',
  make: 'Unknown',
  engine: 'Petrol (spark ignition)',
  turbo: false,
  expectedSensors: [],
);

const allProfiles = [nexonPetrol, swiftPetrol, genericPetrol];

VehicleProfile profileById(String id) =>
    allProfiles.firstWhere((p) => p.id == id, orElse: () => genericPetrol);

/// Picks the profile from the VIN maker. Tata -> Nexon, Maruti -> Swift
/// (the two cars this app is built for); the user can override in the UI.
VehicleProfile profileForMaker(String maker) {
  if (maker.startsWith('Tata')) return nexonPetrol;
  if (maker.startsWith('Maruti')) return swiftPetrol;
  return genericPetrol;
}
