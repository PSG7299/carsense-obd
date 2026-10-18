function n = carsim_crossings(x, level)
%CARSIM_CROSSINGS Number of times signal x crosses level (same as the app).
x = x(:) - level;
n = sum(x(1:end-1) .* x(2:end) < 0);
end
