module RegressionDiscontinuity

using Reexport

import Base: size, getindex, getproperty, propertynames, show

using DataFrames
@reexport using Distributions
using FastGaussQuadrature
using Feather
using Intervals
using LinearAlgebra
using GLM
using OffsetArrays
using QuadGK
using RecipesBase
using Setfield
using Statistics
import Statistics: var
@reexport using StatsBase
import StatsBase: fit, weights, nobs
using StatsModels

using Tables

using UnPack


include("running_variable.jl")
include("load_example_data.jl")
include("kernels.jl")
include("imbens_kalyanaraman.jl")
include("local_linear.jl")

export RunningVariable,
    Treated,
    Untreated,
    load_rdd_data,
    Rectangular,
    bandwidth,
    ImbensKalyanaraman,
    linearweights,
    EickerHuberWhite,
    NaiveLocalLinearRD


end
