using PowerSystems
using PowerSystemCaseBuilder
using PowerSimulations
using Dates
using HiGHS
using PlotlyJS

sys = System("saved_systems/ieee9_sienna_with_renewable_and_shiftable_load.json")
transform_single_time_series!(sys, Hour(24), Hour(24))
p_flow_load = sum(get_max_active_power.(get_components(StandardLoad, sys))) 
th_max_power = sum(get_max_active_power.(get_components(ThermalStandard, sys)))
shiftable_load = get_component(ShiftablePowerLoad, sys, "shiftable_load")

solver = optimizer_with_attributes(HiGHS.Optimizer)
template = ProblemTemplate(CopperPlatePowerModel)
set_device_model!(template, StandardLoad, StaticPowerLoad)
set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
#set_device_model!(template, ThermalStandard, ThermalBasicUnitCommitment)
shiftable_model = DeviceModel(
    ShiftablePowerLoad,
    PowerLoadShift;
    #attributes = Dict{String, Any}(
    #    "additional_balance_interval" => Hour(12),
    #),
)
set_device_model!(template, shiftable_model)
models = SimulationModels(;
    decision_models = [
        DecisionModel(template, sys; optimizer = solver, name = "UC"),
    ],
)

feedforward = Dict()
sequence = SimulationSequence(;
    models = models,
    ini_cond_chronology = InterProblemChronology(),
    feedforwards = feedforward,
)

sim = Simulation(;
    name = "ieee9-test",
    steps = 365,
    models = models,
    sequence = sequence,
    simulation_folder = mktempdir(),
    #initial_time = DateTime("2020-07-01T00:00:00"),
)

build!(sim)
execute!(sim; enable_progress_bar = true)
results = SimulationResults(sim);
uc_results = get_decision_problem_results(results, "UC")
p_th = read_realized_variable(uc_results, "ActivePowerVariable__ThermalStandard"; table_format = TableFormat.WIDE)
p_load = read_realized_parameter(uc_results, "ActivePowerTimeSeriesParameter__StandardLoad"; table_format = TableFormat.WIDE)
p_re = read_realized_variable(uc_results, "ActivePowerVariable__RenewableDispatch"; table_format = TableFormat.WIDE)
cost_th = read_realized_expression(uc_results, "ProductionCostExpression__ThermalStandard"; table_format = TableFormat.WIDE)
total_cost = sum(cost_th[!, "generator-3-1"]) + sum(cost_th[!, "generator-2-1"])
p_realized_shiftable = read_realized_expression(uc_results, "RealizedShiftedLoad__ShiftablePowerLoad"; table_format = TableFormat.WIDE)
p_baseline_shiftable = read_realized_parameter(uc_results, "ActivePowerTimeSeriesParameter__ShiftablePowerLoad"; table_format = TableFormat.WIDE)

tstamp = p_th[!, 1]
#p_gen1 = p_th[!, "generator-1-1"]
#p_gen2 = p_th[!, "generator-2-1"]
#p_gen3 = p_th[!, "generator-3-1"]
#p_gen_pv = p_re[!, "PV_Bus_1"]
#p_gen_wind = p_re[!, "Wind_Bus_1"]
#p_load5 = -p_load[!, "load51"]
#p_load6 = -p_load[!, "load61"]
#p_load8 = -p_load[!, "load81"]
#total_p_load = p_load5 + p_load6 + p_load8

plot([
    scatter(
        x = tstamp,
        y = p_realized_shiftable[!, "shiftable_load"],
        mode = "lines",
        name = "Shiftable Load",
        line = attr(color = "blue"),
    ),
    scatter(
        x = tstamp,
        y = p_baseline_shiftable[!, "shiftable_load"],
        mode = "lines",
        name = "Baseline Shiftable Load",
        line = attr(color = "red"),
    ),
], Layout(
        yaxis_title="Active Power [MW]",
        title = "Comparison of Shiftable Load",
    ),
)

