# How to compare if our results are valid 

`cdo diffv output.nc reference_results/sequential_double_output.nc`


ex:

		cdo 		diffn: Processed 156800 values from 14 variables over 2 timesteps [0.03s 24MB]


`cdo diffv <OUR_OUTPUT> <REFERENCE_OUTPUT>`

This output shows that the output is identitcal. Really you only need to worry about differences if you compare a CPU run to a GPU run:

ex:

		6 of 7 records differ
		0 of 7 records differ more than 0.001

If we get the above output, we run a second test:
`cdo infon -sub <OUR_OUTPUT.nc> reference_results/sequential_double_output.nc`

		cdo(1) sub: Processed 156800 values form 14 variables over 2 timesteps 
		cdo 		infon: Processed 78400 values from 7 variables ove 1 timestep [0.1s 25MB]

This will also show the difference between each of the arrays (how much our result with the gpu run is off from the expected result we are comparing to). If all *Minimum* column values are below our threshold of *1e-11*, then our result is valid.


## Submission:
- Path to implementation 
	- Here, they want the path to the folder we are sending into our build command. ex. when `cmake -DMU_IMPL=seq` then path would be `/home/b/b382786/scc_at_isc24/implementations/sequential`.
- Build Script
	- ex: `/home/b/b382786/make.example`
- Slurm logs
	- `.out` && `.err`, possibly output from seff
		- `seff <SLURM_OUTPUT> >> slurm-<SLURM_JOB_ID>.eff`
- Summary list fo optimizations performed
- Plots to confirm performance results
- (opt) Profiler analysis output and interpretation 
- (opt) Experience report for using OpenMP




## Summary of Optimizations Performed 
Lets just create a bullet list here. ex:
- `/home/b/b382786/scc_at_isc24/implementations/sequential/graupel.cpp`, `ln 109`
	- Loop unrolling. 
	- before:

		
		  // TODO @ryan HERE, parallelisation task loop 1
		  size_t oned_vec_index;
		  for (size_t i = ke - 1; i < ke; --i) {
		    for (size_t j = ivstart; j < ivend; j++) {
		      oned_vec_index = i * ivend + j;
		      if ((std::max({q[lqc].x[oned_vec_index], q[lqr].x[oned_vec_index],
		                     q[lqs].x[oned_vec_index], q[lqi].x[oned_vec_index],
		                     q[lqg].x[oned_vec_index]}) > qmin) or
		          ((t[oned_vec_index] < tfrz_het2) and
		           (q[lqv].x[oned_vec_index] >
		            qsat_ice_rho(t[oned_vec_index], rho[oned_vec_index])))) {
		        jmx_ = jmx_ + 1;
		        ind_k[jmx] = i;
		        ind_i[jmx] = j;
		        is_sig_present[jmx] =
		            std::max({q[lqs].x[oned_vec_index], q[lqi].x[oned_vec_index],
		                      q[lqg].x[oned_vec_index]}) > qmin;
		        jmx = jmx_;
		      }
		
		      for (size_t ix = 0; ix < np; ix++) {
		        if (i == (ke - 1)) {
		          kmin[j][qp_ind[ix]] = ke + 1;
		          q[qp_ind[ix]].p[j] = 0.0;
		          vt[j][ix] = 0.0;
		        }
		
		        if (q[qp_ind[ix]].x[oned_vec_index] > qmin) {
		          kmin[j][qp_ind[ix]] = i;
		        }
		      }
		    }
		  }


	- after: 
	

		// TODO @ryan 
		for(one){
			for(two){
				doThing()
			}
		}

	
	- So I changed it from all that junk to doThing because we instantly go from (whatever the time complexity of that mess was) to O(1) time (doThing() is very powerful). 


1) Misc loop optimizations on all 3 loops, plus added compilation flags, but we fail: `5 of 7 records differ more than 0.001`

Unsure if single is good, just focusing on double precision for right now. Currently is not good enough, going to tone down the Cmake compilation flags to try that.

with -O3
```
               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     1 : 0000-00-00 00:00:00       0    11200       0    1800 : F F     0.011442  4.4456e-05 : ta
     2 : 0000-00-00 00:00:00       0    11200       0    1596 : F F   3.0243e-06   0.0018833 : hus
     3 : 0000-00-00 00:00:00       0    11200       0      49 : F T   4.9927e-15     0.50000 : clw
     4 : 0000-00-00 00:00:00       0    11200       0    1693 : F T   2.6626e-07     0.98405 : cli
     5 : 0000-00-00 00:00:00       0    11200       0     256 : F T   3.9573e-18  4.9463e-12 : qr
     6 : 0000-00-00 00:00:00       0    11200       0    3076 : F T   2.3071e-06     0.90545 : qs
     7 : 0000-00-00 00:00:00       0    11200       0    2824 : F T   2.5739e-06     0.92839 : qg
  7 of 7 records differ
  1 of 7 records differ more than 0.001
cdo    diffn: Processed 156800 values from 14 variables over 2 timesteps [0.04s 24MB]
```

