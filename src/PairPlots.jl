module PairPlots

using RecipesBase
using Measures
using NamedTupleTools
using Tables

using Statistics
using StatsBase

using Printf
using Requires
using StaticArrays
using PolygonOps
using Contour
using Plots


function corner(
        table,
        labels = map(string, Tables.columnnames(table));
        title="",
        plotcontours=true,
        plotscatter=true,
        plotpercentiles=[15,50,84],
        histfunc=prepare_hist,
        filterscatter=true,
        hist_kwargs=(;),
        hist2d_kwargs=(;),
        contour_kwargs=(;),
        scatter_kwargs=(;),
        percentiles_kwargs=(;),
        appearance=(;),
        lens=nothing,
        lens_kwargs=(;),
        bonusplot=nothing,
        # Remaining kwargs are for the overall plot group
        kwargs...
    )

    # Simple error check to see if the user has imported a plotting package...
    if !hasmethod(RecipesBase.plot, ())
        error("You must run `using Plots` before calling this function")
    end

    if !Tables.istable(table)
        error("You must supply data in a format consistent with the definition in Tables.jl, e.g. a Named Tuple of vectors.")
    end


    if any(!isascii, labels)
        @warn "Non-ascii labels detected. Some plotting backends require passing these using LaTeX escapes, e.g. \\alpha instead of α"
    end

    columns = Tables.columnnames(table)
    n = length(columns)

    # Merge keywords for different subplots & series
    hist_kwargs=merge((; nbins=20, color=:black), hist_kwargs, (;yticks=[]))
    hist2d_kwargs=merge((; nbins=32, color=:Greys, colorbar=:none), hist2d_kwargs)
    contour_kwargs=merge((; color=:black, linewidth=1.5), contour_kwargs)
    scatter_kwargs=merge((; color=:black, alpha=0.1, markersize=1.5, markerstrokewidth=0), scatter_kwargs)
    percentiles_kwargs=merge((;linestyle=:dash, color=:black), percentiles_kwargs)
    appearance = merge((;
        framestyle=:box,
        xrotation = 45,
        yrotation = 45,
        # margin=-6Measures.mm,
        grid=:none,
        xformatter=:plain,
        yformatter=:plain,
        zformatter=t->"",
        titlefontsize=10,
        tick_direction=:out,
        label="",
    ), appearance)

    threeD = get(hist2d_kwargs, :seriestype, nothing) == :wireframe

    # Calculate a default reasonable size unless overriden
    # s = 250*n
    # kwargs = merge((;size = (s,s)), kwargs)


    # Rather than messing with linking axes, let's just take over setting the plot limits ourselves
    ex = [extrema(Tables.getcolumn(table, i)) for i in 1:n]
    mins = [ex[1] for ex in ex]
    maxs = [ex[2] for ex in ex]
    # By how much should we oversize the limits
    lim_factor = 1.05


    # Overall plot scale factor
    sf = 1

    pad_top = 20sf
    pad_left = 20sf
    w=40sf
    h=40sf
    p=1sf
    pad_right = 0sf
    pad_bottom = 10sf
    pad_bonus = iseven(n) ? 20sf : 5sf


    full_width = (pad_left+(w+p)*n+pad_right)
    full_height = (pad_top+(h+p)*n+pad_bottom)
    parent = RecipesBase.plot(
        # size=((w+p)*n, ((w+p)*n+pad_top)),
        size=(full_width*4,full_height*4),
        framestyle=:none,
        title=title;
        left_margin=-10Measures.mm,
        kwargs...
    )


    # Build grid of nxn plots
    k = 1
    for row in 1:n, col in 1:n

        if row < col
            # push!(subplots, emptyplot())
            continue
        end
        k+=1


        # fmt(label) = "\$\\mathrm{$label}\$"
        fmt(label) = "\$$label\$"
        kw = (;
            title = row == col ? labels[row] : "",
            xguide = threeD || row == n ? fmt(labels[col]) : "",
            yguide = threeD || col == 1  && row > 1 ? fmt(labels[row]) : "",
            xformatter = threeD || row == n ? appearance.xformatter : t->"",
            yformatter = threeD || col == 1 && row > 1 ? appearance.yformatter : t->"",

            # For crudlely tweaking aspect ratios of the plots to account for
            # top_margin = row == 1 ? 10Measures.mm : :match,
            # left_margin = col == 1 ? 8Measures.mm : :match,
            # right_margin = col == n ? 6Measures.mm : :match,

            xlims=(mins[col], maxs[col]).*lim_factor,
            label="",
            subplot=k,
        )
        x=(col-1)*(w+p)+pad_left
        y=(row-1)*(h+p)+pad_top
        inset = bbox(x*Measures.mm, y*Measures.mm, w*Measures.mm, h*Measures.mm, :left)
    

        if row != col
            kw = (;kw..., ylims=(mins[row], maxs[row]).*lim_factor)
        end

        # subplot = 
        if row == col
            # 1D histogram
            # RecipesBase.plot!(rand(10,10);seriestype=:heatmap, colorbar=:none, framestyle=:none, kw...)
            hist(Tables.getcolumn(table, row), histfunc, merge(appearance, kw, hist_kwargs, (;inset)), plotpercentiles, merge(kw, percentiles_kwargs))
        else row > col
            # 2D histogram 
            # RecipesBase.plot!(rand(10,10);seriestype=:heatmap, colorbar=:none, framestyle=:none, kw...)
            hist(Tables.getcolumn(table, row), Tables.getcolumn(table, col), histfunc, merge(appearance, kw, hist2d_kwargs, (;inset)), merge(kw,contour_kwargs), merge(kw,scatter_kwargs), plotcontours, plotscatter, filterscatter)
        end
        # push!(subplots, subplot)
    end

    if !isnothing(lens)
        k += 1
        nspan = floor(mean(1:n))
        x=nspan*(w+p)+pad_bonus+pad_left
        y=pad_top
        bonuswidth = full_width-x
        bonusheight = full_height-pad_bottom-pad_top-nspan*(h+p) - pad_bonus 
        inset = bbox(x*Measures.mm, y*Measures.mm, bonuswidth*Measures.mm, bonusheight*Measures.mm, :left)
        if lens ∈ columns
            kw = (;label="", subplot=k, title=labels[findfirst(==(lens), columns)])
            hist(Tables.getcolumn(table, lens), histfunc, merge(appearance, kw, hist_kwargs, (;inset), lens_kwargs), plotpercentiles, merge(kw, percentiles_kwargs))
        elseif lens[1] ∈ columns && lens[2] ∈ columns
            kw = (;label="", subplot=k, title=labels[findfirst(==(lens[1]), columns)]*" vs. "*labels[findfirst(==(lens[2]), columns)])
            hist(Tables.getcolumn(table, lens[1]), Tables.getcolumn(table, lens[2]), histfunc, merge(appearance, kw, hist2d_kwargs, (;inset), lens_kwargs), merge(kw,contour_kwargs), merge(kw,scatter_kwargs), plotcontours, plotscatter, filterscatter)
        end
    elseif !isnothing(bonusplot)
        k += 1
        nspan = floor(mean(1:n))
        x=nspan*(w+p)+pad_bonus+pad_left
        y=pad_top
        bonuswidth = full_width-x-pad_bonus
        bonusheight = full_height-pad_bottom-pad_top-nspan*(h+p) - pad_bonus 
        inset = bbox(x*Measures.mm, y*Measures.mm, bonuswidth*Measures.mm, bonusheight*Measures.mm, :left)
        kw = (;inset,subplot=k)
        bonusplot(kw)
    end


    return parent
