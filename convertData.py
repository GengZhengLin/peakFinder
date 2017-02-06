import h5py
import numpy as np
import struct
import argparse

parser = argparse.ArgumentParser(description='Convert hdf5 file to C readable binary file')
parser.add_argument('-events', type=int, default=200)

args = parser.parse_args()

filename = '/reg/d/psdm/cxi/cxitut13/scratch/cpo/test_bigh5.h5'
# filename = '../h5data/small_test.h5'
converted_file = '/reg/d/psdm/cxi/cxitut13/scratch/cpo/test{0}.bin'.format(args.events)

fr = h5py.File(filename,'r')
cspad = fr['cspad']
fw = open(converted_file,'wb')
for i in range(args.events):
	for j in range(cspad.shape[1]):
		cspad[i,j,:,:].tofile(fw)
		# fw.write(struct.pack('f',cspad[i,j,:,:]))
		# for x in range(cspad.shape[2]):
		# 	for y in range(cspad.shape[3]):
fw.close()
print('converted to ' + converted_file)
# fr2 = open(converted_file, 'rb')
# c = np.fromfile(fr2, dtype=cspad.dtype)
# for i in range(100):
# 	print(c[i])


