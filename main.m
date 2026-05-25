% =========================================================================
% main.m
% IoT-Based Crowd Crush Prevention System for Hajj Mina Area
%
% MASTER ORCHESTRATION FILE
%
% COURSE:   IoT Systems / Smart Systems Engineering
% PROJECT:  Real-Time Crowd Crush Prevention using IoT + ML + Cloud
%
% DESCRIPTION:
%   This is the entry point for the full simulation. It coordinates all
%   system modules in a 60-sample loop with 16-second simulated intervals:
%
%   [1] simulate_zone_sensors  → Generate raw IoT sensor readings
%   [2] process_zone_data      → Smooth with moving average + detect anomalies
%   [3] classify_zone          → ML Decision Tree classification
%   [4] compute_zone_risk      → Weighted composite risk scoring
%   [5] predict_crush_eta      → Linear regression crush time prediction
%   [6] generate_recommendations → Rerouting, dispatch, pilgrim guidance
%   [7] send_to_thingspeak     → Cloud upload (set write keys below)
%   [8] dashboard              → Live MATLAB visualization
%
% USAGE:
%   Simply run:  main
%   in the MATLAB command window. All modules must be on the MATLAB path.
%
% THINGSPEAK CONFIGURATION:
%   Set your channel write keys in the CONFIG section below.
%   Use 'DEMO_MODE' to skip cloud uploads during testing.
%
% OUTPUT:
%   - Live dashboard figure (updates every iteration)
%   - Console log: per-zone status, risk, ETA, and recommendations
%   - Session summary at the end with statistics
%   - MATLAB workspace variables for post-analysis
% =========================================================================

clc; clear; close all;

fprintf('=========================================================\n');
fprintf('  HAJJ MINA CROWD CRUSH PREVENTION SYSTEM — IoT Project  \n');
fprintf('=========================================================\n');
fprintf('  Initializing system...\n\n');

% =========================================================================
% CONFIGURATION
% =========================================================================

% --- Simulation parameters -----------------------------------------------
NUM_ITERATIONS     = 60;   % Total number of simulation samples
SAMPLE_INTERVAL_S  = 16;   % Seconds between samples (16s matches ThingSpeak limit)
NUM_ZONES          = 4;
HISTORY_WINDOW     = 15;   % Density window for ETA regression

% --- ThingSpeak Write API Keys (one per zone channel) --------------------
% Replace with your actual ThingSpeak Write API keys.
% Set to 'DEMO_MODE' to run offline without cloud uploads.
THINGSPEAK_KEYS = { ...
    '6BNFGF0X48Q2BXDR', ...   % Zone 1: Jamarat Bridge
    'J7O6Y1LQVWF2D98S', ...   % Zone 2: Tent City North
    'R9L874JRDB046OU5', ...   % Zone 3: Tent City South
    '3OG17CL4SNBSEK6'  ...   % Zone 4: Emergency Exit Path
};

% --- Zone names (must match simulate_zone_sensors.m) --------------------
ZONE_NAMES = { ...
    'Jamarat Bridge', ...
    'Tent City North', ...
    'Tent City South', ...
    'Emergency Exit Path' ...
};

% =========================================================================
% SYSTEM INITIALIZATION
% =========================================================================

% --- Initialize history buffer for moving average filter -----------------
% history.density_hist  : (N×5) — density readings per zone
% history.speed_hist    : (N×5) — speed readings per zone
% history.pressure_hist : (N×5) — pressure readings per zone
% history.temp_hist     : (N×5) — temperature readings per zone
history.density_hist  = [];
history.speed_hist    = [];
history.pressure_hist = [];
history.temp_hist     = [];

% --- Pre-allocate density history matrix for ETA prediction -------------
% This matrix grows each iteration up to NUM_ITERATIONS rows.
density_history_all = zeros(0, NUM_ZONES);

