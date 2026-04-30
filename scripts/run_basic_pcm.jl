using PowerSystems
using PowerSystemCaseBuilder
using PowerSimulations
using Dates
using HiGHS
using PlotlyJS
const PSI = PowerSimulations
sys = System("saved_systems/ieee9_sienna.json")
transform_single_time_series!(sys, Hour(24), Hour(24))
p_flow_load = sum(get_max_active_power.(get_components(StandardLoad, sys))) 
th_max_power = sum(get_max_active_power.(get_components(ThermalStandard, sys)))

solver = optimizer_with_attributes(HiGHS.Optimizer)
template = ProblemTemplate(CopperPlatePowerModel)
set_device_model!(template, StandardLoad, StaticPowerLoad)
set_device_model!(template, ThermalStandard, ThermalDispatchNoMin)
#set_device_model!(template, ThermalStandard, ThermalBasicUnitCommitment)

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
    steps = 365,
    models = models,
    sequence = sequence,
    simulation_folder = mktempdir(),
    #initial_time = DateTime("2020-07-01T00:00:00"),
)

build!(sim)
PSI.execute!(sim; enable_progress_bar = true)
results = PSI.SimulationResults(sim);
uc_results = get_decision_problem_results(results, "UC")
p_th = read_realized_variable(uc_results, "ActivePowerVariable__ThermalStandard"; table_format = TableFormat.WIDE)
p_load = read_realized_parameter(uc_results, "ActivePowerTimeSeriesParameter__StandardLoad"; table_format = TableFormat.WIDE)

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
        name = "Generator 1",
        line = attr(color = "blue"),
    ),
    scatter(
        x = tstamp,
        y = p_gen2,
        mode = "lines",
        name = "Generator 2",
        line = attr(color = "green"),
    ),
    scatter(
        x = tstamp,
        y = p_gen3,
        mode = "lines",
        name = "Generator 3",
        line = attr(color = "red"),
    ),
    #scatter(
    #    x = tstamp,
    #    y = total_p_load,
    #    mode = "lines",
    #    name = "Total Load",
    #    line = attr(color = "black", dash = "dash"),
    #)
], Layout(
    title = "Thermal Generation Dispatch Over Time",
    xaxis = attr(title = "Time"),
    yaxis = attr(title = "Active Power (MW)"),
    template = "plotly_white",
))