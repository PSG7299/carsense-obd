function [sc, names] = carsim_scenarios(name)
%CARSIM_SCENARIOS Fault scenarios for the car simulation.
%   sc = carsim_scenarios('worn_catalyst') returns the scenario parameters.
%   [~, names] = carsim_scenarios() lists all scenario names.

names = {'healthy', 'vacuum_leak', 'worn_catalyst', 'dead_o2_sensor', ...
         'stuck_thermostat', 'overheating', 'misfire', 'weak_battery', ...
         'alternator_fault'};
if nargin < 1
  sc = [];
  return;
end

% Healthy baseline.
sc.name         = name;
sc.leak         = 0.02;    % un-metered air fraction (lean error before trims)
sc.osc          = 1.0;     % catalyst oxygen storage capacity (1 = new)
sc.o2_dead      = false;   % upstream O2 sensor stuck at bias voltage
sc.thermostat   = 'ok';    % 'ok' | 'stuck_open' | 'fan_dead'
sc.misfire_rate = 0;       % misfire events per 0.1 s step
sc.batt_ocv     = 12.65;   % battery open-circuit voltage, V
sc.batt_r       = 0.011;   % battery internal resistance, ohm
sc.alt_ok       = true;    % alternator charging
sc.description  = 'Everything working normally.';

switch name
  case 'healthy'
  case 'vacuum_leak'
    sc.leak = 0.16;
    sc.description = 'Intake vacuum leak: engine runs lean, ECU adds ~16% fuel (long-term trim).';
  case 'worn_catalyst'
    sc.osc = 0.004;
    sc.description = 'Catalytic converter has lost its oxygen storage: rear O2 sensor copies the front one.';
  case 'dead_o2_sensor'
    sc.o2_dead = true;
    sc.description = 'Front O2 sensor dies mid-drive (stuck at 0.45 V bias): no switching, ECU falls back to a rich map.';
  case 'stuck_thermostat'
    sc.thermostat = 'stuck_open';
    sc.description = 'Thermostat stuck open: engine never reaches operating temperature.';
  case 'overheating'
    sc.thermostat = 'fan_dead';
    sc.description = 'Radiator fan not working: coolant temperature climbs past 112 C at idle.';
  case 'misfire'
    sc.misfire_rate = 0.15;
    sc.description = 'Cylinder 1 misfiring (worn spark plug / coil): rough, unsteady idle.';
  case 'weak_battery'
    sc.batt_ocv = 12.25;
    sc.batt_r   = 0.015;
    sc.description = 'Ageing battery: partly discharged, deep voltage dip while cranking.';
  case 'alternator_fault'
    sc.batt_ocv = 12.55;
    sc.alt_ok   = false;
    sc.description = 'Alternator not charging: battery drains while the engine runs.';
  otherwise
    error('carsim:scenario', 'Unknown scenario "%s"', name);
end
end
