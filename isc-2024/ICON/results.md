# Base Runs 

Base Sequential, Single:

			Runtime:
```
input file: tasks/20k.nc
itime: 0
dt: 30
qnc: 100
time taken : 2778 milliseconds
```
			Accuracy:
```
               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     1 : 0000-00-00 00:00:00       0  1843200       0  716521 : F F    0.0050092  1.8341e-05 : ta
     2 : 0000-00-00 00:00:00       0  1843200       0  600785 : F F   1.3422e-06  0.00031924 : hus
     3 : 0000-00-00 00:00:00       0  1843200       0  111384 : F T   2.6839e-08      1.0000 : clw
     4 : 0000-00-00 00:00:00       0  1843200       0  719033 : F T   7.1132e-11      1.0000 : cli
     5 : 0000-00-00 00:00:00       0  1843200       0  313709 : F T   1.9558e-08      1.0000 : qr
     6 : 0000-00-00 00:00:00       0  1843200       0  736400 : F T   1.7978e-07      1.0000 : qs
     7 : 0000-00-00 00:00:00       0  1843200       0  635076 : F T   9.5826e-07      1.0000 : qg
  7 of 7 records differ
  5 of 7 records differ more than 0.001
cdo    diffn: Processed 25804800 values from 14 variables over 2 timesteps [0.10s 45MB]
```

Base Sequential Double:

			Runtime: 
```
input file: tasks/20k.nc
itime: 0
dt: 30
qnc: 100
time taken : 2423 milliseconds
```
			Accuracy:
```
cdo    diffn: Processed 25804800 values from 14 variables over 2 timesteps [0.11s 52MB]
```



# Optimized:
Optimized Sequential, single 

			Runtime: 
```
input file: tasks/20k.nc
itime: 0
dt: 30
qnc: 100
time taken : 621 milliseconds
```
			Accuracy:
```
               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     1 : 0000-00-00 00:00:00       0  1843200       0  711598 : F F      0.22600  0.00090603 : ta
     2 : 0000-00-00 00:00:00       0  1843200       0  600408 : F F   5.9593e-05     0.19908 : hus
     3 : 0000-00-00 00:00:00       0  1843200       0  113168 : F T   1.2328e-05      1.0000 : clw
     4 : 0000-00-00 00:00:00       0  1843200       0  741497 : F T   3.7939e-05      1.0000 : cli
     5 : 0000-00-00 00:00:00       0  1843200       0  372587 : F T   3.3361e-08      1.0000 : qr
     6 : 0000-00-00 00:00:00       0  1843200       0  772984 : F T   5.3346e-05      1.0000 : qs
     7 : 0000-00-00 00:00:00       0  1843200       0  674932 : F T   2.7109e-05      1.0000 : qg
  7 of 7 records differ
  5 of 7 records differ more than 0.001
cdo    diffn: Processed 25804800 values from 14 variables over 2 timesteps [0.14s 45MB]
```

Optimized Sequential, Double 

			Runtime:
```
input file: tasks/20k.nc
itime: 0
dt: 30
qnc: 100
time taken : 563 milliseconds
```
			Accuracy:
```

               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     1 : 0000-00-00 00:00:00       0  1843200       0  353888 : F F   2.8422e-13  9.8888e-16 : ta
     2 : 0000-00-00 00:00:00       0  1843200       0    3984 : F F   3.4694e-18  4.0709e-16 : hus
     3 : 0000-00-00 00:00:00       0  1843200       0   40906 : F T   4.3368e-19     0.80000 : clw
     4 : 0000-00-00 00:00:00       0  1843200       0  406234 : F T   4.0658e-20      1.0000 : cli
     5 : 0000-00-00 00:00:00       0  1843200       0  236262 : F T   8.6736e-19      1.0000 : qr
     6 : 0000-00-00 00:00:00       0  1843200       0  408710 : F T   4.3368e-19      1.0000 : qs
     7 : 0000-00-00 00:00:00       0  1843200       0  358762 : F T   1.6263e-19      1.0000 : qg
  7 of 7 records differ
  3 of 7 records differ more than 0.001
cdo    diffn: Processed 25804800 values from 14 variables over 2 timesteps [0.18s 52MB]
```

