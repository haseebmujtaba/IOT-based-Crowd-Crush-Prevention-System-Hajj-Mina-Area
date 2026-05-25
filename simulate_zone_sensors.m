function zone_data = simulate_zone_sensors(iteration)
    zone_configs = struct();

    zone_configs(1).name             = 'Jamarat Bridge';
    zone_configs(1).base_density     = 4.2;   % people/m² — near-critical baseline
    zone_configs(1).base_speed       = 0.6;   % m/s — slow due to narrowness
    zone_configs(1).base_pressure    = 0.55;  % moderate pressure
    zone_configs(1).base_temp        = 38.5;  % °C — sun-exposed bridge
    zone_configs(1).anomaly_prob     = 0.25;  % 25% chance of anomaly spike

    zone_configs(2).name             = 'Tent City North';
    zone_configs(2).base_density     = 2.8;
    zone_configs(2).base_speed       = 0.9;
    zone_configs(2).base_pressure    = 0.35;
    zone_configs(2).base_temp        = 37.0;
    zone_configs(2).anomaly_prob     = 0.12;

    zone_configs(3).name             = 'Tent City South';
    zone_configs(3).base_density     = 3.1;
    zone_configs(3).base_speed       = 0.85;
    zone_configs(3).base_pressure    = 0.40;
    zone_configs(3).base_temp        = 37.8;
    zone_configs(3).anomaly_prob     = 0.15;

    zone_configs(4).name             = 'Emergency Exit Path';
    zone_configs(4).base_density     = 1.2;   % should be near-empty
    zone_configs(4).base_speed       = 1.3;   % fast evacuation flow
    zone_configs(4).base_pressure    = 0.15;
    zone_configs(4).base_temp        = 36.0;
    zone_configs(4).anomaly_prob     = 0.08;

    % ---- Noise and drift parameters -------------------------------------
    density_noise_std  = 0.3;    % +/-0.3 people/m2 sensor noise
    speed_noise_std    = 0.08;   % +/-0.08 m/s
    pressure_noise_std = 0.04;   % +/-0.04 pressure units
    temp_noise_std     = 0.5;    % +/-0.5 degrees C

    % Time-based drift: crowd density rises and falls with a sinusoidal
    % pattern mimicking daily prayer schedule peaks (~every 30 iterations)
    time_drift = 0.4 * sin(2 * pi * iteration / 30);

    % ---- Generate readings for each zone --------------------------------
    num_zones = 4;
    zone_data(num_zones) = struct('name', [], 'density', [], ...
                                  'speed', [], 'pressure', [], ...
                                  'temperature', []);

    for z = 1:num_zones
        cfg = zone_configs(z);

        % --- Gaussian sensor noise (realistic sensor imprecision) --------
        d_noise = density_noise_std  * randn();
        s_noise = speed_noise_std    * randn();
        p_noise = pressure_noise_std * randn();
        t_noise = temp_noise_std     * randn();

        % --- Compute base reading with time drift ------------------------
        raw_density  = cfg.base_density  + time_drift + d_noise;
        raw_speed    = cfg.base_speed    - 0.05 * time_drift + s_noise;
        raw_pressure = cfg.base_pressure + 0.08 * time_drift + p_noise;
        raw_temp     = cfg.base_temp     + 0.3  * time_drift + t_noise;

        % --- Anomaly injection (random crowd surge event) ----------------
        % Simulates sudden bottleneck or panic movement
        if rand() < cfg.anomaly_prob
            raw_density  = raw_density  + 1.5 + rand() * 1.0;  % surge
            raw_speed    = raw_speed    - 0.3 - rand() * 0.2;  % slowdown
            raw_pressure = raw_pressure + 0.20 + rand() * 0.1; % pressure rise
            raw_temp     = raw_temp     + 1.5 + rand() * 1.0;  % heat buildup
        end

        % --- Physical boundary clamping ----------------------------------
        % Sensors have physical limits; values outside range = saturation
        raw_density  = max(0.1, min(10.0, raw_density));   % 0.1-10 people/m2
        raw_speed    = max(0.0, min(2.5,  raw_speed));     % 0-2.5 m/s
        raw_pressure = max(0.0, min(1.0,  raw_pressure));  % 0-1 normalized
        raw_temp     = max(25.0, min(50.0, raw_temp));     % 25-50 degrees C

        % --- Store in output struct -------------------------------------
        zone_data(z).name        = cfg.name;
        zone_data(z).density     = raw_density;
        zone_data(z).speed       = raw_speed;
        zone_data(z).pressure    = raw_pressure;
        zone_data(z).temperature = raw_temp;
    end

    % ====================================================================
    % CRITICAL SURGE EVENT — Iteration 35, Jamarat Bridge (Zone 1)
    % ====================================================================
    % This block simulates a sudden catastrophic crowd surge on Jamarat
    % Bridge at iteration 35 — approximately 9 minutes into the session.
    %
    % Physically, this models what happened in real Hajj crush events:
    % a wave of pilgrims from a branching path merges unexpectedly with
    % the main flow, causing all 4 sensors to spike simultaneously:
    %
    %   Density  -> 7.8  p/m2   (well above 6.0 critical threshold)
    %   Speed    -> 0.12 m/s    (near-stopped flow, severe turbulence)
    %   Pressure -> 0.91        (above 0.8 critical threshold)
    %   Temp     -> 42.3 deg C  (above 40 deg C heat stress threshold)
    %
    % All 4 anomaly flags will trigger simultaneously.
    % ML classifier will return 'Critical'.
    % Risk score will exceed 75 (Critical level).
    % ETA module will output "CRUSH IMMINENT — ETA: NOW".
    % Emergency dispatch, zone closure, and evacuation are auto-triggered.
    % ====================================================================
    CRITICAL_SURGE_ITERATION = 35;

    if iteration == CRITICAL_SURGE_ITERATION

        % Override Zone 1 (Jamarat Bridge) with critical surge values.
        % Small noise is retained so readings look like real sensors,
        % not artificially flat numbers.
        surge_density  = 7.8  + 0.15 * randn();   % critical: >> 6.0
        surge_speed    = 0.12 + 0.02 * randn();   % critical: << 0.3
        surge_pressure = 0.91 + 0.02 * randn();   % critical: >> 0.8
        surge_temp     = 42.3 + 0.30 * randn();   % critical: >> 40.0

        % Clamp to physical sensor limits (keep values realistic)
        surge_density  = max(6.5,  min(10.0, surge_density));
        surge_speed    = max(0.0,  min(0.20, surge_speed));
        surge_pressure = max(0.85, min(1.0,  surge_pressure));
        surge_temp     = max(41.0, min(50.0, surge_temp));

        % Overwrite zone 1 readings with surge values
        zone_data(1).density     = surge_density;
        zone_data(1).speed       = surge_speed;
        zone_data(1).pressure    = surge_pressure;
        zone_data(1).temperature = surge_temp;

        % Print a hard-to-miss console banner at the moment of surge
        fprintf('\n');
        fprintf('########################################################\n');
        fprintf('##                                                    ##\n');
        fprintf('##   !!! CRITICAL SURGE EVENT — JAMARAT BRIDGE !!!   ##\n');
        fprintf('##                                                    ##\n');
        fprintf('##   Iteration : %02d / 60                             ##\n', iteration);
        fprintf('##   Density   : %.2f p/m2  [THRESHOLD: 6.0]        ##\n', surge_density);
        fprintf('##   Speed     : %.2f m/s   [THRESHOLD: 0.30]       ##\n', surge_speed);
        fprintf('##   Pressure  : %.2f       [THRESHOLD: 0.80]       ##\n', surge_pressure);
        fprintf('##   Temp      : %.1f deg C [THRESHOLD: 40.0]       ##\n', surge_temp);
        fprintf('##                                                    ##\n');
        fprintf('##   ALL 4 SENSORS IN CRITICAL RANGE                 ##\n');
        fprintf('##   EMERGENCY PROTOCOLS NOW ACTIVE                  ##\n');
        fprintf('##                                                    ##\n');
        fprintf('########################################################\n');
        fprintf('\n');

    end

end