using PowerSystems
using PowerSystemCaseBuilder
using Random
using TimeSeries
Random.seed!(1234)

sys = System("raw_data/scenarios/Original/ieee9_v32.raw")
rts_sys = build_system(PSISystems, "modified_RTS_GMLC_DA_sys_noForecast"; force_build = true)

function update_operation_cost!(sys, rts_sys)
    gen_names = ["generator-1-1", "generator-2-1", "generator-3-1"]
    rts_gen_names = ["101_STEAM_4", "213_CT_1", "321_CC_1"]
    fuel_types = [ThermalFuels.COAL, ThermalFuels.NATURAL_GAS, ThermalFuels.NATURAL_GAS]
    prime_movers = [PrimeMovers.ST, PrimeMovers.CT, PrimeMovers.CC]
    for (ix, gen_name) in enumerate(gen_names)
        gen = get_component(ThermalStandard, sys, gen_name)
        rts_gen = get_component(ThermalStandard, rts_sys, rts_gen_names[ix])
        mid_slope = rts_gen.operation_cost.variable.value_curve.function_data.y_coords[2]
        fuel_cost = rts_gen.operation_cost.variable.fuel_cost
        new_op_cost = ThermalGenerationCost(
            variable = CostCurve(
                value_curve = LinearCurve(mid_slope * fuel_cost),
                power_units = rts_gen.operation_cost.variable.power_units,
                vom_cost = rts_gen.operation_cost.variable.vom_cost,
            ),
            fixed = rts_gen.operation_cost.fixed,
            start_up = rts_gen.operation_cost.start_up,
            shut_down = rts_gen.operation_cost.shut_down,
        )
        set_operation_cost!(gen, new_op_cost)
        set_prime_mover_type!(gen, prime_movers[ix])
        set_fuel!(gen, fuel_types[ix])
    end
end

function add_load_time_series!(sys, rts_sys)
    load_names = ["load51", "load61", "load81"]
    rts_load_names = ["Alder", "Bacon", "Caesar"]
    for (ix, load_name) in enumerate(load_names)
        load = get_component(StandardLoad, sys, load_name)
        rts_load = get_component(PowerLoad, rts_sys, rts_load_names[ix])
        ts_array = get_time_series_array(SingleTimeSeries, rts_load, "max_active_power"; ignore_scaling_factors = true)
        add_time_series!(sys, load, SingleTimeSeries(; name = "max_active_power", data = ts_array, scaling_factor_multiplier = get_max_active_power))
    end
end

function add_renewable_generators!(sys, rts_sys)
    coal_gen = get_component(ThermalStandard, sys, "generator-1-1")
    solar = RenewableDispatch(;
        name = "PV_Bus_1",
        available = false,
        bus = get_bus(coal_gen),
        active_power = 0.0,
        reactive_power = 0.0,
        rating = 1.25, # 125 MW Plant
        prime_mover_type = PrimeMovers.PVe,
        reactive_power_limits = (min = -0.5, max = 0.5),
        power_factor = 1.0,
        operation_cost = RenewableGenerationCost(nothing),
        base_power = 100.0,
    )
    wind = RenewableDispatch(;
        name = "Wind_Bus_1",
        available = false,
        bus = get_bus(coal_gen),
        active_power = 0.0,
        reactive_power = 0.0,
        rating = 1.25, # 125 MW plant
        prime_mover_type = PrimeMovers.WT,
        reactive_power_limits = (min = -0.5, max = 0.5),
        power_factor = 1.0,
        operation_cost = RenewableGenerationCost(nothing),
        base_power = 100.0,
    )
    add_component!(sys, solar)
    add_component!(sys, wind)

    gen_names = ["PV_Bus_1", "Wind_Bus_1"]
    rts_gen_names = ["101_PV_1", "122_WIND_1"]
    for (ix, gen_name) in enumerate(gen_names)
        gen = get_component(RenewableDispatch, sys, gen_name)
        rts_gen = get_component(RenewableDispatch, rts_sys, rts_gen_names[ix])
        ts_array = get_time_series_array(SingleTimeSeries, rts_gen, "max_active_power"; ignore_scaling_factors = true)
        add_time_series!(sys, gen, SingleTimeSeries(; name = "max_active_power", data = ts_array, scaling_factor_multiplier = get_max_active_power))
    end
