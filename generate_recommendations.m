function recs = generate_recommendations(zone_data_array, processed_array, ...
                                          risk_array, label_array, eta_array)
% =========================================================================
% generate_recommendations.m
% IoT-Based Crowd Crush Prevention System — Recommendation Engine
%
% PURPOSE:
%   Generates actionable safety recommendations for each zone based on:
%   - ML classification label (Safe/Warning/Critical)
%   - Composite risk score
%   - Crush ETA prediction
%   - Specific anomaly flags (density, speed, pressure, temperature)
%
%   The system goes beyond monitoring by generating:
%   1. REROUTING INSTRUCTIONS — which corridors to redirect pilgrims to
%   2. EMERGENCY DISPATCH ALERTS — which emergency units to mobilize
%   3. AUTHORITY NOTIFICATIONS — messages to Hajj command center
%   4. PILGRIM GUIDANCE MESSAGES — Arabic/English announcements
%
% INPUTS:
%   zone_data_array  — 1×5 struct array from simulate_zone_sensors()
%   processed_array  — 1×5 struct array from process_zone_data()
%   risk_array       — 1×5 struct array from compute_zone_risk()
%   label_array      — 1×5 cell array of strings {'Safe','Warning','Critical'}
%   eta_array        — 1×5 struct array from predict_crush_eta()
%
% OUTPUT:
%   recs             — 1×5 struct array, each zone element contains:
%                      .zone_name         String
%                      .status            'Safe' / 'Warning' / 'Critical'
%                      .rerouting         Cell array of rerouting instructions
%                      .emergency_dispatch Cell array of dispatch actions
%                      .authority_notification String to command center
%                      .pilgrim_guidance  String for public announcement
%                      .action_priority   'NONE' / 'MONITOR' / 'RESPOND' / 'EMERGENCY'
% =========================================================================

    % ---- Zone interconnection map (which zones redirect to which) -------
    % Defines safe alternative corridors for each zone.
    % Based on Mina area geometry: zones share boundaries.
    reroute_map = { ...
        'Jamarat Bridge',    {'Tent City North Exit B', 'Tent City South Exit A', 'Alternate Bridge Level 2'}; ...
        'Tent City North',   {'Emergency Exit Path North', 'Ring Road Access Point A', 'Jamarat Bridge Level 3'}; ...
        'Tent City South',   {'Emergency Exit Path South', 'Ring Road Access Point B', 'Jamarat Bridge Level 2'}; ...
        'Emergency Exit Path', {'Tent City North Entry', 'Tent City South Entry', 'Perimeter Track West'}  ...
    };

    % ---- Emergency unit availability table ----------------------------
    % Maps risk levels to dispatch units
    dispatch_units = struct();
    dispatch_units.medical    = 'Medical Response Team (MRT)';
    dispatch_units.crowd      = 'Crowd Control Unit (CCU)';
    dispatch_units.helicopter = 'Medevac Helicopter Unit';
    dispatch_units.fire       = 'Fire & Rescue Team';
    dispatch_units.police     = 'Hajj Security Police';
    dispatch_units.water      = 'Mobile Water/Cooling Station';

    num_zones = length(processed_array);
    recs(num_zones) = struct( ...
        'zone_name', [], 'status', [], ...
        'rerouting', {{}}, 'emergency_dispatch', {{}}, ...
        'authority_notification', [], 'pilgrim_guidance', [], ...
        'action_priority', []);

    for z = 1:num_zones

        pz       = processed_array(z);
        risk     = risk_array(z);
        label    = label_array{z};
        eta      = eta_array(z);
        zone_name = pz.name;

        % ---- Find rerouting options for this zone ----------------------
        alt_routes = {};
        for r = 1:size(reroute_map, 1)
            if strcmp(reroute_map{r, 1}, zone_name)
                alt_routes = reroute_map{r, 2};
                break;
            end
        end

        % ---- Build recommendations based on status --------------------
        rerouting         = {};
        emergency_dispatch = {};
        authority_msg     = '';
        pilgrim_guidance  = '';
        action_priority   = 'NONE';

        switch label

            % ==============================================================
            case 'Safe'
            % ==============================================================
                action_priority = 'NONE';
                rerouting       = {'No rerouting required — maintain current flow'};
                pilgrim_guidance = sprintf( ...
                    '[%s] Conditions are normal. Continue moving steadily. | الأوضاع طبيعية، واصلوا التحرك بانتظام.', ...
                    zone_name);
                authority_msg = sprintf( ...
                    '[ROUTINE] %s — Risk: %.1f/100 (%s). All parameters nominal. No action required.', ...
                    zone_name, risk.score, risk.level);
                emergency_dispatch = {'No dispatch required'};

            % ==============================================================
            case 'Warning'
            % ==============================================================
                action_priority = 'RESPOND';

                % Rerouting: redirect some flow to alternatives
                if ~isempty(alt_routes)
                    rerouting{end+1} = sprintf( ...
                        'REDIRECT 30%% of flow from %s → %s', ...
                        zone_name, alt_routes{1});
                    rerouting{end+1} = sprintf( ...
                        'Open additional access: %s', alt_routes{2});
                    rerouting{end+1} = sprintf( ...
                        'Close 1 entry gate to %s — use %s instead', ...
                        zone_name, alt_routes{3});
                end

                % Add density-specific action
                if pz.flag_density
                    rerouting{end+1} = sprintf( ...
                        'Density %.2f p/m² — Activate crowd metering at %s entry points', ...
                        pz.density_smooth, zone_name);
                end

                % Speed warning
                if pz.flag_speed
                    rerouting{end+1} = sprintf( ...
                        'Turbulent flow detected (%.2f m/s) — Deploy stewards to guide movement', ...
                        pz.speed_smooth);
                end

                % Dispatch units
                emergency_dispatch{end+1} = sprintf( ...
                    'DISPATCH: %s to %s', dispatch_units.crowd, zone_name);
                emergency_dispatch{end+1} = sprintf( ...
                    'DISPATCH: %s to %s', dispatch_units.medical, zone_name);
                if pz.flag_temp
                    emergency_dispatch{end+1} = sprintf( ...
                        'DISPATCH: %s near %s', dispatch_units.water, zone_name);
                end
                emergency_dispatch{end+1} = sprintf( ...
                    'ALERT: %s — patrol route to include %s', ...
                    dispatch_units.police, zone_name);

                % Pilgrim guidance
                pilgrim_guidance = sprintf( ...
                    '[%s] Elevated density detected. Please move to alternative routes: %s. Move calmly and steadily. | كثافة عالية — يرجى التوجه إلى: %s. تحركوا بهدوء.', ...
                    zone_name, alt_routes{1}, alt_routes{1});

                % Authority notification
                authority_msg = sprintf( ...
                    '[WARNING] %s — Risk Score: %.1f/100 (%s). Density: %.2f, Speed: %.2f, Pressure: %.2f, Temp: %.1f°C. ETA: %s. Rerouting in progress.', ...
                    zone_name, risk.score, risk.level, ...
                    pz.density_smooth, pz.speed_smooth, ...
                    pz.pressure_smooth, pz.temp_smooth, eta.message);

            % ==============================================================
            case 'Critical'
            % ==============================================================
                action_priority = 'EMERGENCY';

                % Aggressive rerouting
                rerouting{end+1} = sprintf( ...
                    '🚨 EMERGENCY CLOSURE: Close ALL entry points to %s IMMEDIATELY', zone_name);
                for r = 1:length(alt_routes)
                    rerouting{end+1} = sprintf( ...
                        'MANDATORY REDIRECT → %s (open all gates)', alt_routes{r});
                end
                rerouting{end+1} = sprintf( ...
                    'Activate Zone Isolation Protocol for %s', zone_name);
                rerouting{end+1} = 'Deploy physical barriers at all %s access points';
                rerouting{end+1} = 'Initiate reverse-flow evacuation through emergency corridors';

                % Full emergency dispatch
                emergency_dispatch{end+1} = sprintf( ...
                    '🚨 EMERGENCY DISPATCH: ALL units to %s', zone_name);
                emergency_dispatch{end+1} = sprintf( ...
                    'DISPATCH: %s — 3 units to %s IMMEDIATELY', dispatch_units.medical, zone_name);
                emergency_dispatch{end+1} = sprintf( ...
                    'DISPATCH: %s — full team to %s', dispatch_units.crowd, zone_name);
                emergency_dispatch{end+1} = sprintf( ...
                    'DISPATCH: %s — standby at %s', dispatch_units.helicopter, zone_name);
                emergency_dispatch{end+1} = sprintf( ...
                    'DISPATCH: %s — barrier deployment at %s', dispatch_units.police, zone_name);
                emergency_dispatch{end+1} = sprintf( ...
                    'DISPATCH: %s — 5 units near %s', dispatch_units.water, zone_name);

                % Pilgrim guidance - urgent
                pilgrim_guidance = sprintf( ...
                    '🚨 [%s] URGENT: Please evacuate this area immediately. Proceed calmly to: %s. Follow steward instructions. | تنبيه عاجل: يرجى مغادرة المنطقة فوراً. توجهوا إلى: %s. اتبعوا تعليمات المرشدين.', ...
                    zone_name, alt_routes{1}, alt_routes{1});

                % Authority notification with full telemetry
                authority_msg = sprintf( ...
                    '[🚨 CRITICAL ALERT] %s — Risk: %.1f/100 (%s). CRUSH THRESHOLD EXCEEDED or IMMINENT. Density: %.2f p/m², Speed: %.2f m/s, Pressure: %.2f, Temp: %.1f°C. %s. Anomalies: %d active. EMERGENCY PROTOCOLS ACTIVATED.', ...
                    zone_name, risk.score, risk.level, ...
                    pz.density_smooth, pz.speed_smooth, ...
                    pz.pressure_smooth, pz.temp_smooth, ...
                    eta.message, pz.anomaly_count);

        end  % end switch

        % ---- Store recommendations ------------------------------------
        recs(z).zone_name              = zone_name;
        recs(z).status                 = label;
        recs(z).rerouting              = rerouting;
        recs(z).emergency_dispatch     = emergency_dispatch;
        recs(z).authority_notification = authority_msg;
        recs(z).pilgrim_guidance       = pilgrim_guidance;
        recs(z).action_priority        = action_priority;

    end  % end zone loop

end