OpenMP Base Sequential Single: 
(OMP_NUM_THREADS = 64)

			Runtime:
```
input file: tasks/20k.nc
itime: 0
dt: 30
qnc: 100
time taken : 208 milliseconds
```
			Accuracy:
```
               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     1 : 0000-00-00 00:00:00       0  1843200       0  594530 : F F      0.22617  0.00090586 : ta
     2 : 0000-00-00 00:00:00       0  1843200       0  517171 : F F   5.9592e-05     0.31449 : hus
     3 : 0000-00-00 00:00:00       0  1843200       0  247075 : F T    0.0034465      1.0000 : clw
     4 : 0000-00-00 00:00:00       0  1843200       0  729940 : F T   3.4488e-05      1.0000 : cli
     5 : 0000-00-00 00:00:00       0  1843200       0  322349 : F T    0.0022881      1.0000 : qr
     6 : 0000-00-00 00:00:00       0  1843200       0  742722 : F T   0.00031990      1.0000 : qs
     7 : 0000-00-00 00:00:00       0  1843200       0  636430 : F T   0.00011746      1.0000 : qg
  7 of 7 records differ
  6 of 7 records differ more than 0.001
cdo    diffn: Processed 25804800 values from 14 variables over 2 timesteps [0.16s 45MB]
```

OpenMP Base Sequential Double:

			Runtime:
```
input file: tasks/20k.nc
itime: 0
dt: 30
qnc: 100
time taken : 179 milliseconds
```
			Accuracy:
```

               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     1 : 0000-00-00 00:00:00       0  1843200       0  683551 : F F      0.22619  0.00090595 : ta
     2 : 0000-00-00 00:00:00       0  1843200       0  598369 : F F   5.9593e-05     0.31449 : hus
     3 : 0000-00-00 00:00:00       0  1843200       0  250343 : F T    0.0034465      1.0000 : clw
     4 : 0000-00-00 00:00:00       0  1843200       0  730046 : F T   3.4488e-05      1.0000 : cli
     5 : 0000-00-00 00:00:00       0  1843200       0  322359 : F T    0.0022881      1.0000 : qr
     6 : 0000-00-00 00:00:00       0  1843200       0  742738 : F T   0.00031990      1.0000 : qs
     7 : 0000-00-00 00:00:00       0  1843200       0  636447 : F T   0.00011746      1.0000 : qg
  7 of 7 records differ
  6 of 7 records differ more than 0.001
cdo    diffn: Processed 25804800 values from 14 variables over 2 timesteps [0.19s 52MB]
```


OpenMP Optimized Sequential Single:

			Runtime: 
```
input file: tasks/20k.nc
itime: 0
dt: 30
qnc: 100
time taken : 33 milliseconds
```
			Accuracy:
```
               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     1 : 0000-00-00 00:00:00       0  1843200       0  594203 : F F      0.22617  0.00090586 : ta
     2 : 0000-00-00 00:00:00       0  1843200       0  516742 : F F   5.9592e-05     0.31449 : hus
     3 : 0000-00-00 00:00:00       0  1843200       0  248022 : F T    0.0034465      1.0000 : clw
     4 : 0000-00-00 00:00:00       0  1843200       0  758727 : F T   3.4488e-05      1.0000 : cli
     5 : 0000-00-00 00:00:00       0  1843200       0  381221 : F T    0.0022881      1.0000 : qr
     6 : 0000-00-00 00:00:00       0  1843200       0  779577 : F T   0.00031990      1.0000 : qs
     7 : 0000-00-00 00:00:00       0  1843200       0  681195 : F T   0.00011746      1.0000 : qg
  7 of 7 records differ
  6 of 7 records differ more than 0.001
cdo    diffn: Processed 25804800 values from 14 variables over 2 timesteps [0.10s 45MB]
```


