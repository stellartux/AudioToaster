using ACME
using Test

include("..\\src\\AudioToaster.jl")

circuitfrommacro = @circuit begin
    r1 = resistor(1e4)
    c1 = capacitor(4.7e-9), [1] ⟷ r1[2], [2] ⟷ gnd
    src = voltagesource(), [+] ⟷ r1[1], [-] ⟷ gnd
    prb = voltageprobe(), [+] ⟷ c1[1], [-] ⟷ gnd
end
circuitfromfile = AudioToaster.loadfile("examples\\simplest.diy")
modelfrommacro = DiscreteModel(circuitfrommacro, 1/44100)
modelfromfile = DiscreteModel(circuitfromfile, 1/44100)
testdata = reshape(rand(1000) .* 2.0 .- 1.0, 1, :)
expected = run!(modelfrommacro, testdata)
actual = run!(modelfromfile, testdata)

for i in 1:length(expected)
    @test expected[i] ≈ actual[i]
end
