import h5py
import numpy as np
from ImgAlgos.PyAlgos import PyAlgos


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


fw = open("peakFindResult_python_{0}".format(events), 'w')

for i in range(events):
	fw.write(hdr)
	peaks = alg.peak_finder_v4r2(cspad[i,:,:,:],thr_low=10, thr_high=150, rank=4, r0=5, dr=0.05)
	# counter += 1
	for peak in peaks :
	    seg,row,col,npix,amax,atot,rcent,ccent,rsigma,csigma,\
	    rmin,rmax,cmin,cmax,bkgd,rms,son = peak[0:17]
	     
	    fw.write( fmt % (seg, row, col, npix, amax, atot, rcent, ccent, rsigma, csigma,\
	                 rmin, rmax, cmin, cmax, bkgd, rms, son))
fw.close()