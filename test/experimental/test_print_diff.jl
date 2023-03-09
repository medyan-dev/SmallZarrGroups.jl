using SmallZarrGroups
using Test

@testset "print diff" begin
    g1 = ZGroup()
    g2 = ZGroup()
    @test string(SmallZarrGroups.show_diff(; g1, g2)) == ""
    SmallZarrGroups.@test_equal g1 g2
    g1["subgroup"] = ZGroup()
    @test string(SmallZarrGroups.show_diff(; g1, g2)) == """
        "subgroup" in g1 but not in g2
        """
    @test string(SmallZarrGroups.show_diff(; g2, g1)) == """
        "subgroup" in g1 but not in g2
        """
    g1["subgroup/ds1"] = [NaN,2,3]
    g2 = deepcopy(g1)
    @test isequal(get!(Returns(nothing), g2, "subgroup/ds1"), [NaN,2,3])
    @test string(SmallZarrGroups.show_diff(; g1, g2)) == ""
    g1["subgroup/ds1"] = [1,2,3]
    @test string(SmallZarrGroups.show_diff(; g1, g2)) == """
        collect(g1["subgroup/ds1/"]):
        [1, 2, 3]
        collect(g2["subgroup/ds1/"]):
        [NaN, 2.0, 3.0]
        """
    attrs(g1)["foo"] = 1
    attrs(g2)["foo"] = 2
    attrs(g2)["bar"] = 3
    attrs(g2["subgroup/ds1"])["foo"] = "1.2"
    @test string(SmallZarrGroups.show_diff(; g1, g2)) == """
        attrs(g1)["foo"] is 1
        attrs(g2)["bar"] is 3
        attrs(g2)["foo"] is 2
        attrs(g2["subgroup/ds1/"])["foo"] is "1.2"
        collect(g1["subgroup/ds1/"]):
        [1, 2, 3]
        collect(g2["subgroup/ds1/"]):
        [NaN, 2.0, 3.0]
        """
    # ignore names starting with "f"
    @test string(SmallZarrGroups.show_diff(startswith("f"); g1, g2)) == """
        attrs(g2)["bar"] is 3
        collect(g1["subgroup/ds1/"]):
        [1, 2, 3]
        collect(g2["subgroup/ds1/"]):
        [NaN, 2.0, 3.0]
        """
end