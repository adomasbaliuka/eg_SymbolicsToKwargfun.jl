### A Pluto.jl notebook ###
# v0.17.5

using Markdown
using InteractiveUtils

# ╔═╡ 4c4bfc78-7224-11ec-211d-f1e60824d35c
begin
	using PlutoUI
	using Symbolics, SymbolicUtils
	using LaTeXStrings,Latexify
	# using Bijections  # could use to specify replacement of variables/names
end

# ╔═╡ b9b5c2e0-537d-4a72-adb9-8474dc8acf98
md"""
# Julia-functions with keyword arguments from symbolic expressions

### (I'm grateful for any advice or improvement suggestions!!!)

## Aim
In this notebook, the (not yet achieved) goal is to eliminate the danger of messing up when copying equations between publications (or LaTeX manuscripts) and Julia-code. 

Such mistakes can lead to graphs or simulation results in a paper no longer matching reported equations. This can make papers difficult to understand, reproduce and build upon their results. Parameters used for plots or simulations/optimizations are sometimes not completely specified or reported incorrectly, which can even make it difficult to say if one's attempt to reproduce the results succeeded.

My current idea of how to work towards eliminating this problem is this:

- Use a `Pluto.jl` notebook instead of a paper, or at least give it as a supplement.
- Enter the equations using `Symbolics.jl` (or `ModelingToolkit.jl`, etc.) and render them as LaTeX. This makes it much easier to read and check them then bracketed Julia code.
- Manipulate the equations and expressions to plug in numbers, run simulations or optimizations, and finally plot results.

However, there are several problems on the way towards this goal. Also, being a beginner at using the Julia SciML ecosystem, it's hard to follow best-practices, especially given the fast pace of development, changes and lack of accessible documentation. The *this I focus on right now* are

- dealing with weird variable names (e.g. with superscripts)
- plugging in numbers for variables, plotting equations and preparing for simulation/optimization, in a way that is simple, convenient, stable and helps catch errors

"""

# ╔═╡ 42f6afaa-cf0d-46dd-b1d9-ebaeafc9e5db
md"""
## Contents
- Render equation with complicated variable names
- substitute an equation that is split up into sub-expressions back into one equation
- Plug in numbers into equation using `substitute`
- Compile Julia function (array input) from the expression (using `build_function`)
- Compile Julia function (keyword-argument input) from the expression
"""

# ╔═╡ b580a960-7780-417e-ae0f-3ac59f4a4a30
md"""
## Use non-standard variable names

Suppose you are dealing with symbols that do not map uniquely to Julia code, for example:
"""

# ╔═╡ 0c2701f4-8e93-4fbc-b18c-52e9d1c213f8
begin
	proper_vars = @variables x a b var"{c^{+}_{\alpha}}"

	c_plus_alpha = var"{c^{+}_{\alpha}}" # abbreviation for latex-symbol
	
	proper_vars
end

# ╔═╡ 6e521fb4-190c-4b68-890b-d39b22537471
md"""
_I'm not sure if it's a good idea to represent such symbols with this hack, i.e., abusing non-standard Julia variable names. This seems to mostly work but leads to problems when the variable is programatically converted to a `Base.Symbol`._

Now imagine you copy an equation with such symbols from a publication and want to keep your names and symbols as close to the original as possible. A toy-example equation:
"""

# ╔═╡ bf6bac04-1957-4aa9-976e-efd76b41632b
begin
	true_eqn = 
		x ~ a^2 + log2((a * b^2 * c_plus_alpha ) / sin(2a * b^2)^2) * sqrt(2a * b^2)
	latexify(true_eqn)
end

# ╔═╡ ea8f56c9-11d1-48e3-ae36-678fab1ad4bd
md"## Reconstruct a split-up equation"

# ╔═╡ 8e96dcbb-5320-4222-9b83-aeedce9ed816
md"Now suppose that the equation (due to being more complicated) is presented as split up into parts (using some helper variables `h_1`, `h_2`). These have to be 'substituted back' into each other to get back the full equation. *For using the full equation, it may not be neccessary (or even a good idea) to reassemble the full symbolic expression. Are there better ways?*"

# ╔═╡ 79537fac-84f7-4bc1-8816-7d0ee433408e
begin
	# auxilliary variables
	helper_vars = @variables h_1 h_2
	
	split_up_eqns = [
		x ~ a^2 + log2(h_1) * sqrt(h_2),
		h_1 ~ h_2 * c_plus_alpha / 2 / sin(h_2)^2,
		h_2 ~ 2a * b^2
	]
	latexify(split_up_eqns)
