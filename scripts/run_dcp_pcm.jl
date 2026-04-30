# =============================================================================
# run_dcp_pcm.jl
#
# Runs a Production Cost Model (PCM) with a DC Power Flow network
# (DCPPowerModel) for the IEEE 9-bus system over 30 days in July.
#
# Unlike the copper-plate model, DCPPowerModel enforces transmission line
# flow limits using a linearized (lossless) DC approximation. This allows
# the optimizer to respect congestion and compute locational prices.
#
# Generator formulation: ThermalDispatchNoMin (continuous, no min-output)
# Network elements: Lines and 2-winding transformers are included as
#                   StaticBranch (DC flow, no losses).
#
# Prerequisite: run generate_system.jl to create ieee9_sienna.json
# =============================================================================

using PowerSystems
using PowerSystemCaseBuilder
using PowerSimulations
using Dates
using HiGHS
using PlotlyJS
const PSI = PowerSimulations

sys = System("saved_systems/ieee9_sienna.json")
transform_single_time_series!(sys, Hour(24), Hour(24))
p_flow_load = sum(get_max_active_power.(get_components(StandardLoad, sys))) * 100.0

solver = optimizer_with_attributes(HiGHS.Optimizer)
# DCPPowerModel: linearized DC power flow, respects line thermal limits
template = ProblemTemplate(DCPPowerModel)
PSI.set_device_model!(template, StandardLoad, StaticPowerLoad)
PSI.set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
# Include network branches so line limits are enforced
PSI.set_device_model!(template, Line, StaticBranch)
PSI.set_device_model!(template, Transformer2W, StaticBranch)

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

sim = PSI.Simulation(;
    name = "ieee9-test",
    steps = 30,
    models = models,
    sequence = sequence,
    simulation_folder = mktempdir(),
    initial_time = DateTime("2020-07-01T00:00:00"),
)

build!(sim)
PSI.execute!(sim; enable_progress_bar = true)
results = PSI.SimulationResults(sim);
uc_results = get_decision_problem_results(results, "UC")
p_th = read_realized_variable(uc_results, "ActivePowerVariable__ThermalStandard"; table_format = TableFormat.WIDE)
p_load = read_realized_parameter(uc_results, "ActivePowerTimeSeriesParameter__StandardLoad"; table_format = TableFormat.WIDE)
cost_th = read_realized_expression(uc_results, "ProductionCostExpression__ThermalStandard"; table_format = TableFormat.WIDE)
total_cost = sum(cost_th[!, "generator-3-1"]) + sum(cost_th[!, "generator-2-1"]) + sum(cost_th[!, "generator-1-1"])

tstamp = p_th[!, 1]
p_gen1 = p_th[!, "generator-1-1"]
p_gen2 = p_th[!, "generator-2-1"]
p_gen3 = p_th[!, "generator-3-1"]
p_load5 = -p_load[!, "load51"]
p_load6 = -p_load[!, "load61"]
p_load8 = -p_load[!, "load81"]
total_p_load = p_load5 + p_load6 + p_load8

plot([
    scatter(
        x = tstamp,
        y = p_gen1,
        mode = "lines",
        name = "Coal Gen",
        line = attr(color = "brown"),
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
        title = "Coal and Gas case: Total Cost $(round(total_cost, digits=1))",
    ),
)