with -O2
```
               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     1 : 0000-00-00 00:00:00       0    11200       0    1800 : F F     0.011442  4.4456e-05 : ta
     2 : 0000-00-00 00:00:00       0    11200       0    1596 : F F   3.0243e-06   0.0018833 : hus
     3 : 0000-00-00 00:00:00       0    11200       0      49 : F T   4.9927e-15     0.50000 : clw
     4 : 0000-00-00 00:00:00       0    11200       0    1693 : F T   2.6626e-07     0.98405 : cli
     5 : 0000-00-00 00:00:00       0    11200       0     256 : F T   3.9573e-18  4.9463e-12 : qr
     6 : 0000-00-00 00:00:00       0    11200       0    3076 : F T   2.3071e-06     0.90545 : qs
     7 : 0000-00-00 00:00:00       0    11200       0    2824 : F T   2.5739e-06     0.92839 : qg
  7 of 7 records differ
  1 of 7 records differ more than 0.001
cdo    diffn: Processed 156800 values from 14 variables over 2 timesteps [0.04s 24MB]
``` 
Somewhat weird it is exactly the same, but I ran it twice and it stayed that way

with -01
```
               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     1 : 0000-00-00 00:00:00       0    11200       0    1800 : F F     0.011442  4.4456e-05 : ta
     2 : 0000-00-00 00:00:00       0    11200       0    1596 : F F   3.0243e-06   0.0018833 : hus
     3 : 0000-00-00 00:00:00       0    11200       0      49 : F T   4.9927e-15     0.50000 : clw
     4 : 0000-00-00 00:00:00       0    11200       0    1693 : F T   2.6626e-07     0.98405 : cli
     5 : 0000-00-00 00:00:00       0    11200       0     256 : F T   3.9573e-18  4.9463e-12 : qr
     6 : 0000-00-00 00:00:00       0    11200       0    3076 : F T   2.3071e-06     0.90545 : qs
     7 : 0000-00-00 00:00:00       0    11200       0    2824 : F T   2.5739e-06     0.92839 : qg
  7 of 7 records differ
  1 of 7 records differ more than 0.001
cdo    diffn: Processed 156800 values from 14 variables over 2 timesteps [0.04s 24MB]
```

with -O0
```
               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     1 : 0000-00-00 00:00:00       0    11200       0    1800 : F F     0.011442  4.4456e-05 : ta
     2 : 0000-00-00 00:00:00       0    11200       0    1596 : F F   3.0243e-06   0.0018833 : hus
     3 : 0000-00-00 00:00:00       0    11200       0      49 : F T   4.9927e-15     0.50000 : clw
     4 : 0000-00-00 00:00:00       0    11200       0    1693 : F T   2.6626e-07     0.98405 : cli
     5 : 0000-00-00 00:00:00       0    11200       0     256 : F T   3.9573e-18  4.9463e-12 : qr
     6 : 0000-00-00 00:00:00       0    11200       0    3076 : F T   2.3071e-06     0.90545 : qs
     7 : 0000-00-00 00:00:00       0    11200       0    2824 : F T   2.5739e-06     0.92839 : qg
  7 of 7 records differ
  1 of 7 records differ more than 0.001
cdo    diffn: Processed 156800 values from 14 variables over 2 timesteps [0.04s 24MB]
```

Next, try recompiling each of them with the `-DCMAKE_CXX_FLAGS=O...`, but move code in /implementations/sequential to be base, so I remove my own optimizations, and see if that is any help
TODO @ryan

just running one to test -O3

AHA
```
cdo    diffn: Processed 156800 values from 14 variables over 2 timesteps [0.04s 24MB]
```

For optimize double:
`tasks/input.nc` [10 milliseconds] -> [2 milliseconds]
`tasks/dbg.nc`   [0 milliseconds] -> [0 milliseconds]
`tasks/20k.nc`   [2807 milliseconds] -> [713 milliseconds]

-Ofast aint accurate enough

```
               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     1 : 0000-00-00 00:00:00       0    11200       0   11200 : F F     0.011480  4.4603e-05 : ta
     2 : 0000-00-00 00:00:00       0    11200       0   11200 : F F   3.0243e-06   0.0018834 : hus
     3 : 0000-00-00 00:00:00       0    11200       0     119 : F T   2.6539e-09      1.0000 : clw
     4 : 0000-00-00 00:00:00       0    11200       0    6610 : F T   2.6626e-07     0.98405 : cli
     5 : 0000-00-00 00:00:00       0    11200       0    6968 : F T   1.4263e-09     0.49883 : qr
     6 : 0000-00-00 00:00:00       0    11200       0    7600 : F T   2.3071e-06     0.90545 : qs
     7 : 0000-00-00 00:00:00       0    11200       0    7112 : F T   2.5739e-06     0.92839 : qg
  7 of 7 records differ
  1 of 7 records differ more than 0.001
```

By default for 1500:
28574 milliseconds

This is only using 1 core, trying ot just set num threads:


