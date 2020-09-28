struct RunningVariable{T, C, VT} <: AbstractVector{T}
	Zs::VT
	cutoff::C
	treated::Symbol
	Ws::BitArray{1}
	function RunningVariable{T, C, VT}(Zs::VT, cutoff::C, treated) where {T, C, VT}
		treated = Symbol(treated)
		if treated ∉ [:>; :>=; :≥; :≧; :<; :<=; :≤; :≦]
			error("treated should be one of [:>; :>=; :≥; :≧; :<; :<=; :≤; :≦ ]")
		elseif treated ∈ [:>=; :≥;  :≧]
			treated = :≥
		elseif treated ∈ [:<=; :≤; :≦]
			treated = :≤
		end
		Ws = broadcast(getfield(Base, treated), Zs, cutoff)
		new(Zs, cutoff, treated, Ws)
	end
end

function RunningVariable(Zs::VT, cutoff::C, treated) where {C,VT}
	RunningVariable{eltype(VT), C, VT}(Zs, cutoff, treated)
end

RunningVariable(Zs; cutoff=0.0, treated = :≥) = RunningVariable(Zs, cutoff, treated)

Base.size(ZsR::RunningVariable) = Base.size(ZsR.Zs)
StatsBase.nobs(ZsR::RunningVariable) = length(ZsR)

Base.@propagate_inbounds function Base.getindex(ZsR::RunningVariable, x::Int)
    @boundscheck checkbounds(ZsR.Zs, x)
    @inbounds ret = getindex(ZsR.Zs, x)
    return ret
end

Base.@propagate_inbounds function Base.getindex(ZsR::RunningVariable, i::AbstractArray) 
    @boundscheck checkbounds(ZsR, i)
    @inbounds Zs = ZsR.Zs[i]
    RunningVariable(Zs, ZsR.cutoff, ZsR.treated)
end




# Tables interface

Tables.istable(ZsR::RunningVariable) = true 
Tables.columnaccess(ZsR::RunningVariable) = true
Tables.columns(ZsR::RunningVariable) = (Ws = ZsR.Ws, Zs = ZsR.Zs, cutoff= fill(ZsR.cutoff, nobs(ZsR)))
function Tables.schema(ZsR::RunningVariable) 
    Tables.Schema((:Ws, :Zs, :cutoff), (eltype(ZsR.Ws), eltype(ZsR.Zs), typeof(ZsR.cutoff)))
end


function fit(::Type{Histogram{T}}, ZsR::RunningVariable; nbins=StatsBase.sturges(length(ZsR))) where {T}
   @unpack cutoff, Zs, treated = ZsR
   if treated in [:<; :≥]
      closed = :left
   else
      closed = :right
   end 
   nbins =  iseven(nbins) ? nbins : nbins + 1
   
   min_Z, max_Z = extrema(Zs)

   bin_width = (max_Z - min_Z)*1.01/nbins

   prop_right = (max_Z - cutoff)*1.01/(max_Z - min_Z)
   prop_left = (cutoff - min_Z)*1.01/(max_Z - min_Z)
   nbins_right = ceil(Int, nbins * prop_right)
   nbins_left = ceil(Int, nbins * prop_left)

   breaks_left = reverse(range(cutoff; step=-bin_width, length=nbins_left))
   breaks_right = range(cutoff; step=bin_width, length=nbins_right)
   
   breaks = collect(sort(unique([breaks_left; breaks_right])))
      
   fit(Histogram{T}, ZsR, breaks; closed=closed)
end


@recipe function f(ZsR::RunningVariable)
	
   nbins = get(plotattributes, :bins,  StatsBase.sturges(length(ZsR)))

   fitted_hist = fit(Histogram, ZsR; nbins=nbins)
   
   yguide --> "Frequency"
   xguide --> "Running variable"
   grid --> false 
   label --> nothing 
   fillcolor --> :lightgray
   thickness_scaling --> 1.7
   linewidth --> 0.3
   ylims --> (0, 1.5 * maximum(fitted_hist.weights))
   
   @series begin
      fitted_hist
   end
   
   @series begin
      seriestype := :vline
      linecolor := :purple
      linestyle := :dash
      linewidth := 1.7
      [ZsR.cutoff]
    end
end



struct RDData{V, R<:RunningVariable}
	Ys::V
	ZsR::R
end

