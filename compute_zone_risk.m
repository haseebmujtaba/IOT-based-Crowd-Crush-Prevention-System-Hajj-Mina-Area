function risk = compute_zone_risk(processed_zone)
% =========================================================================
% compute_zone_risk.m
% IoT-Based Crowd Crush Prevention System — Risk Scoring Module
%
% PURPOSE:
%   Computes a composite Risk Score (0–100) for a single zone using a
%   weighted linear combination of normalized sensor readings. The score
%   integrates crowd density, pressure, movement speed, and temperature
%   into a single interpretable danger metric.
%
%   A higher score = more dangerous. Score above 75 triggers Critical.
%   Score 40–75 = Warning. Score below 40 = Safe.
%
% INPUT:
%   processed_zone — Single processed zone struct containing:
%                    .density_smooth, .speed_smooth,
%                    .pressure_smooth, .temp_smooth
%
% OUTPUT:
%   risk           — Struct with fields:
%                    .score           Composite risk score 0–100
%                    .density_contrib Density component (0–100, weighted)
%                    .pressure_contrib Pressure component (0–100, weighted)
%                    .speed_contrib   Speed component (0–100, weighted)
%                    .temp_contrib    Temperature component (0–100, weighted)
%                    .level           'Low' / 'Moderate' / 'High' / 'Extreme'
%
% WEIGHTING RATIONALE (from Hajj crowd safety literature):
%   Density   40% — Primary indicator of crush likelihood
%   Pressure  30% — Direct measure of body-to-body force
%   Speed     20% — Slow/turbulent flow precedes crush onset
%   Temperature 10% — Heat stress compounds crowd danger
% =========================================================================

    % ---- Sensor normalization ranges ------------------------------------
    % Each sensor reading is scaled to 0–100 within its operational range.
    % Range min = lowest possible safe value.
    % Range max = worst-case dangerous value.

    % Density: 0 people/m² (empty) to 10 people/m² (maximum jam)
    DENSITY_MIN  = 0.0;
    DENSITY_MAX  = 10.0;

    % Pressure: 0 (no pressure) to 1.0 (maximum sensor reading)
    PRESSURE_MIN = 0.0;
    PRESSURE_MAX = 1.0;

    % Speed: higher speed = SAFER. Normalize and invert.
    % 0 m/s = fully stopped/turbulent (maximum danger)
    % 2.5 m/s = free-flowing (minimum danger)
    SPEED_MIN    = 0.0;
    SPEED_MAX    = 2.5;

    % Temperature: 25°C = comfortable. 50°C = lethal heat stress.
    TEMP_MIN     = 25.0;
    TEMP_MAX     = 50.0;

    % ---- Contribution weights (must sum to 1.0) -----------------------
    W_DENSITY  = 0.40;
    W_PRESSURE = 0.30;
    W_SPEED    = 0.20;
    W_TEMP     = 0.10;

    % ---- Normalize each sensor to 0–100 scale --------------------------

    % Density: higher density → higher risk (direct relationship)
    d = processed_zone.density_smooth;
    norm_density = clamp_normalize(d, DENSITY_MIN, DENSITY_MAX);

    % Pressure: higher pressure → higher risk (direct)
    p = processed_zone.pressure_smooth;
    norm_pressure = clamp_normalize(p, PRESSURE_MIN, PRESSURE_MAX);

    % Speed: LOWER speed → HIGHER risk (inverse relationship)
    % We invert: risk from speed = 100 - normalized_speed
    s = processed_zone.speed_smooth;
    norm_speed_raw = clamp_normalize(s, SPEED_MIN, SPEED_MAX);
    norm_speed_risk = 100 - norm_speed_raw;  % invert: slow = dangerous

    % Temperature: higher temperature → higher risk (direct)
    t = processed_zone.temp_smooth;
    norm_temp = clamp_normalize(t, TEMP_MIN, TEMP_MAX);

    % ---- Weighted composite risk score ----------------------------------
    density_contrib  = W_DENSITY  * norm_density;
    pressure_contrib = W_PRESSURE * norm_pressure;
    speed_contrib    = W_SPEED    * norm_speed_risk;
    temp_contrib     = W_TEMP     * norm_temp;

    total_score = density_contrib + pressure_contrib + ...
                  speed_contrib   + temp_contrib;

    % Clamp to [0, 100] for safety (floating-point edge cases)
    total_score = max(0, min(100, total_score));

    % ---- Classify risk level -------------------------------------------
    if total_score < 35
        level = 'Low';
    elseif total_score < 55
        level = 'Moderate';
    elseif total_score < 75
        level = 'High';
    else
        level = 'Extreme';
    end

    % ---- Pack output struct --------------------------------------------
    risk.score            = total_score;
    risk.density_contrib  = density_contrib;
    risk.pressure_contrib = pressure_contrib;
    risk.speed_contrib    = speed_contrib;
    risk.temp_contrib     = temp_contrib;
    risk.level            = level;

end

% =========================================================================
% Helper: clamp_normalize(value, min_val, max_val)
%   Clamps value to [min_val, max_val] then scales to [0, 100]
% =========================================================================
function out = clamp_normalize(val, lo, hi)
    val_clamped = max(lo, min(hi, val));
    out = ((val_clamped - lo) / (hi - lo)) * 100;
end
