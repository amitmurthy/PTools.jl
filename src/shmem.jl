using Base.FS
using Base.Test

fd_mem = ccall(:shm_open, Int, (Ptr{Uint8}, Int, Int), "/julia", JL_O_CREAT | JL_O_RDWR, S_IRWXU)
if !(fd_mem > 0) error("shm_open() failed") end

rc = ccall(:ftruncate, Int, (Int, Int), fd_mem, 4096)
if !(rc == 0) error("ftruncate() failed") end

x = ccall(:mmap, Ptr{Void}, (Ptr{Void}, Int, Int32, Int32, Int32, FileOffset), C_NULL, 4096, 0x01 | 0x02, 0x01, fd_mem, 0)
if !(x == C_NULL) error("ftruncate() failed") end

pi = pointer(Uint8, x)
pa = pointer_to_array(pi, 1024)



