module AudioToaster

#=
n == "connectivity.CopperTrace" ||
n == "connectivity.GroundFill" ||

n == "semiconductors.DIL__IC" ||

n == "semiconductors.ICSymbol" ||

elseif n == "passive.PotentiometerPanel" ||
    n == "passive.TrimmerPotentiometer" ||
    n == "passive.PotentiometerSymbol"
=#

export process, loadfile

using LightXML
using ACME
using WAV

struct Point
    x::Real
    y::Real
end
Point(el::XMLElement) = Point(
    parse(Float64, attribute(el, "x")),
    parse(Float64, attribute(el, "y")))
Point(xy::Union{Array,Tuple}) = Point(xy[1], xy[2])

struct Rectangle
    topleft::Point
    bottomright::Point
end

"""
`Transistor(description, pinout)` where description is an Expr returning an
ACME.Element when evaluated and pinout is a permutation that will be
applied to `[:collector, :base, :emitter]`.

Example:
```julia
t = Transistor(:(bjt(:npn, βf=200)), [1, 2, 3])
```
"""
struct Transistor
    description::Expr
    pinout::Array{Int}
    Transistor(d, p) = isperm(p) && length(p) == 3 ? new Transistor(d, p) : error("Invalid permutation")
end

struct VeroBoard
    area::Rectangle
    horizontal::Bool
end
VeroBoard(c::XMLElement) = VeroBoard(
    Rectangle(Point(c["firstPoint"]),
    Point(c["secondPoint"])),
    content(c["orientation"]) == "HORIZONTAL")

struct TriPadBoard
    area::Rectangle
    horizontal::Bool
end
TriPadBoard(c::XMLElement) = TriPadBoard(
    Rectangle(Point(c["firstPoint"]),
    Point(c["secondPoint"])),
    content(c["orientation"]) == "HORIZONTAL")

struct Breadboard
    location::Point
    fullsize::Bool
    offset::Bool
    orientation::String
end
Breadboard(c::XMLElement) = Breadboard(
    Point(c["point"]),
    content(c["breadboardSize"]) != "Half",
    content(c["powerStripPosition"]) != "Inline"
    content(c["orientation"]))

struct TraceCut
    location::Point
    betweentraces::Bool
end

struct Wire
    startpoint::Point
    endpoint::Point
end
Wire(ps::Union{Array{Point},Tuple{Point,Point}}) = Wire(ps[1], ps[2])

struct CopperTrace
    area::Rectangle
    pins::Array{Point}
end
CopperTrace(a::Rectangle) = CopperTrace(a, [])

"""
Given an ACME.DiscreteModel and the filepath of a WAV
applies the circuit to the WAV and returns a new WAV.
"""
function process(model::DiscreteModel, inputfile::String, outputfile::String)
    y, fs, nbits = wavread(inputfile)
    processed = run!(model, reshape(y, 1, :))
    wavwrite(reshape(processed, length(processed), 1), outputfile, Fs=fs, nbits=nbits)
end

function process(circuit::Circuit, inputfile::String, outputfile::String)
    y, fs, nbits = wavread(inputfile)
    model = DiscreteModel(circuit, 1/fs)
    processed = run!(model, reshape(y, 1, :))
    wavwrite(reshape(processed, length(processed), 1), outputfile, Fs=fs, nbits=nbits)
    return model
end

function iswithin(rect::Rectangle, point::Point)::Bool
    return rect.topleft.x < point.x &&
        rect.bottomright.x > point.x &&
        rect.topleft.y < point.y &&
        rect.bottomright.y > point.y
end

function findcomponentbyname(haystack::XMLElement, needle::Union{Regex,String})
    for component in child_elements(haystack)
        if occursin(needle, content(component["name"]))
            return component
        end
    end
end

"""
Connects a single pin on a component to any other pin occupying the same space.
"""
function addconnection!(circ, col, p::Point, pin)
    haskey(col, p) ? connect!(circ, pin, col[p]) : col[p] = pin
end

"""
Connects both pins of a two legged components, positive then negative on polar components.
"""
function addtwoleggedcomponent!(circ, col, comp, ps::Union{Array{Point},Tuple{Point,Point}})
    addconnection!(circ, col, ps[1], (comp, (1, 1)))
    addconnection!(circ, col, ps[2], (comp, (1, -1)))
end