% --- Pre-allocate session log for post-session summary ------------------
session_log.iteration     = zeros(NUM_ITERATIONS, 1);
session_log.risk_scores   = zeros(NUM_ITERATIONS, NUM_ZONES);
session_log.labels        = cell(NUM_ITERATIONS, NUM_ZONES);
session_log.densities     = zeros(NUM_ITERATIONS, NUM_ZONES);
session_log.eta_minutes   = zeros(NUM_ITERATIONS, NUM_ZONES);

% --- Train ML classifier at startup (first call trains, rest reuse) -----
% Pass empty [] so classify_zone trains on first call.
ml_classifier = [];

fprintf('[INIT] Training ML classifier on synthetic crowd data...\n');
% Dummy zone just to trigger training — result discarded on init
dummy_zone.density_smooth  = 3.0;
dummy_zone.speed_smooth    = 0.8;
dummy_zone.pressure_smooth = 0.3;
dummy_zone.temp_smooth     = 37.0;
[~, ml_classifier] = classify_zone(dummy_zone, ml_classifier);

fprintf('[INIT] System initialization complete.\n');
fprintf('[INIT] Starting %d-sample simulation (%ds intervals)...\n\n', ...
        NUM_ITERATIONS, SAMPLE_INTERVAL_S);
fprintf('=========================================================\n\n');