end

# ╔═╡ 15d8d20e-a209-4941-9d95-dc43a1cde690
md"""
I'm not exactly sure what is the _best_ way of getting back the original equation, but this dirty hack works:
"""

# ╔═╡ 745aa374-ade1-4474-99fd-f51869405a00
"""
**NOTE: Beware, this is just a crappy prototype!**

Substitutes expressions inside `target_expr` as specified by equations `source_eqns`.
For each equation in `source_eqns`, substitutes all occurences of its `lhs` by its `rhs` until none of the `lhs` are left. 

**If there are cyclic dependencies among `source_eqns`, the output is undefined!**
"""
function substitute_all(target_expr, source_eqns,)
    all_eqns = [target_expr, source_eqns...]

	# ------ some consistency checks ----
	# left hand sides of `source_eqns` are unique
    eliminated_expressions = map(x->x.lhs, source_eqns)
    length(Set(eliminated_expressions)) == length(source_eqns) || error(
		"Redundant equations! Eliminated expressions must be unique. Nonunique:
		$eliminated_expressions")

	# left hand sides of `source_eqns` have no variables in common
	intersecting_lhs_vars = intersect(
		Symbolics.get_variables.(eliminated_expressions)...)
	isempty(intersecting_lhs_vars) || error(
		"Output depends on order of source equations due to lhs dependencies: lhs's
		$eliminated_expressions with intersecting variables $intersecting_lhs_vars")

	# ------- actual 'work' -------------
    for i in 2:length(all_eqns)
        all_eqns = substitute.(all_eqns, (Dict(all_eqns[i].lhs => all_eqns[i].rhs),))
    end

    return all_eqns[1]
end

# ╔═╡ 92801458-b302-4e89-8434-4e6bb4c0135e
begin # a basic test:
	recovered_eqn = substitute_all(split_up_eqns[1], split_up_eqns[2:end],)
	recovered_eqn == true_eqn || error("Failure: equations don't match!")
end

# ╔═╡ f2357d35-0c51-4b04-a491-3893ac35f5a4
md"""
## Plug in numbers into the equation

this is the easiest way to plug in numbers into the equation that I have seen so far.
"""

# ╔═╡ fcdd4f4a-59d2-4027-8c30-f56d6782b7ef
begin
	values_to_plug_in = Dict([x=>1e9,
			a=>2.0, b=>3.0, c_plus_alpha=>4.0])
	example_equation_result = substitute(recovered_eqn.rhs, values_to_plug_in)
end

# ╔═╡ 8fdb9251-1865-4e5e-9fac-b888c340e066
md"""
- **Note:** `x=>1e9` doesn't do anything! `substitute` does not (nor should it) check if all substitutions actually take place! This is a point where one might want something to help catch errors.

- **Note:**  `c_plus_alpha` is an alias for var"{c^{+}_{\alpha}}", which is how hat symbol thinks it should LaTeX-render and transform into `Symbol`. At this point, using the alias works.
"""

# ╔═╡ f91d951f-2704-4244-a102-c1fc419337cb
md"""
## Compile equation into a Julia function

Suppose you want to plug in lots of different numbers for your variables and look at the restults, maybe 'plot the equation', which may require to broadcast over arrays, etc. My fear is that the `substitute` way would become too slow.

One way to do it is to create a keyword-argument Julia function from the expression. 
(This might not be a *good* way to do it. Maybe there are better ways to achieve such tasks?)

`Symbolics.jl` provides `build_function`, which can generate a function that takes its arguments (numbers we want to plug in) as an array. 

To get keyword-arguments, one can use `SymbolicUtils.jl`'s `Func` datatype, as well as `toexpr`. However, it seems that these keyword-arguments *must* be provided with default values (I guess that's not so bad), and *must* be named according to `Symbol(variable)`, which interferes with my idea to have weird variable names such as
```julia
@variables var"stupidstuff"
abbreviation = var"stupidstuff" # continue to use abbreviation
```

*Do you have an idea how to deal with that? Of course, using meta-programming, one could build the function manually. However, that's quite a bit of work and hard to get completely right.*
"""

# ╔═╡ 85718649-6050-4cd6-9c6d-83023a6e6030
md"""
### Compile into function that takes arguments as a `Vector`
"""

# ╔═╡ 76c64481-d2af-40b8-bdda-ea2ebc05e8c8
begin
	func_expr = build_function(recovered_eqn, proper_vars)
	Base.remove_linenums!(func_expr) # why does this not remove the linenums?
	func_expr
end

# ╔═╡ 756f6398-2357-4602-8269-d27d60e32b2b
md"""
### Compile into function that takes keyword arguments
"""

# ╔═╡ 27adf4ac-d11a-4e57-b8d9-d69a57f9e045
md"for some reason, `SymbolicUtils.Code` has its own type for saying `x => 1.0`, called `Assignment`. Lets transform the values-to-plug-in above into defaults for the keyword-argument function.
"

# ╔═╡ 105d0d41-6680-48ec-a16c-2c719ab06234
begin
	default_values = Dict([x=>1e9,
				a=>2.0, b=>3.0, c_plus_alpha=>4.0])
	
	kwargs_spec = SymbolicUtils.Code.Assignment.(
		keys(default_values), values(default_values)
	)
end

# ╔═╡ 26454574-c62a-4851-9211-c56e4da9ae8c
md"Build the keyword-argument function:"

# ╔═╡ eea19aaa-a295-4ae5-88fd-e2730710fbb9
begin
	func = Symbolics.Func(
		[], # positional arguments
		kwargs_spec, 
		recovered_eqn.rhs
	)
	kwarg_expr = SymbolicUtils.Code.toexpr(func)
end

# ╔═╡ 30ffb100-2331-494e-9433-09bf96c701fa
md"""
**Note:** we get a keyword-argument named `var"{c^{+}_{\\alpha}}"`, which I don't know how to customize.
"""

# ╔═╡ 5a4b516e-c7d4-4bad-8793-d4c63db23f9b
begin # use kwarg function
	kwargfunction = eval(kwarg_expr)

	kwargfunction() == example_equation_result || error("Mismatched results")
	
	kwargfunction(a = 42.), kwargfunction(a = 42., var"{c^{+}_{\alpha}}"=1.2e5)
end

# ╔═╡ cd16d92b-c605-4b37-ad42-1125c931d2c6
md"Maybe plot something?"

# ╔═╡ a2464c22-3904-44ab-a00b-59570cdf7b7d
begin
	a_range = range(0.1,stop=10.,length=1000)
	
	# note: keyword arguments cannot (I think) be broadcast with `func.()` notation
	eqn_values = broadcast(a_range) do aval
		kwargfunction(a=aval)
	end
end

# ╔═╡ a5c6de65-baeb-49eb-a28a-ac1109806794
# begin # compiling Plots.jl can take a few minutes. Uncomment if you dare!
# 	using Plots 
# 	plot(a_range, eqn_values, label=recovered_eqn.lhs)
# end

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
LaTeXStrings = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
Latexify = "23fbe1c1-3f47-55db-b15f-69d7ec21a316"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
SymbolicUtils = "d1185830-fcd6-423d-90d6-eec64667417b"
Symbolics = "0c5d862f-8b57-4792-8d23-62f2024744c7"

[compat]
LaTeXStrings = "~1.3.0"
Latexify = "~0.15.9"
PlutoUI = "~0.7.29"
SymbolicUtils = "~0.19.1"
Symbolics = "~4.2.3"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.7.1"
manifest_format = "2.0"

[[deps.AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "8eaf9f1b4921132a4cff3f36a1d9ba923b14a481"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.1.4"

[[deps.AbstractTrees]]
git-tree-sha1 = "03e0550477d86222521d254b741d470ba17ea0b5"
uuid = "1520ce14-60c1-5f80-bbc7-55ef81b5835c"
version = "0.3.4"

[[deps.Adapt]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "af92965fb30777147966f58acb05da51c5616b5f"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "3.3.3"

[[deps.ArgCheck]]
git-tree-sha1 = "dedbbb2ddb876f899585c4ec4433265e3017215a"
uuid = "dce04be8-c92d-5529-be00-80e4d2c0e197"
version = "2.1.0"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[deps.ArrayInterface]]
deps = ["Compat", "IfElse", "LinearAlgebra", "Requires", "SparseArrays", "Static"]
git-tree-sha1 = "1ee88c4c76caa995a885dc2f22a5d548dfbbc0ba"
uuid = "4fba245c-0d91-5ea0-9b3e-6abc04ee57a9"
version = "3.2.2"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.AutoHashEquals]]
git-tree-sha1 = "45bb6705d93be619b81451bb2006b7ee5d4e4453"
uuid = "15f4f7f2-30c1-5605-9d31-71845cf9641f"
version = "0.2.0"

[[deps.BangBang]]
deps = ["Compat", "ConstructionBase", "Future", "InitialValues", "LinearAlgebra", "Requires", "Setfield", "Tables", "ZygoteRules"]
git-tree-sha1 = "95831c49cf801756a922e50641361e3b4476a782"
uuid = "198e06fe-97b7-11e9-32a5-e1d131e6ad66"
version = "0.3.33"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.Baselet]]
git-tree-sha1 = "aebf55e6d7795e02ca500a689d326ac979aaf89e"
uuid = "9718e550-a3fa-408a-8086-8db961cd8217"
version = "0.1.1"

