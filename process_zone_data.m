function processed = process_zone_data(zone_data, history)
% =========================================================================
% process_zone_data.m
% IoT-Based Crowd Crush Prevention System — Data Processing Module
%
% PURPOSE:
%   1. Applies a moving average filter (window = 5) to smooth noisy sensor
%      readings and remove transient spikes caused by sensor imprecision.
%   2. Detects anomalies in each zone by comparing smoothed readings against
%      pre-defined safety thresholds.
%   3. Returns a processed struct enriched with smoothed values, boolean
%      anomaly flags, and a human-readable anomaly summary.
%
% INPUTS:
%   zone_data  — 1×5 struct array from simulate_zone_sensors()
%   history    — struct array with fields: density_hist, speed_hist,
%                pressure_hist, temp_hist — each is a (N × 5) matrix
%                where rows = past readings, cols = zones.
%                If history is empty, raw values are used unsmoothed.
%
% OUTPUT:
%   processed  — 1×5 struct array, each element contains:
%                .name              Zone name
%                .density_raw       Raw sensor reading
%                .density_smooth    Moving-average smoothed density
%                .speed_smooth      Smoothed movement speed
%                .pressure_smooth   Smoothed pressure index
%                .temp_smooth       Smoothed temperature
%                .flag_density      Boolean: density anomaly detected
%                .flag_speed        Boolean: speed anomaly detected
%                .flag_pressure     Boolean: pressure anomaly detected
%                .flag_temp         Boolean: temperature anomaly detected
%                .anomaly_count     Total number of active anomaly flags
%                .anomaly_summary   Cell array of anomaly description strings
%
% SAFETY THRESHOLDS (based on Hajj safety research):
%   Density   > 6.0  people/m²  → Dangerous (critical crush risk)
%   Speed     < 0.3  m/s        → Turbulent flow (pre-crush indicator)
%   Pressure  > 0.8  (0–1)      → Critical structural pressure
%   Temp      > 40.0 °C         → Heat stress / heatstroke risk
% =========================================================================

    % ---- Safety threshold constants -------------------------------------
    DENSITY_DANGER_THRESHOLD  = 6.0;   % people/m²
    SPEED_TURBULENCE_THRESHOLD = 0.3;  % m/s
    PRESSURE_CRITICAL_THRESHOLD = 0.8; % normalized (0–1)
    TEMP_HEAT_STRESS_THRESHOLD  = 40.0; % °C

    % ---- Moving average window size -------------------------------------
    MA_WINDOW = 5;

    num_zones = length(zone_data);
    processed(num_zones) = struct( ...
        'name', [], ...
        'density_raw', [], 'density_smooth', [], ...
        'speed_raw',   [], 'speed_smooth',   [], ...
        'pressure_raw',[], 'pressure_smooth',[], ...
        'temp_raw',    [], 'temp_smooth',     [], ...
        'flag_density', false, 'flag_speed', false, ...
        'flag_pressure', false, 'flag_temp', false, ...
        'anomaly_count', 0, 'anomaly_summary', {{}});

    for z = 1:num_zones

        % ---- Extract raw sensor values ----------------------------------
        d_raw = zone_data(z).density;
        s_raw = zone_data(z).speed;
        p_raw = zone_data(z).pressure;
        t_raw = zone_data(z).temperature;

        % ---- Moving average smoothing -----------------------------------
        % Build a sliding window buffer from history + current reading.
        % If fewer than MA_WINDOW readings exist, average what we have.
        if ~isempty(history) && size(history.density_hist, 1) >= 1
            % Stack historical column for zone z with current reading
            d_buf = [history.density_hist(:, z);  d_raw];
            s_buf = [history.speed_hist(:, z);    s_raw];
            p_buf = [history.pressure_hist(:, z); p_raw];
            t_buf = [history.temp_hist(:, z);     t_raw];

            % Take last MA_WINDOW elements
            win = min(MA_WINDOW, length(d_buf));
            d_smooth = mean(d_buf(end - win + 1 : end));
            s_smooth = mean(s_buf(end - win + 1 : end));
            p_smooth = mean(p_buf(end - win + 1 : end));
            t_smooth = mean(t_buf(end - win + 1 : end));
        else
            % First iteration — no history available, use raw values
            d_smooth = d_raw;
            s_smooth = s_raw;
            p_smooth = p_raw;
            t_smooth = t_raw;
        end

        % ---- Anomaly detection using smoothed readings ------------------
        % Using smoothed values avoids false alarms from momentary noise.

        flag_d = d_smooth > DENSITY_DANGER_THRESHOLD;
        flag_s = s_smooth < SPEED_TURBULENCE_THRESHOLD;
        flag_p = p_smooth > PRESSURE_CRITICAL_THRESHOLD;
        flag_t = t_smooth > TEMP_HEAT_STRESS_THRESHOLD;

        % ---- Build human-readable anomaly summary -----------------------
        anomaly_msgs = {};
        if flag_d
            anomaly_msgs{end+1} = sprintf( ...
                '[DENSITY] %.2f p/m² > %.1f threshold — CRUSH RISK', ...
                d_smooth, DENSITY_DANGER_THRESHOLD);
        end
        if flag_s
            anomaly_msgs{end+1} = sprintf( ...
                '[SPEED] %.2f m/s < %.1f threshold — TURBULENT FLOW', ...
                s_smooth, SPEED_TURBULENCE_THRESHOLD);
        end
        if flag_p
            anomaly_msgs{end+1} = sprintf( ...
                '[PRESSURE] %.2f > %.1f threshold — CRITICAL PRESSURE', ...
                p_smooth, PRESSURE_CRITICAL_THRESHOLD);
        end
        if flag_t
            anomaly_msgs{end+1} = sprintf( ...
                '[TEMP] %.1f°C > %.0f°C threshold — HEAT STRESS', ...
                t_smooth, TEMP_HEAT_STRESS_THRESHOLD);
        end

        % ---- Populate output struct ------------------------------------
        processed(z).name             = zone_data(z).name;
        processed(z).density_raw      = d_raw;
        processed(z).density_smooth   = d_smooth;
        processed(z).speed_raw        = s_raw;
        processed(z).speed_smooth     = s_smooth;
        processed(z).pressure_raw     = p_raw;
        processed(z).pressure_smooth  = p_smooth;
        processed(z).temp_raw         = t_raw;
        processed(z).temp_smooth      = t_smooth;
        processed(z).flag_density     = flag_d;
        processed(z).flag_speed       = flag_s;
        processed(z).flag_pressure    = flag_p;
        processed(z).flag_temp        = flag_t;
        processed(z).anomaly_count    = flag_d + flag_s + flag_p + flag_t;
        processed(z).anomaly_summary  = anomaly_msgs;

    end

end
