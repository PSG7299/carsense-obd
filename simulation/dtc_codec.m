function out = dtc_codec(in)
%DTC_CODEC Convert between trouble-code text and the 2-byte SAE J2012 form.
%   b = dtc_codec('P0420')    -> [4 32]
%   c = dtc_codec([4 32])     -> 'P0420'

letters = 'PCBU';
if ischar(in)
  L = find(letters == in(1)) - 1;
  a = L * 64 + hex2dec(in(2)) * 16 + hex2dec(in(3));
  out = [a hex2dec(in(4:5))];
else
  a = in(1); b = in(2);
  out = sprintf('%c%d%X%02X', letters(floor(a / 64) + 1), mod(floor(a / 16), 4), mod(a, 16), b);
end
end
