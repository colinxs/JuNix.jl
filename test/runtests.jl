using JuNix
using Test
using Base.SHA1
using Pkg.GitTools: tree_hash

function paths_generator(path)
    (relpath(joinpath(root, dir), path) for (root, dirs, files) in walkdir(path) for dir in dirs) 
end

function verify_tree(a, b)
    diff = Dict{String,Union{Missing,Tuple{SHA1,SHA1}}}()
    for rpath in paths_generator(a)
        apath = joinpath(a, rpath)
        bpath = joinpath(b, rpath)
        if isdir(bpath) 
            ahash = SHA1(tree_hash(apath)) 
            bhash = SHA1(tree_hash(bpath)) 
            ahash == bhash || push!(diff, (ahash,bhash))
        else
            push!(diff, missing)
        end
    end
    return diff 
end

@testset "JuNix.jl" begin
    # Write your tests here.
end
