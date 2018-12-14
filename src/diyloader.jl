module DIYLoader

#=
n == "boards.TriPadBoard" ||
n == "boards.Breadboard" ||

n == "connectivity.CopperTrace" ||
n == "connectivity.GroundFill" ||

n == "semiconductors.BJTSymbol" ||

n == "semiconductors.TransistorTO92" ||
n == "semiconductors.TransistorTO1" ||
n == "semiconductors.TransistorTO220" ||
n == "semiconductors.TransistorTO3" ||
n == "passive.ElectrolyticCanCapacitor" ||
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
Point(el::XMLElement) = Point(parse(Float64, attribute(el, "x")), parse(Float64, attribute(el, "y")))
Point(xy::Union{Array,Tuple}) = Point(xy[1], xy[2])

struct Rectangle
    topleft::Point
    bottomright::Point
end

struct VeroBoard
    area::Rectangle
    horizontal::Bool
end
VeroBoard(c::XMLElement) = VeroBoard(Rectangle(Point(find_element(c, "firstPoint")),
              Point(find_element(c, "secondPoint"))),
              content(find_element(c, "orientation")) == "HORIZONTAL")

struct TraceCut
    location::Point
    betweentraces::Bool
end

struct Wire
    startpoint::Point
    endpoint::Point
end
Wire(ps::Union{Array{Point},Tuple{Point,Point}}) = Wire(ps[1], ps[2])

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

end

function iswithin(rect::Rectangle, point::Point)::Bool
    return rect.topleft.x < point.x &&
        rect.bottomright.x > point.x &&
        rect.topleft.y < point.y &&
        rect.bottomright.y > point.y
end

function findcomponentbyname(haystack::XMLElement, needle::Union{Regex,String})
    for component in child_elements(haystack)
        if occursin(needle, content(find_element(component, "name")))
            return component
        end
    end
end

function addconnection!(circ, col, p::Point, pin)
    haskey(col, p) ? connect!(circ, pin, col[p]) : col[p] = pin
end

function addtwoleggedcomponent!(circ, col, comp, ps::Union{Array{Point},Tuple{Point,Point}})
    addconnection!(circ, col, ps[1], (comp, (1, 1)))
    addconnection!(circ, col, ps[2], (comp, (1, -1)))
end

"""
Given an element loaded from a diy file, returns the value of that element
i.e. Returns the resistance of resistors, the capacitance of capacitors, etc
"""
function getvalue(el::XMLElement)::Float64
    value = parse(Float64, content(find_element(find_element(el, "value"), "value")))
    unit = content(find_element(find_element(el, "value"), "unit"))[1]
    return convertunitmagnitude(value, unit)
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

"""
Loads a circuit from a .diy file
"""
function loadfile(filepath::String)
    circ = Circuit()
    boards = []
    wires = []
    tracecuts = []

    # references to all of the connected pins
    connections = Dict{Point, Union{Tuple,Symbol}}()

    file = parse_file(filepath)
    fr = root(file)
    gridspacing = parse(Float64,
        content(find_element(find_element(fr, "gridSpacing"), "value")))

    cs = find_element(fr, "components")

    for c in child_elements(cs)
        n = SubString(name(c), 22)

        # store boards until all components are collected
        if n == "boards.VeroBoard"
            push!(boards, VeroBoard(c))

        elseif startswith("passive.Resistor", n)
            addtwoleggedcomponent!(circ, connections,
                add!(circ, resistor(getvalue(c))),
                map(Point, child_elements(find_element(c, "points"))))

        elseif n == "passive.RadialCeramicDiskCapacitor" ||
        n == "passive.AxialElectrolyticCapacitor" ||
        n == "passive.RadialElectrolytic" ||
        n == "passive.AxialFilmCapacitor" ||
        n == "passive.RadialFilmCapacitor" ||
        n == "passive.CapacitorSymbol"
            addtwoleggedcomponent!(circ, connections,
            add!(circ, capacitor(getvalue(c))),
            map(Point, child_elements(find_element(c, "points"))))

        elseif n == "connectivity.HookupWire"
            pointelems = collect(child_elements(find_element(c, "controlPoints")))
            points = (Point(pointelems[1]), Point(pointelems[4]))
            if occursin(r"g(rou)?nd"i, content(find_element(c, "name")))
                for p in points
                    addconnection!(circ, connections, p, :gnd)
                end
            else
                push!(wires, Wire(points))
            end

        elseif n == "connectivity.Jumper" || n == "connectivity.Line"
            push!(wires, Wire(map(Point, child_elements(find_element(c, "points")))))

        elseif n == "electromechanical.OpenJack1__4" ||
        n == "electromechanical.CliffJack1__4" ||
        n == "electromechanical.ClosedJack1__4"

            jackname = content(find_element(c, "name"))
            ps = map(Point, collect(child_elements(find_element(c, "controlPoints"))))

            if occursin(r"output"i, jackname)
                addtwoleggedcomponent!(circ, connections, add!(circ, voltageprobe()), ps)
            elseif occursin(r"input"i, jackname)
                addtwoleggedcomponent!(circ, connections, add!(circ, voltagesource()), ps)
            end

        elseif n == "electromechanical.PlasticDCJack"
            dcmatch = match(r"(-?[\d\.]+)([A-Za-z]*)", content(find_element(c, "value")))
            dcval = convertunitmagnitude(parse(Float64, dcmatch[1]), dcmatch[2])
            points = map(Point, collect(child_elements(find_element(c, "controlPoints"))))
            ps = content(find_element(c, "polarity")) == "CENTER_NEGATIVE" ?
                (points[1], points[3]) : (points[3], points[1])
            addtwoleggedcomponent!(circ, connections, add!(circ, voltagesource(dcval)), ps)

        elseif n == "misc.BatterySymbol"
            value = parse(Float64, content(find_element(find_element(el, "voltageNew"), "value")))
            unit = content(find_element(find_element(el, "voltageNew"), "unit"))[1]
            addtwoleggedcomponent(circ, connections,
                add!(circ, voltagesource(convertunitmagnitude(value, unit))),
                map(Point, child_elements(find_element(c, "points"))))

        elseif n == "misc.GroundSymbol"
            addconnection!(circ, connections,
                Point(find_element(c, "point")),
                :gnd)

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
                map(Point, child_elements(find_element(c, "points"))))

        elseif n == "connectivity.TraceCut"
            push!(tracecuts, TraceCut(
                Point(find_element(c, "point")),
                content(find_element(c, "cutBetweenHoles")) == "true"))

        elseif n == "passive.InductorSymbol"
            addtwoleggedcomponent!(circ, connections,
                add!(circ, inductor(getvalue(c))),
                map(Point, child_elements(find_element(c, "points"))))

        elseif n == ""


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

    free(file)
    return circ
end

end # module DIYLoader
