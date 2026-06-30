using Test
using JSON
import Pkg

const _TRIM_SUPPORTED = VERSION >= v"1.12.0-rc1"
const _JULIAC_ENTRYPOINT_EXPR = "using JuliaC; if isdefined(JuliaC, :main); JuliaC.main(ARGS); else JuliaC._main_cli(ARGS); end"
const _TRIM_COMPILE_TIMEOUT_S = 300.0
const _TRIM_RUN_TIMEOUT_S = 60.0

function _json_project_path()::String
    return normpath(joinpath(dirname(pathof(JSON)), ".."))
end

function _prepare_trim_project(project_path::String, trim_project::String)::Nothing
    mkpath(trim_project)
    cp(joinpath(@__DIR__, "trim", "Project.toml"), joinpath(trim_project, "Project.toml"))
    original_project = Base.active_project()
    try
        Pkg.activate(trim_project)
        Pkg.develop(Pkg.PackageSpec(path = project_path))
        Pkg.instantiate()
    finally
        if original_project !== nothing
            Pkg.activate(dirname(original_project))
        end
    end
    return nothing
end

function _run_command_with_timeout(cmd::Cmd; timeout_s::Float64, log_label::String)
    output_path = tempname()
    out = open(output_path, "w")
    exit_code = -1
    timed_out = false
    try
        proc = run(pipeline(ignorestatus(cmd), stdout = out, stderr = out); wait = false)
        timed_out = _wait_process_with_timeout!(proc; timeout_s, log_label)
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

function _wait_process_with_timeout!(proc::Base.Process; timeout_s::Float64, log_label::String)::Bool
    started_at = time()
    next_log_at = started_at + 10.0
    while Base.process_running(proc)
        now = time()
        if now - started_at >= timeout_s
            try
                kill(proc)
            catch
            end
            return true
        end
        if now >= next_log_at
            elapsed = round(now - started_at; digits = 1)
            println("[trim] $(log_label) WAIT $(elapsed)s")
            flush(stdout)
            next_log_at = now + 10.0
        end
        sleep(0.1)
    end
    try
        wait(proc)
    catch
    end
    return false
end

function _trim_timeout_error(kind::String, script_file::String, output::String = "")
    msg = "trim $(kind) timed out for $(script_file)"
    if !isempty(output)
        msg = string(msg, "\n---- captured output ----\n", output, "\n---- end captured output ----")
    end
    throw(ArgumentError(msg))
end

function _maybe_print_output(header::String, output::String)::Nothing
    isempty(output) && return nothing
    println(header)
    println(output)
    println("---- end output ----")
    return nothing
end

function _run_trim_compile(trim_project::String, script_path::String, output_name::String)
    julia_exe = joinpath(Sys.BINDIR, Base.julia_exename())
    cmd = `$julia_exe --startup-file=no --history-file=no --code-coverage=none --project=$trim_project -e $(_JULIAC_ENTRYPOINT_EXPR) -- --output-exe $output_name --project=$trim_project --experimental --trim=safe $script_path`
    return _run_command_with_timeout(cmd; timeout_s = _TRIM_COMPILE_TIMEOUT_S, log_label = "compile")
end

function _run_trim_executable(run_path::String)
    return _run_command_with_timeout(`$(abspath(run_path))`; timeout_s = _TRIM_RUN_TIMEOUT_S, log_label = "run")
end

function _parse_trim_verify_totals(output::String)
    m = match(r"Trim verify finished with\s+(\d+)\s+errors,\s+(\d+)\s+warnings\.", output)
    m === nothing && return nothing
    return parse(Int, m.captures[1]), parse(Int, m.captures[2])
end

function _count_trim_verify_messages(output::String)::Tuple{Int, Int}
    errors = length(collect(eachmatch(r"Verifier error #\d+:", output)))
    warnings = length(collect(eachmatch(r"Verifier warning #\d+:", output)))
    return errors, warnings
end

function _run_trim_case(trim_project::String, script_file::String, output_name::String)::Nothing
    script_path = joinpath(@__DIR__, script_file)
    @test isfile(script_path)
    println("[trim] compile START $(script_file)")
    start_t = time()
    mktempdir() do tmpdir
        cd(tmpdir) do
            exit_code, output, timed_out = _run_trim_compile(trim_project, script_path, output_name)
            timed_out && _trim_timeout_error("compile", script_file, output)
            totals = _parse_trim_verify_totals(output)
            trim_errors, trim_warnings = if totals === nothing
                fallback = _count_trim_verify_messages(output)
                if exit_code == 0 && fallback == (0, 0)
                    fallback
                else
                    error("failed to parse trim verifier summary:\n$output")
                end
            else
                totals
            end
            if trim_errors > 0 || trim_warnings > 0
                _maybe_print_output("---- trim compile output ($(script_file)) ----", output)
            end
            @test trim_errors == 0
            @test trim_warnings == 0
            output_path = Sys.iswindows() ? "$(output_name).exe" : output_name
            @test exit_code == 0
            @test isfile(output_path)
            run_exit, run_output, run_timed_out = _run_trim_executable(output_path)
            run_timed_out && _trim_timeout_error("executable run", script_file, run_output)
            if run_exit != 0
                _maybe_print_output("---- trim executable output ($(script_file)) ----", run_output)
            end
            @test run_exit == 0
        end
    end
    println("[trim] compile DONE $(script_file) ($(round(time() - start_t; digits = 2))s)")
    return nothing
end

@testset "Trim compile" begin
    if Sys.iswindows()
        println("[trim] skip Windows: JuliaC trim compilation is currently too slow or stalls on Windows CI")
        @test true
    elseif Sys.WORD_SIZE != 64
        println("[trim] skip 32-bit Julia: JuliaC trim compilation is only covered on 64-bit test jobs")
        @test true
    elseif !_TRIM_SUPPORTED
        println("[trim] skip Julia < 1.12: JuliaC trim compilation is unavailable")
        @test true
    else
        project_path = _json_project_path()
        mktempdir() do tmpdir
            trim_project = joinpath(tmpdir, "trim_project")
            _prepare_trim_project(project_path, trim_project)
            _run_trim_case(trim_project, "json_trim_public_entrypoints.jl", "json_trim_public_entrypoints")
        end
    end
end
