function eta_result = predict_crush_eta(density_history_zone, sample_interval_sec)
% =========================================================================
% predict_crush_eta.m
% IoT-Based Crowd Crush Prevention System — Crush ETA Prediction Module
%
% PURPOSE:
%   Uses linear regression (via MATLAB's polyfit) on the last 15 density
%   readings for a single zone to extrapolate when the crowd density will
%   reach the critical crush threshold of 6 people/m².
%
%   This gives responders an estimated "time to crush" so they can
%   proactively dispatch resources before a crush occurs.
%
% ALGORITHM:
%   1. Fit a degree-1 polynomial (line) to the last N readings vs time.
%   2. Find the time t* where the fitted line crosses the 6.0 threshold.
%   3. Subtract the current time to get ETA in minutes.
%   4. If slope is negative or current density is already safe and falling,
%      report "Safe — no crush predicted".
%
% INPUTS:
%   density_history_zone  — Column vector of past density readings for one
%                           zone (all available history, not just last 15)
%   sample_interval_sec   — Seconds between each reading (e.g. 16)
%
% OUTPUT:
%   eta_result            — Struct with fields:
%                           .eta_minutes   ETA in minutes (Inf if safe)
%                           .message       Human-readable prediction string
%                           .current_density  Most recent density reading
%                           .trend_slope      Density change per minute
%                           .is_safe          Boolean: true = no crush predicted
%                           .regression_ok    Boolean: enough data for regression
%
% CONSTANTS:
%   CRITICAL_DENSITY = 6.0  people/m² (crush threshold from safety research)
%   HISTORY_WINDOW   = 15   samples used for regression
% =========================================================================

    CRITICAL_DENSITY  = 6.0;   % people/m² — crush threshold
    HISTORY_WINDOW    = 15;    % number of past samples for regression
    MIN_SAMPLES_REQD  = 3;     % minimum samples before regression is valid

    % ---- Validate and trim history to last HISTORY_WINDOW points -------
    if isempty(density_history_zone)
        eta_result.eta_minutes    = Inf;
        eta_result.message        = 'Insufficient data — monitoring started';
        eta_result.current_density = 0;
        eta_result.trend_slope    = 0;
        eta_result.is_safe        = true;
        eta_result.regression_ok  = false;
        return;
    end

    density_vec = density_history_zone(:);  % ensure column vector

    % Take only the last HISTORY_WINDOW readings
    if length(density_vec) > HISTORY_WINDOW
        density_vec = density_vec(end - HISTORY_WINDOW + 1 : end);
    end

    n = length(density_vec);
    current_density = density_vec(end);

    % ---- Early exit: already at or above critical density --------------
    if current_density >= CRITICAL_DENSITY
        eta_result.eta_minutes    = 0;
        eta_result.message        = sprintf( ...
            '⚠ CRITICAL: Zone already at %.2f p/m² — CRUSH IMMINENT (ETA: NOW)', ...
            current_density);
        eta_result.current_density = current_density;
        eta_result.trend_slope    = 0;
        eta_result.is_safe        = false;
        eta_result.regression_ok  = true;
        return;
    end

    % ---- Check if enough data for regression ---------------------------
    if n < MIN_SAMPLES_REQD
        eta_result.eta_minutes    = Inf;
        eta_result.message        = sprintf( ...
            'Collecting data... (%d/%d samples, current density: %.2f p/m²)', ...
            n, MIN_SAMPLES_REQD, current_density);
        eta_result.current_density = current_density;
        eta_result.trend_slope    = 0;
        eta_result.is_safe        = true;
        eta_result.regression_ok  = false;
        return;
    end

    % ---- Build time axis in minutes ------------------------------------
    % t=0 is the oldest sample; t=current is the latest sample.
    sample_interval_min = sample_interval_sec / 60.0;
    t_past = (0 : n-1)' * sample_interval_min;   % column of past times (min)

    % ---- Linear regression using polyfit (degree 1) -------------------
    % p(1) = slope (density change per minute)
    % p(2) = intercept (density at t=0)
    p = polyfit(t_past, density_vec, 1);
    slope_per_min = p(1);      % people/m²/minute
    intercept     = p(2);      % predicted density at first sample

    % ---- Assess goodness of fit (R²) -----------------------------------
    density_fitted = polyval(p, t_past);
    ss_res = sum((density_vec - density_fitted).^2);
    ss_tot = sum((density_vec - mean(density_vec)).^2);
    if ss_tot > 0
        r_squared = 1 - ss_res / ss_tot;
    else
        r_squared = 1.0;   % constant signal → perfect fit
    end

    % ---- Predict when density hits critical threshold ------------------
    % Line equation: density = slope * t + intercept
    % Solve for t when density = CRITICAL_DENSITY:
    %   t_critical = (CRITICAL_DENSITY - intercept) / slope
    %
    % t_current = last element of t_past
    t_current = t_past(end);

    if slope_per_min <= 0
        % Density is flat or decreasing — no crush predicted
        eta_result.eta_minutes    = Inf;
        eta_result.message        = sprintf( ...
            '✓ Safe — No crush predicted. Density: %.2f p/m², Trend: %.3f p/m²/min (stable/decreasing)', ...
            current_density, slope_per_min);
        eta_result.current_density = current_density;
        eta_result.trend_slope    = slope_per_min;
        eta_result.is_safe        = true;
        eta_result.regression_ok  = true;
        return;
    end

    % Positive slope — density is rising
    t_critical_absolute = (CRITICAL_DENSITY - intercept) / slope_per_min;
    eta_minutes = t_critical_absolute - t_current;

    if eta_minutes <= 0
        % Regression line crosses threshold in the past (noisy data)
        % Use conservative estimate based on remaining headroom + slope
        headroom = CRITICAL_DENSITY - current_density;
        eta_minutes = headroom / slope_per_min;
    end

    % ---- Format output message -----------------------------------------
    if eta_minutes > 60
        eta_result.is_safe = true;
        eta_result.message = sprintf( ...
            '✓ Safe — Crush predicted in %.0f min (>1hr). Density: %.2f p/m², Slope: +%.3f/min (R²=%.2f)', ...
            eta_minutes, current_density, slope_per_min, r_squared);
    elseif eta_minutes > 15
        eta_result.is_safe = false;
        eta_result.message = sprintf( ...
            '⚡ WARNING — Crush predicted in %.1f min. Density: %.2f p/m², Slope: +%.3f/min (R²=%.2f)', ...
            eta_minutes, current_density, slope_per_min, r_squared);
    else
        eta_result.is_safe = false;
        eta_result.message = sprintf( ...
            '🚨 URGENT — Crush predicted in %.1f min! Density: %.2f p/m², Slope: +%.3f/min (R²=%.2f)', ...
            eta_minutes, current_density, slope_per_min, r_squared);
    end

    eta_result.eta_minutes     = eta_minutes;
    eta_result.current_density = current_density;
    eta_result.trend_slope     = slope_per_min;
    eta_result.regression_ok   = true;

end
