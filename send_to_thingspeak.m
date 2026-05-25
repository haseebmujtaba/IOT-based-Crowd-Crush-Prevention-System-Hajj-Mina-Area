function success = send_to_thingspeak(processed_zone, risk, label, zone_index, write_key)
% =========================================================================
% send_to_thingspeak.m
% IoT-Based Crowd Crush Prevention System — Cloud Upload Module
%
% PURPOSE:
%   Uploads real-time sensor data, computed risk scores, and zone status
%   for ONE zone to a ThingSpeak channel using the HTTP REST API via
%   MATLAB's webwrite() function.
%
%   Uses JSON body sent to the /update.json endpoint — this is the correct
%   approach for MATLAB's webwrite(), which requires MediaType to be a JSON
%   media type. Sending form-encoded structs causes a MediaType error.
%
% THINGSPEAK FIELD MAPPING (per zone upload):
%   Field 1 (field1) — Crowd Density        [people/m²]
%   Field 2 (field2) — Movement Speed       [m/s]
%   Field 3 (field3) — Pressure Index       [0–1]
%   Field 4 (field4) — Temperature          [°C]
%   Field 5 (field5) — Risk Score           [0–100]
%   Field 6 (field6) — Status Code          [1=Safe, 2=Warning, 3=Critical]
%
% HOW TO SET UP THINGSPEAK:
%   1. Go to thingspeak.com and log in (free account)
%   2. Click "New Channel" and name it (e.g. "Jamarat Bridge")
%   3. Enable Field 1 through Field 6 and label them accordingly
%   4. Go to the "API Keys" tab and copy your Write API Key
%   5. Paste that key into main.m under THINGSPEAK_KEYS{zone_index}
%
% RATE LIMIT:
%   ThingSpeak free tier allows 1 update per channel every 15 seconds.
%   With 16-second sample intervals and 4 zones, uploads are naturally
%   spaced — no additional pausing is required.
%
% INPUTS:
%   processed_zone — Processed zone struct (from process_zone_data)
%   risk           — Risk struct (from compute_zone_risk)
%   label          — Classification string: 'Safe', 'Warning', 'Critical'
%   zone_index     — Integer 1–4 (used for console logging only)
%   write_key      — ThingSpeak Write API Key string
%                    Use 'DEMO_MODE' to skip upload and simulate success
%
% OUTPUT:
%   success        — true if upload succeeded, false if failed
% =========================================================================

    % ---- ThingSpeak JSON endpoint --------------------------------------
    % The /update.json endpoint accepts a JSON body and returns a JSON
    % response containing the entry_id on success, or 0 on rate limit.
    THINGSPEAK_URL = 'https://api.thingspeak.com/update.json';

    % ---- Map classification label to numeric status code ---------------
    switch label
        case 'Safe',     status_code = 1;
        case 'Warning',  status_code = 2;
        case 'Critical', status_code = 3;
        otherwise,       status_code = 0;
    end

    % ---- DEMO MODE: skip HTTP call entirely ----------------------------
    % Set write_key = 'DEMO_MODE' in main.m during development/testing.
    % Prints what would have been uploaded without making any web request.
    if strcmp(write_key, 'DEMO_MODE')
        fprintf(['   [ThingSpeak Z%d] DEMO MODE | Zone: %-22s | ' ...
                 'D=%.2f p/m² | S=%.2f m/s | P=%.2f | ' ...
                 'T=%.1f°C | Risk=%.1f | Status=%d (%s)\n'], ...
            zone_index, ...
            processed_zone.name, ...
            processed_zone.density_smooth, ...
            processed_zone.speed_smooth, ...
            processed_zone.pressure_smooth, ...
            processed_zone.temp_smooth, ...
            risk.score, status_code, label);
        success = true;
        return;
    end

    % ---- Validate write key -------------------------------------------
    % A valid ThingSpeak Write API Key is exactly 16 alphanumeric characters.
    if isempty(write_key) || length(write_key) < 8
        fprintf('   [ThingSpeak Z%d] ✗ Invalid write key (too short). Skipping upload.\n', ...
            zone_index);
        success = false;
        return;
    end

    % ---- Build JSON payload string ------------------------------------
    % Manually construct the JSON body as a character string.
    % Round values to keep payload clean and within ThingSpeak precision.
    %
    % JSON format expected by ThingSpeak /update.json:
    %   {"api_key":"XXXXXXXXXXXXXXXX","field1":3.14,"field2":0.85,...}
    json_body = sprintf( ...
        '{"api_key":"%s","field1":%.4f,"field2":%.4f,"field3":%.4f,"field4":%.4f,"field5":%.2f,"field6":%d}', ...
        write_key, ...
        round(processed_zone.density_smooth,  4), ...
        round(processed_zone.speed_smooth,    4), ...
        round(processed_zone.pressure_smooth, 4), ...
        round(processed_zone.temp_smooth,     4), ...
        round(risk.score,                     2), ...
        status_code);

    % ---- Configure HTTP options ---------------------------------------
    % MediaType = 'application/json' tells webwrite to send a raw JSON
    % string body rather than form-encoding a struct — this is the fix
    % for the "Expected options.MediaType to be a JSON media type" error.
    % ContentType = 'json' tells webwrite to parse the response as JSON.
    options = weboptions( ...
        'RequestMethod', 'post', ...
        'Timeout',       10, ...
        'MediaType',     'application/json', ...
        'ContentType',   'json');

    % ---- Execute HTTP POST with full error handling -------------------
    try
        response = webwrite(THINGSPEAK_URL, json_body, options);

        % ThingSpeak /update.json returns a struct with field 'entry_id':
        %   entry_id > 0  → success (sequential ID of this data point)
        %   entry_id = 0  → rate limit violation (update sent too soon)
        if isstruct(response) && isfield(response, 'entry_id')
            entry_id = response.entry_id;
        elseif isnumeric(response)
            entry_id = response;
        else
            % Unexpected response format — attempt numeric conversion
            entry_id = str2double(string(response));
            if isnan(entry_id)
                entry_id = -1;
            end
        end

        % ---- Interpret entry_id result --------------------------------
        if entry_id > 0
            % Successful upload confirmed by ThingSpeak
            fprintf(['   [ThingSpeak Z%d] ✓ Uploaded | Entry ID: %d | ' ...
                     'Zone: %-22s | D=%.2f | S=%.2f | P=%.2f | ' ...
                     'T=%.1f°C | Risk=%.1f | Status=%d\n'], ...
                zone_index, entry_id, ...
                processed_zone.name, ...
                processed_zone.density_smooth, ...
                processed_zone.speed_smooth, ...
                processed_zone.pressure_smooth, ...
                processed_zone.temp_smooth, ...
                risk.score, status_code);
            success = true;

        elseif entry_id == 0
            % ThingSpeak rejected the update due to rate limiting.
            % Free tier requires >= 15 seconds between updates per channel.
            fprintf(['   [ThingSpeak Z%d] ⚠ Rate limited (entry_id=0) — ' ...
                     'update sent too soon. Skipping this sample.\n'], ...
                zone_index);
            success = false;

        else
            % entry_id = -1 or other unexpected value
            fprintf(['   [ThingSpeak Z%d] ⚠ Unexpected response ' ...
                     '(entry_id=%d). Upload status unclear.\n'], ...
                zone_index, entry_id);
            success = false;
        end

    catch err
        % Catches: network timeout, DNS failure, SSL error, MATLAB error
        fprintf('   [ThingSpeak Z%d] ✗ Upload failed: %s\n', ...
            zone_index, err.message);
        success = false;
    end

end