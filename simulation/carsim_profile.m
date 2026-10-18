function p = carsim_profile(car)
%CARSIM_PROFILE Vehicle parameters for the simulated cars.
%   p = carsim_profile('nexon') or carsim_profile('swift')
%
%   The values mirror lib/vehicles/profiles.dart in the CarSense app so the
%   MATLAB diagnosis and the app judge the same "normal" ranges.

switch lower(car)
  case 'nexon'
    p.id          = 'tata_nexon_petrol';
    p.name        = 'Tata Nexon (petrol)';
    p.vin         = 'MAT627108NLK12345';
    p.turbo       = true;
    p.idle_rpm    = 800;     % warm idle target, rpm
    p.map_idle    = 36;      % warm idle manifold pressure, kPa
    p.idle_ok     = [700 1000];  p.idle_warn = [600 1200];
    p.max_boost   = 120;     % kPa above atmospheric
    p.crank_amps  = 185;     % 1.2 L turbo 3-cylinder
    p.extra_pids  = hex2dec('46');   % ambient air temperature
  case 'swift'
    p.id          = 'maruti_swift_petrol';
    p.name        = 'Maruti Suzuki Swift (petrol)';
    p.vin         = 'MA3ZFEB1SR0123456';
    p.turbo       = false;
    p.idle_rpm    = 760;
    p.map_idle    = 33;
    p.idle_ok     = [650 900];   p.idle_warn = [550 1100];
    p.max_boost   = 0;
    p.crank_amps  = 165;
    p.extra_pids  = [];
  otherwise
    error('carsim:profile', 'Unknown car "%s" (use nexon or swift)', car);
end

% Shared defaults (same as VehicleProfile defaults in the app).
p.coolant_ok   = [82 105];  p.coolant_warn = [70 112];
p.map_ok       = [25 45];   p.map_warn     = [18 60];
if strcmp(p.id, 'tata_nexon_petrol')
  p.map_ok = [25 50];  p.map_warn = [18 65];
end

% Mode 01 PIDs the simulated engine computer supports.
p.pids = [hex2dec({'01','03','04','05','06','07','0B','0C','0D','0E','0F','11', ...
                   '13','14','15','1C','1F','21','2F','31','33','3C','42','49'})' p.extra_pids];
p.pids = sort(p.pids);
end