[[deps.Bijections]]
git-tree-sha1 = "705e7822597b432ebe152baa844b49f8026df090"
uuid = "e2ed5e7c-b2de-5872-ae92-c73ca462fb04"
version = "0.1.3"

[[deps.ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "926870acb6cbcf029396f2f2de030282b6bc1941"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.11.4"

[[deps.ChangesOfVariables]]
deps = ["ChainRulesCore", "LinearAlgebra", "Test"]
git-tree-sha1 = "bf98fa45a0a4cee295de98d4c1462be26345b9a1"
uuid = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
version = "0.1.2"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "024fe24d83e4a5bf5fc80501a314ce0d1aa35597"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.0"

[[deps.Combinatorics]]
git-tree-sha1 = "08c8b6831dc00bfea825826be0bc8336fc369860"
uuid = "861a8166-3701-5b0c-9a16-15d98fcdc6aa"
version = "1.0.2"

[[deps.CommonSolve]]
git-tree-sha1 = "68a0743f578349ada8bc911a5cbd5a2ef6ed6d1f"
uuid = "38540f10-b2f7-11e9-35d8-d573e4eb0ff2"
version = "0.2.0"

[[deps.Compat]]
deps = ["Base64", "Dates", "DelimitedFiles", "Distributed", "InteractiveUtils", "LibGit2", "Libdl", "LinearAlgebra", "Markdown", "Mmap", "Pkg", "Printf", "REPL", "Random", "SHA", "Serialization", "SharedArrays", "Sockets", "SparseArrays", "Statistics", "Test", "UUIDs", "Unicode"]
git-tree-sha1 = "44c37b4636bc54afac5c574d2d02b625349d6582"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "3.41.0"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[deps.CompositeTypes]]
git-tree-sha1 = "d5b014b216dc891e81fea299638e4c10c657b582"
uuid = "b152e2b5-7a66-4b01-a709-34e65c35f657"
version = "0.1.2"

[[deps.CompositionsBase]]
git-tree-sha1 = "455419f7e328a1a2493cabc6428d79e951349769"
uuid = "a33af91c-f02d-484b-be07-31d278c5ca2b"
version = "0.1.1"

[[deps.ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f74e9d5388b8620b4cee35d4c5a618dd4dc547f4"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.3.0"

[[deps.DataAPI]]
git-tree-sha1 = "cc70b17275652eb47bc9e5f81635981f13cea5c8"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.9.0"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "3daef5523dd2e769dad2365274f760ff5f282c7d"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.11"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DefineSingletons]]
git-tree-sha1 = "0fba8b706d0178b4dc7fd44a96a92382c9065c2c"
uuid = "244e2a9f-e319-4986-a169-4d1fe445cd52"
version = "0.1.2"

[[deps.DelimitedFiles]]
deps = ["Mmap"]
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"

[[deps.DensityInterface]]
deps = ["InverseFunctions", "Test"]
git-tree-sha1 = "80c3e8639e3353e5d2912fb3a1916b8455e2494b"
uuid = "b429d917-457f-4dbc-8f4c-0cc954292b1d"
version = "0.4.0"

[[deps.DiffRules]]
deps = ["LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "9bc5dac3c8b6706b58ad5ce24cffd9861f07c94f"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.9.0"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.Distributions]]
deps = ["ChainRulesCore", "DensityInterface", "FillArrays", "LinearAlgebra", "PDMats", "Printf", "QuadGK", "Random", "SparseArrays", "SpecialFunctions", "Statistics", "StatsBase", "StatsFuns", "Test"]
git-tree-sha1 = "6a8dc9f82e5ce28279b6e3e2cea9421154f5bd0d"
uuid = "31c24e10-a181-5473-b8eb-7969acd0382f"
version = "0.25.37"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "b19534d1895d702889b219c382a6e18010797f0b"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.8.6"

