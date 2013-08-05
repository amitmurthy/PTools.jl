addprocs(7)

using PTools
using Base.Test


# remove all workers
w = workers()

ws1 = WorkerSet(w[1:3], WS_MODE_RR)

@test 2 == remotecall_fetch(ws1, myid)
@test 3 == remotecall_fetch(ws1, myid)
@test 4 == remotecall_fetch(ws1, myid)
@test 2 == remotecall_fetch(ws1, myid)

println("Mode RR PASSED")

function test_ff(id, ws, stime)
    resp = remotecall_fetch(ws, 
    () -> begin
        println("In $(myid())")
        sleep(stime); 
        println("Exiting $(myid())")
        myid() 
    end)
    @test id == resp
    
end

ws2 = WorkerSet(w[4:7], WS_MODE_FF)
@sync begin
    @async test_ff(5, ws2, 2.0)
    @async test_ff(6, ws2, 2.1)
    @async test_ff(7, ws2, 2.2)
    @async test_ff(8, ws2, 2.3)

    # These should get queued and work in the same manner
    @async test_ff(5, ws2, 2.0)
    @async test_ff(6, ws2, 2.1)
    @async test_ff(7, ws2, 2.2)
    @async test_ff(8, ws2, 2.3)
end

println("Mode FF PASSED")



# test regular pmap and @parallel with all processes.
pmap_resp = pmap(x -> myid(), 1:nprocs())
defprocs = procs()
for i in pmap_resp
    @test contains(defprocs, i)
end