StatsBase.nobs(rdd_data::RDData) = nobs(rdd_data.ZsR)

Base.@propagate_inbounds function Base.getindex(rdd_data::RDData, i::AbstractArray) 
    @boundscheck checkbounds(rdd_data.Ys, i)
	@boundscheck checkbounds(rdd_data.ZsR, i)

	@inbounds Ys = rdd_data.Ys[i]
    @inbounds ZsR = rdd_data.ZsR[i]
    RDData(Ys, ZsR)
end

# Tables interface

Tables.istable(::RDData) = true 
Tables.columnaccess(::RDData) = true
Tables.columns(rdd_data::RDData) = merge((Ys = rdd_data.Ys,), Tables.columns(rdd_data.ZsR))
function Tables.schema(rdd_data::RDData) 
    Tables.Schema((:Ys, :Ws, :Zs, :cutoff), (eltype(rdd_data.Ys), eltype(rdd_data.ZsR.Ws), eltype(rdd_data.ZsR.Zs), typeof(cutoff)))
end


function Base.getproperty(obj::RDData, sym::Symbol)
     if sym in (:Ys, :ZsR)
         return getfield(obj, sym)
     else 
         return getfield(obj.ZsR, sym)
     end
end

function Base.propertynames(obj::RDData)
   (Base.fieldnames(typeof(obj))..., Base.fieldnames(typeof(obj.ZsR))...)
end



abstract type RDDIndexing end
	
struct Treated <: RDDIndexing end
struct Untreated <: RDDIndexing end 

function Base.getindex(ZsR::R, i::RealInterval) where R<:Union{RunningVariable, RDData}
   @unpack lb,ub = i
   idx =  lb .<= ZsR.Zs .<= ub 
   Base.getindex(ZsR, idx)
end





@recipe function f(ZsR::RunningVariable,  Ys::AbstractVector)
	RDData(Ys, ZsR)
end

#-------------------------------------------------------
# include this temporarily, from Plots.jl codebase
# until issue 2360 is resolved
error_tuple(x) = x, x
error_tuple(x::Tuple) = x
_cycle(v::AbstractVector, idx::Int) = v[mod(idx, axes(v,1))]
_cycle(v, idx::Int) = v

nanappend!(a::AbstractVector, b) = (push!(a, NaN); append!(a, b))

function error_coords(errorbar, errordata, otherdata...)
    ed = Vector{Float64}(undef, 0)
    od = [Vector{Float64}(undef, 0) for odi in otherdata]
    for (i, edi) in enumerate(errordata)
        for (j, odj) in enumerate(otherdata)
            odi = _cycle(odj, i)
            nanappend!(od[j], [odi, odi])
        end
        e1, e2 = error_tuple(_cycle(errorbar, i))
        nanappend!(ed, [edi - e1, edi + e2])
    end
    return (ed, od...)
end
#----------------------------------------------------------
@recipe function f(rdd_data::RDData)
	
	ZsR = rdd_data.ZsR
   	nbins = get(plotattributes, :bins,  StatsBase.sturges(length(ZsR)))
	
   	fitted_hist = fit(Histogram, ZsR; nbins=nbins)
	zs = StatsBase.midpoints(fitted_hist.edges[1])
	err_length = (zs[2]-zs[1])/2
	binidx = StatsBase.binindex.(Ref(fitted_hist), ZsR)

	tmp_df = rdd_data|> DataFrame
	tmp_df.binidx = binidx
	tmp_df = combine(groupby(tmp_df, :binidx) , [:Ys => mean, :Ys=>length])

	zs = zs[tmp_df.binidx]
	ys = tmp_df.Ys_mean
	
   	yguide --> "Response"
   	xguide --> "Running variable"
   	grid --> false 
	linecolor --> :grey
	linewidth --> 1.2
	thickness_scaling --> 1.7
	legend --> :outertop
	background_color_legend --> :transparent
	foreground_color_legend --> :transparent
 
	zs_scatter, ys_scatter = error_coords(err_length, zs, ys)

	#ylims --> extrema(ys)
	
	@series begin
		label --> "Regressogram"
		seriestype:= :path
	  	zs_scatter, ys_scatter
	end
	
   	@series begin
		label := nothing
      	seriestype := :vline
      	linecolor := :purple
      	linestyle := :dash
      	linewidth := 1.7
      	[ZsR.cutoff]
    end 
end