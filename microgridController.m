function out = microgridController(in, p)
%MICROGRIDCONTROLLER Rule-based dispatch controller for the UpGrid data
%centre microgrid (PV + BESS + grid backstop), implementing the control
%logic in the UpGrid product proposal flowchart:
%
%   1. Measure PV output, demand and BESS state of charge (SOC).
%   2. If solar is available (P_pv > 0):
%        a. PV output >= combined demand -> serve load directly from PV,
%           charge the BESS with the surplus (PV_DIRECT).
%        b. PV output <  combined demand -> PV and BESS discharge
%           together, peak-shaving, with the data centre served first
%           (PEAK_SHAVE).
%      Otherwise (no solar):
%        c. SOC above the reserve minimum -> discharge the BESS to serve
%           load, data centre first then residential (BESS_DISCHARGE).
%        d. SOC at/below the reserve minimum -> shed residential load and
%           hold the data centre only, protecting the critical load and
%           the battery from over-discharge (LOAD_SHED).
%
%   This function is a single control-interval step: call it once per
%   sample in a simulation loop (see runMicrogridSim.m), or drop its body
%   into a MATLAB Function block in Simulink with the same in/out fields.
%
%   INPUTS
%     in.P_pv   Available PV output this interval [kW]
%     in.P_dc   Data centre demand, critical/non-sheddable [kW]
%     in.P_res  Residential demand, sheddable [kW]
%     in.SOC    Battery state of charge at the start of the interval [0-1]
%
%     p.SOC_min       Reserve minimum SOC, battery protected below this [0-1]
%     p.SOC_max       Maximum SOC, charging stops above this [0-1]
%     p.E_bess_cap    Usable battery energy capacity [kWh]
%     p.P_bess_ch_max Maximum battery charge power [kW]
%     p.P_bess_dis_max Maximum battery discharge power [kW]
%     p.dt_h          Control interval length [h]
%
%   OUTPUT (struct)
%     out.state          Controller state name (char row vector):
%                         'PV_DIRECT', 'PEAK_SHAVE', 'BESS_DISCHARGE' or
%                         'LOAD_SHED'
%     out.P_bess         Battery power this interval [kW]; positive =
%                         discharging (supplying load), negative = charging
%     out.P_grid         Grid import [kW]; last-resort backstop only, used
%                         if the data centre load cannot be fully protected
%                         by PV+BESS alone (0 under normal operation)
%     out.P_curtail      PV surplus that could not be used to serve load or
%                         charge the battery [kW] (curtailed/exported)
%     out.P_dc_served    Data centre load actually served [kW]
%     out.P_res_served   Residential load actually served [kW]
%     out.P_shed         Residential load shed this interval [kW]
%
%   Jay Tinsley, UpGrid (Team 39) - data centre microgrid control strategy

    P_pv  = in.P_pv;
    P_dc  = in.P_dc;
    P_res = in.P_res;
    SOC   = in.SOC;

    P_load = P_dc + P_res;

    % Battery discharge power available this interval, limited by both the
    % power rating and the energy stored above the reserve SOC (protects
    % against over-discharge as required by the proposal's benchmarking
    % criteria).
    E_avail_kWh      = max(0, (SOC - p.SOC_min) * p.E_bess_cap);
    P_bess_dis_avail = min(p.P_bess_dis_max, E_avail_kWh / p.dt_h);

    % Battery charge headroom available this interval, limited by both the
    % power rating and the energy space below the maximum SOC (protects
    % against overcharge).
    E_headroom_kWh   = max(0, (p.SOC_max - SOC) * p.E_bess_cap);
    P_bess_ch_avail  = min(p.P_bess_ch_max, E_headroom_kWh / p.dt_h);

    P_grid    = 0;
    P_curtail = 0;

    if P_pv > 0
        if P_pv >= P_load
            % --- Serve load directly from PV, charge BESS with surplus ---
            state        = 'PV_DIRECT';
            P_dc_served  = P_dc;
            P_res_served = P_res;
            P_shed       = 0;

            surplus = P_pv - P_load;
            P_charge = min(surplus, P_bess_ch_avail);
            P_bess   = -P_charge;                 % negative = charging
            P_curtail = surplus - P_charge;        % surplus BESS can't absorb
        else
            % --- PV + BESS discharge together, peak shaving ---
            % Data centre load is served first, then residential.
            state = 'PEAK_SHAVE';
            shortfall = P_load - P_pv;
            P_bess = min(shortfall, P_bess_dis_avail);   % positive = discharge

            P_supply = P_pv + P_bess;             % total power available to load
            P_dc_served  = min(P_dc, P_supply);
            P_res_served = min(P_res, max(0, P_supply - P_dc));
            P_shed = P_res - P_res_served;

            % Last-resort grid backstop only if even the data centre cannot
            % be fully covered by PV + BESS (should not occur if the BESS is
            % sized adequately for the microgrid's peak shortfall).
            P_grid = max(0, P_dc - P_dc_served);
            P_dc_served = P_dc_served + P_grid;
        end
    else
        if SOC > p.SOC_min
            % --- Discharge BESS to serve load, data centre first ---
            state  = 'BESS_DISCHARGE';
            P_bess = min(P_load, P_bess_dis_avail);

            P_dc_served  = min(P_dc, P_bess);
            P_res_served = min(P_res, max(0, P_bess - P_dc));
            P_shed = P_res - P_res_served;

            P_grid = max(0, P_dc - P_dc_served);
            P_dc_served = P_dc_served + P_grid;
        else
            % --- Load shed: hold data centre only, protect the battery ---
            state  = 'LOAD_SHED';
            P_bess = min(P_dc, P_bess_dis_avail);  % whatever remains above reserve

            P_dc_served  = P_bess;
            P_res_served = 0;
            P_shed = P_res;

            % Grid backstop keeps the critical data centre load alive once
            % the battery has reached its reserve floor.
            P_grid = max(0, P_dc - P_dc_served);
            P_dc_served = P_dc_served + P_grid;
        end
    end

    out.state        = state;
    out.P_bess       = P_bess;
    out.P_grid       = P_grid;
    out.P_curtail    = P_curtail;
    out.P_dc_served  = P_dc_served;
    out.P_res_served = P_res_served;
    out.P_shed       = P_shed;
end
