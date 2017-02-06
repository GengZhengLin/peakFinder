import h5py
import numpy as np
from ImgAlgos.PyAlgos import PyAlgos
import timeit


data_file = "/reg/d/psdm/cxi/cxitut13/scratch/cpo/test_bigh5.h5"
# data_file = "small_test.h5"
events = 1000
fsrc = h5py.File(data_file,'r')
cspad = fsrc['cspad']
alg = PyAlgos()
alg.set_peak_selection_pars(npix_min=2, npix_max=50, amax_thr=10, atot_thr=20, son_min=5)
# hdr = '\nSeg  Row  Col  Npix    Amptot'
# fmt = '%3d %4d %4d  %4d  %8.1f'

hdr = 'Seg  Row  Col  Npix      Amax      Atot   rcent   ccent rsigma  csigma '+\
      'rmin rmax cmin cmax    bkgd     rms     son\n'
fmt = '%3d %4d %4d  %4d  %8.1f  %8.1f  %6.1f  %6.1f %6.2f  %6.2f %4d %4d %4d %4d  %6.2f  %6.2f  %6.2f\n'

cspad = cspad[0:events,:,:,:]
# fw = open("peakFindResult_python", 'w')
total_count = np.array(0,'i')

from mpi4py import MPI
comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

# print("size:{0},rank:{1}".format(size,rank))
counter = np.array(0,'i')
if rank == 0:
    start = timeit.default_timer()
    
for i in range(events):
	# fw.write(hdr)
	if i % size != rank: continue
	peaks = alg.peak_finder_v4r2(cspad[i,:,:,:],thr_low=10, thr_high=150, rank=4, r0=5, dr=0.05)
	counter += 1
	# for peak in peaks :
	#     seg,row,col,npix,amax,atot,rcent,ccent,rsigma,csigma,\
	#     rmin,rmax,cmin,cmax,bkgd,rms,son = peak[0:17]
	     
	#     fw.write( fmt % (seg, row, col, npix, amax, atot, rcent, ccent, rsigma, csigma,\
	#                  rmin, rmax, cmin, cmax, bkgd, rms, son))

comm.Reduce(counter,total_count)

if rank == 0:
    stop = timeit.default_timer()
    print("size:{0}",format(size))
    print("time: {0}".format(stop - start))
    print("counter: {0}".format(total_count))
# fw.close()

# import psana
# ds = psana.MPIDataSource('exp=cxitut13:run=10')
# det = psana.Detector('DscCsPad')
# from ImgAlgos.PyAlgos import PyAlgos
# alg = PyAlgos()
# alg.set_peak_selection_pars(npix_min=2, npix_max=50, amax_thr=10, atot_thr=20, son_min=5)
# hdr = '\nSeg  Row  Col  Npix    Amptot'
# fmt = '%3d %4d %4d  %4d  %8.1f'
# num_of_events = 1000
# start = timeit.default_timer()
# counter = 0
# for nevent,evt in enumerate(ds.events()):
#     if nevent>=num_of_events : break
#     nda = det.calib(evt)
#     if nda is None: continue
#     peaks = alg.peak_finder_v4r2(nda, thr_low=10, thr_high=150, rank=4, r0=5, dr=0.05)
#     # print hdr
#     # for peak in peaks :
#     #     seg,row,col,npix,amax,atot = peak[0:6]
#     #     print fmt % (seg, row, col, npix, atot)
# stop = timeit.default_timer()
# print("time: {0}".format(stop - start))



