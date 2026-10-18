function [v, id] = obd_decode(pid, d)
%OBD_DECODE Decode SAE J1979 mode 01 data bytes into a physical value.
%   [v, id] = obd_decode(5, 123)  -> v = 83, id = 'ECT'
%   (PIDs are written in decimal for speed: 12 = 0x0C, 66 = 0x42 ...)
%   Formulas and channel ids match lib/obd/pids.dart in the CarSense app.

ab = @(d) d(1) * 256 + d(2);
switch pid
  case 4, v = d(1) * 100 / 255;       id = 'LOAD';
  case 5, v = d(1) - 40;              id = 'ECT';
  case 6, v = (d(1) - 128) * 100 / 128; id = 'STFT1';
  case 7, v = (d(1) - 128) * 100 / 128; id = 'LTFT1';
  case 11, v = d(1);                   id = 'MAP';
  case 12, v = ab(d) / 4;              id = 'RPM';
  case 13, v = d(1);                   id = 'VSS';
  case 14, v = d(1) / 2 - 64;          id = 'TIMING';
  case 15, v = d(1) - 40;              id = 'IAT';
  case 17, v = d(1) * 100 / 255;       id = 'TPS';
  case 20, v = d(1) / 200;             id = 'O2V_B1S1';
  case 21, v = d(1) / 200;             id = 'O2V_B1S2';
  case 31, v = ab(d);                  id = 'RUNTIME';
  case 33, v = ab(d);                  id = 'DIST_MIL';
  case 47, v = d(1) * 100 / 255;       id = 'FUEL_LVL';
  case 49, v = ab(d);                  id = 'DIST_CLR';
  case 51, v = d(1);                   id = 'BARO';
  case 60, v = ab(d) / 10 - 40;        id = 'CAT_B1S1';
  case 66, v = ab(d) / 1000;           id = 'ECU_V';
  case 70, v = d(1) - 40;              id = 'AMBIENT';
  case 73, v = d(1) * 100 / 255;       id = 'APP_D';
  otherwise
    error('obd:decode', 'PID %02X not supported by the decoder', pid);
end
end