[[deps.DomainSets]]
deps = ["CompositeTypes", "IntervalSets", "LinearAlgebra", "StaticArrays", "Statistics"]
git-tree-sha1 = "5f5f0b750ac576bcf2ab1d7782959894b304923e"
uuid = "5b8099bc-c8ec-5219-889f-1d9e522a28bf"
version = "0.5.9"

[[deps.Downloads]]
deps = ["ArgTools", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[deps.DynamicPolynomials]]
deps = ["DataStructures", "Future", "LinearAlgebra", "MultivariatePolynomials", "MutableArithmetics", "Pkg", "Reexport", "Test"]
git-tree-sha1 = "585de0d658506cf0fe5808026edff662bef5bf03"
uuid = "7c1d4256-1411-5781-91ec-d7bc3513ac07"
version = "0.4.1"

[[deps.EllipsisNotation]]
deps = ["ArrayInterface"]
git-tree-sha1 = "3fe985505b4b667e1ae303c9ca64d181f09d5c05"
uuid = "da5c29d0-fa7d-589e-88eb-ea29b0a81949"
version = "1.1.3"

[[deps.ExprTools]]
git-tree-sha1 = "b7e3d17636b348f005f11040025ae8c6f645fe92"
uuid = "e2ba6199-217a-4e67-a87a-7c52f15ade04"
version = "0.1.6"