end
export corner

function hist(a, histfunc, hist_kwargs, plotpercentiles, percentiles_kwargs,)

    x, h = histfunc(a, hist_kwargs.nbins)

    minx, maxx = extrema(a)
    extent = maxx - minx
    # h_scaled = h ./ maximum(h) .* extent
    # h_scaled .+= minx
    h_scaled = h
    pcs = []
    a_sorted = sort(a)
    if length(plotpercentiles) > 0
        pcs = quantile(a_sorted, plotpercentiles./100, sorted=true)
    end
    # WIP: replace the title with an annotation so that the margins don't get messed up.
    if get(hist_kwargs, :title, "") != ""
        pcs_title = quantile(a_sorted, [0.16, 0.5, 0.84], sorted=true)
        med = pcs_title[2]
        low = med - pcs_title[1]
        high =  pcs_title[3] - med
        title = @sprintf("\$%s = %.2f^{+%.2f}_{-%.2f}\$", hist_kwargs.title, pcs_title[2], high, low)
        xc = mean(x)
        yc = maximum(h_scaled) * 1.15
        hist_kwargs = (;hist_kwargs..., title)
    end
    hist_kwargs = delete(hist_kwargs, :nbins)
    percentiles_kwargs = delete(percentiles_kwargs,:title)
    # p = RecipesBase.plot()

    kw = merge((;seriestype=:step), hist_kwargs)
    if kw.seriestype==:step
        x = x .- step(x)/2
    end
    RecipesBase.plot!(x, h_scaled; seriestype=:step, kw...)

    if length(pcs) > 0
        RecipesBase.plot!(pcs; seriestype=:vline, percentiles_kwargs...)
    end

    # return p
