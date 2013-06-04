module PTools

include("srvr_task.jl")
include("j_shm.jl")
include("queued_tasks.jl")

global _debug = false
function _set_debug(d)
    global _debug
    _debug = d
end

#export STask
#export Jshm

end
