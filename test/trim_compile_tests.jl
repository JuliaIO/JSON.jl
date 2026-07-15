using StructUtils
using Test

const _TRIM_SAFE_ERROR_BUDGET = 0 # JSON typed/untyped parse + write, error budget zero
const _TRIM_SUPPORTED = VERSION >= v"1.12.0-rc1"
const _TRIM_PRE_RELEASE = !isempty(VERSION.prerelease)
const _JULIAC_ENTRYPOINT_EXPR = "using JuliaC; if isdefined(JuliaC, :main); JuliaC.main(ARGS); else JuliaC._main_cli(ARGS); end"

# Pkg.test() sets JULIA_LOAD_PATH restrictively, which prevents subprocesses
# from finding stdlib packages like Pkg.  Remove it so subprocesses get the
# default load path.
function _clean_cmd(cmd::Cmd)
    env = Dict{String,String}(k => v for (k, v) in ENV if k != "JULIA_LOAD_PATH")
    # juliac sessions must not execute precompile workloads: they would bake
    # JIT-only instances into the image for the verifier to reject
    env["JULIAC_DISABLE_PRECOMPILE_WORKLOADS"] = "1"
    return setenv(cmd, env)
end

function _trim_use_bundle()::Bool
    default = Sys.iswindows() ? "1" : "0"
    return get(ENV, "JSON_TRIM_BUNDLE", default) == "1"
end

function _setup_trim_env()
    # JuliaC requires Julia 1.12+ and can't be in [extras] without breaking
    # Pkg.test() on older Julia versions.  Create a temp project that dev's
    # StructUtils from the local checkout and adds JuliaC.
    json_path = normpath(joinpath(@__DIR__, ".."))
    # use whatever StructUtils this test session resolved: a dev checkout is
    # dev'd into the temp env; a registry copy is added normally
    su_path = normpath(joinpath(dirname(pathof(StructUtils)), ".."))
    su_setup = startswith(su_path, joinpath(homedir(), ".julia", "packages")) ?
        "Pkg.add(\"StructUtils\")" : "Pkg.develop(path=$(repr(su_path)))"
    env_path = mktempdir()
    julia = joinpath(Sys.BINDIR, Base.julia_exename())
    setup_script = joinpath(env_path, "setup.jl")
    # TODO: drop once Parsers.jl#207 (trim fixes for the float overflow-widening
    # ladder) is released — JSON's number parsing pulls Parsers' float path into
    # every workload graph
    write(setup_script, """
    import Pkg
    $(su_setup)
    Pkg.develop(path=$(repr(json_path)))
    Pkg.add(url="https://github.com/JuliaData/Parsers.jl", rev="trim-verifier-fixes")
    Pkg.add("JuliaC")
    """)
    println("[trim] setting up temp environment with JuliaC...")
    flush(stdout)
    exit_code, output, timed_out = _run_command_with_timeout(
        _clean_cmd(`$julia --startup-file=no --history-file=no --project=$env_path $setup_script`);
        timeout_s = 120.0, log_label = "setup"
    )
    rm(setup_script; force = true)
    if exit_code != 0 || timed_out
        println("[trim] setup FAILED (exit=$exit_code, timed_out=$timed_out)")
        println(output)
        error("failed to set up trim test environment")
    end
    println("[trim] temp environment ready")
    return env_path
end

function _run_trim_compile(project_path::String, script_path::String, output_name::String; timeout_s::Float64 = 120.0, bundle_dir::Union{Nothing, String} = nothing)
    julia_exe = joinpath(Sys.BINDIR, Base.julia_exename())
    cmd = if bundle_dir === nothing
        _clean_cmd(`$julia_exe --startup-file=no --history-file=no --code-coverage=none --project=$project_path -e $(_JULIAC_ENTRYPOINT_EXPR) -- --output-exe $output_name --project=$project_path --experimental --trim=safe $script_path`)
    else
        _clean_cmd(`$julia_exe --startup-file=no --history-file=no --code-coverage=none --project=$project_path -e $(_JULIAC_ENTRYPOINT_EXPR) -- --output-exe $output_name --bundle $bundle_dir --project=$project_path --experimental --trim=safe $script_path`)
    end
    return _run_command_with_timeout(cmd; timeout_s = timeout_s, log_label = "compile")
end