end

set_units_base_system!(sys, "NATURAL_UNITS")
add_load_time_series!(sys, rts_sys)
update_operation_cost!(sys, rts_sys)
to_json(sys, "saved_systems/ieee9_sienna.json"; force=true)

add_renewable_generators!(sys, rts_sys)
coal_gen = get_component(ThermalStandard, sys, "generator-1-1")
pv_gen = get_component(RenewableDispatch, sys, "PV_Bus_1")
wind_gen = get_component(RenewableDispatch, sys, "Wind_Bus_1")
set_available!(coal_gen, false)
set_available!(pv_gen, true)
set_available!(wind_gen, true)
to_json(sys, "saved_systems/ieee9_sienna_with_renewable.json"; force=true)


function add_storage!(sys)
    coal_gen = get_component(ThermalStandard, sys, "generator-1-1")
    storage = EnergyReservoirStorage(
        name = "Storage_Bus_1",
        available = true,
        bus = coal_gen.bus,
        prime_mover_type = PrimeMovers.OT,
        storage_technology_type = StorageTech.LIB,
        storage_capacity = 4.0, # 400 MWh,
        storage_level_limits = (min = 0.0, max = 1.0),
        initial_storage_capacity_level = 0.5,
        rating = 1.0, # 100 MW,
        active_power = 0.0,
        input_active_power_limits = (min = 0.0, max = 1.0), # 100 MW
        output_active_power_limits = (min = 0.0, max = 1.0), # 100 MW
        efficiency = (in = 0.93, out = 0.93),
        reactive_power = 0.0,
        reactive_power_limits = (min = -1.0, max = 1.0),
        base_power = 100.0,
    )
    add_component!(sys, storage)
end

add_storage!(sys)
to_json(sys, "saved_systems/ieee9_sienna_with_storage.json"; force=true)

function add_shiftable_load!(sys)
    load = get_component(StandardLoad, sys, "load51")
    shiftable_load = ShiftablePowerLoad(;
        name = "shiftable_load",
        available = true,
        bus = get_bus(load),
        active_power = get_max_active_power(load),
        active_power_limits = (min = 0.0, max = get_max_active_power(load)),
        reactive_power = get_constant_reactive_power(load),
        max_active_power = get_max_active_power(load),
        max_reactive_power = get_max_constant_reactive_power(load),
        base_power = get_base_power(load),
        load_balance_time_horizon = 1, # not used yet
        operation_cost = LoadCost(;
            variable = CostCurve(
                LinearCurve(0.0), # No cost for shifting up
                UnitSystem.NATURAL_UNITS,
                LinearCurve(5.0) # Only cost for shifting down
            ),
            fixed = 0.0,
        ),
    )
    add_component!(sys, shiftable_load)
    set_available!(load, false)
    copy_time_series!(shiftable_load, load)

    tstamps =
        TimeSeries.timestamp(get_time_series_array(SingleTimeSeries, shiftable_load, "max_active_power"))
    up_vals = 0.1 * ones(length(tstamps)) # Only 10% of the load can be shifted up at each time step
    down_vals = 0.2 * rand(length(tstamps)) # Up to 50% of the load can be shifted down at each time step randomly
    up_array = TimeArray(tstamps, up_vals)
    down_array = TimeArray(tstamps, down_vals)
    up_ts = SingleTimeSeries(
        "shift_up_max_active_power",
        up_array;
        scaling_factor_multiplier = get_max_active_power,
    )
    down_ts = SingleTimeSeries(
        "shift_down_max_active_power",
        down_array;
        scaling_factor_multiplier = get_max_active_power,
    )
    add_time_series!(sys, shiftable_load, up_ts)
    add_time_series!(sys, shiftable_load, down_ts)
end

sys_shiftable = System("saved_systems/ieee9_sienna_with_renewable.json")
set_units_base_system!(sys_shiftable, "DEVICE_BASE")
add_shiftable_load!(sys_shiftable)
set_units_base_system!(sys_shiftable, "NATURAL_UNITS")
to_json(sys_shiftable, "saved_systems/ieee9_sienna_with_renewable_and_shiftable_load.json"; force=true)
