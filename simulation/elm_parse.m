function payload = elm_parse(txt)
%ELM_PARSE Re-assemble the payload of the first ECU from ELM327 CAN 11-bit
%   text (headers on). Handles single frames and ISO-TP multi-frame replies.
%   Returns [] for NO DATA / errors.

txt = upper(strrep(strrep(txt, '>', ''), ' ', ''));
lines = regexp(txt, '[\r\n]+', 'split');
frames = {};
for i = 1:numel(lines)
  l = strtrim(lines{i});
  if isempty(l) || isempty(regexp(l, '^[0-9A-F]+$', 'once')) || numel(l) < 5
    continue;
  end
  if isempty(frames) || strcmp(l(1:3), frames{1}.ecu)
    frames{end+1} = struct('ecu', l(1:3), 'b', sscanf(l(4:end), '%2x')'); %#ok<AGROW>
  end
end
if isempty(frames), payload = []; return; end

first = frames{1}.b;
type = floor(first(1) / 16);
if type == 0
  len = mod(first(1), 16);
  payload = first(2:1 + len);
elseif type == 1
  len = mod(first(1), 16) * 256 + first(2);
  data = first(3:end);
  for i = 2:numel(frames)
    data = [data frames{i}.b(2:end)]; %#ok<AGROW>
  end
  payload = data(1:len);
else
  payload = [];
end
end
