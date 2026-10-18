function sim = carsim_simulate(car, scenario, seed)
%CARSIM_SIMULATE Simulate a petrol car from cold start to warm idle.
%   sim = carsim_simulate('nexon', 'worn_catalyst', 1)
%
%   Models (sample time 0.1 s, 1200 s from a cold start at 30 C ambient):
%    * coolant warm-up with a thermostat / radiator fan
%    * idle speed with cold fast-idle and random misfires
%    * closed-loop fuel control: narrow-band O2 sensor, transport delay,
%      short-term trim (switching integrator) and long-term trim learning
%    * catalytic converter oxygen storage -> downstream O2 sensor
%    * battery (open-circuit voltage + internal resistance) and alternator
%    * a simple engine-computer that sets trouble codes (DTCs), the
%      check-engine light and readiness monitors from what it sees
%
%   The last 30 s (300 samples) are the "scan window" the app will read.

if nargin < 3, seed = 1; end
rng(seed);
p  = carsim_profile(car);
sc = carsim_scenarios(scenario);

dt = 0.1;  T = 1200;  n = round(T / dt);
t  = (0:n-1)' * dt;
Tamb = 30;

% ---- outputs
ect = zeros(n,1); rpm = ect; stft = ect; ltft = ect; o2u = ect; o2d = ect;
lamu = ect; cat = ect; batt = ect; closed = false(n,1); misfire = false(n,1);

% ---- states
T_c = Tamb; st = 0; lt = 0; vu = 0.45; vd = 0.45; s = 0.5; dip = 0;
catT = Tamb;
delay = 3;                         % 0.3 s fuel -> O2 transport delay
lam_buf = ones(delay, 1);
alpha_u = dt / (0.08 + dt);        % upstream O2 response
alpha_d = dt / (0.30 + dt);        % downstream O2 response
t_closed = inf;

for k = 1:n
  tk = t(k);

  % -- coolant temperature: heat in vs. radiator (thermostat-controlled)
  open_frac = min(max((T_c - 85) / 10, 0), 1);   % thermostat opens 85..95 C
  switch sc.thermostat
    case 'ok',         kr = 5e-4 + open_frac * (0.010 - 5e-4);
    case 'stuck_open', kr = 0.0075;
    case 'fan_dead',   kr = 5e-4 + open_frac * (0.0028 - 5e-4);
  end
  T_c = T_c + (0.25 - kr * (T_c - Tamb)) * dt + 0.01 * randn;
  warm = min(max((T_c - 30) / 55, 0), 1);

  % -- idle speed (fast idle when cold) with misfire dips
  dip = dip * 0.6;
  if rand < sc.misfire_rate
    dip = dip + 200 + 80 * rand;
    misfire(k) = true;
  end
  rpm(k) = p.idle_rpm + 350 * (1 - warm) - dip + 8 * randn;

  % -- closed-loop fuel control
  is_closed = T_c > 45 && tk > 40;
  if is_closed && isinf(t_closed), t_closed = tk; end
  o2_died  = sc.o2_dead && tk >= 600;             % sensor fails mid-drive
  o2_fault = o2_died && tk > max(t_closed, 600) + 60;   % ECU has detected it
  if is_closed && ~o2_fault
    lean = vu < 0.45;
    if k > 1 && lean ~= (o2u(k-1) < 0.45)       % switch: proportional jump
      st = st + 1.5 * (2 * lean - 1);
    end
    st = st + 6 * dt * (2 * lean - 1);          % integrator ramp
    st = min(max(st, -25), 25);
    lt = lt + st * dt / 20;                     % long-term learning
    lt = min(max(lt, -25), 25);
  elseif ~is_closed
    st = 0;
  end
  if o2_fault, st = 0; end                       % fallback: hold learned LTFT
  fuel = 1 + (st + lt) / 100;
  lam  = (1 + sc.leak) / fuel;
  if ~is_closed, lam = lam * 0.93; end           % open-loop enrichment
  if o2_fault,   lam = lam * 0.98; end           % safe, slightly rich fallback
  lam  = lam + 0.003 * randn;
  lam_buf = [lam_buf(2:end); lam];
  lu = lam_buf(1);

  % -- catalyst oxygen storage (0 = empty/rich, 1 = full/lean)
  s = s + ((lu - 1) / sc.osc + (0.5 - s) * 0.05) * dt;
  s = min(max(s, 0), 1);
  through = max(0, (abs(s - 0.5) - 0.4) / 0.1);  % breakthrough when nearly empty/full
  ld = 0.995 + (lu - 0.995) * through;

  % -- O2 sensors (narrow-band switching characteristic)
  vt_u = 0.1 + 0.8 / (1 + exp((lu - 1) * 300));
  vt_d = 0.1 + 0.8 / (1 + exp((ld - 1) * 300));
  if o2_died
    vu = 0.45 + 0.004 * randn;
  else
    vu = vu + alpha_u * (vt_u - vu);
  end
  vd = vd + alpha_d * (vt_d - vd) + 0.004 * randn;

  % -- catalyst temperature
  catT = catT + (300 + 3.9 * (T_c - 30) - catT) * dt / 60;

  % -- charging voltage (engine running)
  if sc.alt_ok
    batt(k) = 14.15 + 0.03 * randn;
  else
    batt(k) = sc.batt_ocv - 30 * sc.batt_r + 0.02 * randn;
  end

  ect(k) = T_c; stft(k) = st; ltft(k) = lt; o2u(k) = vu; o2d(k) = vd;
  lamu(k) = lu; cat(k) = catT; closed(k) = is_closed;
