
import h5py
import numpy as np
# f = h5py.File('/reg/d/psdm/cxi/cxitut13/scratch/cpo/test_bigh5.h5','r')
# fw = h5py.File('small_test.h5','w')
# cspad = f['cspad']
# fw['cspad'] = cspad[0:5,:,:,:]
# fw.close()
# # cspadw = fw.create_dataset('cspad',data=cspad[0:5,:,:,:],dtype=cspad.dtype)

# f = h5py.File('small_test.h5','r')
# cspad = f['cspad']
# print 'Shape of entire dataset:',cspad.shape
# nimages = cspad.shape[0]
# for i in range(nimages):
#     image = np.array(cspad[0,:,:,:])
#     print 'Shape of event',i,'is',image.shape
#     if i>3: break

src_file = '/reg/d/psdm/cxi/cxitut13/scratch/cpo/test_bigh5.h5'
dst_file = '/reg/d/psdm/cxi/cxitut13/scratch/cpo/test_bigh5_resized.h5'
fsrc = h5py.File(src_file,'r')
fdst = h5py.File(dst_file,'w')
cspad = fsrc['cspad']
# fdst.create_dataset('cspad',shape=(cspad[0] * cspad[1], cspad[2], cspad[3]),dtype=cspad.dtype)
# for i in range(cspad.shape[0]):
# 	for j in range(cspad.shape[1]):
# 		fdst['cspad'][i*cspad.shape[1]+j,:,:]=cspad[i,j,:,:]
new_shape=(cspad.shape[0] * cspad.shape[1], cspad.shape[2], cspad.shape[3])
# fdst['cspad']=cspad[...].reshape(new_shape)
fdst.create_dataset('cspad',data=cspad[...].reshape(new_shape),dtype=cspad.dtype)
fdst.close()