function _run_command_with_timeout(cmd::Cmd; timeout_s::Float64, log_label::String)
    output_path = tempname()
    out = open(output_path, "w")
    exit_code = -1
    timed_out = false
    try
        proc = run(pipeline(ignorestatus(cmd), stdout = out, stderr = out); wait = false)
        timed_out = _wait_process_with_timeout!(proc; timeout_s = timeout_s, log_label = log_label)
        exit_code = something(proc.exitcode, -1)
    finally
        close(out)
    end
    output = try
        read(output_path, String)
    catch
        ""
    finally
        rm(output_path; force = true)
    end
    return exit_code, output, timed_out
end

function _wait_process_with_timeout!(proc::Base.Process; timeout_s::Float64, log_label::String)
    started_at = time()
    next_log_at = started_at + 10.0
    timed_out = false
    while Base.process_running(proc)
        now = time()
        if now - started_at >= timeout_s
            timed_out = true
            try; kill(proc); catch; end
            break
        end
        if now >= next_log_at
            elapsed = round(now - started_at; digits = 1)
            println("[trim] $(log_label) WAIT $(elapsed)s")
            flush(stdout)
            next_log_at = now + 10.0
        end
        sleep(0.1)
    end
    try; wait(proc); catch; end
    return timed_out
end

function _parse_trim_verify_totals(output::String)
    m = match(r"Trim verify finished with\s+(\d+)\s+errors,\s+(\d+)\s+warnings\.", output)
    m === nothing && return nothing
    return parse(Int, m.captures[1]), parse(Int, m.captures[2])
end

function _trim_executable_timeout_s()::Float64
    default = Sys.iswindows() ? "120.0" : "30.0"
    return parse(Float64, get(ENV, "JSON_TRIM_EXE_TIMEOUT_S", default))
end

function _run_trim_case(project_path::String, script_file::String, output_name::String)
    script_path = joinpath(@__DIR__, script_file)
    @test isfile(script_path)
    println("[trim] compile START $(script_file)")
    start_t = time()
    mktempdir() do tmpdir
        cd(tmpdir) do
            bundle_dir = _trim_use_bundle() ? joinpath(tmpdir, "bundle") : nothing
            exit_code, output, timed_out = _run_trim_compile(project_path, script_path, output_name; bundle_dir = bundle_dir)
            if timed_out
                println("[trim] compile TIMED OUT for $(script_file)")
                println(output)
                @test false
                return
            end
            totals = _parse_trim_verify_totals(output)
            trim_errors, trim_warnings = if totals === nothing
                exit_code == 0 ? (0, 0) : error("failed to parse trim verifier summary:\n$output")
            else
                totals
            end
            if get(ENV, "JSON_TRIM_PRINT_OUTPUT", "0") == "1" || trim_errors > 0
                println("---- trim compile output ($(script_file)) ----")
                println(output)
                println("---- end output ----")
            end
            @test trim_errors <= _TRIM_SAFE_ERROR_BUDGET
            @test trim_warnings >= 0
            output_path = Sys.iswindows() ? "$(output_name).exe" : output_name
            if trim_errors == 0
                run_path = bundle_dir === nothing ? output_path : joinpath(bundle_dir, "bin", output_path)
                @test exit_code == 0
                @test isfile(run_path)
                run_timeout_s = _trim_executable_timeout_s()
                run_cmd = `$(abspath(run_path))`
                run_exit, run_output, run_timed_out = _run_command_with_timeout(run_cmd; timeout_s = run_timeout_s, log_label = "run")
                if run_timed_out
                    println("[trim] executable TIMED OUT for $(script_file)")
                    println(run_output)
                end
                if run_exit != 0
                    println("---- trim executable output ($(script_file)) ----")
                    println(run_output)
                    println("---- end output ----")
                end
                @test !run_timed_out
                @test run_exit == 0
            else
                @test exit_code != 0
            end
        end
    end
    println("[trim] compile DONE $(script_file) ($(round(time() - start_t; digits = 2))s)")
    return nothing
end

@testset "Trim compile" begin
    if !_TRIM_SUPPORTED
        println("[trim] skip Julia < 1.12: JuliaC trim compilation is unavailable")
        @test true
    elseif _TRIM_PRE_RELEASE
        println("[trim] skip prerelease Julia: trim verifier behavior is not stable yet")
        @test true
    else
        project_path = _setup_trim_env()
        # trim builds set the trim_build preference: it prunes the tier-0
        # tree route (and its invokelatest classic boundary) out of the
        # typed-parse entry, leaving the :hot lazy descent's static graph
        write(joinpath(project_path, "LocalPreferences.toml"),
            "[StructUtils]\ntrim_build = true\n")
        _run_trim_case(project_path, "hot_lazy_trim_safe.jl", "hot_lazy_trim_safe")
    end
end
