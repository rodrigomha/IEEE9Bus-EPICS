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
using PowerSystemCaseBuilder
const PSY = PowerSystems
const PSID = PowerSimulationsDynamics
const PF = PowerFlows

######################
### Data Exploring ###
######################

raw_path = "raw_data/scenarios/RTS_Esc487MW.raw"
dyr_path = "raw_data/RTS_CtrlsModified_STAB1.dyr"
sys = System(raw_path, dyr_path)

pf = solve_power_flow(ACPowerFlow(), sys)
pf["bus_results"]

########################
### Simulation Setup ###
########################

#### BranchTrip ####
time_span = (0.0, 20.0)
perturbation_trip = BranchTrip(1.0, Line, "BUS5-BUS7-i_1")
gen = get_component(DynamicInjection, sys, "generator-2-1")
perturbation_change = ControlReferenceChange(11.0, gen, :P_ref, 0.7)
gen1 = get_component(DynamicInjection, sys, "generator-1-1")
perturbation_gen = GeneratorTrip(1.0, gen1)

sim = PSID.Simulation(
    ResidualModel, # Type of formulation: Residual for using Sundials with IDA
    sys, # System
    mktempdir(), # Output directory
    time_span,
    perturbation_change
    #perturbation_trip;
    #perturbation_gen
)

show_states_initial_value(sim)

PSID.execute!(sim, IDA(), abstol = 1e-3, reltol = 1e-3)

results = read_results(sim)
t, v = get_voltage_magnitude_series(results, 7)
plot(t, v)