end
function hist(a, b, histfunc, hist2d_kwargs, contour_kwargs, scatter_kwargs, plotcontours, plotscatter, filterscatter)

    x, y, H = histfunc(a, b, hist2d_kwargs.nbins)

    threeD = get(hist2d_kwargs, :seriestype, nothing) == :wireframe

    # Calculate levels for contours
    levels = 1 .- exp.(-0.5 .* (0.5:0.5:2.1).^2)
    ii = sortperm(reshape(H,:))
    h2flat = H[ii]
    sm = cumsum(h2flat)
    sm /= sm[end]
    V = sort(map(v0 -> h2flat[sm .≤ v0][end], levels))
    if any(==(0), diff(V))
        @warn "Too few points to create valid contours"
    end

    # # Exclude histogram spaces outside the outer contour
    masked_weights = fill(NaN, size(H))
    # # Old method of masking out histogram squares
    # # if plotscatter && !threeD
    # #     mask = H .>= V[1]
    # # else
    # #     mask = trues(size(H))
    # # end
    if plotscatter &&!threeD
        mask = H .> V[1]
    else
        mask = trues(size(H))
    end
    masked_weights[mask] .= H[mask]
    # masked_weights = H

    levels_final = [0; V; maximum(H) * (1 + 1e-4)]

    # p = RecipesBase.plot()
    if threeD
        scatter_kwargs = merge(scatter_kwargs, (; seriestype=:scatter3d))
        # if !hasproperty(contour_kwargs, :seriestype)
        #     contour_kwargs = merge(contour_kwargs, (;seriestype=:contour3d))
        # end
        plotcontours = false
    end
    RecipesBase.plot!(x, y, masked_weights; seriestype=:heatmap, hist2d_kwargs...)

    if plotscatter
        if filterscatter
            points = scatter_filtering(b, a, x,y,H, [V[1]])
        else
            points = (b,a)
        end
        # TODO: handle threeD
        if get(scatter_kwargs, :seriestype, nothing) == :scatter3d
            z = zeros(size(y))
            RecipesBase.plot!(b, a, z; scatter_kwargs...)
        else
            RecipesBase.plot!(points; seriestype=:scatter, scatter_kwargs...)
        end
    end

    if plotcontours
        RecipesBase.plot!(x, y, H; seriestype=:contour, levels=levels_final, colorbar=:none, contour_kwargs...)
        # GR does not yet support transparent filled contours. This would allow us to have even nicer edges to the histogram/contour boundary
        # outer_cmap = cgrad([RGBA(255,255,255,1.0), RGBA(255,255,255,0.0)])
        # RecipesBase.plot!(p, x, y, H; seriestype=:contourf, levels=[0,levels_final[2], levels_final[3]], colorbar=:none, contour_kwargs..., color=outer_cmap)
    end
    # p
end

emptyplot() = RecipesBase.plot(framestyle=:none, background_color_inside=:transparent)

# Default histogram calculations
"""
    prepare_hist(vector, nbins)

Use the StatsBase function to return a centered histogram from `vector` with `nbins`.
Must return a tuple of bin centres, followed by bin weights (of the same length).
"""
function prepare_hist(a, nbins)
    h = fit(Histogram, a; nbins)
    x = first(only(h.edges))+step(only(h.edges))/2 : step(only(h.edges)) : last(only(h.edges))-step(only(h.edges))/2
    return x, h.weights
end
"""
    prepare_hist(vector, nbins)

Use the StatsBase function to return a centered histogram from `vector` with `nbins`x`nbins`.
Must return a tuple of bin centres along the horizontal, bin centres along the vertical,
and a matrix of bin weights (of matching dimensions).
"""
function prepare_hist(a, b, nbins)
    h = fit(Histogram, (a,b); nbins)
    y = range(first(h.edges[1]), step=step(h.edges[1]), length=size(h.weights,1))
    x = range(first(h.edges[2]), step=step(h.edges[2]), length=size(h.weights,2))
    return x, y, h.weights
end

# Filter the scatter plot to remove points inside the first contour
# for performance and better display
function scatter_filtering(b, a, x,y,H, level)

    inds = eachindex(b,a)
    outside = trues(size(inds))

    # calculate the outer contour manually
    c = contours(x,y,H', level)
    for poly in lines(first(levels(c)))
        xs, ys = coordinates(poly)
        poly = SVector.(xs,ys)
        push!(poly, SVector(xs[begin], ys[begin]))
        # poly = [xs ys; xs[begin] ys[begin]]
        for i in inds
            point = SVector(b[i],a[i])
            ins = inpolygon(point, poly, in=false, on=true, out=true)
            outside[i] &= ins
        end
    end
    return b[outside], a[outside]

end


# Special support for MCMCChains.
# They have additional table fields :iteration and :chain that should not be shown
# by default.
# In future, we might add the ability to colour the output by chain number.
function __init__()
    @require MCMCChains="c7f686f2-ff18-58e9-bc7b-31028e88f75d" begin
        function corner(chains::MCMCChains.Chains, args...; kwargs...)
            props = keys(chains)
            # values = (reshape(chains[prop].data,:) for prop in props)
            values = (vec(chains[prop].data) for prop in props)
            table = namedtuple(props, values)
            return corner(table, args...; kwargs...)
        end
    end
    nothing
end



end # module