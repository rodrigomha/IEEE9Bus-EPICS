using Pkg
Pkg.activate(".")
Pkg.instantiate()

using PowerSimulationsDynamics
using PowerSystems
using Logging
using PowerFlows
using Sundials
using PlotlyJS
using PowerNetworkMatrices
using SparseArrays
using PowerSystemCaseBuilder
using OrdinaryDiffEq
using CSV
using DataFrames
const PSY = PowerSystems
const PSID = PowerSimulationsDynamics
const PF = PowerFlows

######################
### Data Exploring ###
######################

raw_path = "raw_data/scenarios/RTS_Esc487MW.raw"
dyr_path = "raw_data/RTS_CtrlsModified_RE.dyr"
sys = System(raw_path, dyr_path)

pf = solve_power_flow(ACPowerFlow(), sys)

for l in get_components(StandardLoad, sys)
    transform_load_to_constant_impedance(l)
end

###################################
### Simulation Setup: Line Trip ###
###################################

#### BranchTrip ####
time_span = (0.0, 20.0)
perturbation_trip = BranchTrip(0.5, Line, "BUS5-BUS7-i_1")

sim = PSID.Simulation(
    ResidualModel, # Type of formulation: Residual for using Sundials with IDA
    sys, # System
    mktempdir(), # Output directory
    time_span,
    #perturbation_change
    perturbation_trip;
    frequency_reference = ConstantFrequency(),
    #perturbation_gen
)

show_states_initial_value(sim)

PSID.execute!(sim, IDA(), dtmax = 0.02, abstol = 1e-4, reltol = 1e-4)

results = read_results(sim)

voltage_sienna_plots_line_trip = [scatter(x = get_voltage_magnitude_series(results, bus_number)[1], y = get_voltage_magnitude_series(results, bus_number)[2], name = "Sienna: BUS$bus_number", line = attr(color = "black", dash = "dot")) for bus_number in 1:9];

plot(voltage_sienna_plots_line_trip,
    Layout(
        title="Bus Voltage Magnitude after Line 5-7 Trip",
        xaxis_title="Time (s)",
        yaxis_title="Voltage Magnitude (p.u.)",
    ),
)