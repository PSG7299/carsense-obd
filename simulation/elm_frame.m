function txt = elm_frame(payload)
%ELM_FRAME Format a response payload the way an ELM327 prints it on
%   ISO 15765-4 CAN 11-bit with headers on and spaces off (ATH1 ATS0),
%   including ISO-TP first/consecutive frames for payloads over 7 bytes.
%   txt = elm_frame([hex2dec('41') 5 123])  -> '7E80341057B'

h = @(b) sprintf('%02X', b);
payload = payload(:)';
n = numel(payload);
if n <= 7
  txt = ['7E8' h(n) h(payload)];
  return;
end
lines = {['7E81' sprintf('%X', floor(n / 256)) h(mod(n, 256)) h(payload(1:6))]};
seq = 1;
for i = 7:7:n
  chunk = payload(i:min(i + 6, n));
  chunk = [chunk zeros(1, 7 - numel(chunk))];
  lines{end+1} = ['7E82' sprintf('%X', mod(seq, 16)) h(chunk)]; %#ok<AGROW>
  seq = seq + 1;
end
txt = strjoin(lines, char(13));
end