[[deps.FillArrays]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "Statistics"]
git-tree-sha1 = "8756f9935b7ccc9064c6eef0bff0ad643df733a3"
uuid = "1a297f60-69ca-5386-bcde-b61e274b549b"
version = "0.12.7"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[deps.Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "8d511d5b81240fc8e6802386302675bdf47737b9"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.4"

[[deps.HypertextLiteral]]
git-tree-sha1 = "2b078b5a615c6c0396c77810d92ee8c6f470d238"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.3"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "f7be53659ab06ddc986428d3a9dcc95f6fa6705a"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.2"

[[deps.IfElse]]
git-tree-sha1 = "debdd00ffef04665ccbb3e150747a77560e8fad1"
uuid = "615f187c-cbe4-4ef1-ba3b-2fcf58d6d173"
version = "0.1.1"

[[deps.InitialValues]]
git-tree-sha1 = "40c555f961d7ccf86d8ccd150b9eef379cbfa0a3"
uuid = "22cec73e-a1b8-11e9-2c92-598750a2cf9c"
version = "0.3.0"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.IntervalSets]]
deps = ["Dates", "EllipsisNotation", "Statistics"]
git-tree-sha1 = "3cc368af3f110a767ac786560045dceddfc16758"
uuid = "8197267c-284f-5f27-9208-e0e47529a953"
version = "0.5.3"

[[deps.InverseFunctions]]
deps = ["Test"]
git-tree-sha1 = "a7254c0acd8e62f1ac75ad24d5db43f5f19f3c65"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.2"

[[deps.IrrationalConstants]]
git-tree-sha1 = "7fd44fd4ff43fc60815f8e764c0f352b83c49151"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.1.1"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "642a199af8b68253517b80bd3bfd17eb4e84df6e"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.3.0"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "8076680b162ada2a031f707ac7b4953e30667a37"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.2"

[[deps.LaTeXStrings]]
git-tree-sha1 = "f2355693d6778a178ade15952b7ac47a4ff97996"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.0"

[[deps.LabelledArrays]]
deps = ["ArrayInterface", "ChainRulesCore", "LinearAlgebra", "MacroTools", "StaticArrays"]
git-tree-sha1 = "41158dee1d434944570b02547d404e075da15690"
uuid = "2ee39098-c373-598a-b85f-a56591580800"
version = "1.7.0"

