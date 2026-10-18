function b = obd_encode(pid, v)
%OBD_ENCODE Encode a physical value into SAE J1979 mode 01 data bytes.
%   b = obd_encode(12, 812.5)   -> [12 178]
%   For O2 sensor PIDs 0x14..0x1B pass [volts trim%] (trim NaN = not used).
%   PIDs are written in decimal for speed (12 = 0x0C, 66 = 0x42 ...).
%   Inverse of obd_decode; formulas match lib/obd/pids.dart.

u8  = @(x) min(max(round(x), 0), 255);
u16 = @(x) [floor(min(max(round(x), 0), 65535) / 256), mod(min(max(round(x), 0), 65535), 256)];
pct = @(x) u8(x * 255 / 100);
trim = @(x) u8(x * 128 / 100 + 128);

switch pid
  case 4,                          b = pct(v);
  case {5, 15, 70}, b = u8(v + 40);
  case {6, 7},         b = trim(v);
  case {11, 13, 51}, b = u8(v);
  case 12,                          b = u16(v * 4);
  case 14,                          b = u8((v + 64) * 2);
  case {17, 47, 73}, b = pct(v);
  case {20, 21, 22, 23, 24, 25, 26, 27}
    if numel(v) < 2 || isnan(v(2)), t = 255; else, t = trim(v(2)); end
    b = [u8(v(1) * 200), t];
  case {31, 33, 49}, b = u16(v);
  case 60,                          b = u16((v + 40) * 10);
  case 66,                          b = u16(v * 1000);
  otherwise
    error('obd:encode', 'PID %02X not supported by the encoder', pid);
end
end
