# Time-stamp: <2012-02-23 11:46:30 Tao Liu>

"""Module Description

Copyright (c) 2012 Tao Liu <taoliu@jimmy.harvard.edu>

This code is free software; you can redistribute it and/or modify it
under the terms of the BSD License (see the file COPYING included with
the distribution).

@status:  experimental
@version: $Revision$
@author:  Tao Liu
@contact: taoliu@jimmy.harvard.edu
"""

# ------------------------------------
# python modules
# ------------------------------------

#from collections import Counter
from array import array as pyarray
from MACS2.Constants import *
from random import gammavariate as rgamma
from random import seed as rseed
from math import log
import pymc
from pymc import deterministic
# ------------------------------------
# constants
# ------------------------------------

LOG2E = log(2.718281828459045,2)        # for converting natural log to log2

gfold_dict = {}                         # temporarily save all precomputed gfold

# ------------------------------------
# Misc functions
# ------------------------------------
# def histogram ( vl, breaks=None, minv=None, maxv=None, binsize=None):
#     """Return histogram statistics.

#     Parameters:

#     vl: 2D numpy.array as [ [value, length], [value, length], ...]
    
#     breaks: if breaks is not None and a valid integar, split [min,max]
#     of values in vl into number of equal sized bins. Otherwise, no
#     binning is involved.

#     Return Value:
#     Counter object


#     when breaks is not None, key values in Counter is the start points
#     of each bin.
    
#     """
#     assert breaks == None or isinstance(breaks,int)
    
#     ret = Counter()

#     if breaks == None and binsize == None:
#         for (v,l) in vl:
#             ret[v] += int(l)
#     else:
#         if maxv == None:
#             maxv = vl[:,0].max()
#         if minv == None:
#             minv = vl[:,0].min()
#         if binsize == None:
#             binsize = (maxv-minv)/breaks
#         for (v,l) in vl:
#             k = (v - minv)//binsize*binsize + minv
#             #print k
#             ret[ k ] += int(l)

#     return ret

# def histogram2D ( md ):
#     """Return histogram statistics.

#     Parameters:

#     vl: 2D numpy.array as [ [value, length], [value, length], ...]
    
#     breaks: if breaks is not None and a valid integar, split [min,max]
#     of values in vl into number of equal sized bins. Otherwise, no
#     binning is involved.

#     Return Value:
#     Counter object


#     when breaks is not None, key values in Counter is the start points
#     of each bin.
    
#     """
#     ret = Counter()

#     for (m, d, l) in md:
#         ret[ (m,d) ] += int(l)

#     return ret


def MCMCPoissonPosteriorRatio (sample_number, burn, count1, count2):
    """MCMC method to calculate ratio distribution of two Posterior Poisson distributions.

    sample_number: number of sampling. It must be greater than burn, however there is no check.
    burn: number of samples being burned.
    count1: observed counts of condition 1
    count2: observed counts of condition 2

    return: list of log2-ratios
    """
    lam1 = pymc.Uniform('U1',0,10000)   # prior of lambda is uniform distribution
    lam2 = pymc.Uniform('U2',0,10000)   # prior of lambda is uniform distribution    
    poi1 = pymc.Poisson('P1',lam1,value=count1,observed=True) # Poisson with observed value count1
    poi2 = pymc.Poisson('P2',lam2,value=count2,observed=True) # Poisson with observed value count2
    @deterministic
    def ratio (l1=lam1,l2=lam2):
        return log(l1) - log(l2)
    mcmcmodel  = pymc.MCMC([ratio,lam1,poi1,lam2,poi2])
    mcmcmodel.sample(iter=sample_number, progress_bar=False, burn=burn)    
    return map(lambda x:x*LOG2E, ratio.trace())

rseed(10)

def MLEPoissonPosteriorRatio (sample_number, burn, count1, count2):
    """MLE method to calculate ratio distribution of two Posterior Poisson distributions.

    MLE of Posterior Poisson is Gamma(k+1,1) if there is only one observation k.

    sample_number: number of sampling. It must be greater than burn, however there is no check.
    burn: number of samples being burned.
    count1: observed counts of condition 1
    count2: observed counts of condition 2

    return: list of log2-ratios
    """
    ratios = pyarray('f',[])
    ra = ratios.append
    for i in xrange(sample_number):
        x1 = rgamma(count1+1,1)
        x2 = rgamma(count2+1,1)
        ra( log(x1,2) - log(x2,2) )
    return ratios[int(burn):]

def get_gfold ( v1, v2, precompiled_get=None, cutoff=0.01, sample_number=1000, burn=100, offset=0, mcmc=False):    
    # try cached gfold in this module first
    if gfold_dict.has_key((v1,v2)):
        return gfold_dict[(v1,v2)]

    # calculate ratio+offset

    # first, get the value from precompiled table
    try:
        V = precompiled_get( v1, v2 )
        if v1 > v2:
            # X >= 0
            ret = max(0,V+offset)
        elif v1 < v2:
            # X < 0
            ret = min(0,V+offset)
        else:
            ret = 0.0
        
    except IndexError:
        if mcmc:
            P_X = MCMCPoissonPosteriorRatio(sample_number,burn,v1,v2)
            i = int( (sample_number-burn) * cutoff)
        else:
            P_X = MLEPoissonPosteriorRatio(sample_number,0,v1,v2)
            i = int(sample_number * cutoff)            

        P_X = map(lambda x:x+offset,sorted(P_X))
        P_X_mean = float(sum(P_X))/len(P_X)
        
        if P_X_mean >= 0:
            # X >= 0
            ret = max(0,P_X[i])
        elif P_X_mean < 0:
            # X < 0
            ret = min(0,P_X[-1*i])

    gfold_dict[(v1,v2)] = ret
    return ret

#def convert_gfold ( v, cutoff = 0.01, precompiled_gfold=None, mcmc=False ):
def convert_gfold ( v, precompiled_gfold, sample_number=5000, burn=500, offset=0, cutoff=0.01, mcmc=False):
    """Take (name, count1, count2), try to extract precompiled gfold
    from precompiled_gfold.get; if failed, calculate the gfold using
    MCMC if mcmc is True, or simple MLE solution if mcmc is False.
    """
    ret = []
    retadd = ret.append
    get_func = precompiled_gfold.get
    for i in xrange(len(v[0])):
        rid= v[0][i]
        v1 = int(v[1][i])
        v2 = int(v[2][i])
        # calculate gfold from precompiled table, MCMC or MLE
        gf = get_gfold(v1,v2,precompiled_get=get_func,cutoff=cutoff,sample_number=sample_number,burn=burn,offset=offset,mcmc=mcmc)
        retadd([rid,gf])
    return ret

# ------------------------------------
# Classes
# ------------------------------------