[[deps.Latexify]]
deps = ["Formatting", "InteractiveUtils", "LaTeXStrings", "MacroTools", "Markdown", "Printf", "Requires"]
git-tree-sha1 = "a8f4f279b6fa3c3c4f1adadd78a621b13a506bce"
uuid = "23fbe1c1-3f47-55db-b15f-69d7ec21a316"
version = "0.15.9"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LogExpFunctions]]
deps = ["ChainRulesCore", "ChangesOfVariables", "DocStringExtensions", "InverseFunctions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "e5718a00af0ab9756305a0392832c8952c7426c1"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.6"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "3d3e902b31198a27340d0bf00d6ac452866021cf"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.9"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[deps.Metatheory]]
deps = ["AutoHashEquals", "DataStructures", "Dates", "DocStringExtensions", "Parameters", "Reexport", "TermInterface", "ThreadsX", "TimerOutputs"]
git-tree-sha1 = "0886d229caaa09e9f56bcf1991470bd49758a69f"
uuid = "e9d8d322-4543-424a-9be4-0cc815abe26c"
version = "1.3.3"

[[deps.MicroCollections]]
deps = ["BangBang", "Setfield"]
git-tree-sha1 = "4f65bdbbe93475f6ff9ea6969b21532f88d359be"
uuid = "128add7d-3638-4c79-886c-908ea0c25c34"
version = "0.1.1"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "bf210ce90b6c9eed32d25dbcae1ebc565df2687f"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.0.2"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[deps.MultivariatePolynomials]]
deps = ["DataStructures", "LinearAlgebra", "MutableArithmetics"]
git-tree-sha1 = "fa6ce8c91445e7cd54de662064090b14b1089a6d"
uuid = "102ac46a-7ee4-5c85-9060-abc95bfdeaa3"
version = "0.4.2"

[[deps.MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "73deac2cbae0820f43971fad6c08f6c4f2784ff2"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "0.3.2"

[[deps.NaNMath]]
git-tree-sha1 = "f755f36b19a5116bb580de457cda0c140153f283"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "0.3.6"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[deps.PDMats]]
deps = ["LinearAlgebra", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "ee26b350276c51697c9c2d88a072b339f9f03d73"
uuid = "90014a1f-27ba-587c-ab20-58faa44d9150"
version = "0.11.5"

[[deps.Parameters]]
deps = ["OrderedCollections", "UnPack"]
git-tree-sha1 = "34c0e9ad262e5f7fc75b10a9952ca7692cfc5fbe"
uuid = "d96e819e-fc66-5662-9728-84c9c7592b0a"
version = "0.12.3"

[[deps.Parsers]]
deps = ["Dates"]
git-tree-sha1 = "d7fa6237da8004be601e19bd6666083056649918"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.1.3"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "Markdown", "Random", "Reexport", "UUIDs"]
git-tree-sha1 = "7711172ace7c40dc8449b7aed9d2d6f1cf56a5bd"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.29"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "2cf929d64681236a2e074ffafb8d568733d2e6af"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.2.3"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.QuadGK]]
deps = ["DataStructures", "LinearAlgebra"]
git-tree-sha1 = "78aadffb3efd2155af139781b8a8df1ef279ea39"
uuid = "1fd47b50-473d-5c70-9696-f719f8f3bcdc"
version = "2.4.2"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.RecipesBase]]
git-tree-sha1 = "6bf3f380ff52ce0832ddd3a2a7b9538ed1bcca7d"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.2.1"

[[deps.RecursiveArrayTools]]
deps = ["Adapt", "ArrayInterface", "ChainRulesCore", "DocStringExtensions", "FillArrays", "LinearAlgebra", "RecipesBase", "Requires", "StaticArrays", "Statistics", "ZygoteRules"]
git-tree-sha1 = "6b96eb51a22af7e927d9618eaaf135a3520f8e2f"
uuid = "731186ca-8d62-57ce-b412-fbd966d074cd"
version = "2.24.0"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.Referenceables]]
deps = ["Adapt"]
git-tree-sha1 = "e681d3bfa49cd46c3c161505caddf20f0e62aaa9"
uuid = "42d2dcc6-99eb-4e98-b66c-637b7d73030e"
version = "0.1.2"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "8f82019e525f4d5c669692772a6f4b0a58b06a6a"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.2.0"

[[deps.Rmath]]
deps = ["Random", "Rmath_jll"]
git-tree-sha1 = "bf3188feca147ce108c76ad82c2792c57abe7b1f"
uuid = "79098fc4-a85e-5d69-aa6a-4863f24498fa"
version = "0.7.0"

