export generate

# TODO
# load triplet from flake or drv 
    

# generate(mod::Module, args...; kwargs...) = generate(pkgdir(mod), args...; kwargs...)
# function generate(path::String; platforms::Vector{AbstractPlatform}=[HostPlatform()], include_lazy::Bool=false)
function generate(
    env_path::String = pwd(),
    platforms::Vector{<:AbstractPlatform}=[HostPlatform()],
    include_lazy::Bool=false,
    out_path::AbstractString="Depot.json",
    registries = Pkg.Registry.reachable_registries()
)
    ctx = Context(; registries, env=EnvCache(Types.projectfile_path(env_path)))
    pkgs = collect_packages(ctx, platforms, include_lazy)
    depot = resolve_depot(generate_depot(pkgs, ctx), ctx)
    # depot = generate_depot(pkgs, ctx) 

    open(out_path, "w") do io_out
        if success(`prettier --help`)
            open(pipeline(`prettier --parser json`, io_out), write=true) do io_in 
                JSON3.write(io_in, depot)
            end
        else
            JSON3.write(io_out, depot)
        end
    end
end

function printtypes(x::AbstractDict, indent="")
    for (k, v) in x
        print(indent, k, "=>")
        printtypes(v, indent * "  ")
    end
end
printtypes(x, indent) = println(indent, typeof(x))