function addtransistor!(circuit, col, transistor, pins, orientation)
    for i in 1:3
        addconnection!(circuit, col, transistor, pins[i], orientation[i])
    end
end

"""
Given an element loaded from a diy file, returns the value of that element
i.e. Returns the resistance of resistors, the capacitance of capacitors, etc
"""
function getvalue(el::XMLElement)::Float64
    return convertunitmagnitude(
        parse(Float64, content(el["value"]["value"])),
        content(el["value"]["unit"])[1])
end

function convertunitmagnitude(value::Real, unit::Char)::Real
    unitdict = Dict{Char, Float64}(
        'K'=>1e3,
        'k'=>1e3,
        'M'=>1e6,
        'p'=>1e-12,
        'n'=>1e-9,
        'u'=>1e-6,
        'm'=>1e-3
    )
    return haskey(unitdict, unit) ? value * unitdict[unit] : value
end

function convertunitmagnitude(value::Real, unit::String)::Real
    return length(unit) == 0 ? value : convertunitmagnitude(value, unit[1])
end

function connectcopperstrips(circ::Circuit, connections, board::VeroBoard; tracecuts)

end

function connectcopperstrips(circ::Circuit, connections, board::TriPadBoard; tracecuts)

end

function connectcopperstrips(circ::Circuit, connections, board::Breadboard; tracecuts)
    strips = []


end