end

% ------------------------------------------------------------- scan window
w = (n - 299):n;
sc_win.RPM      = rpm(w);
sc_win.ECT      = ect(w);
sc_win.STFT1    = stft(w);
sc_win.LTFT1    = ltft(w);
sc_win.O2V_B1S1 = o2u(w);
sc_win.O2T_B1S1 = stft(w);
sc_win.O2V_B1S2 = o2d(w);
sc_win.MAP      = p.map_idle + 20 * (sc.leak - 0.02) + 0.4 * randn(300, 1);
sc_win.IAT      = 38 + 0.3 * randn(300, 1);
sc_win.LOAD     = 24 + 1.0 * randn(300, 1);
sc_win.TIMING   = 8 + 1.0 * randn(300, 1);
sc_win.VSS      = zeros(300, 1);
sc_win.TPS      = 15.3 + 0.1 * randn(300, 1);
sc_win.APP_D    = 14.1 * ones(300, 1);
sc_win.RUNTIME  = t(w);
sc_win.DIST_MIL = zeros(300, 1);
sc_win.FUEL_LVL = 55 * ones(300, 1);
sc_win.DIST_CLR = 2240 * ones(300, 1);
sc_win.BARO     = 98 * ones(300, 1);
sc_win.CAT_B1S1 = cat(w);
sc_win.ECU_V    = batt(w);
sc_win.BATT     = batt(w);
sc_win.AMBIENT  = Tamb * ones(300, 1);

% ------------------------------------------- engine computer: DTCs, MIL, monitors
last = (n - 599):n;   % last 60 s
up_sw = carsim_crossings(o2u(last), 0.45);
dn_sw = carsim_crossings(o2d(last), 0.45);
stored = {}; pending = {};
up_amp = max(o2u(last)) - min(o2u(last));
if closed(end) && up_amp < 0.2,               stored{end+1} = 'P0134'; end
if up_amp >= 0.2 && up_sw >= 10 && dn_sw / up_sw > 0.6,        stored{end+1} = 'P0420'; end
total_trim = mean(stft(w) + ltft(w));
if total_trim > 25,      stored{end+1}  = 'P0171';
elseif total_trim > 12,  pending{end+1} = 'P0171';
elseif total_trim < -25, stored{end+1}  = 'P0172';
elseif total_trim < -12, pending{end+1} = 'P0172';
end
if max(ect) < 70,         pending{end+1} = 'P0128'; end
if max(ect) > 112,        stored{end+1}  = 'P0217'; end
if mean(batt(w)) < 12.8,  stored{end+1}  = 'P0562'; end
if sum(misfire(w)) >= 5,  stored{end+1}  = 'P0301'; end

% Readiness monitors (byte C = supported, byte D = incomplete).
% Supported: catalyst(0), EVAP(2), O2 sensor(5), O2 heater(6).
mon_incomplete = 0;
if max(ect) < 70
  mon_incomplete = bitor(mon_incomplete, bitor(bitor(1, 32), 64));  % need a warm engine
end

if ~closed(end)
  fuelsys = 1;
elseif sc.o2_dead
  fuelsys = 16;   % closed loop, fault in feedback system
else
  fuelsys = 2;
end

% --------------------------------------------- battery & charging test trace
tb = (0:199)' * 0.1;
vb = zeros(200, 1);
for i = 1:200
  ti = tb(i);
  if ti < 3
    v = sc.batt_ocv - 3 * sc.batt_r;                        % ignition on
  elseif ti < 3.2
    v = sc.batt_ocv - 1.4 * p.crank_amps * sc.batt_r;       % starter inrush
  elseif ti < 4.2
    v = sc.batt_ocv - p.crank_amps * sc.batt_r;             % cranking
  elseif ti < 5.0
    v = sc.batt_ocv - 15 * sc.batt_r - 0.25;                % engine catching
  elseif sc.alt_ok
    v = 14.15;
  else
    v = sc.batt_ocv - 30 * sc.batt_r;
  end
  vb(i) = v + 0.02 * randn;
end

sim.car = car;
sim.scenario = scenario;
sim.description = sc.description;
sim.params = sc;
sim.profile = p;
sim.vin = p.vin;
sim.dt = dt;
sim.t = t;
sim.full = struct('ECT', ect, 'RPM', rpm, 'STFT1', stft, 'LTFT1', ltft, ...
                  'O2V_B1S1', o2u, 'O2V_B1S2', o2d, 'LAMBDA', lamu, ...
                  'CAT', cat, 'BATT', batt, 'CLOSED', double(closed));
sim.scan = sc_win;
sim.scan_t = t(w);
sim.fuelsys = fuelsys;
sim.dtc_stored = stored;
sim.dtc_pending = pending;
sim.mil = ~isempty(stored);
sim.mon_supported = bitor(bitor(1, 4), bitor(32, 64));
sim.mon_incomplete = mon_incomplete;
sim.battery_test = [tb vb];
end