[[deps.Rmath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "68db32dff12bb6127bac73c209881191bf0efbb7"
uuid = "f50d1b31-88e8-58de-be2c-1cc44531875f"
version = "0.3.0+0"

[[deps.RuntimeGeneratedFunctions]]
deps = ["ExprTools", "SHA", "Serialization"]
git-tree-sha1 = "cdc1e4278e91a6ad530770ebb327f9ed83cf10c4"
uuid = "7e49a35a-f44a-4d26-94aa-eba1b4ca6b47"
version = "0.5.3"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[deps.SciMLBase]]
deps = ["ArrayInterface", "CommonSolve", "ConstructionBase", "Distributed", "DocStringExtensions", "IteratorInterfaceExtensions", "LinearAlgebra", "Logging", "RecipesBase", "RecursiveArrayTools", "StaticArrays", "Statistics", "Tables", "TreeViews"]
git-tree-sha1 = "68c2ee0351edd3c39f67a017d2d1d12f939126dc"
uuid = "0bca4576-84f4-4d90-8ffe-ffa030f20462"
version = "1.25.0"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Setfield]]
deps = ["ConstructionBase", "Future", "MacroTools", "Requires"]
git-tree-sha1 = "0afd9e6c623e379f593da01f20590bacc26d1d14"
uuid = "efcf1570-3423-57d1-acb7-fd33fddbac46"
version = "0.8.1"

