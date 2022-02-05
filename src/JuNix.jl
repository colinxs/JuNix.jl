module JuNix

# Write your package code here.

using Pkg: Pkg, Types, Operations, Registry
using Pkg.MiniProgressBars: MiniProgressBar, print_progress_bottom, show_progress, end_progress
using Pkg.Types: Context, EnvCache
using Artifacts: Artifacts
using Base: SHA1, UUID
using Base.BinaryPlatforms: AbstractPlatform, HostPlatform
using TOML
# using Git
using LibGit2
using Dates
# using ArgParse
using Printf
using SHA
using JSON3
using StructTypes: StructTypes, StructType
using Downloads: download


include("types.jl")
include("api.jl")

const GENERATED_FILENAME = "Depot.nix"

function collect_packages(ctx::Context, platforms::Vector{<:AbstractPlatform}, include_lazy::Bool)
    pkgs = PackageInfo[]
    deps = Pkg.dependencies(ctx.env)
    pkg_server = Pkg.pkg_server()
    for (uuid, dep) in deps
        (; name, version, tree_hash, is_tracking_path, is_tracking_repo, is_tracking_registry, source) = dep

        is_tracking_path && error("$name ($uuid) because it is tracking a local path: $source")
        tree_hash !== nothing || continue # stdlib

        pkg = PackageInfo(;
            name, uuid, version, tree_hash, source, is_tracking_path, is_tracking_repo, is_tracking_registry
        )
        load_repos!(pkg, ctx)
        load_archives!(pkg, ctx, pkg_server)
        load_artifacts!(pkg, ctx, pkg_server)
        push!(pkgs, pkg)
    end
    return pkgs
end

function load_repos!(pkg::PackageInfo, ctx::Context)
    if (pkg.is_tracking_registry || pkg.is_tracking_repo) && pkg.source !== nothing
        for url in Operations.find_urls(ctx.registries, pkg.uuid)
            @debug "Adding repo $repo_url to dependency $(pkg.name) ($(pkg.uuid))"
            push!(pkg.repos, Repo(; url))
        end
    end
    return pkg
end

function load_archives!(pkg::PackageInfo, ctx::Context, pkg_server)
    if pkg_server !== nothing
        url = "$pkg_server/package/$(pkg.uuid)/$(pkg.tree_hash)"
        @debug "Adding Pkg server archive $url to dependency $(pkg.name) ($(pkg.uuid))"
        push!(pkg.archives, Archive(; url))
    end
    for repo in pkg.repos
        url = Operations.get_archive_url_for_version(repo.url, pkg.tree_hash)
        url !== nothing && push!(pkg.archives, Archive(; url))
    end
    return pkg
end

function load_artifacts!(pkg::PackageInfo, ctx::Context, pkg_server)
    for (artifacts_toml, artifacts) in Operations.collect_artifacts(pkg.source)
        for (name, artifact) in artifacts
            archives = Archive[]
            if pkg_server !== nothing
                archive = Archive(; url="$pkg_server/artifact/$(pkg.tree_hash)")
                push!(archives, archive)
            end
            if haskey(artifact, "download")
                for d in artifact["download"] 
                    archive = Archive(; url=d["url"], sha256=d["sha256"])
                    push!(archives, archive)
                end
            else
                @warn "Artifact missing 'download' section: $(artifact.name) $(artifact.tree_hash)"
            end
            augmented = Artifact(;
                name,
                tree_hash=artifact["git-tree-sha1"],
                lazy=get(artifact, "lazy", false),
                arch=get(artifact, "arch", nothing),
                os=get(artifact, "os", nothing),
                libc=get(artifact, "libc", nothing),
                libstdcxx_version=get(artifact, "libstdcxx_version", nothing),
                cxxstring_abi=get(artifact, "cxxstring_abi", nothing),
                julia_version=get(artifact, "julia_version", nothing),
                extra=Dict{String,Any}(
                    k => v for (k, v) in artifact if !(
                        k in (
                            "lazy",
                            "arch",
                            "os",
                            "libc",
                            "libstdcxx_version",
                            "cxxstring_abi",
                            "jucxxstring_abilia_version",
                            "download",
                            "git-tree-sha1",
                        )
                    )
                ),
                archives,
            )
            push!(pkg.artifacts, augmented)
        end
    end
end