plot([
    scatter(
        x = tstamp,
        y = p_gen_pv,
        mode = "lines",
        name = "PV Gen",
        line = attr(color = "gold"),
    ),
    scatter(
        x = tstamp,
        y = p_gen_wind,
        mode = "lines",
        name = "Wind Gen",
        line = attr(color = "green"),
    ),
    scatter(
        x = tstamp,
        y = p_gen2,
        mode = "lines",
        name = "CT Gen",
        line = attr(color = "blue"),
    ),
    scatter(
        x = tstamp,
        y = p_gen3,
        mode = "lines",
        name = "CC Gen",
        line = attr(color = "red"),
    ),
    scatter(
        x = tstamp,
        y = total_p_load,
        mode = "lines",
        name = "Total Load",
        line = attr(color = "black", dash = "dot"),
    )
], Layout(
        yaxis_title="Active Power [MW]",
        title = "Gas, PV and Wind case: Total Cost $(round(total_cost, digits=1))",
    ),
)

### Find Critical Days ###

# Find hour with lowest thermal generation > 0: Min Inertia #
p_th_sum = p_gen2 + p_gen3
low_thermal_ixs = sortperm(p_th_sum)
p_th_sum_sorted = p_th_sum[low_thermal_ixs]
first_sorted_ix_positive = findfirst(x -> x>0.0, p_th_sum_sorted)
num_hours_with_zero_thermal = first_sorted_ix_positive - 1
ix_low_thermal = low_thermal_ixs[first_sorted_ix_positive]

tstamp_low_thermal = tstamp[ix_low_thermal]
gas_low_thermal = p_th_sum[ix_low_thermal]
load_low_thermal = total_p_load[ix_low_thermal]
wind_low_thermal = p_gen_wind[ix_low_thermal]
pv_low_thermal = p_gen_pv[ix_low_thermal]

# Find hour with lowest demand #
p_load_sum = p_load5 + p_load6 + p_load8
low_demand_ixs = sortperm(p_load_sum)
p_load_sum_sorted = p_load_sum[low_demand_ixs]
first_sorted_low_demand = 1
ix_low_demand = low_demand_ixs[first_sorted_low_demand]

tstamp_low_demand = tstamp[ix_low_demand]
gas_low_demand = p_th_sum[ix_low_demand]
load_low_demand = total_p_load[ix_low_demand]
wind_low_demand = p_gen_wind[ix_low_demand]
pv_low_demand = p_gen_pv[ix_low_demand]

# Find hour with max demand #
high_demand_ixs = sortperm(p_load_sum)
p_load_sum_sorted = p_load_sum[high_demand_ixs]
first_sorted_high_demand = length(p_load_sum_sorted)
ix_high_demand = high_demand_ixs[first_sorted_high_demand]

tstamp_high_demand = tstamp[ix_high_demand]
gas_high_demand = p_th_sum[ix_high_demand]
load_high_demand = p_load_sum[ix_high_demand]
wind_high_demand = p_gen_wind[ix_high_demand]
pv_high_demand = p_gen_pv[ix_high_demand]

# Find hour with max thermal: (Check if Max Net Load) #
high_thermal_ixs = sortperm(p_th_sum)
p_th_sum_sorted = p_th_sum[high_thermal_ixs]
first_sorted_high_thermal = length(p_th_sum_sorted)
ix_high_thermal = high_thermal_ixs[first_sorted_high_thermal]

tstamp_high_thermal = tstamp[ix_high_thermal]
ct_high_thermal = p_gen2[ix_high_thermal]
cc_high_thermal = p_gen3[ix_high_thermal]
gas_high_thermal = p_th_sum[ix_high_thermal]
load_high_thermal = total_p_load[ix_high_thermal]
wind_high_thermal = p_gen_wind[ix_high_thermal]
pv_high_thermal = p_gen_pv[ix_high_thermal]

# Add script for max-net-load
p_net_load = total_p_load - p_gen_wind - p_gen_pv
max_net_load_ix = argmax(p_net_load)
tstamp_max_net_load = tstamp[max_net_load_ix]