[[deps.SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "b3363d7460f7d098ca0912c69b082f75625d7508"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.0.1"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SpecialFunctions]]
deps = ["ChainRulesCore", "IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "e08890d19787ec25029113e88c34ec20cac1c91e"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.0.0"

[[deps.SplittablesBase]]
deps = ["Setfield", "Test"]
git-tree-sha1 = "39c9f91521de844bad65049efd4f9223e7ed43f9"
uuid = "171d559e-b47b-412a-8079-5efa626c420e"
version = "0.1.14"

[[deps.Static]]
deps = ["IfElse"]
git-tree-sha1 = "7f5a513baec6f122401abfc8e9c074fdac54f6c1"
uuid = "aedffcd0-7271-4cad-89d0-dc628f76c6d3"
version = "0.4.1"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "Random", "Statistics"]
git-tree-sha1 = "88a559da57529581472320892576a486fa2377b9"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.3.1"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StatsAPI]]
git-tree-sha1 = "d88665adc9bcf45903013af0982e2fd05ae3d0a6"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.2.0"

[[deps.StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "51383f2d367eb3b444c961d485c565e4c0cf4ba0"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.33.14"

[[deps.StatsFuns]]
deps = ["ChainRulesCore", "InverseFunctions", "IrrationalConstants", "LogExpFunctions", "Reexport", "Rmath", "SpecialFunctions"]
git-tree-sha1 = "bedb3e17cc1d94ce0e6e66d3afa47157978ba404"
uuid = "4c63d2b9-4356-54db-8cca-17b64c39e42c"
version = "0.9.14"

[[deps.SuiteSparse]]
deps = ["Libdl", "LinearAlgebra", "Serialization", "SparseArrays"]
uuid = "4607b0f0-06f3-5cda-b6b1-a6196a1729e9"

[[deps.SymbolicUtils]]
deps = ["AbstractTrees", "Bijections", "ChainRulesCore", "Combinatorics", "ConstructionBase", "DataStructures", "DocStringExtensions", "DynamicPolynomials", "IfElse", "LabelledArrays", "LinearAlgebra", "Metatheory", "MultivariatePolynomials", "NaNMath", "Setfield", "SparseArrays", "SpecialFunctions", "StaticArrays", "TermInterface", "TimerOutputs"]
git-tree-sha1 = "d8a229358904e51e90a2aa4b48d7ce1f461c7dfe"
uuid = "d1185830-fcd6-423d-90d6-eec64667417b"
version = "0.19.1"

[[deps.Symbolics]]
deps = ["ArrayInterface", "ConstructionBase", "DataStructures", "DiffRules", "Distributions", "DocStringExtensions", "DomainSets", "IfElse", "Latexify", "Libdl", "LinearAlgebra", "MacroTools", "Metatheory", "NaNMath", "RecipesBase", "Reexport", "Requires", "RuntimeGeneratedFunctions", "SciMLBase", "Setfield", "SparseArrays", "SpecialFunctions", "StaticArrays", "SymbolicUtils", "TermInterface", "TreeViews"]
git-tree-sha1 = "3f354e1fac72482a0ba2ad3d7f9a08e8acc367a5"
uuid = "0c5d862f-8b57-4792-8d23-62f2024744c7"
version = "4.2.3"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "TableTraits", "Test"]
git-tree-sha1 = "bb1064c9a84c52e277f1096cf41434b675cd368b"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.6.1"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[deps.TermInterface]]
git-tree-sha1 = "7aa601f12708243987b88d1b453541a75e3d8c7a"
uuid = "8ea1fca8-c5ef-4a55-8b96-4e9afe9c9a3c"
version = "0.2.3"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.ThreadsX]]
deps = ["ArgCheck", "BangBang", "ConstructionBase", "InitialValues", "MicroCollections", "Referenceables", "Setfield", "SplittablesBase", "Transducers"]
git-tree-sha1 = "6dad289fe5fc1d8e907fa855135f85fb03c8fa7a"
uuid = "ac1d9e8a-700a-412c-b207-f0111f4b6c0d"
version = "0.1.9"

[[deps.TimerOutputs]]
deps = ["ExprTools", "Printf"]
git-tree-sha1 = "a5aed757f65c8a1c64503bc4035f704d24c749bf"
uuid = "a759f4b9-e2f1-59dc-863e-4aeb61b1ea8f"
version = "0.5.14"

[[deps.Transducers]]
deps = ["Adapt", "ArgCheck", "BangBang", "Baselet", "CompositionsBase", "DefineSingletons", "Distributed", "InitialValues", "Logging", "Markdown", "MicroCollections", "Requires", "Setfield", "SplittablesBase", "Tables"]
git-tree-sha1 = "3f0945b47207a41946baee6d1385e4ca738c25f7"
uuid = "28d57a85-8fef-5791-bfe6-a80928e7c999"
version = "0.4.68"

[[deps.TreeViews]]
deps = ["Test"]
git-tree-sha1 = "8d0d7a3fe2f30d6a7f833a5f19f7c7a5b396eae6"
uuid = "a2a6695c-b41b-5b7d-aed9-dbfdeacea5d7"
version = "0.3.0"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.UnPack]]
git-tree-sha1 = "387c1f73762231e86e0c9c5443ce3b4a0a9a0c2b"
uuid = "3a884ed6-31ef-47d7-9d2a-63182c4928ed"
version = "1.0.2"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[deps.ZygoteRules]]
deps = ["MacroTools"]
git-tree-sha1 = "8c1a8e4dfacb1fd631745552c8db35d0deb09ea0"
uuid = "700de1a5-db45-46bc-99cf-38207098b444"
version = "0.2.2"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
"""

# ╔═╡ Cell order:
# ╟─b9b5c2e0-537d-4a72-adb9-8474dc8acf98
# ╟─42f6afaa-cf0d-46dd-b1d9-ebaeafc9e5db
# ╠═4c4bfc78-7224-11ec-211d-f1e60824d35c
# ╟─b580a960-7780-417e-ae0f-3ac59f4a4a30
# ╠═0c2701f4-8e93-4fbc-b18c-52e9d1c213f8
# ╟─6e521fb4-190c-4b68-890b-d39b22537471
# ╟─bf6bac04-1957-4aa9-976e-efd76b41632b
# ╟─ea8f56c9-11d1-48e3-ae36-678fab1ad4bd
# ╟─8e96dcbb-5320-4222-9b83-aeedce9ed816
# ╟─79537fac-84f7-4bc1-8816-7d0ee433408e
# ╟─15d8d20e-a209-4941-9d95-dc43a1cde690
# ╟─745aa374-ade1-4474-99fd-f51869405a00
# ╠═92801458-b302-4e89-8434-4e6bb4c0135e
# ╟─f2357d35-0c51-4b04-a491-3893ac35f5a4
# ╠═fcdd4f4a-59d2-4027-8c30-f56d6782b7ef
# ╟─8fdb9251-1865-4e5e-9fac-b888c340e066
# ╟─f91d951f-2704-4244-a102-c1fc419337cb
# ╟─85718649-6050-4cd6-9c6d-83023a6e6030
# ╠═76c64481-d2af-40b8-bdda-ea2ebc05e8c8
# ╟─756f6398-2357-4602-8269-d27d60e32b2b
# ╟─27adf4ac-d11a-4e57-b8d9-d69a57f9e045
# ╠═105d0d41-6680-48ec-a16c-2c719ab06234
# ╟─26454574-c62a-4851-9211-c56e4da9ae8c
# ╠═eea19aaa-a295-4ae5-88fd-e2730710fbb9
# ╟─30ffb100-2331-494e-9433-09bf96c701fa
# ╠═5a4b516e-c7d4-4bad-8793-d4c63db23f9b
# ╟─cd16d92b-c605-4b37-ad42-1125c931d2c6
# ╠═a2464c22-3904-44ab-a00b-59570cdf7b7d
# ╠═a5c6de65-baeb-49eb-a28a-ac1109806794
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
