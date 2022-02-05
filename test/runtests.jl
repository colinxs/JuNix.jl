# using JuNix
using Test
using Base: SHA1
using SHA
using Pkg.GitTools: tree_hash

function dirs_generator(path)
    (relpath(joinpath(root, dir), path) for (root, dirs, files) in walkdir(path) for dir in dirs) 
end

function files_generator(path)
    (relpath(joinpath(root, file), path) for (root, dirs, files) in walkdir(path) for file in files) 
end
function verify_tree2(a, b)
    diff = Dict{String,Union{Missing,Tuple{SHA1,SHA1}}}()
    for rpath in files_generator(a)
        apath = joinpath(a, rpath)
        bpath = joinpath(b, rpath)
        ahash = bytes2hex(sha256(read(apath))) 
        bhash = bytes2hex(sha256(read(apath))) 
        ahash == bhash || (diff[rpath]=(ahash,bhash))
    end
    return diff 
end

function verify_tree(a, b)
    diff = Dict{String,Union{Missing,Tuple{SHA1,SHA1}}}()
    for rpath in dirs_generator(a)
        apath = joinpath(a, rpath)
        bpath = joinpath(b, rpath)
        if isdir(bpath) 
            ahash = SHA1(tree_hash(apath)) 
            bhash = SHA1(tree_hash(bpath)) 
            ahash == bhash || (diff[rpath]=(ahash,bhash))
        else
            diff[rpath]=missing
        end
    end
    return diff 
end
#
# @testset "JuNix.jl" begin
#     # Write your tests here.
# end