"""
Loads a circuit from a .diy file
"""
function loadfile(filepath::String)
    circ = Circuit()
    boards = []
    wires = []
    tracecuts = []
    connections = Dict{Point, Union{Tuple,Symbol}}()
    transistors = Dict{String, Transistor}(
        "2N3904" => Transistor(:(bjt(:npn, βf=200)), [1, 2, 3]),
        "2N3906" => Transistor(:(bjt(:pnp, βf=200)), [1, 2, 3]),
        "BC546" => Transistor(:(bjt(:npn, βf=400)), [1, 2, 3]),
        "BC546A" => Transistor(:(bjt(:npn, βf=200)), [1, 2, 3]),
        "BC546B" => Transistor(:(bjt(:npn, βf=450)), [1, 2, 3]),
        "BC546C" => Transistor(:(bjt(:npn, βf=600)), [1, 2, 3]),
        "BC547" => Transistor(:(bjt(:npn, βf=400)), [1, 2, 3]),
        "BC547A" => Transistor(:(bjt(:npn, βf=200)), [1, 2, 3]),
        "BC547B" => Transistor(:(bjt(:npn, βf=450)), [1, 2, 3]),
        "BC547C" => Transistor(:(bjt(:npn, βf=600)), [1, 2, 3]),
        "BC548" => Transistor(:(bjt(:npn, βf=400)), [1, 2, 3]),
        "BC548A" => Transistor(:(bjt(:npn, βf=200)), [1, 2, 3]),
        "BC548B" => Transistor(:(bjt(:npn, βf=450)), [1, 2, 3]),
        "BC548C" => Transistor(:(bjt(:npn, βf=600)), [1, 2, 3]),
        "BC549" => Transistor(:(bjt(:npn, βf=400)), [1, 2, 3]),
        "BC549A" => Transistor(:(bjt(:npn, βf=200)), [1, 2, 3]),
        "BC549B" => Transistor(:(bjt(:npn, βf=450)), [1, 2, 3]),
        "BC549C" => Transistor(:(bjt(:npn, βf=600)), [1, 2, 3]),
        "BC550" => Transistor(:(bjt(:npn, βf=400)), [1, 2, 3]),
        "BC550A" => Transistor(:(bjt(:npn, βf=200)), [1, 2, 3]),
        "BC550B" => Transistor(:(bjt(:npn, βf=450)), [1, 2, 3]),
        "BC550C" => Transistor(:(bjt(:npn, βf=600)), [1, 2, 3],
        "BC556" => Transistor(:(bjt(:pnp, βf=400)), [1, 2, 3]),
        "BC556A" => Transistor(:(bjt(:pnp, βf=200)), [1, 2, 3]),
        "BC556B" => Transistor(:(bjt(:pnp, βf=450)), [1, 2, 3]),
        "BC556C" => Transistor(:(bjt(:pnp, βf=600)), [1, 2, 3]),
        "BC557" => Transistor(:(bjt(:pnp, βf=400)), [1, 2, 3]),
        "BC557A" => Transistor(:(bjt(:pnp, βf=200)), [1, 2, 3]),
        "BC557B" => Transistor(:(bjt(:pnp, βf=450)), [1, 2, 3]),
        "BC557C" => Transistor(:(bjt(:pnp, βf=600)), [1, 2, 3]),
        "BC558" => Transistor(:(bjt(:pnp, βf=400)), [1, 2, 3]),
        "BC558A" => Transistor(:(bjt(:pnp, βf=200)), [1, 2, 3]),
        "BC558B" => Transistor(:(bjt(:pnp, βf=450)), [1, 2, 3]),
        "BC558C" => Transistor(:(bjt(:pnp, βf=600)), [1, 2, 3]),
        "BC559" => Transistor(:(bjt(:pnp, βf=400)), [1, 2, 3]),
        "BC559A" => Transistor(:(bjt(:pnp, βf=200)), [1, 2, 3]),
        "BC559B" => Transistor(:(bjt(:pnp, βf=450)), [1, 2, 3]),
        "BC559C" => Transistor(:(bjt(:pnp, βf=600)), [1, 2, 3]),
        "BC560" => Transistor(:(bjt(:pnp, βf=400)), [1, 2, 3]),
        "BC560A" => Transistor(:(bjt(:pnp, βf=200)), [1, 2, 3]),
        "BC560B" => Transistor(:(bjt(:pnp, βf=450)), [1, 2, 3]),
        "BC560C" => Transistor(:(bjt(:pnp, βf=600)), [1, 2, 3])
    )
    file = parse_file(filepath)
    fr = root(file)
    gridspacing = parse(Float64, content(fr["gridSpacing"]["value"]))
    for c in child_elements(fr["components"])
        n = SubString(name(c), 22)

        # store boards until all components are collected
        if n == "boards.VeroBoard"
            push!(boards, VeroBoard(c))

        elseif n == "boards.TriPadBoard"
            push!(boards, TriPadBoard(c))

        elseif n == "boards.Breadboard"
            push!(boards, Breadboard(c))

        elseif startswith("passive.Resistor", n)
            addtwoleggedcomponent!(circ, connections,
                add!(circ, resistor(getvalue(c))),
                map(Point, child_elements(c["points"])))

        elseif n == "passive.RadialCeramicDiskCapacitor" ||
        n == "passive.AxialElectrolyticCapacitor" ||
        n == "passive.RadialElectrolytic" ||
        n == "passive.AxialFilmCapacitor" ||
        n == "passive.RadialFilmCapacitor" ||
        n == "passive.CapacitorSymbol"
            addtwoleggedcomponent!(circ, connections,
                add!(circ, capacitor(getvalue(c))),
                map(Point, child_elements(c["points"])))

        elseif n == "connectivity.HookupWire"
            pointelems = collect(child_elements(c["controlPoints"]))
            points = (Point(pointelems[1]), Point(pointelems[4]))
            if occursin(r"g(rou)?nd"i, content(c["name"]))
                for p in points
                    addconnection!(circ, connections, p, :gnd)
                end
            else
                push!(wires, Wire(points))
            end

        elseif n == "connectivity.Jumper" || n == "connectivity.Line"
            push!(wires, Wire(map(Point, child_elements(c["points"]))))

        # treat terminal strips like a bunch of wires
        elseif n == "boards.TerminalStrip"
            points = map(Point, collect(child_elements(c["controlPoints"])))
            terminalcount = parse(Int, content(c["terminalCount"]))
            for t in 1:terminalcount
                push!(wires, Wire(points[t], points[t + terminalcount]))
            end

        elseif n == "electromechanical.OpenJack1__4" ||
        n == "electromechanical.CliffJack1__4" ||
        n == "electromechanical.ClosedJack1__4"
            jackname = content(c["name"])
            ps = map(Point, collect(child_elements(c["controlPoints"])))
            if occursin(r"output"i, jackname)
                addtwoleggedcomponent!(circ, connections, add!(circ, voltageprobe()), ps)
            elseif occursin(r"input"i, jackname)
                addtwoleggedcomponent!(circ, connections, add!(circ, voltagesource()), ps)
            end

        elseif n == "electromechanical.PlasticDCJack"
            dcmatch = match(r"(-?[\d\.]+)([A-Za-z]*)", content(c["value"]))
            dcval = convertunitmagnitude(parse(Float64, dcmatch[1]), dcmatch[2])
            points = map(Point, collect(child_elements(c["controlPoints"])))
            ps = content(c["polarity"]) == "CENTER_NEGATIVE" ?
                (points[1], points[3]) : (points[3], points[1])
            addtwoleggedcomponent!(circ, connections, add!(circ, voltagesource(dcval)), ps)

        elseif n == "misc.BatterySymbol"
            value = parse(Float64, content(el["voltageNew"]["value"]))
            unit = content(el["voltageNew"]["unit"])[1]
            addtwoleggedcomponent(circ, connections,
                add!(circ, voltagesource(convertunitmagnitude(value, unit))),
                map(Point, child_elements(c["points"])))

        elseif n == "misc.GroundSymbol"
            addconnection!(circ, connections, Point(c["point"]), :gnd)

        elseif n == "semiconductors.DiodeSymbol" ||
        n == "semiconductors.SchottkyDiodeSymbol" ||
        n == "semiconductors.ZenerDiodeSymbol" ||
        n == "semiconductors.DiodeGlass" ||
        n == "semiconductors.DiodePlastic" ||
        n == "semiconductors.LEDSymbol" ||
        n == "semiconductors.LED"
            # TODO: load diode specifics from diode name
            # for now, default diode will do
            addtwoleggedcomponent!(circ, connections,
                add!(circ, diode()),
                map(Point, child_elements(c["points"])))

        elseif n == "connectivity.TraceCut"
            push!(tracecuts, TraceCut(
                Point(c["point"]),
                content(c["cutBetweenHoles"]) == "true"))

        elseif n == "passive.InductorSymbol"
            addtwoleggedcomponent!(circ, connections,
                add!(circ, inductor(getvalue(c))),
                map(Point, child_elements(c["points"])))

        elseif n == "semiconductors.BJTSymbol"
            val = uppercase(content(c["value"]))
            t = if haskey(transistors, val)
                    transistors[val].description
                else
                    bjt(content(c["polarity"]) == "NPN" ? :npn : :pnp)
                end
            addtransistor!(circ, connections,
                add!(circ, t),
                map(Point, collect(child_elements(c["controlPoints"]))),
                content(c["flip"]) == "Y"
                    ? [:base, :collector, :emitter]
                    : [:base, :emitter, :collector])

        elseif n == "semiconductors.TransistorTO92" ||
        n == "semiconductors.TransistorTO1" ||
        n == "semiconductors.TransistorTO220"
            points = map(Point, collect(child_elements(c["points"])))
            pins = [:collector, :base, :emitter]
            value = uppercase(content(c["value"])))
            if haskey(transistors, value)
                tr = add!(circ, transistors[value].description)
                permute!(pins, transistors[value].pinout)
            else
                tr = add!(circ,
                    bjt(occursin(r"pnp"i, value) ? :pnp : :npn,
                        βf = occursin(r"gain ?= ?\d*\.?\d+"i, value) ?
                        parse(Float64, match(r"gain ?= ?(\d*\.?\d+)"i)) : 200))
                if occursin(r"ebc"i, value)
                    permute!(pins, [3, 2, 1])
                elseif occursin(r"bce"i, value)
                    permute!(pins, [2, 1, 3])
                elseif occursin(r"bec"i, value)
                    permute!(pins, [2, 3, 1])
                elseif occursin(r"ceb"i, value)
                    permute!(pins, [1, 3, 2])
                end
            end
            addtransistor!(circ, connections, tr, points, pins)
        end
    end
    # connect the wires
    for w in wires
        if haskey(connections, w.startpoint) && haskey(connections, w.endpoint)
            connect!(circ, connections[w.startpoint], connections[w.endpoint])
        elseif haskey(connections, w.startpoint) && !haskey(connections, w.endpoint)
            addconnection!(circ, connections, w.endpoint, connections[w.startpoint])
        elseif haskey(connections, w.endpoint) && !haskey(connections, w.startpoint)
            addconnection!(circ, connections, w.startpoint, connections[w.endpoint])
        else
            # handle wires connected to boards or other wires here
        end
    end

    for board in boards
        connectcopperstrips(circ, connections, board, tracecuts)
    end

    free(file)
    return circ
end

end # module AudioToaster