% =========================================================================
% MAIN SIMULATION LOOP
% =========================================================================
for iter = 1:NUM_ITERATIONS

    tic;   % Start timing this iteration

    fprintf('\n╔══════════════════════════════════════════════════════╗\n');
    fprintf('║  ITERATION %02d / %02d   —   Sim Time: %ds              ║\n', ...
            iter, NUM_ITERATIONS, (iter-1) * SAMPLE_INTERVAL_S);
    fprintf('╚══════════════════════════════════════════════════════╝\n');

    % ================================================================
    % STEP 1: Simulate IoT sensor readings for all 5 zones
    % ================================================================
    fprintf('\n[STEP 1] Simulating IoT sensor readings...\n');
    zone_raw = simulate_zone_sensors(iter);

    % ================================================================
    % STEP 2: Process data — smoothing + anomaly detection
    % ================================================================
    fprintf('[STEP 2] Processing sensor data (moving average + anomaly detection)...\n');
    processed = process_zone_data(zone_raw, history);

    % --- Append current readings to history buffers -------------------
    new_density_row  = arrayfun(@(z) z.density,     zone_raw);
    new_speed_row    = arrayfun(@(z) z.speed,        zone_raw);
    new_pressure_row = arrayfun(@(z) z.pressure,     zone_raw);
    new_temp_row     = arrayfun(@(z) z.temperature,  zone_raw);

    history.density_hist  = [history.density_hist;  new_density_row];
    history.speed_hist    = [history.speed_hist;    new_speed_row];
    history.pressure_hist = [history.pressure_hist; new_pressure_row];
    history.temp_hist     = [history.temp_hist;     new_temp_row];

    % Keep history buffer capped at HISTORY_WINDOW rows to save memory
    if size(history.density_hist, 1) > HISTORY_WINDOW
        history.density_hist  = history.density_hist(end - HISTORY_WINDOW + 1:end, :);
        history.speed_hist    = history.speed_hist(end  - HISTORY_WINDOW + 1:end, :);
        history.pressure_hist = history.pressure_hist(end-HISTORY_WINDOW + 1:end, :);
        history.temp_hist     = history.temp_hist(end   - HISTORY_WINDOW + 1:end, :);
    end

    % Also append to full density history (for dashboard trends)
    smooth_densities = arrayfun(@(z) z.density_smooth, processed);
    density_history_all = [density_history_all; smooth_densities];

    % ================================================================
    % STEP 3: ML Classification + STEP 4: Risk Scoring
    % ================================================================
    fprintf('[STEP 3] Classifying zones (Decision Tree ML)...\n');
    fprintf('[STEP 4] Computing risk scores...\n');

    labels  = cell(1, NUM_ZONES);
    risks   = repmat(struct('score', 0, 'level', 'Low', ...
                            'density_contrib', 0, 'pressure_contrib', 0, ...
                            'speed_contrib', 0, 'temp_contrib', 0), 1, NUM_ZONES);

    for z = 1:NUM_ZONES
        [labels{z}, ml_classifier] = classify_zone(processed(z), ml_classifier);
        risks(z)                   = compute_zone_risk(processed(z));
    end

    % ================================================================
    % STEP 5: Predict Crush ETA for each zone
    % ================================================================
    fprintf('[STEP 5] Predicting crush ETA using linear regression...\n');

    etas = repmat(struct('eta_minutes', Inf, 'message', '', ...
                         'is_safe', true, 'current_density', 0, ...
                         'trend_slope', 0, 'regression_ok', false), 1, NUM_ZONES);

    for z = 1:NUM_ZONES
        density_col = density_history_all(:, z);
        etas(z) = predict_crush_eta(density_col, SAMPLE_INTERVAL_S);
    end

    % ================================================================
    % STEP 6: Generate Recommendations
    % ================================================================
    fprintf('[STEP 6] Generating rerouting & emergency recommendations...\n');
    recs = generate_recommendations(zone_raw, processed, risks, labels, etas);

    % ================================================================
    % STEP 7: Upload to ThingSpeak
    % ================================================================
    fprintf('[STEP 7] Uploading to ThingSpeak cloud...\n');
    for z = 1:NUM_ZONES
        send_to_thingspeak(processed(z), risks(z), labels{z}, z, THINGSPEAK_KEYS{z});
        % Brief pause between zone uploads to respect rate limits
        % (Not needed in DEMO_MODE but good practice for real keys)
        % pause(0.5);
    end

    % ================================================================
    % STEP 8: Update live dashboard
    % ================================================================
    fprintf('[STEP 8] Updating live dashboard...\n');
    dashboard(processed, risks, labels, etas, density_history_all, ...
              iter, NUM_ITERATIONS);

    % ================================================================
    % CONSOLE OUTPUT: Per-zone status report
    % ================================================================
    fprintf('\n┌─────────────────────────────────────────────────────┐\n');
    fprintf('│              PER-ZONE STATUS REPORT                  │\n');
    fprintf('└─────────────────────────────────────────────────────┘\n');

    for z = 1:NUM_ZONES
        pz  = processed(z);
        rs  = risks(z);
        lbl = labels{z};
        eta = etas(z);
        rec = recs(z);

        % Status symbol
        switch lbl
            case 'Safe',     sym = '✓';
            case 'Warning',  sym = '⚡';
            case 'Critical', sym = '🚨';
            otherwise,       sym = '?';
        end

        fprintf('\n  %s Zone %d: %-22s [%s]\n', sym, z, pz.name, upper(lbl));
        fprintf('     Density:  %.3f p/m²  |  Speed:   %.3f m/s\n', ...
                pz.density_smooth, pz.speed_smooth);
        fprintf('     Pressure: %.3f       |  Temp:    %.1f°C\n', ...
                pz.pressure_smooth, pz.temp_smooth);
        fprintf('     Risk Score: %.1f/100 (%s)\n', rs.score, rs.level);
        fprintf('     ETA: %s\n', eta.message);

        % Print anomalies if any
        if pz.anomaly_count > 0
            fprintf('     Anomalies (%d active):\n', pz.anomaly_count);
            for a = 1:length(pz.anomaly_summary)
                fprintf('       → %s\n', pz.anomaly_summary{a});
            end
        end

        % Print top rerouting recommendation
        if ~isempty(rec.rerouting) && ~strcmp(rec.rerouting{1}, 'No rerouting required — maintain current flow')
            fprintf('     Rerouting: %s\n', rec.rerouting{1});
        end

        % Print authority notification for Warning/Critical zones
        if strcmp(lbl, 'Warning') || strcmp(lbl, 'Critical')
            fprintf('     Authority: %s\n', rec.authority_notification);
        end

        % Print pilgrim guidance
        fprintf('     Guidance: %s\n', rec.pilgrim_guidance);

        % Print dispatch actions for non-safe zones
        if strcmp(lbl, 'Warning') || strcmp(lbl, 'Critical')
            fprintf('     Dispatch Actions:\n');
            for d = 1:min(3, length(rec.emergency_dispatch))
                fprintf('       • %s\n', rec.emergency_dispatch{d});
            end
        end

        % Log session data
        session_log.iteration(iter)        = iter;
        session_log.risk_scores(iter, z)   = rs.score;
        session_log.labels{iter, z}        = lbl;
        session_log.densities(iter, z)     = pz.density_smooth;
        session_log.eta_minutes(iter, z)   = min(eta.eta_minutes, 999);

    end  % end zone loop

    % ================================================================
    % TIMING — Measure and report iteration duration
    % ================================================================
    elapsed_s = toc;
    fprintf('\n  [Timing] Iteration %02d completed in %.2f seconds\n', iter, elapsed_s);

    % Pause for remainder of interval (skip pause on final iteration)
    if iter < NUM_ITERATIONS
        remaining = max(0, SAMPLE_INTERVAL_S - elapsed_s);
        if remaining > 0.1
            fprintf('  [Timing] Waiting %.1fs for next sample window...\n', remaining);
            % Uncomment to use real-time pacing:
            % pause(remaining);
            % For fast simulation (no real-time wait), comment out the pause above.
        end
    end

