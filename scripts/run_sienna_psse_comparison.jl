# =============================================================================
# run_sienna_psse_comparison.jl
#
# Validates the PowerSimulationsDynamics (Sienna) dynamic model against
# PSS/E reference results for the IEEE 9-bus non-renewable-energy (NRE) case.
#
# Perturbation: trip of line BUS5-BUS7 at t = 1 s (20-second simulation).
#
# Workflow:
#   1. Build the Sienna system from .raw + .dyr files.
#   2. Run the dynamic simulation and extract voltage and speed time series.
#   3. Load the matching PSS/E CSV results from psspy-scripts/results/.
#   4. Overlay both on the same PlotlyJS plots for visual comparison.
#
# Output:
#   - Overlay plot of bus voltage magnitudes (all 9 buses)
#   - Overlay plot of generator speeds (GEN1, GEN2, GEN3)
# =============================================================================

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
using CSV
using DataFrames
const PSY = PowerSystems
const PSID = PowerSimulationsDynamics
const PF = PowerFlows

######################
### Data Exploring ###
######################

raw_path = "raw_data/scenarios/RTS_Esc487MW.raw"
dyr_path = "raw_data/RTS_CtrlsModified_STAB1.dyr"
sys = System(raw_path, dyr_path)

pf = solve_power_flow(ACPowerFlow(), sys)  # confirm steady-state before perturbing

# Constant-impedance loads improve solver convergence and match PSSE load modeling
for l in get_components(StandardLoad, sys)
    transform_load_to_constant_impedance(l)
end

###################################
### Simulation Setup: Line Trip ###
###################################

#### BranchTrip ####
time_span = (0.0, 20.0)
perturbation_trip = BranchTrip(1.0, Line, "BUS5-BUS7-i_1")

# ConstantFrequency reference: frequency is held fixed externally (infinite bus assumption)
# saveat = 0.01 s matches the PSS/E output resolution for a clean comparison
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

PSID.execute!(sim, IDA(),  abstol = 1e-4, reltol = 1e-4, saveat = 0.01)

results = read_results(sim)

voltage_sienna_plots_line_trip = [scatter(x = get_voltage_magnitude_series(results, bus_number)[1], y = get_voltage_magnitude_series(results, bus_number)[2], name = "Sienna: BUS$bus_number", line = attr(color = "black", dash = "dot") ) for bus_number in 1:9]; #line = attr(color = "black", dash = "dot")
speed_sienna_plots_line_trip = [
    scatter(x = get_state_series(results, ("generator-1-1", :ω))[1], y = get_state_series(results, ("generator-1-1", :ω))[2], name = "Sienna: GEN1", line = attr(color = "black", dash = "dot"))
    scatter(x = get_state_series(results, ("generator-2-1", :ω))[1], y = get_state_series(results, ("generator-2-1", :ω))[2], name = "Sienna: GEN2", line = attr(color = "black", dash = "dot"))
    scatter(x = get_state_series(results, ("generator-3-1", :ω))[1], y = get_state_series(results, ("generator-3-1", :ω))[2], name = "Sienna: GEN3", line = attr(color = "black", dash = "dot"))
];

#### PSSE Plotting ####
# Read PSS/E CSV exports produced by the psspy-scripts/main.py workflow
voltage_mag_df_line_trip = CSV.read("psspy-scripts/results/line_trip_5-7/case_NRE/case_NRE_line_fault_All_20s_VOLT.csv", DataFrame)
speed_df_line_trip = CSV.read("psspy-scripts/results/line_trip_5-7/case_NRE/case_NRE_line_fault_All_20s_SPEED.csv", DataFrame)

t_psse = speed_df_line_trip[3:end, 1]
ω_line_trip_gen1 = speed_df_line_trip[3:end, "GEN_BUS1"]
ω_line_trip_gen2 = speed_df_line_trip[3:end, "GEN_BUS2"]
ω_line_trip_gen3 = speed_df_line_trip[3:end, "GEN_BUS3"]

voltage_mag_line_trip_psse = Dict()
bus_names = names(voltage_mag_df_line_trip[!, 2:end])
for col_name in bus_names
    voltage_mag_line_trip_psse[col_name] = voltage_mag_df_line_trip[!, col_name]
end

voltage_psse_plots_line_trip = [scatter(x = t_psse, y = voltage_mag_line_trip_psse[col_name], name = "PSSE: $col_name") for col_name in bus_names];
speed_psse_plots_line_trip = [
    scatter(x = t_psse, y = ω_line_trip_gen1, name = "PSSE: GEN1", line = attr(color = "blue")),
    scatter(x = t_psse, y = ω_line_trip_gen2, name = "PSSE: GEN2", line = attr(color = "red")),
    scatter(x = t_psse, y = ω_line_trip_gen3, name = "PSSE: GEN3", line = attr(color = "green")),
];
#vcat(voltage_psse_plots_line_trip, voltage_sienna_plots_line_trip)
plot( vcat(voltage_psse_plots_line_trip, voltage_sienna_plots_line_trip),
    Layout(
        title="Bus Voltage Magnitude after Line 5-7 Trip",
        xaxis_title="Time (s)",
        yaxis_title="Voltage Magnitude (p.u.)",
    ),
)
# vcat(speed_psse_plots_line_trip, speed_sienna_plots_line_trip)
plot(vcat(speed_psse_plots_line_trip, speed_sienna_plots_line_trip),
    Layout(
        title="Generator Speed after Line 5-7 Trip",
        xaxis_title="Time (s)",
        yaxis_title="Speed (p.u.)",
    ),
)
