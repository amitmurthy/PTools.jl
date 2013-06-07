# To execute:
# julia> addprocs(4)  # start number of desired worker processes
# julia> require("test_queued_tasks.jl")A
# julia> do_queued_tasks_test()

using PTools

type TestTaskStrRev <: WorkerTask
    str::String
end

function _wrkrfn(wt::TestTaskStrRev)
    return reverse(wt.str)
end

function _callback(wt::TestTaskStrRev, ret)
    println("at callback: reversed string: $ret")
end

function do_queued_tasks_test()
    println("initializing...")
    #PTools._set_debug(true)
    prep_remotes()

    for i in 1:10
        qt = QueuedWorkerTask(TestTaskStrRev("parallel $i"), _wrkrfn, _callback, :wrkr_any)
        queue_worker_task(qt)
    end

    for i in 1:10
        qt = QueuedWorkerTask(TestTaskStrRev("sequential $i"), _wrkrfn, _callback, :wrkr_any)
        println(execute_worker_task(qt))
    end
end