end  % end main loop

% =========================================================================
% SESSION SUMMARY
% =========================================================================
fprintf('\n\n');
fprintf('╔══════════════════════════════════════════════════════════╗\n');
fprintf('║               SESSION SUMMARY REPORT                    ║\n');
fprintf('╚══════════════════════════════════════════════════════════╝\n\n');

fprintf('Simulation completed: %d samples × %ds = %d seconds simulated time\n\n', ...
        NUM_ITERATIONS, SAMPLE_INTERVAL_S, NUM_ITERATIONS * SAMPLE_INTERVAL_S);

fprintf('%-22s  %8s  %8s  %8s  %8s  %8s\n', ...
        'Zone', 'AvgRisk', 'MaxRisk', 'AvgDensity', '#Warnings', '#Critical');
fprintf('%s\n', repmat('-', 1, 70));

for z = 1:NUM_ZONES
    avg_risk    = mean(session_log.risk_scores(:, z));
    max_risk    = max(session_log.risk_scores(:, z));
    avg_density = mean(session_log.densities(:, z));
    n_warnings  = sum(strcmp(session_log.labels(:, z), 'Warning'));
    n_critical  = sum(strcmp(session_log.labels(:, z), 'Critical'));

    fprintf('%-22s  %8.1f  %8.1f  %8.3f  %8d  %8d\n', ...
            ZONE_NAMES{z}, avg_risk, max_risk, avg_density, n_warnings, n_critical);
end

fprintf('%s\n', repmat('-', 1, 70));
fprintf('\nMost dangerous zone: ');

[~, worst_z] = max(mean(session_log.risk_scores, 1));
fprintf('%s (avg risk: %.1f)\n', ZONE_NAMES{worst_z}, mean(session_log.risk_scores(:, worst_z)));

total_critical = sum(sum(strcmp(session_log.labels, 'Critical')));
total_warning  = sum(sum(strcmp(session_log.labels, 'Warning')));
fprintf('Total critical zone-events across session: %d\n', total_critical);
fprintf('Total warning zone-events across session:  %d\n', total_warning);

fprintf('\n[SYSTEM] All simulation data saved in MATLAB workspace:\n');
fprintf('         session_log, density_history_all, ml_classifier\n');
fprintf('\n[SYSTEM] Simulation complete. Dashboard remains open.\n\n');

% Export session data to MAT file for offline analysis
save('hajj_simulation_results.mat', 'session_log', 'density_history_all', ...
     'processed', 'risks', 'labels', 'etas', 'recs');
fprintf('[EXPORT] Results saved to hajj_simulation_results.mat\n');
