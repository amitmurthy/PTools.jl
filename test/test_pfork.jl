using PTools

println("testing pfork ...")
assert(pfork(2,ind->ind) == [1:2])
assert(pfork(100,ind->ind) == [1:100])
f(ind) = ones(10,100)*ind
r = pfork(10,f)
should = map(f,1:10)
assert(r == should)

println("testing pfork_shm ...")
n = 10
R = pfork_shm(n, Float32, (n,), (ind, r) -> r[ind]=ind)
should = float32([1:n])
assert(R==should)
assert(isa(R, Array{Float32}))
assert(size(R)==(n,))

n = 10
R = pfork_shm(n, Float32, (3,n), (ind, r) -> r[:,ind]=ind)
should = float32(repmat([1:n]',3,1))
assert(R==should)
assert(isa(R, Array{Float32}))
assert(size(R)==(3,n))

n = 10
param = 10
R = pfork_shm(n, Float32, (3,n), (ind, r, param) -> r[:,ind]=ind*param, param)
should = float32(repmat([1:n]'*param,3,1))
assert(R==should)
assert(isa(R, Array{Float32}))
assert(size(R)==(3,n))

n = 10
R = pfork_shm(n, Float32, (3,n), (ind, r) -> r[:,ind]=ind)
should = float32(repmat([1:n]',3,1))
assert(R==should)
assert(isa(R, Array{Float32}))
assert(size(R)==(3,n))

n = 10
R1,R2 = pfork_shm(n, {(Float32, (3,n)), (Float64, (n,))}, 
              (ind, r1, r2) -> (r1[:,ind]=ind; r2[ind]=ind*ind))
should1 = float32(repmat([1:n]',3,1))
should2 = [1:n].^2
assert(R1==should1)
assert(R2==should2)
assert(isa(R1, Array{Float32}))
assert(isa(R2, Array{Float64}))
assert(size(R1)==(3,n))
assert(size(R2)==(n,))

println("ok!")