OpenMP Optimized Sequential Double:

			Runtime:
```
input file: tasks/20k.nc
itime: 0
dt: 30
qnc: 100
time taken : 25 milliseconds
```
			Accuracy:
```
               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     1 : 0000-00-00 00:00:00       0  1843200       0  683558 : F F      0.22619  0.00090595 : ta
     2 : 0000-00-00 00:00:00       0  1843200       0  600522 : F F   5.9593e-05     0.31449 : hus
     3 : 0000-00-00 00:00:00       0  1843200       0  252074 : F T    0.0034465      1.0000 : clw
     4 : 0000-00-00 00:00:00       0  1843200       0  758825 : F T   3.4488e-05      1.0000 : cli
     5 : 0000-00-00 00:00:00       0  1843200       0  381261 : F T    0.0022881      1.0000 : qr
     6 : 0000-00-00 00:00:00       0  1843200       0  779592 : F T   0.00031990      1.0000 : qs
     7 : 0000-00-00 00:00:00       0  1843200       0  681210 : F T   0.00011746      1.0000 : qg
  7 of 7 records differ
  6 of 7 records differ more than 0.001
cdo    diffn: Processed 25804800 values from 14 variables over 2 timesteps [0.10s 52MB]
```

## Gpu

Base Single GPU:

			Runtime:
```
input file: tasks/20k.nc
itime: 0
dt: 30
qnc: 100
time taken : 2271 milliseconds
```
			Accuracy:
```
cdo    diffn: Processed 25804800 values from 14 variables over 2 timesteps [0.09s 39MB]
```

Base Double GPU:

			Runtime:
```
input file: tasks/20k.nc
itime: 0
dt: 30
qnc: 100
time taken : 2683 milliseconds
```
			Accuracy:
```
cdo    diffn: Processed 25804800 values from 14 variables over 2 timesteps [0.08s 52MB]
```

Optimized Single GPU:

			Runtime:
```
input file: tasks/20k.nc
itime: 0
dt: 30
qnc: 100
time taken : 370 milliseconds
```
			Accuracy:
```

               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     3 : 0000-00-00 00:00:00       0  1843200       0      14 : F T   1.4552e-11  2.2996e-07 : clw
     5 : 0000-00-00 00:00:00       0  1843200       0      46 : F T   2.9104e-11  4.4557e-07 : qr
  2 of 7 records differ
  0 of 7 records differ more than 0.001
cdo    diffn: Processed 25804800 values from 14 variables over 2 timesteps [0.09s 39MB]
```

Optimized Double GPU:

			Runtime: 
```
input file: tasks/20k.nc
itime: 0
dt: 30
qnc: 100
time taken : 602 milliseconds
```
			Accuracy:
```
               Date     Time   Level Gridsize    Miss    Diff : S Z  Max_Absdiff Max_Reldiff : Parameter name
     1 : 0000-00-00 00:00:00       0  1843200       0  353888 : F F   2.8422e-13  9.8888e-16 : ta
     2 : 0000-00-00 00:00:00       0  1843200       0    3984 : F F   3.4694e-18  4.0709e-16 : hus
     3 : 0000-00-00 00:00:00       0  1843200       0   40906 : F T   4.3368e-19     0.80000 : clw
     4 : 0000-00-00 00:00:00       0  1843200       0  406234 : F T   4.0658e-20      1.0000 : cli
     5 : 0000-00-00 00:00:00       0  1843200       0  236262 : F T   8.6736e-19      1.0000 : qr
     6 : 0000-00-00 00:00:00       0  1843200       0  408710 : F T   4.3368e-19      1.0000 : qs
     7 : 0000-00-00 00:00:00       0  1843200       0  358762 : F T   1.6263e-19      1.0000 : qg
  7 of 7 records differ
  3 of 7 records differ more than 0.001
cdo    diffn: Processed 25804800 values from 14 variables over 2 timesteps [0.11s 52MB]
```


Best was: `/build_seq_optimize_double_openmp` 