function generate_depot(pkgs::Vector{PackageInfo}, ctx::Context)
    depot = Depot() 
    (; registries, packages, artifacts) = depot
    for pkg in pkgs
        packages[pkg.tree_hash] = pkg
        for artifact in pkg.artifacts
            if haskey(artifacts, artifact.tree_hash)
                a = artifacts[artifact.tree_hash]
                b = artifact
                @warn "Artifact conflict detected. Attempting merge." a=artifacts[artifact.tree_hash].name b=artifact.name tree_hash=artifact.tree_hash
                for n in (:arch, :os, :libc, :libstdcxx_version, :cxxstring_abi, :julia_version)
                    if getfield(a, n) != getfield(b, n)
                        @warn "Merge failed" key=n a=getfield(a, n) b=getfield(b, n)
                        continue
                    end
                end
                a.lazy &= b.lazy
                for d in get(b, "download", [])
                    archive = Archive(; url=d["url"], sha256=d["sha256"])
                    push!(a.archives, archive)
                end
            else
                artifacts[artifact.tree_hash] = artifact
            end
        end
    end
    return depot 
end

function resolve_depot(depot::Depot, ctx::Context)
    (; registries, packages, artifacts) = depot

    jobs = Channel{Union{Artifact,PackageInfo}}(ctx.num_concurrent_downloads)
    results = Channel(ctx.num_concurrent_downloads)

    to_download = eltype(jobs)[]
    foreach(pkg -> push!(to_download, pkg), values(packages))
    foreach(artifact -> push!(to_download, artifact), values(artifacts))

    @sync begin
        @async begin
            foreach(job -> put!(jobs, job), to_download)
        end
        for i in 1:ctx.num_concurrent_downloads 
            @async begin
                for job in jobs
                    try
                        found = false
                        allerrors = CompositeException()
                        if job isa Artifact
                            res = resolve_archive!(job.archives)
                            res isa Exception && (append!(allerrors.errors, errors) && break)
                            put!(results, job => res)
                        elseif job isa PackageInfo
                            res = resolve_archive!(job.archives)
                            res isa Exception && (append!(allerrors.errors, errors) && break)
                            put!(results, job => res)
                            # for repo in job.repos
                            #     result = get_repo(repo)
                            #     result isa Exception && continue
                            #     found = true
                            #     put!(results, artifact => repo)
                            # end
                        end
                        isempty(allerrors) || put!(results, job => CompositeException(errors))
                    catch e
                        put!(results, job => e)
                    end
                end
            end
        end

        resolved = Depot() 
        bar = MiniProgressBar(; indent=2, header = "Progress", color = Base.info_color(),
                                  percentage=false, always_reprint=true)
        bar.max = length(to_download)
        fancyprint = Pkg.can_fancyprint(ctx.io)

        try
            for i=1:length(to_download)
                job, res = take!(results)
                bar.current = i
                # fancyprint && print_progress_bottom(ctx.io)
                res isa Exception && @error "Error downloading $(job.name) $(job.tree_hash)" exception=res 
                sha256 = res.sha256 === nothing ? nothing : to_nixhash(res.sha256)
                entry = res isa Archive ? (;type="archive", res.url, sha256, origsha256=res.sha256) : (;type="git", res.url, res.tree_hash)
                if job isa PackageInfo
                    entry = merge(entry, (;job.name, job.uuid , job.version))
                    resolved.packages[job.depot_path] = entry
                elseif job isa Artifact 
                    entry = merge(entry, (;job.name, job.lazy, job.arch, job.os, job.libc, job.libstdcxx_version, job.cxxstring_abi, job.julia_version))
                    resolved.artifacts[job.depot_path] = entry
                end
                fancyprint && show_progress(ctx.io, bar)
            end
        finally
            fancyprint && end_progress(ctx.io, bar)
            close(jobs)
            return resolved
        end
    end
end

function resolve_archive!(archives::Vector{Archive})
    errors = Exception[]
    for archive in archives
        io = IOBuffer()
        try
            # download(archive.url, io)
            # archive.sha256 === nothing && (archive.sha256 = bytes2hex(sha256(io)))
            file = download(archive.url)
            archive.sha256 === nothing && (archive.sha256 = nix_hashfile(file)) 
            return archive
        catch e
            e isa InterruptException ? rethrow() : push!(errors, e)
            # push!(errors, CapturedException(e, catch_backtrace()))
        end
    end
    return CompositeException(errors)
end

function to_nixhash(hash::String, type="sha256")
    read(`nix hash to-sri --type sha256 $hash`, String)
end

function nix_hashfile(path::String)
    read(`nix hash file --sri $path`, String)
end

end # module
