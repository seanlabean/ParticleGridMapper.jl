push!(LOAD_PATH, "/Users/sean/GitRepos/ParticleMapper/ParticleGridMapper.jl")
push!(LOAD_PATH, "/Users/sean/GitRepos/Chia-Yu_Hu_ParticleMapper/OctreeBH.jl")

using ParticleGridMapper
using StaticArrays
using PyPlot

const N = 3 #spatial dimension
const T = Float64
const Npart = 1000 #number of particles
const BOXSIZE = 1.0

using Random
Random.seed!(1114)

function get_spherical_cloud(Ngas, rmax)
    X = Vector{SVector{N,T}}(undef, Ngas)
    for i in 1:Ngas
        r3d = rmax * 2 #s.t. the while-loop will be evaluated at least once
        while r3d > rmax
            m_frac = rand() * 0.99;      #m_frac = 0 ~ 0.99
            r3d = rmax * m_frac;
        end
        phi       = ( 2. * rand() - 1. ) * pi
        cos_theta = ( 2. * rand() - 1. )
        x = r3d * sqrt( 1. - cos_theta^2 ) * cos(phi)
        y = r3d * sqrt( 1. - cos_theta^2 ) * sin(phi)
        z = r3d * cos_theta
        X[i] = @SVector [x,y,z]
    end
    return X
end


X = get_spherical_cloud(Npart, 0.5*BOXSIZE)
topnode_length = @SVector(ones(N)) * BOXSIZE  #actual length of tree

center = @SVector [0.,0.,0.]

Mtot = 1.0
mass = ones(Npart) .* (Mtot / Npart) #particle mass

radius = ParticleGridMapper.norm.(X./BOXSIZE)
rho = 2*Mtot/(4*pi) .* radius.^(-2)
volume = mass ./ rho

Nngb = 32
hsml = ( ( Nngb * (Mtot / Npart) / (4*pi/3) ) ./ rho).^(1/3)

part = [DataP2G{N,T}(SVector(X[i]), i, hsml[i], mass[i], 0.0, T[]) for i in eachindex(X)]


#build the tree
treeNgb = buildtree(part, center, topnode_length);


boxsizes = @SVector(ones(N)) * BOXSIZE  #for periodic B.C.

nx = ny = 128
ix,iy = 1,2

xmin = (-0.5, -0.5, -0.5).* BOXSIZE
xmax = (0.5, 0.5, 0.5).* BOXSIZE

println("Cartensian NGP...")
image_cart_NGP = map_particle_to_3Dgrid_NGP_thread(rho, mass, X, (nx,ny,nx), xmin, xmax);
dimlos = filter!(x->(x!=ix)&&(x!=iy), [1,2,3])[1]
image_cart_NGP=dropdims(sum(image_cart_NGP, dims=dimlos),dims=dimlos);

println("Cartensian SPH...")
image_cart_SPH = map_particle_to_2Dgrid_loopP_thread(rho, mass./rho, X, hsml, xmin, xmax,
    ngrids=(nx,ny,nx), xaxis=ix, yaxis=iy, column=true, pbc = (true, true, true));



max_depth = 10
max_depth_true = get_max_tree_depth(treeNgb)
@show max_depth, max_depth_true

treeAMR = deepcopy(treeNgb)
set_max_depth_AMR!(treeAMR, max_depth)
balance_all_level!(treeAMR)

println("AMR SPH...")
@time map_particle_to_AMRgrid_SPH!(treeAMR, rho, volume, X, hsml, boxsizes, treeNgb=treeNgb)
@time map_particle_to_AMRgrid_SPH!(treeAMR, rho, volume, X, hsml, boxsizes)
rhoAMR_SPH = get_AMRfield(treeAMR)
image_SPH = project_AMRgrid_to_image(nx, ny, ix, iy, treeAMR, center, boxsizes);

#treeNgb = buildtree(part, center, topnode_length);
#treeAMR = deepcopy(treeNgb)
#set_max_depth_AMR!(treeAMR, max_depth)
#balance_all_level!(treeAMR)
#
#@time for i in 1:length(X)
#    map_particle_to_AMRgrid_loopP_recursive!(treeAMR, rho[i], volume[i], hsml[i], X[i], boxsizes, 100, BOXSIZE)
#end
#rhoAMR_SPH_2 = get_AMRfield(treeAMR, max_depth=max_depth)
#image_SPH_2 = project_AMRgrid_to_image_thread(nx, ny, ix, iy, treeAMR, center, boxsizes);
#@show all(rhoAMR_SPH_2.≈rhoAMR_SPH)
#@show all(image_SPH_2.≈image_SPH)

println("AMR MFM...")
map_particle_to_AMRgrid_MFM!(treeAMR, rho, X, hsml, boxsizes)
rhoAMR_MFM = get_AMRfield(treeAMR)
image_MFM = project_AMRgrid_to_image(nx, ny, ix, iy, treeAMR, center, boxsizes);



println("AMR NGP...")
map_particle_to_AMRgrid_NGP!(treeAMR, rho)
rhoAMR_NGP = get_AMRfield(treeAMR)
image_NGP = project_AMRgrid_to_image(nx, ny, ix, iy, treeAMR, center, boxsizes);


clf()
fig, ax = subplots(2, 3, figsize=(15, 10))
ax[1].set_title("particle distribution")
ax[1].plot(getindex.(X,1), getindex.(X,2), ".", ms=3, color="red")
ax[1].axis([-0.5*BOXSIZE, 0.5*BOXSIZE, -0.5*BOXSIZE, 0.5*BOXSIZE])
ax[2].set_title("AMR MFM")
ax[2].imshow(log10.(image_MFM'), origin="lower", vmin=-1, vmax=1.5, interpolation="none", extent=(-0.5*BOXSIZE, 0.5*BOXSIZE, -0.5*BOXSIZE, 0.5*BOXSIZE))
ax[3].set_title("Cartesian NGP")
ax[3].imshow(log10.(image_cart_NGP'), origin="lower", vmin=-1, vmax=1.5, interpolation="none", extent=(-0.5*BOXSIZE, 0.5*BOXSIZE, -0.5*BOXSIZE, 0.5*BOXSIZE))
ax[4].set_title("AMR NGP")
ax[4].imshow(log10.(image_NGP'), origin="lower", vmin=-1, vmax=1.5, interpolation="none", extent=(-0.5*BOXSIZE, 0.5*BOXSIZE, -0.5*BOXSIZE, 0.5*BOXSIZE))
ax[5].set_title("Cartesian SPH")
ax[5].imshow(log10.(image_cart_SPH'), origin="lower", vmin=-1, vmax=1.5, interpolation="none", extent=(-0.5*BOXSIZE, 0.5*BOXSIZE, -0.5*BOXSIZE, 0.5*BOXSIZE))
ax[6].set_title("AMR SPH")
ax[6].imshow(log10.(image_SPH'), origin="lower", vmin=-1, vmax=1.5, interpolation="none", extent=(-0.5*BOXSIZE, 0.5*BOXSIZE, -0.5*BOXSIZE, 0.5*BOXSIZE))

fig.tight_layout()
savefig("compare_MFM_SPH_NGP_cloud.png")
