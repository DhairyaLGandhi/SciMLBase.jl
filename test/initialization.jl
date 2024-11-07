using OrdinaryDiffEq, NonlinearSolve, SymbolicIndexingInterface, Test

@testset "CheckInit" begin
    @testset "ODEProblem" begin
        function rhs(u, p, t)
            return [u[1] * t, u[1]^2 - u[2]^2]
        end
        function rhs!(du, u, p, t)
            du[1] = u[1] * t
            du[2] = u[1]^2 - u[2]^2
        end

        oopfn = ODEFunction{false}(rhs, mass_matrix = [1 0; 0 0])
        iipfn = ODEFunction{true}(rhs!, mass_matrix = [1 0; 0 0])

        @testset "Inplace = $(SciMLBase.isinplace(f))" for f in [oopfn, iipfn]
            prob = ODEProblem(f, [1.0, 1.0], (0.0, 1.0))
            integ = init(prob)
            u0, _, success = SciMLBase.get_initial_values(
                prob, integ, f, SciMLBase.CheckInit(), Val(SciMLBase.isinplace(f)))
            @test success
            @test u0 == prob.u0

            integ.u[2] = 2.0
            @test_throws SciMLBase.CheckInitFailureError SciMLBase.get_initial_values(
                prob, integ, f, SciMLBase.CheckInit(), Val(SciMLBase.isinplace(f)))
        end
    end

    @testset "DAEProblem" begin
        function daerhs(du, u, p, t)
            return [du[1] - u[1] * t - p, u[1]^2 - u[2]^2]
        end
        function daerhs!(resid, du, u, p, t)
            resid[1] = du[1] - u[1] * t - p
            resid[2] = u[1]^2 - u[2]^2
        end

        oopfn = DAEFunction{false}(daerhs)
        iipfn = DAEFunction{true}(daerhs!)

        @testset "Inplace = $(SciMLBase.isinplace(f))" for f in [oopfn, iipfn]
            prob = DAEProblem(f, [1.0, 0.0], [1.0, 1.0], (0.0, 1.0), 1.0)
            integ = init(prob, DImplicitEuler())
            u0, _, success = SciMLBase.get_initial_values(
                prob, integ, f, SciMLBase.CheckInit(), Val(SciMLBase.isinplace(f)))
            @test success
            @test u0 == prob.u0

            integ.u[2] = 2.0
            @test_throws SciMLBase.CheckInitFailureError SciMLBase.get_initial_values(
                prob, integ, f, SciMLBase.CheckInit(), Val(SciMLBase.isinplace(f)))

            integ.u[2] = 1.0
            integ.du[1] = 2.0
            @test_throws SciMLBase.CheckInitFailureError SciMLBase.get_initial_values(
                prob, integ, f, SciMLBase.CheckInit(), Val(SciMLBase.isinplace(f)))
        end
    end
end

@testset "OverrideInit" begin
    function rhs2(u, p, t)
        return [u[1] * t + p, u[1]^2 - u[2]^2]
    end

    @testset "No-op without `initialization_data`" begin
        prob = ODEProblem(rhs2, [1.0, 2.0], (0.0, 1.0), 1.0)
        integ = init(prob)
        integ.u[2] = 3.0
        u0, p, success = SciMLBase.get_initial_values(
            prob, integ, prob.f, SciMLBase.OverrideInit(), Val(false))
        @test u0 ≈ [1.0, 3.0]
        @test success
    end

    # unknowns are u[2], p. Parameter is u[1]
    initprob = NonlinearProblem([1.0, 1.0], [1.0]) do x, _u1
        u2, p = x
        u1 = _u1[1]
        return [u1^2 - u2^2, p^2 - 2p + 1]
    end
    update_initializeprob! = function (iprob, integ)
        iprob.p[1] = integ.u[1]
    end
    initprobmap = function (nlsol)
        return [parameter_values(nlsol)[1], nlsol.u[1]]
    end
    initprobpmap = function (nlsol)
        return nlsol.u[2]
    end
    initialization_data = SciMLBase.OverrideInitData(
        initprob, update_initializeprob!, initprobmap, initprobpmap)
    fn = ODEFunction(rhs2; initialization_data)
    prob = ODEProblem(fn, [2.0, 0.0], (0.0, 1.0), 0.0)
    integ = init(prob; initializealg = NoInit())

    @testset "Errors without `nlsolve_alg`" begin
        @test_throws SciMLBase.OverrideInitMissingAlgorithm SciMLBase.get_initial_values(
            prob, integ, fn, SciMLBase.OverrideInit(), Val(false))
    end

    @testset "Solves" begin
        u0, p, success = SciMLBase.get_initial_values(
            prob, integ, fn, SciMLBase.OverrideInit(),
            Val(false); nlsolve_alg = NewtonRaphson())

        @test u0 ≈ [2.0, 2.0]
        @test p ≈ 1.0
        @test success

        initprob.p[1] = 1.0
    end

    @testset "Solves with non-integrator value provider" begin
        _integ = ProblemState(; u = integ.u, p = parameter_values(integ), t = integ.t)
        u0, p, success = SciMLBase.get_initial_values(
            prob, _integ, fn, SciMLBase.OverrideInit(),
            Val(false); nlsolve_alg = NewtonRaphson())

        @test u0 ≈ [2.0, 2.0]
        @test p ≈ 1.0
        @test success

        initprob.p[1] = 1.0
    end

    @testset "Solves without `update_initializeprob!`" begin
        initdata = SciMLBase.@set initialization_data.update_initializeprob! = nothing
        fn = ODEFunction(rhs2; initialization_data = initdata)
        prob = ODEProblem(fn, [2.0, 0.0], (0.0, 1.0), 0.0)
        integ = init(prob; initializealg = NoInit())

        u0, p, success = SciMLBase.get_initial_values(
            prob, integ, fn, SciMLBase.OverrideInit(),
            Val(false); nlsolve_alg = NewtonRaphson())
        @test u0 ≈ [1.0, 1.0]
        @test p ≈ 1.0
        @test success
    end

    @testset "Solves without `initializeprobpmap`" begin
        initdata = SciMLBase.@set initialization_data.initializeprobpmap = nothing
        fn = ODEFunction(rhs2; initialization_data = initdata)
        prob = ODEProblem(fn, [2.0, 0.0], (0.0, 1.0), 0.0)
        integ = init(prob; initializealg = NoInit())

        u0, p, success = SciMLBase.get_initial_values(
            prob, integ, fn, SciMLBase.OverrideInit(),
            Val(false); nlsolve_alg = NewtonRaphson())

        @test u0 ≈ [2.0, 2.0]
        @test p ≈ 0.0
        @test success
    end
end
