using Test

# Get all Julia scripts in the scripts folder
scripts_dir = joinpath(@__DIR__, "..", "scripts")
script_files = filter(f -> endswith(f, ".jl"), readdir(scripts_dir))

@testset "Example Scripts" begin
    for script in script_files
        @testset "$script" begin
            script_path = joinpath(scripts_dir, script)
            @test begin
                include(script_path)
                true
            end
        end
    end
end