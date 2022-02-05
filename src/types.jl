Base.@kwdef mutable struct Repo
    url::String
end
StructType(::Type{Repo}) = StructTypes.Struct()

Base.@kwdef mutable struct Archive
    url::String
    sha256::Union{Nothing,String} = nothing
end
StructType(::Type{Archive}) = StructTypes.Struct()

Base.@kwdef mutable struct Artifact
    name::String
    tree_hash::String
    lazy::Bool = false
    depot_path::String = normpath("artifacts", tree_hash)

    # fields from HostPlatform
    arch::Union{Nothing,String}
    os::Union{Nothing,String}
    libc::Union{Nothing,String}
    libstdcxx_version::Union{Nothing,String}
    cxxstring_abi::Union{Nothing,String}
    julia_version::Union{Nothing,String}
    extra::Dict{String,Any} = Dict{String,Any}()

    archives::Vector{Archive} = Archive[]
end
StructType(::Type{Artifact}) = StructTypes.Struct()

Base.@kwdef mutable struct PackageInfo
    name::String
    uuid::UUID
    version::Union{Nothing,VersionNumber}
    tree_hash::String
    source::String
    depot_path::String = normpath("packages", name, Base.version_slug(uuid, Base.SHA1(tree_hash)))

    is_tracking_path::Bool
    is_tracking_repo::Bool
    is_tracking_registry::Bool

    repos::Vector{Repo} = Repo[]
    archives::Vector{Archive} = Archive[]
    artifacts::Vector{Artifact} = Artifact[]
end
StructType(::Type{PackageInfo}) = StructTypes.Struct()

Base.@kwdef mutable struct Depot 
    registries::Dict{String,Any} = Dict{String,Any}()
    packages::Dict{String,Any} = Dict{String,Any}()
    artifacts::Dict{String,Any} = Dict{String,Any}()
end
StructType(::Type{Depot}) = StructTypes.Struct()
